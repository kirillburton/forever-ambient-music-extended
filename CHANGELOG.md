# Changelog

## 2.0.0

FAME gets its first UI: a settings page and a music window. Both are built from the game's own parts, so they look and behave like the rest of the interface, and both work fully with a gamepad - nothing needs a mouse.

This is the first iteration of the UI, and more is coming (see below).

Features:
- Settings > AddOns > FAME:
  - turn FAME on or off
  - choose which eras you hear - Classic, the Forever soundtrack, Cataclysm through Midnight, with the number of tracks beside each. Only here for the Cataclysm pieces? Untick the rest. The game's own music always plays, whatever you choose
  - a FAME button on the minimap (off unless you turn it on) - left-click for settings, right-click for the music window. It sits down next to other addons' buttons instead of on top of them
  - how often the game's own tracks play, and whether a new place opens with one of them
  - Edit tracklists and Show banned tracks, which open the music window
- the music window - from Settings, the minimap button, a key binding or /fame ui:
  - Here - every extended track that can play where you're standing. Untick one to stop it playing in this zone, or preview it for 20 seconds
  - Zones - the same for any zone, so you can tune Westfall from Stormwind
  - Banned - everything you've banned, with Unban and Unban all
  - what's playing, with Skip, Play extended now and Never play again
- gamepad - we take it seriously:
  - the window opens like any game window, so Forever's own gamepad navigation moves through it. D-pad to move, A to tick, preview or turn the page, B to close
  - every direction is set by hand: left and right stay in a row, up and down stay in a column, and the zone arrows lead straight to each other
  - long lists come in pages of ten, which the gamepad moves through better than a scrolling list
  - no hovering, right-clicking, dragging or typing needed anywhere
  - the window closes when combat starts, and opens again after
- added key binding "Open the music window" under Key Bindings > AddOns
- added /fame ui and /fame settings

Changes:
- if you narrow a place down to only a few extended tracks - say, with most eras switched off - the game's own tracks play more often, so the same few don't come round again and again
- shorter addon list description, and plainer status messages

Bugfixes:
- cutscenes could play two songs at once - a new character's opening cinematic, for one. FAME now stops the moment a cutscene or movie starts, and picks up again after it ends
- in some inns and buildings FAME thought you were at sea and went quiet - now it only does that out on the open sea

What's next:
- for now tracklists only let you take tracks out of a zone. Adding tracks to a zone - any track, anywhere you like - is planned for the next release in some form
- more polish for the window, with gamepad support kept first-class
- evening out volume between tracks, since some extended tracks are louder than the game's own

## 1.0.0

First full release, for the live World of Warcraft: Forever client.

New logo - shown in the in-game addon list.

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
