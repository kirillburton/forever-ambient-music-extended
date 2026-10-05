Put music you extracted from your own retail install here (.mp3 or .ogg,
subfolders are fine), then run:

    python3 tools/local_tracks.py

That writes the entries into ../LocalTracks.lua with real durations and a
first-pass tag guess from each file name. Fix the tags there, then restart the
client -- it indexes addon files at launch, so a /reload is not enough.

This folder ships empty on purpose. No Blizzard audio is bundled with or
distributed by this addon. See the README in the project root for the
extraction steps.
