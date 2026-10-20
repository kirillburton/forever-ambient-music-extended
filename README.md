# Forever Ambient Music Extended (FAME)

Widens the ambient zone music rotation in World of Warcraft: Forever with
tracks from every WoW era, picked to fit where you are standing. It behaves like the default ambient music:
automatic, no UI, no setup. There is just more of it.

425 tracks ship enabled, all of them files the Forever beta client already
has. You can add your own on top (see **Local files**).

---

## Install

1. Copy the `ForeverAmbientMusicExtended` folder into
   `World of Warcraft/_classic_beta_/Interface/AddOns/`.
2. Restart the client (not just `/reload`) — it indexes addon files at launch.
3. Log in. Nothing to configure.

Then verify it loaded:

```
/fame status
```

You should see `on, map 1429` (or whatever zone you are in) and a track count.

---

## How it behaves

FAME keeps the game's music schedule exactly and changes only *which* tracks
play in it.

- **Same silences.** Between tracks it waits the game's own silence interval
  for that place, read from the client's `ZoneMusic` data: 3–5 minutes in
  almost every zone, with separate day and night values where the game has
  them.
- **Loop Music respected.** With the Audio option **Loop Music** on, there
  are no silences, so tracks play back to back, exactly as the game would.
  Switching it on mid-silence starts the next track within ten seconds.
- **The game's own music stays in the mix.** About 40% of tracks are the
  game's own picks for that place (`/fame chance`); the rest come from the
  extended pool.
- **The first track in a new place is the game's own,** the way you'd hear
  it arriving without the addon. `/fame first` lets the extended pool take
  that slot too.
- **Intros still play.** Orgrimmar's fanfare, the Ironforge King theme and
  the rest open their areas on arrival, with the game's own cooldowns.
- **Subzones and inns change the music where the game would.** Walking into
  the Crossroads switches to the Crossroads set; walking into a known inn
  switches to tavern music of that inn's own race. Moving between two places that share music, like
  the Barrens and Orgrimmar, keeps the current track going.
- **Instances, battlegrounds, and anywhere without data are left alone.**
  FAME hands the music channel back and the game plays its own music as
  normal. The same happens with `/fame off`, or with music turned off in the
  sound options.
- **Death is the game's.** From the moment you die until you're alive again,
  through the whole spirit walk back to your corpse, FAME stays out and the
  game's own music rules apply. Coming back to life starts over like
  arriving: the game's own track first.
- **Ships are the game's.** The open seas (The Great Sea, The Forbidding Sea,
  The Veiled Sea) are areas of their own in the game, each with its own
  music. But a ship near the coast can still sit inside a zone's map, so
  FAME checks the game's own zone name (`GetZoneText()`). If the game has you
  somewhere other than the zone on the map, FAME steps aside until you land.
  The name is compared in the client's own language via
  `C_Map.GetAreaInfo`. If the client can't name the area, the check is
  skipped rather than guessed.

### Banning tracks

`/fame ban` bans whatever is playing, whether it's the game's own track, an
extended one or an intro, and ends it the way it would have ended anyway.
Bans apply *before* each decision: the game's tracks and the extended pool
are both filtered first, so a decision only ever lands on an unbanned track.
If the roll asked for one kind and bans have emptied it, the other kind
plays.

If everything a place could play is banned, FAME plays nothing and says so
in chat at decision time: *"All music for the zone was banned, playing
nothing. Unban songs with /fame unban command"*. It then waits the game's
usual silence (at least a minute, even with Loop Music on) before checking
again. `/fame unban` resumes music immediately.

`/fame banlist` lists each banned id with the zone it was banned in;
`/fame unban <id>` and `/fame unban all` undo bans. Bans are by track, so
banning a piece bans it everywhere. They don't reach places FAME leaves to
the game (dungeons, raids, battlegrounds, death, the open sea): there the
game chooses, so `/fame ban` explains it can't ban that music.

Bans are kept in SavedVariables. On beta builds that write SavedVariables
but never load them back, bans last until you log out.

### Why it runs the schedule itself

No API reports when the game's zone music starts or stops, so there is no
moment to slip a track into. What the API does have is `PlayMusic()`, which
suppresses the game's zone music for as long as it runs. So in a mapped zone
FAME plays *everything* through it: the game's own tracks for its share, the
extended ones for theirs, and, during silences, a ten-second silent file
(`Media/silence.mp3`, generated, not extracted) that holds the channel so the
game can't start a track of its own halfway through a silence.

The game's rules come from its own data: `tools/make_originals.py` reads
`AreaTable`, `ZoneMusic`, `ZoneIntroMusicTable` and `SoundKitEntry` for the
Forever branch and writes `Originals.lua`, covering 52 zones, 75 music sets,
27 intros and 265 subzones with music of their own. Subzone names are matched
in the client's own language via `C_Map.GetAreaInfo`.

"Exactly" means the same rules, not the same dice. The game draws each
silence at random from its interval, and so does FAME. Two sessions of plain
WoW don't line up either.

### Fades

Tracks fade into their own ending, and over about a second when something
interrupts one, such as walking into an inn. Nothing in the API fades music
(`StopMusic()` is instant and takes no arguments), so the fade ramps the
`Sound_MusicVolume` CVar down and puts it back.

The client crossfades between `PlayMusic` calls, so for a moment after a
swap the old track is still sounding. The volume therefore stays at zero
through the swap and about a second past it (`SWAP_HOLD`), then the new track
fades in (`FADE_IN`). Before that hold existed, the old track blipped back at
full volume for a split second whenever one track handed over to the next. A
fade that cuts into another one starts from wherever the volume actually is,
so it never jumps up first. The slider's own value is
saved before the first step and restored on every way out: ramp finished,
zone change, release, logout.

The slider is shared, though. You move it; the Settings panel can read it
mid-fade and write that value back on close; and some addons fade it
themselves. [Spoken Quests](https://github.com/rusty-key/spoken-wow) turns
music down to 30% while a line is spoken. It guards the slider the same way
FAME does: if it finds a value it didn't set, it decides you moved it and
gives the channel up for good, never putting it back. Before 0.3.1 the two
took each other for you, and a line overlapping a FAME fade left the music
stuck at a fraction of your level. So FAME now gives way:

- **It knows exactly what it wrote.** After every write it notes the value
  the client reports back. Its mid-fade values also carry an odd offset (0.2
  becomes 0.200537), so no other addon's arithmetic lands on them.
- **Mid-fade, any other value means someone else is working the slider.**
  FAME yields: it stops fading, finishes whatever the fade was for, and puts
  nothing back. For a few seconds after any outside change it swaps tracks
  with a hard cut rather than a fade.
- **While Spoken is ducking or fading, FAME doesn't touch the slider at
  all.** It takes the level Spoken noted before ducking as yours. Spoken has
  no public API for this, so FAME reads its internal state defensively. If a
  Spoken update changes that state, FAME falls back to the general rule
  above.
- **A FAME mid-fade value turning up later is a stale replay.** Once nothing
  else has moved the slider for a few seconds, FAME puts your level back.
- **Any other outside change is your choice** and becomes the level fades
  return to. It's saved, with a note of any fade in progress, so a quit
  mid-fade is healed at the next login. On beta builds that don't load saved
  variables, FAME says so once and asks you to set the slider.

The smoke test runs a line-for-line copy of Spoken's ducking logic against
FAME: lines over idle tracks, a track change mid-line, a line starting
mid-fade, and 40 lines at random moments. The 0.3.0 code fails it, stuck at
9.5% and never recovering. 0.3.1 passes across ten random seeds.

### Inns

Inside an inn FAME plays that tavern's own race and nothing else: the game's
tavern set for that race as the original share, and only tavern tracks of
that race from the extended pool.

Which inn you're in comes from the building's name, as the minimap shows it
inside (`GetMinimapZoneText()`). The race has to be written down by hand in
`ns.inns` at the bottom of `Zones.lua`: the game's own data barely records
it. Nearly every inn it knows plays the generic Alliance or Horde tavern set,
and most Horde and Kalimdor inns have no named building at all. So the list
holds only inns whose race is certain:

| Inn | Race |
|---|---|
| Lion's Pride Inn, Scarlet Raven Tavern, Lakeshire Inn | human |
| Stoutlager Inn, Thunderbrew Distillery, Deepwater Tavern, The Stonefire Tavern | dwarf |
| Gallows' End Tavern | undead |
| The Salty Sailor Tavern | pirate |

Any other inn is left to the game, which plays its own music there: FAME
treats it as an inn when you're resting, indoors and outside a capital, but
the building isn't on the list. The names are English, so on other client
languages every inn falls back to the game.

Capitals are exempt: `IsResting()` is true across an entire capital, so it
says nothing about being in an inn there.

### Commands

| | |
|---|---|
| `/fame on` \| `off` \| `toggle` | run the schedule, or hand music back to the game |
| `/fame status` | what is playing, what comes next, the music set here |
| `/fame skip` | end this track the way it would end anyway: into the silence, or the next track with Loop Music on |
| `/fame next` | end this track and play an extended one now |
| `/fame where` | uiMapID, subzone, music set and its silences, Loop Music |
| `/fame pool [n]` | list the first n tracks eligible here |
| `/fame play <fileDataID>` | play one track now |
| `/fame scan <id> [id …]` | report which fileDataIDs this client actually has |
| `/fame ban` | never play the current track again |
| `/fame banlist` | list banned tracks with the zone each was banned in |
| `/fame unban <id>` \| `all` | allow one banned track again, or all of them |
| `/fame chance <0-100>` | percent of tracks kept as the game's own (default 40) |
| `/fame first` | toggle whether the first track in a new place may be extended |
| `/fame verify` | also probe built-in tracks for presence |
| `/fame debug` | narrate every decision |

Beta note: some Forever builds write SavedVariables but never load them back.
Settings changed with `/fame chance` and friends may not survive a logout. The
defaults are what the addon is tuned for, so this mostly does not matter — but
if you want a permanent change, edit `defaults` at the top of `Core.lua`.

---

## How a track gets chosen

Each track carries tags on three axes plus an optional time of day:

- **biome** — `forest` `darkforest` `enchanted` `jungle` `swamp` `plains`
  `barrens` `desert` `mountain` `snow` `volcanic` `coast` `sea` `cave`
  `underground` `ruins` `blighted` `void` `arcane` `elemental` `sky` `city`
  `town` `tavern`. Every track needs at least one.
- **culture** — `human` `dwarf` `gnome` `nightelf` `highelf` `orc` `tauren`
  `troll` `undead` `goblin` `naga` `draenei` `pandaren` `dragon` `demon`
  `centaur` `tuskarr` `earthen` `arathi` `kultiran` `drust` `vrykul`
  `nerubian` `pirate` `wild`
- **mood** — `calm` `melancholy` `mysterious` `eerie` `ominous` `heroic`
  `sacred` `festive` `somber` `tense` `grand` `playful`
- **time** — `day` or `night`, or neither for a track that fits any hour

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

Every track must also carry **at least one biome**, a statement of where it
belongs. Culture and mood tags a track doesn't carry aren't checked, so a
track tagged only `{ "ruins", "mysterious" }` fits anywhere that allows ruins
and mysterious: specific tracks go to few places, loose ones travel. A
missing *biome* is different. It once meant goblin bazaar music passed the
biome check everywhere and played across the open Barrens. So a track with no
biome now plays nowhere, and `check_zones.lua` flags it.

**Towns and coves.** Some music belongs to a settlement rather than the land
around it. The goblin pieces carry the `town` biome, which only town profiles
allow: Ratchet, Booty Bay, Gadgetzan, Steamwheedle Port and Everlook. Pirate
music, such as the WoD ocean piece "Ts Have It", carries the `pirate` culture,
which only pirate places admit: the towns above plus the coves Wild Shore,
Janeiro's Point, the Bloodsail Compound, The Merchant Coast and Lost Rigger
Cove. Towns are
attached to their zone at the bottom of `Zones.lua`, keyed by the game's area
ID, which works in every client language. Walking into Ratchet switches the
extended pool to the Ratchet profile and walking out switches it back. The
current track keeps playing, because the game's music doesn't change at the
town line either.

A profile may also carry `require`, a list of tags the track **must** have.
Allow-lists can reject a tag but cannot demand one, and that gap is real: the
goblin-settlement pieces carry only `{ "goblin", "playful" }` with no biome at
all, so `biomes = { "tavern" }` happily let them into every inn. The inn
profiles use `require = { "tavern" }` to say the track has to actually *be*
tavern music.

A zone with no entry plays nothing extra, which is the safe default. Dungeons
and raids are intentionally left alone — `ns.instances` in `Zones.lua` is
empty, because the built-in encounter music is written for the encounter.

To widen a zone, add a tag to it. To see the effect without logging in:

```
lua tools/check_zones.lua           # pool size for every zone
lua tools/check_zones.lua 1431      # everything eligible in Duskwood
```

`check_zones.lua` loads the real `Core.lua` matcher against the real data on a
stubbed API, so it also catches Lua syntax errors and tag typos. `lua
tools/smoke.lua` additionally drives the playback loop and every slash command
through three hours of simulated game time.

### Zones covered

All 46 Classic zones and cities, plus the five new Forever zones: Mount Hyjal
(2482), Riverglades (2548), Shen'dralas (2652), Darkspear Islands (2524) and
Zephras Isle (2521 / 2665).

Forever uses the **Classic** uiMapID block (1411–1464), not retail's. The IDs
in `Zones.lua` come from the client's own `UiMap` DB2 for this branch, so they
are the real ones. Zephras Isle's *tags* are a guess from the name — worth
checking in game.

---

## Packaging and releases

Build the zip with the script, not Finder's "Compress" or `zip -r`. On macOS
both add a `__MACOSX/` folder and `.DS_Store`, and CurseForge rejects the
upload for either.

```
python3 tools/package.py                  # -> dist/ForeverAmbientMusicExtended-<version>.zip
python3 tools/package.py --check some.zip # check any zip against the same rules
```

The script packages an explicit list of files (the `.toc`, the Lua files,
`Media/`, and `Music/README.txt`, never your own extracted audio) under a
single `ForeverAmbientMusicExtended/` folder. It checks the result for
`__MACOSX`, dotfiles and anything outside that folder before writing it, and
confirms every file the `.toc` loads is included. The version comes from
`## Version:` in the `.toc`. The same source always produces the same zip.

On GitHub, `.github/workflows/package.yml` runs the syntax, data and
behaviour checks on every push and keeps the built zip under the run's
**Artifacts**. To publish a release:

1. Bump `## Version:` in the `.toc` and commit.
2. `git tag v0.1.1 && git push origin v0.1.1`

The workflow fails before publishing if the tag doesn't match the `.toc`
version. Otherwise it attaches the zip to a GitHub release named after the
tag, which is the file to upload to CurseForge.

## Local files

Audio you extracted from your own retail install can go in the rotation
alongside the built-in tracks. **No Blizzard audio is bundled with or
distributed by this addon.** The `Music` folder ships empty and
`LocalTracks.lua` ships with no entries.

1. Extract the music you want with [wow.export](https://www.kruithne.net/wow.export/)
   or CascView, pointed at your own retail install.
   `sound/music/` is where it lives.
2. Drop the `.mp3` / `.ogg` files into
   `ForeverAmbientMusicExtended/Music/` (subfolders are fine).
3. Generate the entries:

   ```
   python3 tools/local_tracks.py
   ```

   It reads each file's real duration with `ffprobe` and guesses tags from the
   file name.
4. Open `ForeverAmbientMusicExtended/LocalTracks.lua` and fix the tags. Anything left
   with no tags will never be picked, and the script tells you which those
   are. Re-running the script keeps edits you made.
5. **Restart the client.** Files added while logged in will not play until
   the client re-indexes at launch — a `/reload` is not enough.

Requires `ffmpeg` for `ffprobe` (`brew install ffmpeg`).

Pairings worth extracting, if you want somewhere to start: Cataclysm-era
versions of the Classic zones they replaced; Drustvar and Gilneas for
Duskwood; Val'sharah and Draenor's Shadowmoon Valley for the night elf
forests; Highmountain, Nagrand and Ohn'ahran Plains for Mulgore and the
Barrens; Zuldazar and Sholazar Basin for Stranglethorn; Dragonblight and
Icecrown for the Plaguelands; Tiragarde Sound and Stormsong Valley for
Westfall and the coasts. A fair number of these are already in the Forever
client and already enabled — `/fame pool` will show you.

---

## Rebuilding the data

`Tracks.lua` (the extended pool) and `Originals.lua` (the game's own rules)
are both generated. The data comes from [wago.tools](https://wago.tools),
branch `wow_classic_beta`.

```
python3 tools/fetch_music_list.py                                        # 1
python3 tools/probe_durations.py --from-csv tools/cache/music_list.csv --pool
python3 tools/make_tracks.py                                             # 3
python3 tools/make_originals.py            # add --refresh after a client patch
lua tools/check_zones.lua && lua tools/smoke.lua                         # 4
```

`make_originals.py` reads the zone list from `Zones.lua`, so adding a zone
there and re-running it is all that's needed for FAME to know the zone's
music. Ironforge and Undercity are wired by hand in the script
(`INTERIOR_CITIES`), because both cities keep their music on the building
rather than the zone.

1. **`fetch_music_list.py`** dumps every `sound/music/*` file on the branch to
   `tools/cache/music_list.csv` with a first-pass tag guess. The branch filter
   is server-side, so every row is a file this client can actually play.
2. **`probe_durations.py`** measures real durations. `PlayMusic()` loops and
   fires no end event, so the addon stops each track on a timer and a wrong
   length either truncates it or audibly loops it. There is no API to ask the
   client, so each file is downloaded from wago.tools, measured with
   `ffprobe`, and deleted immediately. Results cache in
   `tools/cache/durations.json` (459 entries, already populated) so re-runs
   cost nothing.
3. **`make_tracks.py`** writes `Tracks.lua`, applying `tools/tag_overrides.csv`
   on top of the keyword guesses. Put corrections there, not in `Tracks.lua`.
4. Check the result.

What gets filtered out along the way, in `tools/wagolib.py`:

- cinematic, event, main-title, stinger, jukebox and PvP material
- the stock Classic biome and city sets, plus their Forever remasters — the
  game already plays those in those zones, so they add nothing
- raid and dungeon interiors (Ahn'Qiraj, Naxxramas, Caverns of Time, the
  Forever dungeon sets)
- anything under 30 seconds
- story and boss cues that carry no biome or culture tag, so could never be
  placed safely

That leaves 425 tracks: 89 Classic pieces Forever does not use in these zones,
220 from `sound/music/forever` (including the new zone music), and 116 from
Cataclysm through Midnight.

The Classic count includes the Caverns of Time exterior music: Old Hillsbrad,
Tarren Mill and Durnholde Keep as they were, and the Black Morass. Each was
written for a real place, so they're let through even though the rest of
that folder is instance music. Each was checked by comparing its audio
against every other track in the client (the same composition correlates at
0.8–1.0 even across a remaster), and all of them are distinct.

---

## Verified, and not

Established in game before this was written:

- `PlaySoundFile(id, "Master")` works, and a file the client does not have
  returns a **zero** sound handle while still reporting success. That is the
  only reliable existence check, and the addon uses it for **local files**
  (see `FAME:Playable`): the first time such a track comes up it starts it on
  the Music channel and stops it in the same frame, caching the answer for the
  session. Built-in fileDataIDs skip the probe, since they were already
  checked against this client's own file list when `Tracks.lua` was generated
  — `/fame verify` probes them too, which is worth doing after a patch.
- `StopMusic()` does not stop the built-in zone music, only music started
  with `PlayMusic()`.
- Game audio plays by fileDataID; file paths work only for files inside an
  addon's own folder.

Established from the client's own data files on wago.tools:

- The branch file list matches what the client will play. All ten fileDataIDs
  tested in game agree with it — `625753` and `4872416` present, the other
  eight absent.
- Forever's uiMapIDs are the Classic block, and the new zones are Mount Hyjal,
  Riverglades, Shen'dralas, Darkspear Islands and Zephras Isle.

Established in game since:

- `PlayMusic(fileDataID)` displaces the built-in zone music, and the game's
  music comes back after `StopMusic()`.

Still assumptions, flagged rather than relied on:

- **`PlayMusic("Interface\\AddOns\\…\\x.mp3")` plays a local addon file.**
  This now matters a lot: it is how silences are held. If it fails, `status`
  says so and silences fall back to `StopMusic()`, which lets the game start
  its own music mid-silence. That's audible, not broken.
- **The game starts a place's music immediately on arrival** rather than
  waiting out a silence first. FAME does the same. Compare against
  `/fame off` if arrivals feel busier than plain WoW.
- **Silence is measured from the end of one track to the start of the
  next.** That's the natural reading of `SilenceIntervalMin/Max`.
- **A PlayMusic change may crossfade.** When a fade leads into silence,
  FAME keeps the volume down 2.5 seconds longer (`QUIET_AFTER` in
  `Core.lua`), so an old track's tail can't swell back up.
- **`StopSound(handle, 0)`** takes a fade-out time. If it does not, the
  presence probe could leave a short audible blip the first time each local
  file comes up. Built-in tracks are not probed by default.
- **`Sound_ZoneMusicNoDelay` is the Loop Music CVar.** This now decides
  whether silences happen at all. It falls back to `Sound_LoopMusic`, then to
  assuming off (the game's default); `/fame where` shows which.
- **`SetCVar("Sound_MusicVolume", …)`** is writable by addons. If it is
  protected on this client the fade degrades to an instant stop rather than
  erroring, which is the pre-fade behaviour.
- **Interface number `16001`.** Confirm with
  `/run print((select(4, GetBuildInfo())))` and update the `.toc` if it moved.
- **Zephras Isle's tags**, which are a guess from the zone name.
