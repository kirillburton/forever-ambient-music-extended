# Forever Ambient Music Extended (FAME)

**For World of Warcraft: Forever.** Not retail, not Classic Era.

Classic's zone music is beautiful and there is not very much of it. After a few
hundred hours you know every bar of Elwynn Forest.

FAME widens the rotation without changing the rhythm. The game's own music
schedule stays as it is: the same silences between tracks, the same intros on
arrival, its own tracks still in the mix. But some of those tracks now come
from a pool of **425 more**, each chosen to fit where you are standing:
Classic pieces Forever doesn't use in those zones, the new Forever zone music,
and selections from Cataclysm through Midnight.

Install it and play. It sounds like the default ambient music, with more
variety.

---

## New in 2.0: settings and a music window

FAME now has a UI, built from the game's own parts so it looks and behaves
like the rest of the interface, and **fully playable with a gamepad**.

- **Choose your eras.** Only here for the Cataclysm pieces? Untick the rest.
- **Edit tracklists.** See every extended track that can play in a zone,
  preview it for 20 seconds, and untick what doesn't fit for you.
- **Bans in one place.** Everything you've banned, with Unban and Unban all.
- **A minimap button**, if you want one.

This is the first version of the UI. For now tracklists let you take tracks
out of a zone; adding tracks to a zone is planned for the next release.

---

## What it sounds like

- **Duskwood** draws on Drustvar, Cinderwold, the Emerald Nightmare and
  Twilight's Shroud.
- **Mulgore** gets Highmountain, Ohn'ahran Plains and the Gustberry Lowlands.
- **Stranglethorn Vale** gets Zuldazar, Sholazar Basin and Zul'Aman.
- **The Plaguelands** get Lordaeron, Mourning's Rest and the Maw.
- **Inns** play their own race's tavern music: dwarven drinking songs in
  Thunderbrew Distillery, human ones in the Lion's Pride, sea shanties in
  Booty Bay's Salty Sailor.
- **Pirate coves** get "Ts Have It", the Warlords of Draenor ocean theme, in
  Booty Bay, Wild Shore, The Merchant Coast and Lost Rigger Cove.
- **Hillsbrad** gets its own past: the Caverns of Time music for Old
  Hillsbrad, Tarren Mill and Durnholde Keep.
- Sholazar Basin's day and night variants only play at the right hour.

Every track is tagged by biome, culture and mood, and plays only where all of
its tags fit. A night elf lament won't wander into Orgrimmar.

## It keeps the game's rhythm

- **The same silences** between tracks as the game, read from its own data:
  three to five minutes in most zones.
- **Loop Music is respected.** Turn it on in Audio options and tracks play
  back to back.
- **40% of tracks are still the game's own**, and the first track when you
  arrive somewhere is too. Both are adjustable.
- **Intros still play**, like Orgrimmar's fanfare and the Ironforge King
  theme, on the game's own cooldowns.
- **Subzones and inns switch music where the game would.**
- Never the same track twice in a row, and tracks fade rather than cut off.
- **Left alone:** dungeons, raids, battlegrounds, death and the corpse run,
  ship crossings, cutscenes, and anywhere with music turned off. There the
  game's own music plays, untouched.

## Settings and the music window

**Settings > AddOns > FAME**, from what most players want to what few do:

- turn FAME on or off;
- **Music from:** one checkbox per era, with its number of tracks;
- **Minimap button:** left-click for settings, right-click for the music
  window. It sits down next to other addons' buttons, not on top of them;
- how often the game's own tracks play, and **Game's track on arrival**;
- **Edit tracklists** and **Show banned tracks**.

**The music window** (also from the minimap button, a key binding, or
`/fame ui`):

- **Here:** every extended track that can play where you're standing.
  Untick one to stop it playing in this zone, or preview it.
- **Zones:** the same for any zone, so you can tune Westfall from Stormwind.
- **Banned:** everything you've banned.
- Along the top, what's playing, with **Skip**, **Play extended now** and
  **Never play again**.

**With a gamepad:** the window opens like any game window, so Forever's own
gamepad navigation moves through it. D-pad to move, A to tick, preview or
turn the page, B to close. Every direction is set by hand, so the cursor
goes where you expect, and nothing needs hovering, right-clicking, dragging
or typing. Bind **Open the music window** under Key Bindings > AddOns to
reach it from your controller. The window closes during combat.

## Install

1. Drop the `ForeverAmbientMusicExtended` folder into
   `World of Warcraft/_forever_/Interface/AddOns/`
2. **Restart the client.** It indexes addon files at launch, so a `/reload`
   is not enough.
3. Log in. There is nothing to set up.

**You don't need retail, and the empty Music folder is normal.** Every track
FAME plays is already in your Forever client.

## Commands

Everything is also in the UI, but if you prefer chat:

| Command | What it does |
|---|---|
| `/fame ui` | open the music window |
| `/fame settings` | open FAME's settings |
| `/fame status` | what's playing, and what comes next |
| `/fame skip` | end this track as it would end anyway |
| `/fame next` | play an extended track now |
| `/fame ban` | never play this track again |
| `/fame banlist` | banned tracks, and where |
| `/fame unban <id>` or `/fame unban all` | allow banned tracks again |
| `/fame on`, `/fame off` | run FAME, or leave the music to the game |

`/fame help` lists the rest.

## Coverage

All 46 Classic zones and cities, plus every new Forever zone: Mount Hyjal,
Riverglades, Shen'dralas, Darkspear Islands and Zephras Isle. Most zones have
20–60 tracks to draw from.

By era: 89 Classic pieces Forever doesn't use in these zones, 220 from the
Forever soundtrack, and 116 across Cataclysm, Mists, Warlords, Legion,
Battle for Azeroth, Shadowlands, Dragonflight, The War Within and Midnight.

**No Blizzard audio is bundled with or distributed by this addon.** Every
track FAME plays is a file your Forever client already has.

## Plays well with Spoken Quests

When Spoken Quests turns the music down for a voiced line, FAME gives way and
doesn't touch the volume. Your music volume always ends up where you set it.

## Notes

- Inns are recognised by their English names, so on other client languages
  they fall back to the game's own music. Everything else works in any
  language.
- Made for interface 16001.

## Found something that sounds wrong?

"Track X felt wrong in zone Y" is the most useful report this addon can get,
and it's usually a one-line fix. `/fame status` shows the track's name and
ID. Leave a comment here or open an issue on
[GitHub](https://github.com/kirillburton/forever-ambient-music-extended/issues).
