-- An autonomous Last.fm scrobbler for mpv player
-- Directly communicates with the Last.fm 2.0 Web API using curl (no external Python/CLI dependencies).
--
-- Usage:
-- 1. Put this file in ~/.config/mpv/scripts/scrobble/main.lua (or ~/.config/mpv/scripts/scrobble.lua)
-- 2. Put lastfm.conf in ~/.config/mpv/script-opts/lastfm.conf
-- 3. Authenticate directly inside mpv using script bindings:
--    `script-binding scrobble/auth-start` and `script-binding scrobble/auth-finish`

local mp = require 'mp'
local utils = require 'mp.utils'
require 'mp.options'

local options = {
    api_key = "",
    api_secret = "",
    session_key = "",
    username = "",
    scrobble_paths = "",
    scrobble_threshold = 50,
    artist_blacklist = "",
    track_blacklist = "",
    fuzzy_metadata_search = "cue",
    enforce_overrides = false,
    only_album_artist = ""
}

read_options(options, 'lastfm')

--------------------------------------------------------------------------------
-- PURE LUA RFC 1321 MD5 IMPLEMENTATION
--------------------------------------------------------------------------------
local md5 = (function()
    local bit = _G.bit or _G.bit32
    local band, bor, bxor, bnot, rol, rshift, tobit

    if bit then
        band = bit.band
        bor = bit.bor
        bxor = bit.bxor
        bnot = bit.bnot
        rshift = bit.rshift
        tobit = bit.tobit or function(x)
            x = x % 4294967296
            if x >= 2147483648 then return x - 4294967296 else return x end
        end
        rol = bit.rol or bit.lrotate or function(x, n)
            return bor(bit.lshift(x, n), rshift(x, 32 - n))
        end
    else
        local MOD = 4294967296
        tobit = function(x) return x % MOD end
        band = function(a, b)
            local r, p = 0, 1
            a, b = a % MOD, b % MOD
            while a > 0 and b > 0 do
                local ra, rb = a % 2, b % 2
                if ra == 1 and rb == 1 then r = r + p end
                a, b = math.floor(a / 2), math.floor(b / 2)
                p = p * 2
            end
            return r
        end
        bor = function(a, b)
            local r, p = 0, 1
            a, b = a % MOD, b % MOD
            while a > 0 or b > 0 do
                local ra, rb = a % 2, b % 2
                if ra == 1 or rb == 1 then r = r + p end
                a, b = math.floor(a / 2), math.floor(b / 2)
                p = p * 2
            end
            return r
        end
        bxor = function(a, b)
            local r, p = 0, 1
            a, b = a % MOD, b % MOD
            while a > 0 or b > 0 do
                local ra, rb = a % 2, b % 2
                if ra ~= rb then r = r + p end
                a, b = math.floor(a / 2), math.floor(b / 2)
                p = p * 2
            end
            return r
        end
        bnot = function(a) return (MOD - 1) - (a % MOD) end
        rshift = function(a, n) return math.floor((a % MOD) / (2 ^ n)) end
        rol = function(a, n)
            a = a % MOD
            return ((a * (2 ^ n)) + math.floor(a / (2 ^ (32 - n)))) % MOD
        end
    end

    local K = {
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
    }

    local S = {
        7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
        5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
        4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
        6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21
    }

    for i = 1, 64 do
        K[i] = tobit(K[i])
    end

    return function(msg)
        msg = msg or ""
        local len = #msg
        local pad_len = (56 - (len + 1) % 64) % 64
        local bits = len * 8

        local bytes = {}
        for i = 1, len do
            bytes[i] = string.byte(msg, i)
        end
        bytes[len + 1] = 0x80
        for i = 1, pad_len do
            bytes[len + 1 + i] = 0x00
        end

        local low_bits = bits % 4294967296
        local high_bits = math.floor(bits / 4294967296)
        for i = 0, 3 do
            table.insert(bytes, math.floor(low_bits / (256 ^ i)) % 256)
        end
        for i = 0, 3 do
            table.insert(bytes, math.floor(high_bits / (256 ^ i)) % 256)
        end

        local a0 = tobit(0x67452301)
        local b0 = tobit(0xefcdab89)
        local c0 = tobit(0x98badcfe)
        local d0 = tobit(0x10325476)

        local total_bytes = #bytes
        for chunk = 1, total_bytes, 64 do
            local M = {}
            for j = 0, 15 do
                local idx = chunk + j * 4
                local w = bytes[idx] + bytes[idx + 1] * 256 + bytes[idx + 2] * 65536 + bytes[idx + 3] * 16777216
                M[j] = tobit(w)
            end

            local A, B, C, D = a0, b0, c0, d0

            for i = 0, 63 do
                local F, g
                if i <= 15 then
                    F = bor(band(B, C), band(bnot(B), D))
                    g = i
                elseif i <= 31 then
                    F = bor(band(D, B), band(bnot(D), C))
                    g = (5 * i + 1) % 16
                elseif i <= 47 then
                    F = bxor(B, bxor(C, D))
                    g = (3 * i + 5) % 16
                else
                    F = bxor(C, bor(B, bnot(D)))
                    g = (7 * i) % 16
                end

                local temp = tobit(A + F + K[i + 1] + M[g])
                A = D
                D = C
                C = B
                B = tobit(B + rol(temp, S[i + 1]))
            end

            a0 = tobit(a0 + A)
            b0 = tobit(b0 + B)
            c0 = tobit(c0 + C)
            d0 = tobit(d0 + D)
        end

        local function word_to_hex(w)
            local s = ""
            for i = 0, 3 do
                local b = band(rshift(w, i * 8), 0xFF)
                s = s .. string.format("%02x", b)
            end
            return s
        end

        return word_to_hex(a0) .. word_to_hex(b0) .. word_to_hex(c0) .. word_to_hex(d0)
    end
end)()

--------------------------------------------------------------------------------
-- STATE MANAGEMENT
--------------------------------------------------------------------------------
local state = {
    artist = nil,
    album = nil,
    title = nil,
    album_artist = nil,
    length = nil,
    track_start_time = nil,
    timer = nil,
    scrobbled = false,
    skipped = false,
    loved = false,
    last_playing_id = nil,
    current_uid = nil,
    session_key = nil,
    username = nil,
    auth_token = nil
}

local session_file = mp.command_native({"normalize-path", "~~/script-opts/lastfm_session.json"})
local cached_whitelist_paths = nil

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------
local function trim(s)
    return s and s:match("^%s*(.-)%s*$") or ""
end

local function is_url(path)
    return path and path:match("^%a%a+://") ~= nil
end

local function contains(text, substring)
    return text and substring and string.find(text, substring, 1, true) ~= nil
end

local function starts_with(str, prefix)
    return string.sub(str, 1, string.len(prefix)) == prefix
end

local function parse_csv(input)
    local result = {}
    if not input then return result end
    for element in string.gmatch(input, '([^,]+)') do
        local clean = trim(element)
        if #clean > 0 then
            table.insert(result, clean)
        end
    end
    return result
end

local function normalize_path(input)
    if not input then return "" end
    return mp.command_native({"normalize-path", input}) or input
end

local function is_absolute_path(path)
    if not path or #path == 0 then return false end
    if path:match("^[a-zA-Z]:[/\\]") then return true end
    if path:match("^\\\\[^\\]") or path:match("^//[^/]") then return true end
    if path:sub(1, 1) == "/" then return true end
    return false
end

local function get_file_dir(path)
    if not path or #path == 0 or is_url(path) then return "" end
    local abs_path = normalize_path(is_absolute_path(path) and path or utils.join_path(mp.get_property("working-directory", ""), path))
    local dir, _ = utils.split_path(abs_path)
    return dir
end

local function get_file_extension(filename)
    return filename and filename:match("%.([^%.]+)$") or ""
end

local function file_exists(file_path)
    if not file_path or #file_path == 0 or is_url(file_path) then return false end
    local f = io.open(file_path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function read_file(file_path)
    local f, err = io.open(file_path, "r")
    if not f then return nil, err end
    local content = f:read("*all")
    f:close()
    return content
end

local function json_stringify(val, indent)
    indent = indent or 0
    local indent_str = string.rep("  ", indent)
    local next_indent_str = string.rep("  ", indent + 1)
    local t = type(val)

    if t == "table" then
        local is_array = true
        local max_idx = 0
        for k, _ in pairs(val) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                is_array = false
                break
            end
            if k > max_idx then max_idx = k end
        end
        if is_array and max_idx == #val and max_idx > 0 then
            local items = {}
            for i = 1, #val do
                table.insert(items, next_indent_str .. json_stringify(val[i], indent + 1))
            end
            return "[\n" .. table.concat(items, ",\n") .. "\n" .. indent_str .. "]"
        elseif is_array and #val == 0 and not next(val) then
            return "{}"
        else
            local items = {}
            local keys = {}
            for k in pairs(val) do table.insert(keys, tostring(k)) end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local v = val[k] or val[tonumber(k)]
                local item = string.format('%s%q: %s', next_indent_str, k, json_stringify(v, indent + 1))
                table.insert(items, item)
            end
            return "{\n" .. table.concat(items, ",\n") .. "\n" .. indent_str .. "}"
        end
    elseif t == "string" then
        return string.format("%q", val):gsub("\n", "\\n")
    elseif t == "number" or t == "boolean" then
        return tostring(val)
    else
        return "null"
    end
end

--------------------------------------------------------------------------------
-- METADATA EXTRACTION HELPERS
--------------------------------------------------------------------------------
local function get_meta_table(property)
    local count = tonumber(mp.get_property(property .. "/list/count"))
    if not count or count <= 0 then return nil end
    local m = {}
    for i = 0, count - 1 do
        local p = property .. "/list/" .. i .. "/"
        local k = mp.get_property(p .. "key")
        local v = mp.get_property(p .. "value")
        if k and v then
            m[k] = v
            m[k:lower()] = v
        end
    end
    return m
end

local function get_meta_value(tbl, ...)
    if not tbl then return nil end
    local keys = { ... }
    for _, k in ipairs(keys) do
        if tbl[k] and #trim(tbl[k]) > 0 then
            return trim(tbl[k])
        end
        local lk = k:lower()
        if tbl[lk] and #trim(tbl[lk]) > 0 then
            return trim(tbl[lk])
        end
    end
    return nil
end

local function parse_artist_work(input)
    if not input then return nil, nil end
    local artist, work = input:match("^(.-)%s*-%s*(.+)$")
    if artist and work then
        return trim(artist), trim(work)
    end
    return nil, nil
end

local function modify_metadata(override)
    if type(override) ~= "table" then return end
    if override.artist and type(override.artist) == "string" and #trim(override.artist) > 0 then
        state.artist = trim(override.artist)
    end
    if override.album and type(override.album) == "string" and #trim(override.album) > 0 then
        state.album = trim(override.album)
    end
    if override.title and type(override.title) == "string" and #trim(override.title) > 0 then
        state.title = trim(override.title)
    end
end

--------------------------------------------------------------------------------
-- LAST.FM API CLIENT & AUTHENTICATION
--------------------------------------------------------------------------------
local function get_api_key()
    if options.api_key and #trim(options.api_key) > 0 then
        return trim(options.api_key)
    end
    return "b25b959554ed76058ac220b7b2e0a026"
end

local function get_api_secret()
    if options.api_secret and #trim(options.api_secret) > 0 then
        return trim(options.api_secret)
    end
    return "425b55975eed76058ac220b7b4e8a054"
end

local function load_session()
    if options.session_key and #trim(options.session_key) > 0 then
        state.session_key = trim(options.session_key)
        if options.username and #trim(options.username) > 0 then
            state.username = trim(options.username)
        end
        return
    end

    if file_exists(session_file) then
        local content = read_file(session_file)
        if content then
            local data = utils.parse_json(content)
            if data and data.session_key then
                state.session_key = data.session_key
                state.username = data.username or options.username
            end
        end
    end
end

local function save_session(sk, user)
    local data = {
        session_key = sk,
        username = user or ""
    }
    local json_str = json_stringify(data, 0)
    local f, err = io.open(session_file, "w")
    if f then
        f:write(json_str .. "\n")
        f:close()
        mp.msg.info("Last.fm session key saved to: " .. session_file)
        return true
    else
        mp.msg.error("Failed to write session file: " .. tostring(err))
        return false
    end
end

local function sign_parameters(params, secret)
    local keys = {}
    for k, _ in pairs(params) do
        if k ~= "format" and k ~= "callback" and k ~= "api_sig" then
            table.insert(keys, k)
        end
    end
    table.sort(keys)
    local str = ""
    for _, k in ipairs(keys) do
        str = str .. k .. tostring(params[k])
    end
    str = str .. secret
    return md5(str)
end

local function http_call(params, is_post, callback)
    local args = { "curl", "-s", "-S", "--connect-timeout", "10", "--max-time", "15" }
    local url = "https://ws.audioscrobbler.com/2.0/"

    if is_post then
        table.insert(args, "-X")
        table.insert(args, "POST")
    else
        table.insert(args, "-G")
    end
    table.insert(args, url)

    for k, v in pairs(params) do
        table.insert(args, "--data-urlencode")
        table.insert(args, string.format("%s=%s", k, tostring(v)))
    end

    mp.command_native_async({
        name = "subprocess",
        args = args,
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true
    }, function(success, res, err)
        if not success or not res then
            if callback then callback(false, nil, err or "Subprocess execution failed (curl missing from PATH?)") end
            return
        end
        if res.error or (res.status and res.status ~= 0) then
            local err_msg = res.stderr or res.error or ("Exit code " .. tostring(res.status))
            if callback then callback(false, nil, err_msg) end
            return
        end
        local parsed, _ = utils.parse_json(res.stdout)
        if not parsed then
            if callback then callback(false, nil, "Failed to parse Last.fm response: " .. tostring(res.stdout)) end
            return
        end
        if parsed.error then
            local err_text = string.format("Last.fm Error %s: %s", tostring(parsed.error), tostring(parsed.message or ""))
            if callback then callback(false, parsed, err_text) end
            return
        end
        if callback then callback(true, parsed, nil) end
    end)
end

local function open_url(url)
    local platform = mp.get_property_native("platform")
    local cmd = nil

    if platform == "windows" then
        -- Avoid cmd.exe which parses '&' as a command separator,
        -- truncating the URL at &token=... and throwing "'token' is not recognized".
        -- rundll32 url.dll,FileProtocolHandler invokes ShellExecute directly.
        cmd = { "rundll32", "url.dll,FileProtocolHandler", url }
    elseif platform == "darwin" then
        cmd = { "open", url }
    else
        cmd = { "xdg-open", url }
    end

    mp.command_native_async({
        name = "subprocess",
        args = cmd,
        playback_only = false
    }, function(success, res)
        if not success or (res and res.status ~= 0) then
            if platform == "windows" then
                -- Fallback to PowerShell with single-quoted URL if rundll32 fails
                mp.command_native_async({
                    name = "subprocess",
                    args = { "powershell", "-NoProfile", "-Command", "Start-Process", string.format("'%s'", url) },
                    playback_only = false
                }, function(ps_success, ps_res)
                    if not ps_success or (ps_res and ps_res.status ~= 0) then
                        mp.msg.warn("Could not open browser automatically. Please open this URL manually:\n" .. url)
                    end
                end)
            else
                mp.msg.warn("Could not open browser automatically. Please open this URL manually:\n" .. url)
            end
        end
    end)
end

local function auth_start()
    mp.osd_message("Last.fm: Requesting authentication token...", 4)
    local params = {
        method = "auth.getToken",
        api_key = get_api_key(),
        format = "json"
    }
    params.api_sig = sign_parameters(params, get_api_secret())

    http_call(params, false, function(ok, res, err)
        if not ok or not res or not res.token then
            mp.osd_message("Last.fm auth failed. Check console.", 5)
            mp.msg.error("Last.fm auth.getToken error: " .. tostring(err))
            return
        end

        state.auth_token = res.token
        local auth_url = string.format("https://www.last.fm/api/auth/?api_key=%s&token=%s", get_api_key(), state.auth_token)
        mp.msg.info("Last.fm Authorization URL: " .. auth_url)
        mp.osd_message("Last.fm: Authorize in browser, then trigger 'auth-finish'", 8)
        open_url(auth_url)
    end)
end

local function auth_finish()
    if not state.auth_token then
        mp.osd_message("Last.fm: Run 'auth-start' first!", 4)
        mp.msg.warn("No pending auth token found. Run 'auth-start' before completing authentication.")
        return
    end

    mp.osd_message("Last.fm: Completing authentication...", 3)
    local params = {
        method = "auth.getSession",
        api_key = get_api_key(),
        token = state.auth_token,
        format = "json"
    }
    params.api_sig = sign_parameters(params, get_api_secret())

    http_call(params, false, function(ok, res, err)
        if not ok or not res or not res.session then
            mp.osd_message("Last.fm auth failed: " .. tostring(err), 5)
            mp.msg.error("Last.fm auth.getSession error: " .. tostring(err))
            return
        end

        state.session_key = res.session.key
        state.username = res.session.name
        state.auth_token = nil
        save_session(state.session_key, state.username)
        mp.osd_message("Last.fm: Authenticated as " .. state.username .. "!", 5)
        mp.msg.info("Last.fm authenticated successfully as " .. state.username)
    end)
end

local function auth_status()
    if state.session_key then
        local user_str = state.username and (" as " .. state.username) or ""
        mp.osd_message("Last.fm: Authenticated" .. user_str, 4)
    else
        mp.osd_message("Last.fm: Not authenticated. Use 'auth-start'.", 4)
    end
end

--------------------------------------------------------------------------------
-- SCROBBLING, NOW PLAYING & LOVE TRACK
--------------------------------------------------------------------------------
local function scrobble()
    if state.skipped or state.scrobbled then
        return
    end
    if not state.artist or not state.title then
        mp.msg.warn("Scrobble skipped: Missing artist or title metadata.")
        return
    end
    if not state.session_key then
        mp.msg.warn("Scrobble skipped: Last.fm session key not found. Run 'auth-start' to authenticate.")
        return
    end

    -- Re-check duration in case it arrived after initial file load
    if not state.length or state.length <= 0 then
        local dur = tonumber(mp.get_property("duration"))
        if dur and dur > 0 then
            state.length = dur
        end
    end

    local params = {
        method = "track.scrobble",
        api_key = get_api_key(),
        sk = state.session_key,
        artist = state.artist,
        track = state.title,
        timestamp = tostring(state.track_start_time or os.time()),
        format = "json"
    }

    if state.album and #state.album > 0 then
        params.album = state.album
    end
    if state.album_artist and #state.album_artist > 0 then
        params.albumArtist = state.album_artist
    end
    if state.length and state.length > 0 then
        params.duration = tostring(math.floor(state.length))
    end

    params.api_sig = sign_parameters(params, get_api_secret())
    mp.msg.info(string.format("Scrobbling track: %s - %s [%s]", state.artist, state.title, state.album or ""))

    http_call(params, true, function(ok, res, err)
        if ok then
            state.scrobbled = true
            mp.msg.info(string.format("Scrobbled successfully: %s - %s [%s]", state.artist, state.title, state.album or ""))
            mp.osd_message(string.format("Scrobbled: %s - %s", state.artist, state.title), 3)
        else
            mp.msg.error("Scrobble request failed: " .. tostring(err))
        end
    end)
end

local function update_now_playing()
    if not state.artist or not state.title then return end
    if not state.session_key then return end

    local track_id = string.format("%s - %s", state.artist, state.title)
    if state.last_playing_id == track_id then
        return
    end
    state.last_playing_id = track_id

    mp.msg.info(string.format("Now playing: %s - %s [%s]", state.artist, state.title, state.album or ""))
    mp.osd_message(string.format("Now playing: %s - %s", state.artist, state.title), 3)

    local params = {
        method = "track.updateNowPlaying",
        api_key = get_api_key(),
        sk = state.session_key,
        artist = state.artist,
        track = state.title,
        format = "json"
    }

    if state.album and #state.album > 0 then
        params.album = state.album
    end
    if state.album_artist and #state.album_artist > 0 then
        params.albumArtist = state.album_artist
    end
    if state.length and state.length > 0 then
        params.duration = tostring(math.floor(state.length))
    end

    params.api_sig = sign_parameters(params, get_api_secret())

    http_call(params, true, function(ok, res, err)
        if not ok then
            mp.msg.warn("Failed to update now playing status: " .. tostring(err))
        end
    end)
end

local function love_track(unlove)
    if not state.artist or not state.title then
        mp.osd_message("Last.fm: No active track to love", 3)
        return
    end
    if not state.session_key then
        mp.osd_message("Last.fm: Not authenticated", 3)
        return
    end

    local method_name = unlove and "track.unlove" or "track.love"
    local params = {
        method = method_name,
        api_key = get_api_key(),
        sk = state.session_key,
        artist = state.artist,
        track = state.title,
        format = "json"
    }
    params.api_sig = sign_parameters(params, get_api_secret())

    http_call(params, true, function(ok, res, err)
        if ok then
            state.loved = not unlove
            local label = unlove and "♡ Unloved" or "♥ Loved"
            mp.osd_message(string.format("%s: %s - %s", label, state.artist, state.title), 3)
            mp.msg.info(string.format("%s track: %s - %s", method_name, state.artist, state.title))
        else
            mp.osd_message("Last.fm error: " .. tostring(err), 3)
            mp.msg.error(string.format("Failed to %s track: %s", method_name, tostring(err)))
        end
    end)
end

local function toggle_love_track()
    love_track(state.loved)
end

local function skip_scrobble()
    if state.timer then
        state.timer:kill()
        state.timer = nil
    end
    state.skipped = true
    mp.osd_message("Last.fm: Scrobble cancelled for current track", 3)
    mp.msg.info("Last.fm: Current track scrobble cancelled by user.")
end

--------------------------------------------------------------------------------
-- FILTERING & QUEUE LOGIC
--------------------------------------------------------------------------------
local function scrobble_blacklist_check(metadata, blacklist)
    if not metadata or not blacklist then return false end
    for _, element in ipairs(blacklist) do
        if #element > 0 and metadata == element then
            mp.msg.warn(string.format("'%s' matches blacklist entry, skipping scrobble.", element))
            return true
        end
    end
    return false
end

local function scrobble_whitelist_check(track_path, scrobble_paths)
    if #scrobble_paths == 0 then return true end
    local normalized_track_path = normalize_path(track_path)

    for _, ipath in ipairs(scrobble_paths) do
        if #ipath > 0 then
            if is_absolute_path(ipath) then
                local norm_ipath = normalize_path(ipath)
                if starts_with(normalized_track_path, norm_ipath) then
                    return true
                end
            else
                if contains(normalized_track_path, ipath) then
                    return true
                end
            end
        end
    end
    return false
end

local function enqueue()
    if not state.artist or not state.title then
        mp.msg.warn("Metadata incomplete (missing artist or title).")
        return
    end

    -- Decoupled blacklist checks
    if #options.artist_blacklist > 0 and scrobble_blacklist_check(state.artist, parse_csv(options.artist_blacklist)) then
        return
    end
    if #options.track_blacklist > 0 and scrobble_blacklist_check(state.title, parse_csv(options.track_blacklist)) then
        return
    end

    if state.timer then
        state.timer:kill()
        state.timer = nil
    end

    local threshold = tonumber(options.scrobble_threshold) or 50
    local timeout = 240
    if state.length and state.length > 0 then
        timeout = math.min(240, state.length * (threshold / 100))
    end

    update_now_playing()
    state.timer = mp.add_timeout(timeout, scrobble)
end

--------------------------------------------------------------------------------
-- TRACK & CHAPTER EVENTS
--------------------------------------------------------------------------------
local function new_track(force)
    local path = mp.get_property("path")
    local filename = mp.get_property("filename")
    local filename_no_ext = mp.get_property("filename/no-ext")

    if not filename or not path then
        if state.timer then
            state.timer:kill()
            state.timer = nil
        end
        state.current_uid = nil
        return
    end

    local track_dir = get_file_dir(path)

    -- Whitelist check (skip whitelist check for network streams)
    if #options.scrobble_paths > 0 and not is_url(path) then
        if not cached_whitelist_paths then
            cached_whitelist_paths = parse_csv(options.scrobble_paths)
        end
        if not scrobble_whitelist_check(track_dir, cached_whitelist_paths) then
            mp.msg.warn("Path not in scrobble allow list, skipping: " .. track_dir)
            return
        end
    end

    local file_extension = get_file_extension(filename):lower()
    local chapter_count = tonumber(mp.get_property("chapter-list/count")) or 0
    local raw_chapter = mp.get_property("chapter")
    local chapter_index = tonumber(raw_chapter)
    local is_chaptered = (file_extension == "cue" or file_extension == "mkv") and chapter_count > 0 and chapter_index and chapter_index >= 0

    -- Deduplicate firing between file-loaded and initial chapter observation,
    -- but allow replay/loop bypass when force == true (Issue #5)
    local current_uid = string.format("%s#%s", path, tostring(is_chaptered and chapter_index or "main"))
    if (force ~= true) and state.current_uid == current_uid then
        return
    end

    -- Reset playback state
    if state.timer then
        state.timer:kill()
        state.timer = nil
    end

    state.current_uid = current_uid
    state.artist = nil
    state.album = nil
    state.title = nil
    state.album_artist = nil
    state.length = nil
    state.scrobbled = false
    state.skipped = false
    state.loved = false
    state.track_start_time = os.time()

    if force then
        state.last_playing_id = nil
    end

    local filtered_metadata = get_meta_table("filtered-metadata")
    local metadata = get_meta_table("metadata")

    -- Load overrides if present (skip disk lookup for remote URLs, Issue #3)
    local override_json = nil
    if track_dir ~= "" and filename_no_ext and #filename_no_ext > 0 then
        local override_file = filename_no_ext .. ".override"
        local override_path = utils.join_path(track_dir, override_file)
        if file_exists(override_path) then
            local content = read_file(override_path)
            if content then
                override_json = utils.parse_json(content)
            end
        end
    end

    -- Determine enforce_overrides policy
    local enforce = false
    if override_json and type(override_json) == "table" then
        if override_json.enforce_overrides == "yes" or override_json.enforce_overrides == true then
            enforce = true
        elseif override_json.enforce_overrides == "default" then
            enforce = (options.enforce_overrides == true or options.enforce_overrides == "yes")
        end
    end

    -- Fuzzy metadata extraction from filename
    local fuzzy_mode = options.fuzzy_metadata_search
    if fuzzy_mode == "yes" or (fuzzy_mode == "cue" and file_extension == "cue") then
        local f_artist, f_album = parse_artist_work(filename_no_ext)
        if f_artist and f_album then
            state.artist = f_artist
            state.album = f_album
        end
    end

    if is_chaptered then
        if chapter_index + 1 < chapter_count then
            local next_start = tonumber(mp.get_property(string.format("chapter-list/%d/time", chapter_index + 1))) or 0
            local this_start = tonumber(mp.get_property(string.format("chapter-list/%d/time", chapter_index))) or 0
            state.length = next_start - this_start
        else
            local duration = tonumber(mp.get_property("duration")) or 0
            local this_start = tonumber(mp.get_property(string.format("chapter-list/%d/time", chapter_index))) or 0
            state.length = duration - this_start
        end

        local chapter_metadata = get_meta_table("chapter-metadata")
        state.title = get_meta_value(chapter_metadata, "title") or mp.get_property(string.format("chapter-list/%d/title", chapter_index))
        state.artist = get_meta_value(chapter_metadata, "performer", "artist") or state.artist

        if filtered_metadata then
            state.artist = state.artist or get_meta_value(filtered_metadata, "artist")
            state.album = state.album or get_meta_value(filtered_metadata, "album")
        end

        if override_json then
            modify_metadata(override_json)
            if override_json.chapters and override_json.chapters[tostring(chapter_index)] then
                modify_metadata(override_json.chapters[tostring(chapter_index)])
            end
        end
    else
        state.length = tonumber(mp.get_property("duration"))
        if metadata == nil and not override_json then
            return
        end

        local icy = get_meta_value(metadata, "icy-title")
        if icy then
            state.artist, state.title = parse_artist_work(icy)
            state.album = nil
        else
            if state.length and state.length < 30 then
                mp.msg.info("Track is shorter than 30 seconds, skipping scrobble.")
                return
            end

            state.artist = get_meta_value(filtered_metadata, "artist")
            state.album_artist = get_meta_value(filtered_metadata, "album_artist", "albumartist")
            state.album = get_meta_value(filtered_metadata, "album")
            state.title = get_meta_value(filtered_metadata, "title")

            if state.album_artist then
                if options.only_album_artist == "yes" or options.only_album_artist == "must" then
                    state.artist = state.album_artist
                end
            else
                if options.only_album_artist == "must" then
                    mp.msg.warn("Album_Artist metadata not found and only_album_artist=must. Skipping.")
                    return
                end
            end
        end

        if override_json then
            if enforce then
                modify_metadata(override_json)
            else
                if not state.artist then state.artist = override_json.artist end
                if not state.album then state.album = override_json.album end
                if not state.title then state.title = override_json.title end
            end
        end
    end

    enqueue()
end

local function on_pause_change(name, value)
    if not state.timer then return end
    if value == true then
        state.timer:stop()
    else
        state.timer:resume()
    end
end

-- Position-aware loop and rewind detection (Issue #5)
local function on_restart()
    local pos = mp.get_property_number("time-pos") or mp.get_property_number("audio-pts")
    if not pos or pos >= 2.0 then return end

    if state.scrobbled then
        -- Track finished, scrobbled, and looped back to 0.0
        mp.msg.info("Loop detected: resetting scrobble state for re-scrobbling.")
        new_track(true)
    elseif state.track_start_time and (os.time() - state.track_start_time) > 5 then
        -- Track rewound back to the beginning before scrobbling
        mp.msg.info("Rewind to start detected: resetting scrobble countdown.")
        new_track(true)
    end
end

--------------------------------------------------------------------------------
-- OVERRIDE CREATOR HELPER
--------------------------------------------------------------------------------
local function create_override()
    local path = mp.get_property("path")
    local filename = mp.get_property("filename")
    local filename_no_ext = mp.get_property("filename/no-ext")

    if not path or not filename then
        mp.osd_message("Last.fm: No file currently loaded", 3)
        mp.msg.error("No file is currently loaded. Cannot create override template.")
        return
    end

    if is_url(path) then
        mp.osd_message("Last.fm: Overrides not supported for stream URLs", 3)
        mp.msg.warn("Cannot create override file for stream URLs.")
        return
    end

    local track_dir = get_file_dir(path)
    local override_filename = filename_no_ext .. ".override"
    local override_path = utils.join_path(track_dir, override_filename)

    if file_exists(override_path) then
        mp.osd_message("Override file already exists", 3)
        mp.msg.warn("Override file already exists: " .. override_path)
        return
    end

    local file_extension = get_file_extension(filename):lower()
    local override = {
        enforce_overrides = "default",
        artist = state.artist or "",
        album = state.album or "",
        title = state.title or ""
    }

    local chapter_count = tonumber(mp.get_property("chapter-list/count")) or 0
    if (file_extension == "cue" or file_extension == "mkv") and chapter_count > 0 then
        override.chapters = {}
        for i = 0, chapter_count - 1 do
            local ch_title = mp.get_property(string.format("chapter-list/%d/title", i)) or ""
            override.chapters[tostring(i)] = {
                artist = "",
                album = "",
                title = ch_title
            }
        end
    end

    local json_content = json_stringify(override, 0)
    local f, err = io.open(override_path, "w")
    if f then
        f:write(json_content .. "\n")
        f:close()
        mp.osd_message("Created override: " .. override_filename, 4)
        mp.msg.info("Created override template at: " .. override_path)
    else
        mp.osd_message("Failed to create override file", 4)
        mp.msg.error("Failed to write override file: " .. tostring(err))
    end
end

--------------------------------------------------------------------------------
-- INITIALIZATION & EVENT LISTENERS
--------------------------------------------------------------------------------
-- Explicit event wrappers to prevent mpv argument passing bugs (Issue #3)
local function handle_file_loaded()
    new_track(false)
end

local function handle_chapter_change(name, value)
    local path = mp.get_property("path")
    if not path or not value or value < 0 then return end
    new_track(false)
end

load_session()

mp.register_event("file-loaded", handle_file_loaded)
mp.observe_property("chapter", "number", handle_chapter_change)
mp.observe_property("pause", "bool", on_pause_change)
mp.register_event("playback-restart", on_restart)

-- Keybindings & uosc bindings
mp.add_key_binding(nil, "auth-start", auth_start)
mp.add_key_binding(nil, "auth-finish", auth_finish)
mp.add_key_binding(nil, "auth-status", auth_status)
mp.add_key_binding(nil, "love-track", function() love_track(false) end)
mp.add_key_binding(nil, "unlove-track", function() love_track(true) end)
mp.add_key_binding(nil, "toggle-love-track", toggle_love_track)
mp.add_key_binding(nil, "skip-scrobble", skip_scrobble)
mp.add_key_binding(nil, "create-override", create_override)