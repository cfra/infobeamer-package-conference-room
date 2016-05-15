gl.setup(1280, 720)

sys.set_flag("slow_gc")

local json = require "json"
local schedule
local current_room

util.resource_loader{
    "progress.frag",
}

local changed_talks = {
    "open space",
    "FLTI im Male_stream HipHop",
    "Kickboxen",
    "Entdeckungsreise Programmieren",
    "decolonial feminism",
    "Was ist das für 1 Leckerei?",
    "Sachsen: ein sicheres Herkunftsland."
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
    print("Processing config_update...")
    rooms = {}
    for idx, room in ipairs(config.rooms) do
        if room.serial == sys.get_env("SERIAL") then
            print("found my room")
            current_room = room
        end
        rooms[room.name] = room
        print("Adding room ", room.name, " = ", room.name_short)
    end

    act_foreground = CONFIG.foreground_color
    act_background = CONFIG.background_color
    spacer = resource.create_colored_texture(act_foreground.rgba())
end)

function true_child(name)
    if name == "dateutil" then
        return false
    end
    if name == "defusedxml" then
        return false
    end
    return true
end

local children = {}
node.event("child_add", function(child_name)
    if not true_child(child_name) then
        return
    end
    print("Adding child ", child_name)
    children[#children + 1] = child_name
end)

node.event("child_remove", function(child_name)
    if not true_child(child_name) then
        return
    end
    local new_children = {}
    print("Removing child ", child_name)
    for idx,child in ipairs(children) do
        if child ~= child_name then
            new_children[#new_children + 1] = child
        end
    end
    children = new_children
end)

hosted_init()

local base_time = N.base_time or 0
local all_talks = {}
local day = 0

local shift_x = 0
local shift_y = 0
local speed_x = 0
local speed_y = 0
local act_foreground = CONFIG.foreground_color
local act_background = CONFIG.background_color

function make_color(r,g,b,a)
    local color = {}
    color.r = r
    color.g = g
    color.b = b
    color.a = a
    color.rgba_table = {color.r, color.g, color.b, color.a}
    color.rgba = function()
        return color.r, color.g, color.b, color.a
    end
    color.rgb_with_a = function(alpha)
        return color.r, color.g, color.b, alpha
    end
    color.clear = function()
        gl.clear(color.r, color.g, color.b, color.a)
    end
    return color
end

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
    end

    print("PARSING talks")
    all_talks = {}
    for idx,talk in ipairs(schedule) do
        talk.title, _ = talk.title:gsub("\t"," ")
        if CONFIG.font:width(talk.title, 30) > 860 then
            talk["lines"] = wrap(talk.title, 60)
            if #talk.lines == 1 then
                talk.lines[2] = table.concat(talk.speakers, ", ")
            end
        end
        if talk.start_unix > now and talk.start_unix < now + 24 * 3600 then
            all_talks[#all_talks + 1] = talk
        elseif talk.start_unix < now and talk.end_unix + 15 * 60 > now then
            cur_talks[#cur_talks + 1] = talk
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
            speed_x = math.random(4,7) / 80
            speed_y = math.random(4,7) / 80
            local color_sel = math.random(0,2)
            if color_sel == 0 then
                act_foreground = make_color(0.105,0.737,0.22,1)
                act_background = make_color(0.086,0.086,0.094,1)
            elseif color_sel == 1 then
                act_foreground = make_color(0.44,0.44,0.80,1)
                act_background = make_color(0.086,0.086,0.094,1)
            else
                act_foreground = make_color(0.93333,0.301,0.18,1)
                act_background = make_color(0.086,0.086,0.094,1)
            end
            print("Color Color Color", act_foreground)
            spacer = resource.create_colored_texture(act_foreground.rgba())
            repeat
                current_idx = current_idx + 1
                if current_idx > #screens then
                    screens = get_screens()
                    current_idx = 1
                end
                current = screens[current_idx]
            until current.time ~= 0
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

function mk_talkmulti(y, talk, is_running, changed)
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
        local shortname
        if rooms[talk.place] then
            shortname = rooms[talk.place].name_short
        else
            shortname = talk.place
        end

        local talk_color = act_foreground
        if changed then
                talk_color = make_color(1.0,1.0,1.0,1.0)
        end
        CONFIG.font:write(30, y, talk.start_str, 30, talk_color.rgb_with_a(alpha))
        CONFIG.font:write(190, y, shortname, 30, talk_color.rgb_with_a(alpha))
        CONFIG.font:write(400, y, top_line, 24, talk_color.rgb_with_a(alpha))
        CONFIG.font:write(400, y+28, bottom_line, 24, talk_color.rgb_with_a(alpha))

        if sys.now() > switch then
            next_line()
            switch = sys.now() + 3
        end
    end
end

function mk_talk(y, talk, is_running, changed)
    local shortname
    if rooms[talk.place] then
        shortname = rooms[talk.place].name_short
    else
        shortname = talk.place
    end
    local alpha
    if is_running then
        alpha = 0.5
    else
        alpha = 1.0
    end

    local talk_color = act_foreground
    if changed then
        talk_color = make_color(1.0,1.0,1.0,1.0)
    end

    return function()
        CONFIG.font:write(30, y, talk.start_str, 30, talk_color.rgb_with_a(alpha))
        CONFIG.font:write(190, y, shortname, 30, talk_color.rgb_with_a(alpha))
        CONFIG.font:write(400, y, talk.title, 30, talk_color.rgb_with_a(alpha))
    end
end

local content = switcher(function()
    local rv = {{
        -- Announcement, eg Plenum.
        -- Update date in the prepare function and text in the draw function
        -- use date -d 'May 22 23:00:00 2015' +%s
        -- to get timestamp
        time = 0,
        prepare = function()
        end;
        draw = function()
            CONFIG.font:write(40, 10, "Ankündigung", 70, act_foreground.rgba())
            spacer:draw(0, 120, WIDTH, 122, 0.6)

            local start_date = 1463235300
            local difference = start_date - get_now()

            local time_to_event = ""
            if difference <= 0 then
                time_to_event = string.format("Jetzt")
            elseif difference < 100 then
                time_to_event = string.format("In %d Minuten", difference / 60)
            else
                time_to_event = string.format("In %.1f Stunden", difference / 3600)
            end
            print("TIME TO EVENT: ", time_to_event, " START: ", start_date, " NOW: ", get_now())
            CONFIG.font:write(40, 180, time_to_event .. " (16:15) Plenum", 90, act_foreground.rgba())
            CONFIG.font:write(40, 300, "Thema: Rauchen", 60, act_foreground.rgba())
            CONFIG.font:write(40, 380, "Am/Im Zirkuszelt", 60, act_foreground.rgba())
            CONFIG.font:write(40, 460, "Bei schlechtem Wetter im Speisesaal", 40, act_foreground.rgba())
        end
    },
    {
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
                        local talk_changed = false
                        for idx2,changed in ipairs(changed_talks) do
                            if talk.title == changed then
                                talk_changed = true
                            end
                        end
                        if talk.lines then
                            add_content(mk_talkmulti(y, talk, not time_sep, talk_changed))
                        else
                            add_content(mk_talk(y, talk, not time_sep, talk_changed))
                        end
                        y = y + 62
                    end
                end
            else
                CONFIG.font:write(400, 330, "No other talks.", 50, act_foreground.rgba())
            end

            return content
        end;
        draw = function(content)
            CONFIG.font:write(40, 10, "Programm", 70, act_foreground.rgba())
            --spacer:draw(0, 120, WIDTH, 122, 0.6)
            for _, func in ipairs(content) do
                func()
            end
        end
    }}
    for idx,child in ipairs(children) do
        rv[#rv + 1] = {
            time = 10,
            prepare = function()
            end;
            draw = function()
                local frame = resource.render_child(child)
                frame:draw(0,0,WIDTH,HEIGHT)
                frame:dispose()
            end
        }
    end
    return rv
end)

function node.render()
    if base_time == 0 then
        return
    end

    content.prepare()

    act_background.clear()
    CONFIG.background.ensure_loaded():draw(0, 0, WIDTH, HEIGHT)

    if shift_x + speed_x > 20 or shift_x + speed_x < -20 then
        speed_x = -speed_x
    end
    if shift_y + speed_y > 10 or shift_y + speed_y < -10 then
        speed_y = -speed_y
    end

    shift_x = shift_x + speed_x
    shift_y = shift_y + speed_y

    gl.pushMatrix()
    gl.scale(0.95,0.95,1.0)
    gl.translate(shift_x,shift_y,0.0)

    util.draw_correct(CONFIG.logo.ensure_loaded(), 20, 20, 300, 120)
    if current_room then
        CONFIG.font:write(400, 20, current_room.name_short, 70, act_foreground.rgba())
    end
    CONFIG.font:write(850, 20, clock.get(), 70, act_foreground.rgba())
    -- font:write(WIDTH-300, 20, string.format("Day %d", day), 100, act_foreground.rgba())
    gl.popMatrix()

    local fov = math.atan2(HEIGHT, WIDTH*2) * 360 / math.pi
    gl.perspective(fov, WIDTH/2, HEIGHT/2, -WIDTH,
                        WIDTH/2, HEIGHT/2, 0)
    gl.pushMatrix()
    gl.scale(0.95,0.95,1.0)
    gl.translate(shift_x,shift_y,0.0)
    content.draw()
    gl.popMatrix()
end
