# Forever Ambient Music Extended (FAME)

**For World of Warcraft: Forever.** Not retail, not Classic Era.

Classic's zone music is beautiful and there is not very much of it. After a few
hundred hours you know every bar of Elwynn Forest.

This addon widens the rotation without changing the rhythm. The game's own
music schedule stays exactly as it is — the same silences between tracks, the
same intros on arrival, its own tracks still in the mix — but some of those
tracks now come from a pool of **408 more**, each chosen to fit where you are
standing: Classic pieces Forever doesn't use in those zones, the new Forever
zone music, and selections from Cataclysm through Midnight.

No UI, no setup, nothing to click. It sounds like the default ambient music,
with more variety.

---

## What it sounds like

- **Duskwood** draws on Drustvar, Cinderwold, the Emerald Nightmare and
  Twilight's Shroud.
- **Mulgore** gets Highmountain, Ohn'ahran Plains and the Gustberry Lowlands.
- **Stranglethorn Vale** gets Zuldazar, Sholazar Basin and Zul'Aman.
- **The Plaguelands** get Lordaeron, Mourning's Rest and the Maw.
- **Inns and taverns** play the right culture's rest-area music for wherever
  you happen to be sitting.
- Sholazar Basin's day and night variants only play at the right hour.

Nothing turns up out of place. Every track is tagged by biome, culture and
mood, and every zone is an allow-list on all three axes — a track plays only
if *every* tag it carries is welcome there. A night elf lament will not wander
into Orgrimmar. Zones with nothing suitable stay quiet rather than reaching.

## It keeps the game's rhythm

- **The same silences.** Between tracks it waits exactly as long as the game
  would in that place, read from the game's own data: three to five minutes
  in most zones.
- **Loop Music is respected.** Turn it on in Audio options and tracks play
  back to back, just as the game's would.
- **40% of tracks are still the game's own,** and the first track when you
  arrive somewhere always is. Both are adjustable.
- **Intros still play** — Orgrimmar's fanfare, the Ironforge King theme — on
  the game's own cooldowns.
- **Subzones and inns switch music where the game would:** the Crossroads,
  Booty Bay, every inn in its own culture's tavern music.
- Never the same track twice in a row, and tracks fade out rather than
  cutting off.
- Dungeons, raids and battlegrounds are left completely alone, and so are
  death, the spirit walk back, ship crossings on the open sea, and anywhere
  with music turned off. There the game's own music rules apply, untouched.

## Ban what you don't like

Hear something you never want again? `/fame ban` stops it and bans it,
whether it's the game's own track or an extended one. Banned tracks are left
out before every decision, so the next pick is always something you allow.
`/fame banlist` shows what you've banned and where; `/fame unban <id>` or
`/fame unban all` brings tracks back.

## Install

1. Drop the `ForeverAmbientMusicExtended` folder into
   `World of Warcraft/_classic_beta_/Interface/AddOns/`
2. **Restart the client.** The client indexes addon files at launch, so a
   `/reload` is not enough.
3. Log in. There is nothing to configure.

Check it loaded with `/fame status`. Every command is under `/fame`.

## Commands

| | |
|---|---|
| `/fame on` \| `off` \| `toggle` | turn the extended rotation on or off |
| `/fame status` | what is playing, how big the pool is here |
| `/fame skip` | end this track as it would end anyway |
| `/fame next` | end this track, play an extended one now |
| `/fame where` | uiMapID, subzone, resting/indoors, server hour |
| `/fame pool [n]` | list the tracks eligible where you are standing |
| `/fame play <fileDataID>` | play one track now |
| `/fame ban` | ban the current track |
| `/fame banlist` | list banned tracks and where |
| `/fame unban <id>` \| `all` | allow banned tracks again |
| `/fame chance <0-100>` | percent of tracks kept as the game's own |
| `/fame first` | let the first track in a new place be extended too |
| `/fame debug` | narrate every decision |

## Coverage

All 46 Classic zones and cities, plus every new Forever zone: Mount Hyjal,
Riverglades, Shen'dralas, Darkspear Islands and Zephras Isle. Most zones have
20–60 eligible tracks; none has fewer than twelve.

By era: 73 Classic pieces Forever doesn't use in these zones, 220 from the
Forever soundtrack itself, and 115 across Cataclysm, Mists, Warlords, Legion,
Battle for Azeroth, Shadowlands, Dragonflight, The War Within and Midnight.

**No Blizzard audio is bundled with or distributed by this addon.** Every
built-in track is a file your Forever client already has — the list was
generated from the client's own file manifest, so there is nothing to
download and nothing to go missing.

## Notes

- Forever beta writes SavedVariables but does not always load them back, so a
  setting changed with `/fame chance`, or a ban, may not survive a logout. The defaults
  are what the addon is tuned for, so this rarely matters.
- Tuned for interface 16001. If a patch moves it, the `.toc` needs one line
  changed.

## Found something that sounds wrong?

Please report it — "track X felt wrong in zone Y" is the single most useful
bug report this addon can get, and it is usually a one-line fix. 
Use `/fame status` for exact ids.

Zone pools
and track tags are both plain data files you can read and edit yourself.