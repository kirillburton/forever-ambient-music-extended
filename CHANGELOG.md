# Changelog

## 1.0.0

First full release, for the live World of Warcraft: Forever client.

Changes:
- tidier command output - every command answers with a short headline and aligned details
- tracks are shown by name, e.g. mus_80_drustvar_h (1780914), instead of a bare file ID - in /fame status, /fame pool, /fame ban and /fame banlist
- track lengths and time left read as minutes and seconds
- /fame status now shows how far into the track you are and what comes next - the game's silence, or the next track with Loop Music on
- /fame help is split into everyday and troubleshooting commands, and shows each setting's current value
- /fame where is now the place for troubleshooting details - map, subzone, inn, music set, Loop Music, volume
- an unknown command now says so instead of just printing the help
- removed /fame verify - every track FAME plays is now checked against the live client before each release

## 0.3.2

Bugfixes:
- New Avalon (Eastern Plaguelands) could play minutes of silence instead of music - the game's own music data there lists three files that don't exist in the client. FAME now only uses music the client actually has
- added music switching for Twilight Hollow in Riverglades, a subzone with its own music in the live client
- install instructions now point to the live client's _forever_ folder instead of _classic_beta_

Every track FAME plays has been checked against the live Forever client (1.60.1.70532)

## 0.3.1

Bugfixes:
- music volume could get stuck quiet when used together with Spoken Quests (or other addons that lower the music while something plays) - when a voiced line started or ended during a track fade, both addons took the other's volume change for the player's and neither put it back. FAME now gives way:
  - while Spoken Quests lowers the music for a line, FAME doesn't touch the volume at all - a track change mid-line becomes a hard cut instead of a fade
  - if anything else moves the volume in the middle of a fade, FAME stops fading and leaves it as set
  - your own volume changes are still kept, and a volume left mid-fade by a quit is restored at the next login

## 0.3.0

Features:
- more music from the client:
  - "Ts Have It" (the Warlords of Draenor ocean theme) now plays in pirate places: Booty Bay, Wild Shore, Janeiro's Point, the Bloodsail Compound, The Merchant Coast and Lost Rigger Cove
  - Hillsbrad gets its own past: the Caverns of Time music for Old Hillsbrad, Tarren Mill and Durnholde Keep. The Black Morass music goes to the Swamp of Sorrows
- inns now play the tavern's own race only - dwarven drinking songs in Thunderbrew Distillery, human ones in the Lion's Pride, sea shanties in Booty Bay's Salty Sailor. Inns whose race isn't known revert to the game's default music

Forsaken Flame (8.1 Darkshore Warfront) isn't in the Forever client, so it can't be added as a built-in track

Bugfixes:
- music volume could get stuck somewhere between your level and 0% - FAME now recognises its own mid-fade values and puts your level back, while changes you make yourself are kept
- music kept looping when the game took over during a fade-out (e.g. entering a dungeon or dying right after crossing a border)
- "Ts Have It" was in the track list but never played

## 0.2.0

Features:
- added commands:
  - /fame ban - bans the current track
  - /fame banlist - lists banned tracks and where
  - /fame unban [id] or /fame unban all - allow banned tracks again

Ban blacklists a track, doesn't matter whether the track is original or extended - though all "default behavior" conditions like dungeons, raids, corpse walk are unbannable. Bans are applied before each decision, so a pick only ever lands on an unbanned track

Bugfixes:
- death condition (corpse walk) follows original music rules - when in spirit form, no extended music, always emulating what the game does originally
- ship travel follows in-game rules

## 0.1.0

First version: keeps the game's own music schedule and silences, and swaps a share of its tracks for ones from every WoW era, matched to each place by biome, culture and mood.
