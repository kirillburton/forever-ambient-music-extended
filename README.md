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

There's nothing to set up. It sounds like the default ambient music, with
more variety. When you want a say in what plays, there's a settings page and
a music window, both built from the game's own parts and fully playable with
a gamepad.

Optionally, it can also play zone music from modern WoW, which
[a small script](https://kirillburton.github.io/forever-ambient-music-extended/import/)
puts on your own computer (see [Music from modern WoW](#music-from-modern-wow-optional)).

**No Blizzard audio is bundled with or distributed by this addon.** Every
track it plays is a file your Forever client already has, or one you
imported yourself.

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

You don't need retail, and the `Music` folder is meant to be empty: every
track FAME plays is already in your Forever client. The folder is only for
[optional extras](#adding-your-own-music-experimental).

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
  open sea, cutscenes and movies, and anywhere you've turned music off. FAME steps aside there and
  the game's own music plays as normal.

Nothing should turn up out of place: a track only plays where every one of
its tags is welcome (see [How a track gets chosen](#how-a-track-gets-chosen)).
A zone with nothing suitable plays only the game's own music rather than
reaching for something that doesn't fit.

FAME's tracks also play wherever the Forever client itself puts them, subzone
by subzone, whatever their tags say: Felwood's cursed-land music in Felwood,
the Forever themes in Riverglades' subzones.

### Coverage

All 46 Classic zones and cities, plus the new Forever zones: Mount Hyjal,
Riverglades, Shen'dralas, Darkspear Islands and Zephras Isle. Most zones
have 20–60 extended tracks to draw from; none has fewer than twelve. If you
narrow a place down below eight (switching most eras off, say), the game's own
tracks play more often, so the same few don't come round again and again.

## Music from modern WoW (optional)

FAME can also play zone music from every era of the retail game: The
Burning Crusade to Midnight, and the Classic pieces Forever lacks. That
music is Blizzard's, so FAME can't ship it. Instead, a small script puts it
on your own computer, copied from your installed retail game if you have
one, otherwise downloaded from Blizzard's own servers, with every file
checked against Blizzard's checksum.

1. Open **Settings > AddOns > FAME > Import music** (or type `/fame import`)
   for the address, or go straight to
   [the instructions page](https://kirillburton.github.io/forever-ambient-music-extended/import/).
2. Paste one line into PowerShell (Windows), Terminal (Mac) or a terminal
   (Linux, Steam Deck), and pick the expansions you want.
3. Restart the game.

The music goes into its own addon folder,
`_forever_/Interface/AddOns/ForeverAmbientMusicExtended_RetailPack`.
Updating FAME never touches it, and deleting the folder removes it all.
Run the script again any time to add or remove expansions.

It's placed with care. Cataclysm rebuilt the old world's music area by
area and Forever kept the areas, so that music plays exactly where retail
plays it: Stonetalon Peak's night elf themes at the Peak, not across
Stonetalon. Everything else plays only where it fits a zone's own land and
people, at most 80 tracks a zone, mixed across expansions. The Burning
Crusade and Wrath of the Lich King appear in Settings once you have their
music.

## Settings and the music window

**Settings > AddOns > FAME** goes from what most players want to what few do:

1. **Extend the zone music**: FAME on or off.
2. **Music from**: one checkbox per era, Classic, Forever,
   then Cataclysm through Midnight, each with its number of tracks beside it
   ("89 tracks · +36 from retail" with the retail pack). Unticking an era
   takes its tracks out of the extended pool everywhere. The game's own
   music always plays. Right under them, **Import music** shows how to add
   music from modern WoW, and what you already have.
3. **Minimap button**: on unless you turn it off.
   Left-click opens the music window, right-click these settings. It finds
   a spot clear of other addons' minimap buttons; drag it with the mouse to
   put it somewhere else.
4. **More options**: the share of the game's own tracks, and **Game's track
   on arrival**: whether a new place opens with one of them.
5. **Edit tracklists** and **Show banned tracks**: open the music window on
   its Zones or Banned tab.

**The music window** opens from that button, `/fame ui`, the key binding
"Open the music window" (Key Bindings > AddOns), or the minimap button.

- **Now playing** across the top: the track, its era and time, with
  **Skip**, **Play extended now**, **Not in this zone** (out of this zone
  only, as unticking it below does) and **Never play again** (everywhere).
- **Here**: every extended track that fits where you're standing. Untick a
  track to stop it playing in this zone. Other zones keep it. **Preview**
  plays its first 20 seconds, then the music carries on as if a track had
  ended. A track that's banned, from an era you've turned off, or plays only
  by day or by night says so in its row. Without the retail pack, the list
  ends with a greyed **Retail music pack** row saying how many tracks it
  would add here.
- **Zones**: the same for any zone. Step through with `<` and `>`, or press
  the zone's name for a menu of every zone, grouped by continent. Choices
  for a zone also cover the towns and coves inside it, and tracks that play
  only in some subzones say where.
- **Banned**: your bans, with **Unban** and **Unban all**.

### With a gamepad

Both screens are built from the game's own templates, and the window
registers itself with Forever's gamepad layer when it opens, so that layer
handles it like Blizzard's windows: the D-pad moves between rows, buttons
and tabs, A ticks, previews or turns the page, and B closes the window.
Long lists come in pages of ten with Previous and Next page buttons rather
than a scrolling list, since the gamepad navigation moves through plain
buttons best. Every D-pad direction is set explicitly: left and right stay
within a row of controls, up and down stay in a column, and the zone
switcher runs `<`, zone name, `>` in a row, with down from the name landing
on the shown zone in its menu. Nothing needs a mouse:
no hovering, right-clicking, dragging or typing.

The window closes when combat starts and opens again once it ends. In
combat the game refuses addon changes to gamepad navigation, and there's
nothing to choose there anyway. Bind "Open the music window" to
a button to reach it without the keyboard.

## Commands

Everything is under `/fame`. `/fame help` lists the commands with each
setting's current value.

| Everyday | |
|---|---|
| `/fame ui` | open the music window |
| `/fame settings` | open FAME's page in Settings |
| `/fame import` | music from modern WoW: where to get it, and what you have |
| `/fame status` | what's playing, how far in, and what comes next |
| `/fame skip` | end this track the way it would end anyway: into the usual silence, or straight to the next track with Loop Music on |
| `/fame next` | play an extended track now |
| `/fame remove` | stop this track and never play it in this zone again |
| `/fame ban` | stop this track and never play it again, anywhere |
| `/fame banlist` | your banned tracks, with the zone each was banned in |
| `/fame unban <id>` \| `all` | allow one banned track again, or all of them |
| `/fame chance <0-100>` | share of tracks that are the game's own (default 40) |
| `/fame first` | let a new place open with an extended track (off by default) |
| `/fame on` \| `off` \| `toggle` | run FAME, or leave the music to the game |

| Troubleshooting | |
|---|---|
| `/fame where` | where FAME thinks you are, which music set applies, silences, Loop Music, volume |
| `/fame pool [n]` | the extended tracks that fit here |
| `/fame play <id>` | play a track by its file ID (or retail ID, for an imported one) |
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
  Core.lua                     scheduler, location, volume, commands, placement
  Options.lua                  the Settings page
  Window.lua                   the music window, zone menu, key binding, minimap entry
  Import.lua                   the "Music from modern WoW" window
  Bindings.xml                 the "Open the music window" key binding
  Zones.lua                    zone profiles, towns, coves, inns, retail fit   (hand-written)
  Tracks.lua                   the extended pool                  (generated)
  ForeverPlaces.lua            where the Forever client plays those tracks   (generated)
  RetailTracks.lua             the retail pack's tracks: IDs, tags, places, no audio   (generated)
  Originals.lua                the game's own music rules         (generated)
  LocalTracks.lua              your own audio files               (generated, ships empty)
  Media/                       logo, and a generated silent mp3
docs/import/                   the import page, scripts and track list (GitHub Pages)
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
game names the zone as one of the seas (a ship crossing open water).

## How a track gets chosen

Each track carries tags on three axes, plus an optional time of day:

- **biome**: `forest` `darkforest` `enchanted` `jungle` `swamp` `plains`
  `barrens` `desert` `mountain` `snow` `volcanic` `coast` `sea` `cave`
  `underground` `ruins` `blighted` `void` `arcane` `elemental` `sky` `city`
  `town` `tavern`
- **culture**: `human` `dwarf` `gnome` `nightelf` `highelf` `orc` `tauren`
  `troll` `undead` `goblin` `naga` `draenei` `pandaren` `dragon` `demon`
  `centaur` `tuskarr` `earthen` `arathi` `kultiran` `drust` `vrykul`
  `nerubian` `pirate` `titan` `wild`
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

**The player's own choices** narrow the eligible pool further, at pick time:
bans (everywhere), eras switched off in Settings (each track's `era` field in
`Tracks.lua`), and tracks unticked for one zone in the music window (saved
per uiMapID). They apply only to the extended pool. The game's own tracks,
its silences and intros are never filtered by them.

**Where the Forever client puts a track.** `ForeverPlaces.lua` records, for
each of FAME's tracks, the areas whose music set includes it in the Forever
client's own `AreaTable`/`ZoneMusic`. A track is in the pool there whatever
its tags say: anywhere in the zone for the zone's own area, only in that
subzone for a subzone (recognised by `GetSubZoneText()`, in the client's
language). Areas named "DELETE ME" or "UNUSED" are left out.

**The retail pack** (`RetailTracks.lua`, only the tracks the player's
`Pack.lua` lists) doesn't go through the open matching: it's several times
FAME's own pool and would bury every zone's character. Two routes instead:

- *Where retail plays it.* Cataclysm's old-world music is placed area by
  area, and Forever kept the area IDs, so each track's `at` lists the Forever
  areas retail plays it in, zone-wide or per subzone, as above.
- *Fitting the zone's strict list,* `ns.retailFit` in `Zones.lua`: only the
  land and people that define the zone, plus kindred peoples (Drustvar's
  music in Duskwood). The first biome is the zone's signature, which a track
  naming no people must carry. Of the tracks that fit, the closest 80 are
  kept, turn about by era, with at most 6 variations of one piece and 20
  from one expansion (`RETAIL_CAP`, `PER_FAMILY`, `PER_ERA` in `Core.lua`).
  The choice is made from the whole list, imported or not, so a zone's
  music doesn't shift with which expansions a player imported.

`lua tools/retail_report.lua` shows what every zone gets, and
`lua tools/retail_report.lua 1442` one zone in full.

**Small pools.** The extended share is capped at one eighth of the pool size
(`SMALL_POOL` in `Core.lua`), so where fewer than eight extended tracks fit,
the game's own play more often than the configured 40% instead of the same
few repeating.

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

### The retail music pack

The pack's data is built from an installed retail client, sharing the
`Data` folder with Forever:

```
python3 tools/retail_catalog.py      # tools/retail_catalog.csv: every retail-only music file, tagged
python3 tools/make_retail_tracks.py  # RetailTracks.lua: the `world` and `sibling` rows, with retail's areas
python3 tools/make_forever_places.py # ForeverPlaces.lua (Forever's own placements, no retail needed)
python3 tools/make_import_list.py    # docs/import/retail-pack.tsv: what the import scripts fetch
lua tools/retail_report.lua          # what each zone ends up with
```

- **`retail_catalog.py`** reads both clients' manifests from the local
  `Data` folder, retail's zone-music tables to see where each track plays,
  and the wowdev community listfile for names. Tags come from
  `tools/retail_zone_tags.csv` (one row per zone), refined by the music set's
  name. Old `zonemusic/<place>/` tracks that another zone borrows take
  `<place>`'s tags instead. `tools/retail_tag_overrides.csv` has the final
  word. The `status` column marks the pack: `world` and `sibling`.
- **`make_import_list.py`** records, per track, its encoding key (also its
  checksum), size, where it sits on Blizzard's CDN and its chunk layout, so
  the scripts can fetch and unwrap it without understanding Blizzard's
  formats. The scripts download this list every time they run, so
  regenerating it and pushing fixes every player's next import.
- **`docs/import/`** is published by GitHub Pages: the page, `import-retail.sh`
  (Mac, Linux, Steam Deck: bash, curl, od, awk) and `import-retail.ps1`
  (Windows PowerShell 5.1). Bump `VERSION` and both scripts'
  `SCRIPT_VERSION` together when either changes, so older copies say to
  update.

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
