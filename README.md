# Last.fm Scrobbler for MPV Player

A standalone, lightweight, and asynchronous Last.fm scrobbler for the [mpv media player](https://mpv.io).

It communicates directly and asynchronously with the Last.fm 2.0 Web API using `curl` and an embedded pure Lua MD5 signature engine.

---

## Features

- **No External Scrobbler Binaries:** Works natively with mpv and system `curl`.
- **Asynchronous Execution:** Background HTTP calls ensure zero video drops or audio stutter.
- **In-App Authentication:** Authorize your Last.fm account directly inside mpv without touching a terminal.
- **Now Playing & Scrobbling:** Instant "Now Playing" notifications and accurate threshold-based scrobbles.
- **Full Loop Support:** Automatically detects looped tracks (`--loop-file`) and rewinds to re-trigger both the "Now Playing" status and a fresh scrobble timer.
- **Love / Unlove Tracks:** Favorite tracks directly while listening (fully compatible with [uosc](https://github.com/tomasklaen/uosc) menus).
- **Skip Scrobble:** Cancel the scrobble timer for the current track with one keypress.
- **Metadata Overrides & CUE Support:** Create `.override` JSON templates to fix mistagged files or chaptered CUE sheets without touching original files.
- **Whitelists & Blacklists:** Filter scrobbling by media directory, artist name, or track title.

---

## Installation

### 1. Place the Script and Config

- **Linux / macOS (`~/.config/mpv/`):**
  ```bash
  mkdir -p ~/.config/mpv/scripts/scrobble ~/.config/mpv/script-opts
  cp main.lua ~/.config/mpv/scripts/scrobble/main.lua
  cp lastfm.conf ~/.config/mpv/script-opts/lastfm.conf
  ```

- **Windows (`%APPDATA%\mpv\`):**
  - Place `main.lua` in `%APPDATA%\mpv\scripts\scrobble\main.lua`
  - Place `lastfm.conf` in `%APPDATA%\mpv\script-opts\lastfm.conf`

> **Note:** `curl` must be available in your system `PATH` (included by default in modern Windows, macOS, and Linux).

---

## Authentication

1. Add the authentication shortcuts to your `input.conf`:
```ini
  ctrl+a script-binding scrobble/auth-start
   ctrl+f script-binding scrobble/auth-finish
```
2. Play any track in mpv and press `ctrl+a` (or run `script-binding scrobble/auth-start` in the mpv console).
3. Your default web browser will open to Last.fm. Click **Allow Access**.
4. Return to mpv and press `ctrl+f` (or run `script-binding scrobble/auth-finish`).
5. A confirmation message will appear on the OSD, and your session key will be automatically saved to `script-opts/lastfm_session.json`.

---

## Keybindings (`input.conf`)

Add these recommended shortcuts to your `~/.config/mpv/input.conf`:

```ini
# Last.fm Playback Controls
L       script-binding scrobble/toggle-love-track   # Love / Unlove current track
ctrl+s  script-binding scrobble/skip-scrobble       # Cancel scrobbling current track
O       script-binding scrobble/create-override     # Create .override JSON template

# Authentication
ctrl+a  script-binding scrobble/auth-start          # Start OAuth web login
ctrl+f  script-binding scrobble/auth-finish         # Complete authentication
ctrl+S  script-binding scrobble/auth-status         # Authentication status
```

### uosc Integration

#### 1. Add to uosc Menu (`input.conf`)
uosc builds its context menu by parsing `#!` comments in `input.conf`:
```ini
# Items in a "Last.fm" submenu
L      script-binding scrobble/toggle-love-track #! Last.fm > Toggle Love track
ctrl+s script-binding scrobble/skip-scrobble     #! Last.fm > Skip scrobble
O      script-binding scrobble/create-override   #! Last.fm > Create override template
```

#### 2. Add to uosc Control Bar (`uosc.conf`)
To add dedicated buttons to the proximity control bar above the timeline, insert them into the `controls` property in `script-opts/uosc.conf`:
```ini
# Adds Love (heart) and Skip buttons to the control bar
controls=...,command:favorite:script-binding scrobble/toggle-love-track?Toggle Love track,command:skip_next:script-binding scrobble/skip-scrobble?Skip scrobble,...
```

---

## Configuration (`lastfm.conf`)

Adjust settings in `~/.config/mpv/script-opts/lastfm.conf`:

| Option | Default | Description |
| :--- | :--- | :--- |
| `scrobble_threshold` | `50` | Percentage of track played before submitting scrobble (min 30s). |
| `scrobble_paths` | `""` | Comma-separated paths/folder names to whitelist. Empty allows all. |
| `artist_blacklist` | `""` | Comma-separated list of artist names to ignore. |
| `track_blacklist` | `""` | Comma-separated list of track titles to ignore. |
| `fuzzy_metadata_search` | `cue` | Parse `"Artist - Album"` from filename (`yes`, `no`, `cue`). |
| `only_album_artist` | `no` | Prioritize `Album_Artist` tags (`yes`, `no`, `must`). |
| `enforce_overrides` | `no` | Force `.override` values to supersede embedded tags (`yes`, `no`). |
| `api_key` | `""` | Custom Last.fm API key (optional; defaults to built-in key). |
| `api_secret` | `""` | Custom Last.fm API secret (optional; defaults to built-in secret). |

---

## Metadata Overrides

To override tags without altering your audio files:
1. Press `O` (`create-override`) during playback.
2. A `<filename>.override` template is generated in the media directory.
3. Edit the JSON file to override the `artist`, `album`, or `title`:
```json
{
  "artist": "Correct Artist",
  "album": "Correct Album",
  "title": "Correct Title",
  "enforce_overrides": "yes"
}
```
For CUE sheets, individual chapter indexes (`"0"`, `"1"`, etc.) can be overridden under the `"chapters"` key.
