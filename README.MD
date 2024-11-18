# Last.fm Scrobbler for MPV Player

## Project Description
This project is a Last.fm scrobbler designed for the MPV media player. It enables users to scrobble tracks played in MPV to their Last.fm account.

## Configuration
The scrobbler is configured using a file named `lastfm.conf`. Below are the key configuration options:

- **username**: Your Last.fm username. Run `scrobbler add-user` to set this up.
- **scrobble_paths**: A comma-separated list of file paths or folders from which to scrobble media. Only tracks from these paths will be scrobbled.
- **scrobble_threshold**: The percentage of a track that must be played before it is scrobbled (e.g., 50 for halfway).
- **artist_blacklist**: A comma-separated list of artists whose tracks should not be scrobbled.
- **track_blacklist**: A comma-separated list of track titles that should not be scrobbled.
- **fuzzy_metadata_search**: Controls whether to perform a fuzzy search for artist and album names based on the filename. Options are `yes`, `no`, or `cue`.
- **enforce_overrides**: If set to `yes`, metadata from a separate `.override` file will take precedence over other sources.

For more information, read the example `lastfm.conf` file, as everything is well documented there.

## Installation
1. **Download the Repository**: Clone or download the repository from GitHub.
2. **Copy Files**: Place the `scrobble` folder into the MPV scripts directory and the `last.fm` folder into the script options directory:
   - **For Windows**: 
     - Copy `scrobble` to `C:\Users\<YourUsername>\AppData\Roaming\mpv\scripts\`
     - Copy `last.fm` to `C:\Users\<YourUsername>\AppData\Roaming\mpv\script-opts\`
   - **For Unix/Linux**: 
     - Copy `scrobble` to `~/.config/mpv/scripts/`
     - Copy `last.fm` to `~/.config/mpv/script-opts/`
3. **Run the Following Command**: After placing the files, run the following command to add your Last.fm user:
   ```
   scrobbler add-user
   ```

## Usage
To utilize the override feature, create a shortcut in your `input.conf`:
```
O script-binding scrobble/create-override
```