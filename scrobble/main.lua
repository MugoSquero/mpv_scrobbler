-- An over-engineered last.fm scrobbler for mpv player
-- last.fm scrobbler for mpv
-- derived from https://github.com/l29ah/w3crapcli/blob/master/last.fm/mpv-lastfm.lua
--
-- Usage:
-- put this file in ~/.config/mpv/scripts/scroble/
-- put lastfm.conf in ~/.config/mpv/script-opts/
-- put https://github.com/hauzer/scrobbler somewhere in your PATH
-- run `scrobbler add-user` and follow the instructions
-- create a shortcut for overrides in input.conf if you want to use this feature (e.g., O script-binding scrobble/create-override)

-- TODO(squero): LOVE TRACK /w uosc support!!
-- TODO(squero): skip scrobbling current track with a key press (what about now-playing?)
-- TODO(squero): Support video formats for music videos (partially)

local mp = require 'mp'
local utils = require 'mp.utils'
require 'mp.options'
dkjson = require("lib/dkjson")

local options = {
    username = "change username in script-opts/lastfm.conf",
    scrobble_paths = "change scrobble_paths in script-opts/lastfm.conf",
    scrobble_threshold = "change scrobble_threshold in script-opts/lastfm.conf",
    artist_blacklist = "change artist_blacklist in script-opts/lastfm.conf",
    track_blacklist = "change track_blacklist in script-opts/lastfm.conf",
    fuzzy_metadata_search = "change fuzzy_metadata_search in script-opts/lastfm.conf",
    enforce_overrides = false,
    only_album_artist = "change only_album_artist in script-opts/lastfm.conf"
}

read_options(options, 'lastfm')

function trim(s)
    return s:match("^%s*(.-)%s*$")
end

function contains(text, substring)
    return string.find(text, substring) ~= nil
end

function starts_with(str, prefix)
    return string.sub(str, 1, string.len(prefix)) == prefix
end

function parseCSV(input)
    local result = {}
    for element in string.gmatch(input, '([^,]+)') do
        table.insert(result, trim(element))
    end
    return result
end

function escape_pattern(str)
    return str:gsub("([%.%+%-%*%?%[%]%(%)%$%^%{%}])", "%%%1")
end

function remove_substring(input, toRemove)
    -- Use gsub to replace the substring with an empty string
    return input:gsub(escape_pattern(toRemove), "")
end

function normalize_path(input)
    return mp.command_native({"normalize-path", input})
end

function get_file_extension(filename)
    return filename and filename:match("%.([^%.]+)$") or "No file path available"
end

function is_absolute_path(path)
    -- Check for Windows absolute path (e.g., C:\path\to\file)
    if path:gsub("/", "\\"):match("^[a-zA-Z]:\\") then
        return true
    end

    -- Check for Unix-like absolute path (e.g., /path/to/file)
    if path:sub(1, 1) == "/" then
        return true
    end

    return false
end

function get_absolute_path(path, filename)
    local absolute_path = nil

    if is_absolute_path(path) then
        absolute_path = path
    else
        absolute_path = normalize_path(mp.get_property("working-directory") .. "/" .. mp.get_property("path"))
    end

    return remove_substring(absolute_path, filename)
end

function createFile(path, filename, content)
    local filePath = path .. '/' .. filename
    
    -- Check if the file already exists
    local file = io.open(filePath, "r")
    if file then
        file:close()
        return false, "Error: File already exists."
    end

    -- Create and write to the file
    file = io.open(filePath, "w")
    if file then
        file:write(content)
        file:close()
        return true
    else
        return false, "Error: Unable to create file."  -- Return false if there was an error
    end
end

function get_meta_table(property)
    if mp.get_property(property .. "/list/count") then
        local m = {}
        for i = 0, mp.get_property(property .. "/list/count") - 1 do
            local p = property .. "/list/"..i.."/"
            m[mp.get_property(p.."key")] = mp.get_property(p.."value")
        end
        return m
    end
    return
end

function subprocess(args)
    local cmd = {
        name = "subprocess",
        args = args,
        playback_only = false,
        capture_stdout = true
    }
    local res = mp.command_native(cmd)
    if not res.error then
        return res.stdout
    else
        msg.error("Error getting data from stdout")
        return
    end
end

-- Function to scrobble the current track
local function scrobble()
    mp.msg.info(string.format("Scrobbling current track: %s - %s [%s]", artist, title, album))
    mp.osd_message(string.format("Scrobbling current track: %s - %s [%s]", artist, title, album))

    local result = subprocess({ "scrobbler", "scrobble", string.format("--album=%s", album), string.format("--duration=%ds", length), "--", options.username, artist, title, song_play_time })

    if not result or #result == 0 then
        mp.msg.error("Scrobble command failed: No output received.")
    else
        mp.msg.info("Scrobble command executed successfully: " .. result)
    end
end

function scrobble_blacklist_check(metadata, blacklist)
    local skip_scrobble = false

    for _, element in ipairs(blacklist) do
        if element == nil or #element == 0 then
            goto continue
        end
        if metadata ~= element then
            goto continue
        else
            mp.msg.warn(string.format("%s is in blacklist, skipping scrobbling.", element))
            skip_scrobble = true
            break
        end
        ::continue::
    end

    return skip_scrobble
end

function enqueue() -- Implement blacklisting here
    if artist and title then
        if #options.artist_blacklist > 0 then
            if scrobble_blacklist_check(artist, parseCSV(options.artist_blacklist)) then return end
        elseif #options.track_blacklist > 0 then
            if scrobble_blacklist_check(title, parseCSV(options.track_blacklist)) then return end
        end
        if tim then tim.kill(tim) end
        if length then
            timeout = math.min(240, length / (100 / tonumber(options.scrobble_threshold)))
        else
            timeout = 240
        end
        if last_playing_track ~= artist .. title then 
            mp.msg.info(string.format("Now playing: %s - %s [%s]", artist, title, album))
            mp.osd_message(string.format("Now playing: %s - %s [%s]", artist, title, album))
            local result = subprocess({ "scrobbler", "now-playing", string.format("--album=%s", album), string.format("--duration=%ds", length), "--", options.username, artist, title })
        end
        last_playing_track = artist .. title
        tim = mp.add_timeout(timeout, scrobble)
    else
        mp.msg.error("No metadata was found.")
    end
end

function on_pause_change(name, value)
    if value == true and tim then
        tim:stop() -- stop the timer when paused
    end

    if value == false and tim then
        tim:resume() -- resume the timer when played
    end
end

function parse_artist_work(input)
    -- Use string.match to capture the artist and album
    local artist, album = input:match("^(.-)%s*-%s*(.+)$")
    
    -- Check if both artist and album were found
    if artist and album then
        return artist, album
    else
        return nil, nil -- Return nil if the format is incorrect
    end
end

function scrobble_whitelist_check(track_path, scrobble_paths)
    local should_scrobble = false

    for _, ipath in ipairs(scrobble_paths) do
        if ipath == nil or #ipath == 0 then
            goto continue
        end
        if is_absolute_path(ipath) then
            if not starts_with(track_path, normalize_path(ipath)) then
                goto continue
            else
                should_scrobble = true
                break
            end
        else
            if not contains(track_path, ipath) then
                goto continue
            else
                should_scrobble = true
                break
            end
        end
        ::continue::
    end
    return should_scrobble
end

function table_includes(table, value)
    for _, v in ipairs(table) do
        if v == value then  -- Check if the current value matches the target value
            return true
        end
    end
    return false
end

function read_file(filePath)
    local file, err = io.open(filePath, "r")  -- Open the file in read mode
    if not file then
        return nil, "Error opening file: " .. err  -- Return nil and error message if file cannot be opened
    end

    local content = file:read("*all")  -- Read the entire content of the file
    file:close()  -- Close the file
    return content  -- Return the content of the file
end

function modify_metadata(override_json)
    if #override_json["artist"] > 0 then
        artist = override_json["artist"]
    end

    if #override_json["album"] > 0 then
        album = override_json["album"]
    end

    if #override_json["title"] > 0 then
        title = override_json["title"]
    end
end

function new_track(name)
    local path = mp.get_property("path")
    local filename = mp.get_property("filename")
    local filename_no_ext = mp.get_property("filename/no-ext")
    local filtered_metadata = get_meta_table("filtered-metadata")
    local metadata = get_meta_table("metadata")

    skip_path_check = nil

    if filename == nil then
        return
    end


    if skip_path_check ~= filename then
        if #options.scrobble_paths > 0 then
    
            track_path = get_absolute_path(path, filename)
            local scrobble_paths = parseCSV(options.scrobble_paths)
    
            -- Check if media path is in whitelist
            if not scrobble_whitelist_check(track_path, scrobble_paths) then
                mp.msg.warn("Path is not in allow list, skipping scrobbling.")
                return
            end

            skip_path_check = filename
        end

    end
    -- Mark the scrobble time of the track
    song_play_time = os.date("%Y-%m-%d.%H:%M")

    file_extension = get_file_extension(filename)

    --options.enforce_overrides
    local override_file = filename_no_ext .. ".override"
    local files_in_directory = utils.readdir(track_path, "files")
    if table_includes(files_in_directory, override_file) then
        local file_content = read_file(override_file)
        override_json = utils.parse_json(file_content)
        modify_metadata(override_json)
    end

    -- fuzzy_metadata_search
    fuzzy_metadata_search = options.fuzzy_metadata_search
    if #fuzzy_metadata_search > 0 and fuzzy_metadata_search ~= "no" then
        if fuzzy_metadata_search == "yes" then
            artist, album = parse_artist_work(filename_no_ext)
        elseif fuzzy_metadata_search == "cue" then
            if file_extension == "cue" then
                artist, album = parse_artist_work(filename_no_ext)
            end
        end
    end

    if file_extension == "cue" or file_extension == "mkv" then
        local chapter_count = tonumber(mp.get_property("chapter-list/count"))
        local chapter_index = mp.get_property("chapter")
        if chapter_index == nil then
            return
        end

        if chapter_index == -1 or chapter_index == "-1" then
            return
        end
        chapter_index = tonumber(chapter_index)

        if override_json then
            modify_metadata(override_json["chapters"][tostring(chapter_index)])
        end

        if chapter_index+1 < chapter_count then
            local next_chapter_starts = mp.get_property(string.format("chapter-list/%d/time", chapter_index+1))
            local this_chapter_starts = mp.get_property(string.format("chapter-list/%d/time", chapter_index))
            length = next_chapter_starts - this_chapter_starts
        else
            local duration = mp.get_property("duration")
            local this_chapter_starts = mp.get_property(string.format("chapter-list/%d/time", chapter_index))
            length = duration - this_chapter_starts
        end
        chapter_metadata = get_meta_table("chapter-metadata")
        title = chapter_metadata["title"]
        artist = chapter_metadata["performer"] and chapter_metadata["performer"] or artist

        if not artist and filtered_metadata == nil then
            mp.msg.error("No metadata was found.")
            return
        end

        if filtered_metadata ~= nil then
            if not artist then
                artist = filtered_metadata["Artist"]
            end
            if not album then
                album = filtered_metadata["Album"]
            end
        end

        if override_json then
            if (override_json["enforce_overrides"] == "yes") or (override_json["enforce_overrides"] == "default" and options.enforce_overrides) then
                modify_metadata(override_json)
                modify_metadata(override_json["chapters"][tostring(chapter_index)])
            end
        end
    else
        length = mp.get_property("duration")
    
        if metadata == nil and not override_json then
            -- mp.msg.error("No metadata was found.")
            return
        end
    
        local icy = metadata["icy-title"]
        if icy then
            artist, title = parse_artist_work(icy)
            album = nil
        else
            if length and tonumber(length) < 30 then return end -- last.fm doesn't allow scrobbling short tracks
            artist = filtered_metadata["Artist"]
            album_artist = filtered_metadata["Album_Artist"]

            if album_artist then
                if #options.only_album_artist > 0 then
                    if options.only_album_artist == "yes" or options.only_album_artist == "must" then
                        artist = album_artist
                    end
                end
            else
                if options.only_album_artist == "must" then
                    mp.msg.warn("The Album_Artist metada was not found, Mustn't scrobble.")
                    return
                end
            end

            album = filtered_metadata["Album"]
            title = filtered_metadata["Title"]
        end
        if override_json then
            if (override_json["enforce_overrides"] == "yes") or (override_json["enforce_overrides"] == "default" and options.enforce_overrides) then
                modify_metadata(override_json)
            end
        end
    end
    enqueue()
end

function on_restart()
    audio_pts = mp.get_property("audio-pts")
    -- FIXME a better check for -loop'ing tracks
    if ((not audio_pts) or (tonumber(audio_pts) < 1)) then
        new_track()
    end
end

function prettify_json(input_table)
    -- Convert the table to a JSON string with pretty formatting
    local json_string, pos, err = dkjson.encode(input_table, { indent = true })
    
    -- Check for errors during encoding
    if err then
        return nil, "Error encoding JSON: " .. err
    end
    
    return json_string
end

function create_override()
    local path = mp.get_property("path")
    local filename = mp.get_property("filename")
    local filename_no_ext = mp.get_property("filename/no-ext")
    local override_file = filename_no_ext .. ".override"

    if filename == nil then
        mp.msg.error("No file has been loaded. Please try again in a moment")
        return
    end

    local file_extension = get_file_extension(filename)
    local absolute_path = get_absolute_path(path, filename)

    -- Create the JSON-like table
    local override = {
        enforce_overrides = "default",
        artist = "",
        album = "",
        title = ""
    }

    -- Only include chapters if the file extension is "cue"
    if file_extension == "cue" then
        local chapter_count = tonumber(mp.get_property("chapter-list/count"))
        override.chapters = {}
        
        -- Populate the chapters based on the chapter count
        for i = 0, chapter_count - 1 do
            override.chapters[tostring(i)] = {
                artist = "",
                album = "",
                title = ""
            }
        end
    end

    local override_json = prettify_json(override)
    createFile(absolute_path, override_file, override_json)
end

-- mp.observe_property("metadata/list/count", nil, new_track)
mp.register_event("file-loaded", new_track)
mp.observe_property("chapter", nil, new_track)
-- mp.register_event("playback-restart", on_restart)
mp.observe_property("pause", "bool", on_pause_change)
mp.add_key_binding(nil, 'create-override', create_override)
