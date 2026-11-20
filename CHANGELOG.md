# Changelog

## 2.1.0

Music from modern WoW, if you want it, placed with care. Plus finer control over what plays where.

Features:
- music from modern WoW (optional):
  - FAME can now play zone music from every era of the retail game - The Burning Crusade to Midnight, and the Classic pieces Forever lacks. Blizzard's music can't ship with an addon, so a small script puts it on your own computer: copied from your installed retail game if you have one, otherwise downloaded from Blizzard's own servers. Every file is checked against Blizzard's checksum
  - Settings > AddOns > FAME > Import music (right under the eras), or /fame import, shows where to get the script and what you have. It runs on Windows, Mac, Linux and the Steam Deck, and only uses what your system already has
  - it all goes into its own addon folder, ForeverAmbientMusicExtended_RetailPack. Updating FAME never touches it, and deleting that folder removes it
  - placed with care, not sprinkled everywhere. Cataclysm rebuilt the old world's music area by area, and Forever kept the areas, so that music plays exactly where retail plays it - Stonetalon Peak's night elf themes at the Peak, not across Stonetalon. Everything else plays only where it fits a zone's own land and people, at most 80 tracks a zone, mixed across expansions so no single one takes over
  - The Burning Crusade and Wrath of the Lich King appear in Settings once you have their music, and every era shows how many retail tracks it adds
- Not in this zone - a new button next to Never play again, and /fame remove. Takes the playing track out of this zone only, instead of banning it everywhere. Tick it again in the music window to undo
- the zone name on the Zones tab opens a menu of every zone, grouped by continent. Pick one with the mouse or the D-pad; the arrows still step through them
- Forever's own music now also plays wherever the Forever client itself puts it, subzone by subzone - Felwood's cursed-land music in Felwood, the Forever themes in Riverglades' and Zephras Isle's subzones

Changes:
- the minimap button is on by default. Left-click opens the music window, right-click Settings. If you turned it off, it stays off
- Import music sits right under the eras in Settings, where the retail counts point
- the "Forever soundtrack" era is now just "Forever"
- tracks that only play in some subzones say so in the zone view ("only in Stonetalon Peak")
- Zephras Isle appears once in the music window, and your choices cover both of its maps
- with a gamepad, the import window's address is selected too, ready for Ctrl+C

What's next:
- the Windows import script is new: if you try it, please report how it went
- adding tracks to a zone, any track, anywhere you like
- evening out volume between tracks

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
