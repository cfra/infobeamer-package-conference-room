gl.setup(1280, 720)

sys.set_flag("slow_gc")

local json = require "json"
local schedule
local current_room

util.resource_loader{
    "progress.frag",
}

local white = resource.create_colored_texture(1,1,1)

util.file_watch("schedule.json", function(content)
    print("reloading schedule")
    schedule = json.decode(content)
    print("loaded schedule. Len: ", #schedule)
end)

local rooms
local spacer = white

node.event("config_update", function(config)
    rooms = {}
    for idx, room in ipairs(config.rooms) do
        if room.serial == sys.get_env("SERIAL") then
            print("found my room")
            current_room = room
        end
        rooms[room.name] = room
    end
    spacer = resource.create_colored_texture(CONFIG.foreground_color.rgba())
end)

hosted_init()

local base_time = N.base_time or 0
local current_talk
local all_talks = {}
local day = 0

function get_now()
    return base_time + sys.now()
end

function check_next_talk()
    local now = get_now()
    local room_next = {}
    for idx, talk in ipairs(schedule) do
        if rooms[talk.place] and not room_next[talk.place] and talk.start_unix + 25 * 60 > now then 
            room_next[talk.place] = talk
        end
    end

    for room, talk in pairs(room_next) do
        talk.slide_lines = wrap(talk.title, 30)

        if #talk.title > 25 then
            talk.lines = wrap(talk.title, 60)
            if #talk.lines == 1 then
                talk.lines[2] = table.concat(talk.speakers, ", ")
            end
        end
    end

    if current_room and room_next[current_room.name] then
        current_talk = room_next[current_room.name]
    else
        current_talk = nil
    end

    print("PARSING talks")
    all_talks = {}
    for idx,talk in ipairs(schedule) do
        if talk.start_unix + 25 * 60 > now and talk.start_unix < now + 24 * 3600 then
            if not current_talk or talk.place ~= current_talk.place then
                all_talks[#all_talks + 1] = talk
            end
        end
    end
    table.sort(all_talks, function(a, b)
        if a.start_unix < b.start_unix then
            return true
        elseif a.start_unix > b.start_unix then
            return false
        else
            return a.place < b.place
        end
    end)
    print("PARSED talks. Count: ", #all_talks)
end

function wrap(str, limit, indent, indent1)
    limit = limit or 72
    local here = 1
    local wrapped = str:gsub("(%s+)()(%S+)()", function(sp, st, word, fi)
        if fi-here > limit then
            here = st
            return "\n"..word
        end
    end)
    local splitted = {}
    for token in string.gmatch(wrapped, "[^\n]+") do
        splitted[#splitted + 1] = token
    end
    return splitted
end

local clock = (function()
    local base_time = N.base_time or 0

    local function set(time)
        base_time = tonumber(time) - sys.now()
    end

    util.data_mapper{
        ["clock/midnight"] = function(since_midnight)
            print("NEW midnight", since_midnight)
            set(since_midnight)
        end;
    }

    local function get()
        local time = (base_time + sys.now()) % 86400
        return string.format("%d:%02d", math.floor(time / 3600), math.floor(time % 3600 / 60))
    end

    return {
        get = get;
        set = set;
    }
end)()

util.data_mapper{
    ["clock/set"] = function(time)
        base_time = tonumber(time) - sys.now()
        N.base_time = base_time
        check_next_talk()
        print("UPDATED TIME", base_time)
    end;
    ["clock/day"] = function(new_day)
        day = new_day
        print("UPDATED DAY", new_day)
    end;
}

function switcher(get_screens)
    local current_idx = 0
    local current
    local current_state
    local switch = sys.now()
    local screens = get_screens()

    local function prepare()
        local now = sys.now()
        if now > switch then
            print("Switching screen currently at ", current_idx)
            -- find next screen
            current_idx = current_idx + 1
            if current_idx > #screens then
                screens = get_screens()
                current_idx = 1
            end
            current = screens[current_idx]
            print("Switched to ", current_idx, " will stay there ", current.time, " seconds")
            switch = now + current.time
            current_state = current.prepare()
        end
    end

    local function draw()
        current.draw(current_state)
    end
    return {
        prepare = prepare;
        draw = draw;
    }
end

local content = switcher(function()
    return {{
        time = CONFIG.other_rooms,
        prepare = function()
            local content = {}

            local function add_content(func)
                content[#content+1] = func
            end

            local function mk_spacer(y)
                return function()
                    spacer:draw(0, y, WIDTH, y+2, 0.6)
                end
            end

            local function mk_talkmulti(y, talk, is_running)
                local alpha
                if is_running then
                    alpha = 0.5
                else
                    alpha = 1.0
                end

                local line_idx = 999999
                local top_line
                local bottom_line
                local function next_line()
                    line_idx = line_idx + 1
                    if line_idx > #talk.lines then
                        line_idx = 2
                        top_line = talk.lines[1]
                        bottom_line = talk.lines[2] or ""
                    else
                        top_line = bottom_line
                        bottom_line = talk.lines[line_idx]
                    end
                end

                next_line()

                local switch = sys.now() + 3

                return function()
                    CONFIG.font:write(30, y, talk.start_str, 30, CONFIG.foreground_color.rgb_with_a(alpha))
                    CONFIG.font:write(190, y, talk.place, 30, CONFIG.foreground_color.rgb_with_a(alpha))
                    CONFIG.font:write(400, y, top_line, 24, CONFIG.foreground_color.rgb_with_a(alpha))
                    CONFIG.font:write(400, y+28, bottom_line, 24, CONFIG.foreground_color.rgb_with_a(alpha*0.6))

                    if sys.now() > switch then
                        next_line()
                        switch = sys.now() + 1
                    end
                end
            end

            local function mk_talk(y, talk, is_running)
                local alpha
                if is_running then
                    alpha = 0.5
                else
                    alpha = 1.0
                end

                return function()
                    CONFIG.font:write(30, y, talk.start_str, 30, CONFIG.foreground_color.rgb_with_a(alpha))
                    CONFIG.font:write(190, y, talk.place, 30, CONFIG.foreground_color.rgb_with_a(alpha))
                    CONFIG.font:write(400, y, talk.title, 30, CONFIG.foreground_color.rgb_with_a(alpha))
                end
            end

            local y = 140
            local time_sep = false
            if #all_talks > 0 then
                for idx, talk in ipairs(all_talks) do
                    print("adding talk: " .. talk.title)
                    if not time_sep and talk.start_unix > get_now() then
                        if idx > 1 then
                            y = y + 5
                            add_content(mk_spacer(y))
                            y = y + 20
                        end
                        time_sep = true
                    end
                    if y < 680 then
                        if talk.lines then
                            add_content(mk_talkmulti(y, talk, not time_sep))
                        else
                            add_content(mk_talk(y, talk, not time_sep))
                        end
                        y = y + 62
                    end
                end
            else
                CONFIG.font:write(400, 330, "No other talks.", 50, CONFIG.foreground_color.rgba())
            end

            return content
        end;
        draw = function(content)
            CONFIG.font:write(40, 10, "Programm", 70, CONFIG.foreground_color.rgba())
            spacer:draw(0, 120, WIDTH, 122, 0.6)
            for _, func in ipairs(content) do
                func()
            end
        end
    },
    {
        -- Announcement, eg Plenum.
        -- Update date in the prepare function and text in the draw function
        time = 10,
        prepare = function()
        end;
        draw = function()
            local start_date = os.time({tz='CEST', day=22, month=5, year=2015, hour=22, min=45, sec=0})
            local difference = start_date - get_now()

            local time_to_event = ""
            if difference <= 0 then
                time_to_event = "Jetzt:"
            else
                time_to_event = string.format("In %d Minuten:", difference / 60)
            end
            CONFIG.font:write(40, 10, "Ankündigung", 70, CONFIG.foreground_color.rgba())
            spacer:draw(0, 120, WIDTH, 122, 0.6)
            print("TIME TO EVENT: ", time_to_event)
            CONFIG.font:write(40, 180, time_to_event, 30, CONFIG.foreground_color.rgba())
            CONFIG.font:write(40, 240, "Plenum", 30, CONFIG.foreground_color.rgba())
        end
    }}
end)

function node.render()
    if base_time == 0 then
        return
    end

    content.prepare()

    CONFIG.background_color.clear()
    CONFIG.background.ensure_loaded():draw(0, 0, WIDTH, HEIGHT)

    util.draw_correct(CONFIG.logo.ensure_loaded(), 20, 20, 300, 120)
    if current_room then
        CONFIG.font:write(400, 20, current_room.name_short, 70, CONFIG.foreground_color.rgba())
    end
    CONFIG.font:write(850, 20, clock.get(), 70, CONFIG.foreground_color.rgba())
    -- font:write(WIDTH-300, 20, string.format("Day %d", day), 100, CONFIG.foreground_color.rgba())

    local fov = math.atan2(HEIGHT, WIDTH*2) * 360 / math.pi
    gl.perspective(fov, WIDTH/2, HEIGHT/2, -WIDTH,
                        WIDTH/2, HEIGHT/2, 0)
    content.draw()
end
