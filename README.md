<p align="center">
  <img src="art/fame-logo-512.png" alt="FAME logo" width="200">
</p>

# Forever Ambient Music Extended (FAME)

An addon for **World of Warcraft: Forever** that widens the zone music
rotation. The game's own rhythm is kept exactly: the same silences between
tracks, the same intros, its own tracks still in the mix. Some of those
tracks now come from a pool of **425 more**, each chosen to fit where you're
standing. They're drawn from Classic pieces Forever doesn't use in those
zones, the new Forever soundtrack, and selections from Cataclysm through
Midnight.

There's no UI and nothing to set up. It sounds like the default ambient
music, with more variety.

**No Blizzard audio is bundled with or distributed by this addon.** Every
track it plays is a file your Forever client already has.

- [For players](#for-players): install, what to expect, commands
- [For developers](#for-developers): how tracks are chosen, the data
  pipeline, tests, releases

---

# For players

## Install

1. Download the latest zip from
   [Releases](https://github.com/kirillburton/forever-ambient-music-extended/releases)
   (or from CurseForge).
2. Extract the `ForeverAmbientMusicExtended` folder into
   `World of Warcraft/_forever_/Interface/AddOns/`.
3. **Restart the client.** It indexes addon files at launch, so `/reload`
   isn't enough.
4. Log in. There's nothing to configure.

To check that it loaded, type `/fame status`.

## What to expect

- **The same silences.** Between tracks FAME waits as long as the game would
  in that place, taken from the game's own data: three to five minutes in
  most zones, with separate day and night values where the game has them.
- **Loop Music is respected.** With **Loop Music** on in the Audio options,
  tracks play back to back, as the game's would.
- **The game's own music stays in the mix.** About 40% of tracks are the
  game's own picks for that place, and the first track when you arrive
  somewhere is always one of them. You can change both (see
  [Commands](#commands)).
- **Intros still play.** Orgrimmar's fanfare, the Ironforge King theme and
  the rest open their areas on the game's own cooldowns.
- **Subzones switch music where the game would.** Walking into the Crossroads
  switches to the Crossroads music. Moving between two places that share
  music keeps the current track going.
- **Inns play their own race's tavern music:** dwarven songs in Thunderbrew
  Distillery, human ones in the Lion's Pride, sea shanties in Booty Bay's
  Salty Sailor. An inn whose race isn't known is left to the game.
- **Settlements and coves get their own music.** Goblin music plays only in
  goblin towns (Ratchet, Booty Bay, Gadgetzan, Steamwheedle Port, Everlook),
  and pirate music only there and in the pirate coves.
- **Tracks fade** rather than cut off, and the same track never plays twice
  in a row.
- **Some places are left entirely to the game:** dungeons, raids,
  battlegrounds, being dead or walking back to your corpse, ships on the
  open sea, and anywhere you've turned music off. FAME steps aside there and
  the game's own music plays as normal.

Nothing should turn up out of place: a track only plays where every one of
its tags is welcome (see [How a track gets chosen](#how-a-track-gets-chosen)).
A zone with nothing suitable plays only the game's own music rather than
reaching for something that doesn't fit.

### Coverage

All 46 Classic zones and cities, plus the new Forever zones: Mount Hyjal,
Riverglades, Shen'dralas, Darkspear Islands and Zephras Isle. Most zones
have 20–60 extended tracks to draw from.

## Commands

Everything is under `/fame`. `/fame help` lists the commands with each
setting's current value.

| Everyday | |
|---|---|
| `/fame status` | what's playing, how far in, and what comes next |
| `/fame skip` | end this track the way it would end anyway: into the usual silence, or straight to the next track with Loop Music on |
| `/fame next` | play an extended track now |
| `/fame ban` | stop this track and never play it again |
| `/fame banlist` | your banned tracks, with the zone each was banned in |
| `/fame unban <id>` \| `all` | allow one banned track again, or all of them |
| `/fame chance <0-100>` | share of tracks that are the game's own (default 40) |
| `/fame first` | let a new place open with an extended track (off by default) |
| `/fame on` \| `off` \| `toggle` | run FAME, or leave the music to the game |

| Troubleshooting | |
|---|---|
| `/fame where` | where FAME thinks you are, which music set applies, silences, Loop Music, volume |
| `/fame pool [n]` | the extended tracks that fit here |
| `/fame play <id>` | play a track by its file ID |
| `/fame scan <id> …` | check which file IDs your client has |
| `/fame debug` | print every decision to chat |

### Banning tracks

`/fame ban` works on anything that's playing: the game's own track, an
extended one or an intro. Bans are per track, so a banned track is gone
everywhere. Banned tracks are filtered out before every pick, so the next
track is always one you allow.

If you ban everything a place could play, FAME plays nothing there and tells
you so in chat. `/fame unban` brings music back immediately.

Bans don't apply where FAME leaves the music to the game (dungeons, raids,
death, the open sea), because there the game picks.

## Other addons

FAME fades tracks by moving the music volume slider, as some other addons
do. It's written to share the slider. If anything else moves it mid-fade,
FAME stops fading and leaves it alone. With
[Spoken Quests](https://github.com/rusty-key/spoken-wow), FAME doesn't touch
the slider at all while Spoken has the music turned down for a line. Your
volume always ends up where you set it.

## Known limitations

- **Settings may not survive a logout on some builds.** Some Forever builds
  write saved variables but don't load them back. If so, settings and bans
  last until you log out. FAME tells you once if it detects this. The
  defaults are what the addon is tuned for.
- **Inns are recognised by their English names.** On other client languages,
  inns fall back to the game's own music. Everything else works in any
  language.
- **Interface version 16001.** If a client patch moves it, the addon may show
  as out of date until the `.toc` is updated. Check yours with
  `/run print((select(4, GetBuildInfo())))`.

## Reporting a track that sounds wrong

"Track X felt wrong in zone Y" is the most useful report this addon can get,
and it's usually a one-line fix.
[Open an issue](https://github.com/kirillburton/forever-ambient-music-extended/issues)
with the name and ID `/fame status` shows, and where you were. In the
meantime, `/fame ban` gets rid of it.

---

# For developers

## Repository layout

```
ForeverAmbientMusicExtended/   the addon, exactly as it ships
  Core.lua                     scheduler, location, volume, commands
  Zones.lua                    zone profiles, towns, coves, inns   (hand-written)
  Tracks.lua                   the extended pool                  (generated)
  Originals.lua                the game's own music rules         (generated)
  LocalTracks.lua              your own audio files               (generated, ships empty)
  Media/                       logo, and a generated silent mp3
tools/                         data pipeline, tests, packaging
art/                           logo source (SVG) and a 512 px PNG
```

Requirements for the tools: Python 3, Lua 5.1, and `ffmpeg` (for `ffprobe`)
if you measure durations or add local files.

## How playback works

No API reports when the game's zone music starts or stops, so there's no
moment to slip a track into. What the API does have is `PlayMusic()`, which
suppresses the game's zone music for as long as it plays. So in a place FAME
covers, it plays everything through `PlayMusic()` and runs the game's
schedule itself:

- the game's own tracks for their share, and extended ones for the rest;
- during silences, a short silent file (`Media/silence.mp3`) that holds the
  channel, so the game can't start a track of its own halfway through;
- silence lengths, music sets, intros and their cooldowns taken from the
  game's own tables (`Originals.lua`).

Same rules, not the same dice: the game draws each silence at
random from its interval, and so does FAME.

`PlayMusic()` loops and fires no end event, so each track is stopped on a
timer, using durations measured from the actual files. Nothing in the API
fades music, so fades ramp the `Sound_MusicVolume` CVar and restore it.
FAME records every value it writes and yields as soon as it sees one it
didn't. The slider's real value is saved, so a logout mid-fade is repaired
at the next login.

Wherever FAME isn't confident, it calls `StopMusic()` and hands the channel
back to the game: instances, death, places with no data, and anywhere the
game's own zone name disagrees with the map (ships at sea).

## How a track gets chosen

Each track carries tags on three axes, plus an optional time of day:

- **biome**: `forest` `darkforest` `enchanted` `jungle` `swamp` `plains`
  `barrens` `desert` `mountain` `snow` `volcanic` `coast` `sea` `cave`
  `underground` `ruins` `blighted` `void` `arcane` `elemental` `sky` `city`
  `town` `tavern`
- **culture**: `human` `dwarf` `gnome` `nightelf` `highelf` `orc` `tauren`
  `troll` `undead` `goblin` `naga` `draenei` `pandaren` `dragon` `demon`
  `centaur` `tuskarr` `earthen` `arathi` `kultiran` `drust` `vrykul`
  `nerubian` `pirate` `wild`
- **mood**: `calm` `melancholy` `mysterious` `eerie` `ominous` `heroic`
  `sacred` `festive` `somber` `tense` `grand` `playful`
- **time**: `day` or `night`, or neither for a track that fits any hour

Each zone in `Zones.lua` is an allow-list on each axis, keyed by uiMapID. A
track is eligible when **every** tag it carries is allowed:

```lua
[1431] = { -- Duskwood
    biomes   = { "darkforest", "blighted" },
    cultures = { "human", "undead", "drust", "wild" },
    moods    = { "eerie", "ominous", "melancholy", "mysterious", "somber" },
    resting  = REST_ALLIANCE,
},
```

So specific tracks go to few places and loosely tagged ones travel. Every
track must carry at least one biome, a statement of where it belongs. A
track with no biome plays nowhere, and `check_zones.lua` flags it.

A profile can also `require` tags a track must have. Allow-lists can reject
a tag but can't demand one. The inn profiles use `require = { "tavern" }`, so
only actual tavern music plays in inns.

**Towns and coves** are profiles attached to an area inside a zone, keyed by
the game's area ID so they work in every client language. The `town` biome
and `pirate` culture are only allowed in those profiles, which keeps goblin
and pirate music in goblin and pirate places. Walking in or out switches
the pool without interrupting the current track, as the game's music
doesn't change at the town line either.

**Inns** are matched by name (`GetMinimapZoneText()`) against `ns.inns` at
the bottom of `Zones.lua`, which records each known inn's race by hand. The
game's data barely records it. `IsResting()` alone can't be used, because
it's true across entire capitals.

Dungeons and raids are intentionally not covered: their music is written for
the encounters.

**Forever's map IDs** are the Classic block (1411–1464), plus new IDs for
its new zones: Mount Hyjal 2482, Riverglades 2548, Shen'dralas 2652,
Darkspear Islands 2524, Zephras Isle 2521 and 2665.

### Fixing a track that's out of place

- A track's tags are wrong: add a line to `tools/tag_overrides.csv` and
  re-run `python3 tools/make_tracks.py`. Don't edit `Tracks.lua` by hand;
  it's regenerated.
- A zone allows too much or too little: edit its profile in `Zones.lua`.

Then check the result without launching the game:

```
lua tools/check_zones.lua           # pool size for every zone
lua tools/check_zones.lua 1431      # everything eligible in Duskwood
lua tools/smoke.lua                 # drive the addon through simulated play
```

`check_zones.lua` loads the real `Core.lua` matcher against the real data on
a stubbed WoW API, so it also catches syntax errors and tag typos.
`smoke.lua` drives the scheduler and every slash command through hours of
simulated game time, including zone changes, death, inns, bans, Loop Music,
and a stand-in for Spoken Quests' volume ducking.

## Rebuilding the data

`Tracks.lua` and `Originals.lua` are generated from the client's own data on
[wago.tools](https://wago.tools), branch `wowf` (WoW: Forever).

```
python3 tools/fetch_music_list.py                    # 1. list the client's music
python3 tools/probe_durations.py --from-csv tools/cache/music_list.csv --pool
python3 tools/make_tracks.py                         # 3. write Tracks.lua
python3 tools/casc_scan.py --ids-out tools/cache/wowf_root.txt
python3 tools/make_originals.py                      # add --refresh after a client patch
python3 tools/casc_scan.py --check-addon             # every track is in the client
lua tools/check_zones.lua && lua tools/smoke.lua
```

1. **`fetch_music_list.py`** lists every `sound/music/*` file on the branch
   in `tools/cache/music_list.csv`, with a first guess at its tags from the
   file name.
2. **`probe_durations.py`** measures each file's real length, since a wrong
   one either cuts a track short or audibly loops it. Each file is
   downloaded, measured with `ffprobe` and deleted right away. Results are
   cached in `tools/cache/durations.json`.
3. **`make_tracks.py`** writes `Tracks.lua`, applying `tag_overrides.csv` on
   top of the guesses.
4. **`casc_scan.py`** reads the installed client's file manifest directly
   from its local CASC storage. `make_originals.py` uses it to drop files
   the client doesn't have, and `--check-addon` confirms every track the
   addon references is present.
5. **`make_originals.py`** reads `AreaTable`, `ZoneMusic`,
   `ZoneIntroMusicTable` and `SoundKitEntry` for every zone in `Zones.lua`
   and writes the game's own sets, silences, intros and subzone music to
   `Originals.lua`. Adding a zone to `Zones.lua` and re-running it is all
   it takes for FAME to know that zone's music.

Filtered out of the extended pool (`tools/wagolib.py`): cinematic, event,
title-screen, stinger, jukebox and PvP music; the stock sets the game
already plays in these zones; raid and dungeon interiors; anything under 30
seconds; and story or boss cues with no biome or culture to place them by.
The Caverns of Time *exterior* music (Old Hillsbrad, Tarren Mill, Durnholde
Keep, the Black Morass) is kept, since it was written for real places.

## Adding your own music (experimental)

You can add audio extracted from your own retail install to the rotation.
None is shipped: the `Music` folder and `LocalTracks.lua` are empty.

1. Extract tracks with [wow.export](https://www.kruithne.net/wow.export/)
   from your own install (`sound/music/`).
2. Put the `.mp3` / `.ogg` files in `ForeverAmbientMusicExtended/Music/`
   (subfolders are fine).
3. Run `python3 tools/local_tracks.py`. It measures each file and guesses
   tags from the file name.
4. Fix the tags in `LocalTracks.lua`. Untagged tracks are never picked, and
   the script lists them. Re-running it keeps your edits.
5. Restart the client.

Local files are checked once per session before their first play, and any
the client can't load are skipped.

## Packaging and releases

Build the zip with the script, not Finder's Compress or `zip -r`, which add
`__MACOSX/` and `.DS_Store` entries that CurseForge rejects:

```
python3 tools/package.py                    # -> dist/ForeverAmbientMusicExtended-<version>.zip
python3 tools/package.py --check some.zip   # check any zip against the same rules
```

It packages an explicit list of files under a single
`ForeverAmbientMusicExtended/` folder (never your own audio), confirms that
every file the `.toc` loads is included, and produces the same zip from the
same source every time.

GitHub Actions (`.github/workflows/package.yml`) runs the syntax, data and
behaviour checks on every push and keeps the built zip as a run artifact.
To release:

1. Bump `## Version:` in the `.toc`, add a `CHANGELOG.md` entry, and commit.
2. `git tag v1.0.1 && git push origin v1.0.1`

The workflow refuses a tag that doesn't match the `.toc` version. Otherwise
it publishes a GitHub release with the zip attached.

## Contributing

Issues and pull requests are welcome, especially tag and zone corrections.
Before opening a PR, run `lua tools/check_zones.lua && lua tools/smoke.lua`,
and regenerate rather than hand-edit `Tracks.lua` and `Originals.lua`.

By submitting a pull request, you agree that your contribution may be
included in the project and distributed under its license.

---

## License

Copyright © 2026 Kirill Budnikov. All rights reserved. The source is public
to read, report against and contribute to, but it may not be copied,
modified or redistributed without permission. See [LICENSE](LICENSE).

World of Warcraft and its music are trademarks and property of Blizzard
Entertainment. This is an unofficial fan project, not affiliated with or
endorsed by Blizzard.
