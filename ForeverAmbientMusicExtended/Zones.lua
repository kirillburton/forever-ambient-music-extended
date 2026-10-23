-- Zones.lua -- which tracks are allowed where.
--
-- Keyed by uiMapID, never by zone name: the names are localized, the IDs are
-- not.  These IDs come from the client's own UiMap DB2 for the Forever beta
-- (wago.tools branch wowf), so they are the real thing rather
-- than retail IDs -- Forever uses the Classic 1411..1464 block plus a handful
-- of new ones.  `/fame where` prints the ID for wherever you are standing if
-- you need to check or add one.
--
-- MATCHING RULES.  A track is eligible in a zone when *every* tag it carries
-- is allowed by that zone:
--
--   * it carries every tag listed in the zone's `require`, if there is one
--   * every biome tag on the track must appear in the zone's `biomes`
--   * every culture tag must appear in `cultures`
--   * every mood tag must appear in `moods`
--   * a "day"/"night" tag must match the current server hour
--
-- `require` exists because the other three are allow-lists, and an allow-list
-- cannot keep out a track that simply has nothing to check.  The goblin
-- settlement pieces carry only { "goblin", "playful" } -- no biome at all --
-- so `biomes = { "tavern" }` let them into every inn.  `require` is the only
-- way to say a track must actually *be* tavern music.
--
-- Tags the track does not carry are simply not checked, so a track tagged
-- only { "ruins", "mysterious" } fits any zone that allows ruins and
-- mysterious.  The lists are allow-lists: widening a zone means adding a tag
-- to it, and a zone with no entry at all plays nothing extra.  That is the
-- deliberate default -- silence beats a tuba solo in the Plaguelands.
--
-- Leaving one of the three lists out of a zone is the same as writing an
-- empty one: it rejects every track that carries a tag on that axis.  Always
-- give a zone all three.  `lua tools/check_zones.lua` flags a zone whose pool
-- came out thin, which is what that mistake looks like.
--
-- Inns are handled per building, not per zone: see ns.inns at the bottom.
-- `capital = true` marks the six capitals, where IsResting() is true on every
-- street and so says nothing about being in an inn.
--
-- Everything else the game would play -- the zone's tracks, its subzones',
-- its intros, its silences -- comes from the client's own data in
-- Originals.lua, not from here.

local ADDON, ns = ...

-- Shared presets, so the zone list below stays readable. -------------------

local REST_MOODS = { "festive", "calm", "playful", "eerie", "sacred", "melancholy" }

local function joined(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, tag in ipairs(list) do out[#out + 1] = tag end
    end
    return out
end

-- An inn pool requires the "tavern" tag rather than merely allowing it.  
-- Without that, anything carrying no biome tag of its own walks straight in.
local function restPool(cultures)
    return {
        require = { "tavern" },
        biomes = { "tavern" },
        cultures = cultures,
        moods = REST_MOODS,
    }
end

-- Goblin towns.  Their bazaar music is the sound of the town itself, not of
-- the land around it, so it plays only inside them: those tracks carry the
-- `town` biome, and only these profiles allow it.  A town keeps everything
-- its zone allows and adds the town on top.
--
-- `towns` in a zone entry is keyed by AreaTable ID rather than name, so it
-- works in every locale.  Find a town's ID by name in AreaTable on
-- wago.tools (branch wowf).  After adding one, re-run
-- tools/make_originals.py so FAME can recognise the area, then check
-- `/fame where` inside it shows that area ID.
local function town(zone)
    return {
        biomes = joined(zone.biomes, { "town" }),
        cultures = joined(zone.cultures, { "goblin", "pirate" }),
        moods = joined(zone.moods, { "playful", "festive" }),
    }
end

-- Pirate coves: the sea and its pirates, but no goblin bazaar.  This is
-- where "Ts Have It" (the WoD ocean music) and its kind belong -- they carry
-- the `pirate` culture, which open coastline does not admit.
local function cove(zone)
    return {
        biomes = joined(zone.biomes, { "coast", "sea" }),
        cultures = joined(zone.cultures, { "pirate" }),
        moods = joined(zone.moods, { "playful", "festive", "tense" }),
    }
end

ns.zones = {

    -- ===================== Eastern Kingdoms =====================

    [1416] = { -- Alterac Mountains
        biomes = { "mountain", "snow", "plains", "forest" },
        cultures = { "human", "dwarf", "undead", "orc", "wild" },
        moods = { "calm", "melancholy", "mysterious", "somber", "grand", "heroic", "tense" },
    },
    [1417] = { -- Arathi Highlands
        biomes = { "plains", "mountain", "coast" },
        cultures = { "human", "dwarf", "orc", "troll", "arathi", "wild" },
        moods = { "calm", "mysterious", "heroic", "grand", "melancholy" },
    },
    [1418] = { -- Badlands
        biomes = { "desert", "mountain", "cave", "underground", "ruins" },
        cultures = { "dwarf", "orc", "dragon", "wild" },
        moods = { "mysterious", "ominous", "somber", "tense", "grand" },
    },
    [1419] = { -- Blasted Lands
        biomes = { "blighted", "desert", "ruins", "void" },
        cultures = { "demon", "orc", "undead", "naga" },
        moods = { "ominous", "eerie", "somber", "tense", "mysterious" },
    },
    [1420] = { -- Tirisfal Glades
        biomes = { "blighted", "darkforest", "plains" },
        cultures = { "undead", "human", "drust" },
        moods = { "ominous", "eerie", "somber", "melancholy", "mysterious" },
    },
    [1421] = { -- Silverpine Forest
        biomes = { "darkforest", "blighted", "coast" },
        cultures = { "undead", "human", "drust", "wild" },
        moods = { "eerie", "ominous", "melancholy", "somber", "mysterious" },
    },
    [1422] = { -- Western Plaguelands
        biomes = { "blighted", "plains", "forest" },
        cultures = { "undead", "human" },
        moods = { "somber", "ominous", "eerie", "melancholy" },
    },
    [1423] = { -- Eastern Plaguelands
        biomes = { "blighted", "forest", "ruins" },
        cultures = { "undead", "nerubian" },
        moods = { "ominous", "eerie", "somber", "grand", "mysterious" },
    },
    [1424] = { -- Hillsbrad Foothills
        biomes = { "plains", "forest", "coast", "mountain" },
        cultures = { "human", "dwarf", "undead", "orc", "wild" },
        moods = { "calm", "melancholy", "mysterious", "festive", "tense" },
    },
    [1425] = { -- The Hinterlands
        biomes = { "forest", "jungle", "mountain", "coast" },
        cultures = { "troll", "dwarf", "human", "wild" },
        moods = { "mysterious", "calm", "ominous", "tense", "grand" },
    },
    [1426] = { -- Dun Morogh
        biomes = { "snow", "mountain", "forest", "plains", "cave", "underground" },
        cultures = { "dwarf", "gnome", "earthen", "wild" },
        moods = { "calm", "grand", "mysterious", "melancholy", "heroic", "festive" },
    },
    [1427] = { -- Searing Gorge
        biomes = { "volcanic", "mountain", "underground", "cave", "elemental", "ruins" },
        cultures = { "dwarf", "dragon", "goblin" },
        moods = { "ominous", "tense", "grand", "mysterious" },
    },
    [1428] = { -- Burning Steppes
        biomes = { "volcanic", "mountain", "elemental", "ruins" },
        cultures = { "dwarf", "dragon", "orc", "demon" },
        moods = { "ominous", "tense", "grand", "mysterious", "somber" },
    },
    [1429] = { -- Elwynn Forest
        biomes = { "forest", "plains" },
        cultures = { "human", "dwarf", "gnome", "wild" },
        moods = { "calm", "festive", "playful", "mysterious", "heroic", "grand" },
    },
    [1430] = { -- Deadwind Pass
        biomes = { "darkforest", "ruins", "blighted", "arcane" },
        cultures = { "undead", "human", "demon" },
        moods = { "eerie", "ominous", "somber", "mysterious" },
    },
    [1431] = { -- Duskwood
        biomes = { "darkforest", "blighted" },
        cultures = { "human", "undead", "drust", "wild" },
        moods = { "eerie", "ominous", "melancholy", "mysterious", "somber" },
    },
    [1432] = { -- Loch Modan
        biomes = { "mountain", "forest", "plains", "cave", "underground" },
        cultures = { "dwarf", "gnome", "troll", "earthen", "wild" },
        moods = { "calm", "mysterious", "melancholy", "grand", "festive" },
    },
    [1433] = { -- Redridge Mountains
        biomes = { "mountain", "forest", "plains" },
        cultures = { "human", "orc", "dwarf", "wild" },
        moods = { "calm", "tense", "mysterious", "heroic", "grand" },
    },
    [1434] = { -- Stranglethorn Vale
        biomes = { "jungle", "coast", "sea", "ruins" },
        cultures = { "troll", "human", "goblin", "naga", "wild" },
        moods = { "mysterious", "ominous", "tense", "calm", "grand", "festive", "playful" },
    },
    [1435] = { -- Swamp of Sorrows
        biomes = { "swamp", "blighted", "ruins" },
        cultures = { "troll", "orc", "naga", "undead", "wild" },
        moods = { "eerie", "ominous", "mysterious", "somber", "tense" },
    },
    [1436] = { -- Westfall
        biomes = { "plains", "coast", "sea", "ruins" },
        cultures = { "human", "kultiran", "goblin", "wild" },
        moods = { "calm", "melancholy", "somber", "mysterious", "eerie", "tense" },
    },
    [1437] = { -- Wetlands
        biomes = { "swamp", "coast", "forest", "sea" },
        cultures = { "dwarf", "dragon", "troll", "naga", "kultiran", "wild" },
        moods = { "calm", "mysterious", "eerie", "melancholy", "grand" },
    },
    [1453] = { -- Stormwind City
        capital = true,
        biomes = { "city", "arcane", "coast" },
        cultures = { "human", "dwarf", "gnome", "arathi", "earthen" },
        moods = { "grand", "calm", "heroic", "festive", "playful", "mysterious",
                  "melancholy" },
    },
    [1455] = { -- Ironforge
        capital = true,
        biomes = { "city", "underground", "cave", "arcane" },
        cultures = { "dwarf", "gnome", "earthen" },
        moods = { "grand", "calm", "festive", "heroic", "mysterious", "playful" },
    },
    [1458] = { -- Undercity
        capital = true,
        biomes = { "city", "underground", "blighted" },
        cultures = { "undead", "nerubian" },
        moods = { "ominous", "eerie", "somber", "grand", "mysterious" },
    },
    [2548] = { -- Riverglades (new in Forever)
        biomes = { "forest", "plains", "swamp", "coast" },
        cultures = { "human", "dwarf", "drust", "wild" },
        moods = { "calm", "mysterious", "melancholy", "festive", "eerie", "playful" },
    },

    -- Alterac Valley (1459), Warsong Gulch (1460) and Arathi Basin (1461) are
    -- deliberately absent: battlegrounds have their own PvP music, and this
    -- is not the place to argue with it.

    -- ========================= Kalimdor =========================

    [1411] = { -- Durotar
        biomes = { "barrens", "plains", "desert", "coast", "mountain" },
        cultures = { "orc", "troll", "goblin", "wild" },
        moods = { "heroic", "tense", "calm", "grand", "mysterious", "playful" },
    },
    [1412] = { -- Mulgore
        biomes = { "plains", "barrens", "mountain" },
        cultures = { "tauren", "centaur", "wild" },
        moods = { "calm", "grand", "melancholy", "mysterious", "heroic" },
    },
    [1413] = { -- The Barrens
        biomes = { "barrens", "plains", "desert", "coast", "mountain" },
        cultures = { "orc", "tauren", "troll", "centaur", "goblin", "wild" },
        moods = { "calm", "tense", "mysterious", "grand", "heroic", "playful" },
    },
    [1438] = { -- Teldrassil
        biomes = { "forest", "enchanted" },
        cultures = { "nightelf", "wild" },
        moods = { "calm", "mysterious", "sacred", "melancholy", "grand" },
    },
    [1439] = { -- Darkshore
        biomes = { "coast", "darkforest", "forest", "sea", "ruins" },
        cultures = { "nightelf", "naga", "drust", "wild" },
        moods = { "melancholy", "eerie", "mysterious", "somber", "calm" },
    },
    [1440] = { -- Ashenvale
        biomes = { "forest", "darkforest", "enchanted" },
        cultures = { "nightelf", "orc", "demon", "wild" },
        moods = { "calm", "mysterious", "sacred", "melancholy", "tense", "eerie" },
    },
    [1441] = { -- Thousand Needles
        biomes = { "desert", "mountain", "plains", "barrens" },
        cultures = { "tauren", "centaur", "goblin", "naga", "wild" },
        moods = { "mysterious", "calm", "grand", "tense", "playful" },
    },
    [1442] = { -- Stonetalon Mountains
        biomes = { "mountain", "forest", "plains" },
        cultures = { "nightelf", "orc", "tauren", "goblin", "wild" },
        moods = { "calm", "mysterious", "tense", "melancholy", "grand" },
    },
    [1443] = { -- Desolace
        biomes = { "desert", "blighted", "barrens", "coast", "ruins" },
        cultures = { "centaur", "naga", "undead", "demon", "wild" },
        moods = { "somber", "ominous", "eerie", "mysterious", "melancholy" },
    },
    [1444] = { -- Feralas
        biomes = { "forest", "jungle", "enchanted", "coast", "ruins" },
        cultures = { "nightelf", "highelf", "troll", "naga", "wild" },
        moods = { "calm", "mysterious", "sacred", "melancholy", "grand" },
    },
    [1445] = { -- Dustwallow Marsh
        biomes = { "swamp", "coast", "plains" },
        cultures = { "human", "orc", "dragon", "naga", "kultiran", "wild" },
        moods = { "eerie", "mysterious", "somber", "tense", "calm" },
    },
    [1446] = { -- Tanaris
        biomes = { "desert", "coast", "sea", "ruins" },
        cultures = { "goblin", "dragon", "naga", "wild" },
        moods = { "mysterious", "calm", "tense", "grand", "playful" },
    },
    [1447] = { -- Azshara
        biomes = { "forest", "coast", "sea", "ruins", "arcane" },
        cultures = { "nightelf", "highelf", "naga", "demon", "wild" },
        moods = { "mysterious", "melancholy", "eerie", "grand", "calm" },
    },
    [1448] = { -- Felwood
        biomes = { "darkforest", "blighted" },
        cultures = { "demon", "nightelf", "wild" },
        moods = { "ominous", "eerie", "somber", "tense", "mysterious" },
    },
    [1449] = { -- Un'Goro Crater
        biomes = { "jungle", "volcanic", "cave" },
        cultures = { "troll", "dragon", "wild" },
        moods = { "mysterious", "tense", "calm", "ominous", "grand" },
    },
    [1450] = { -- Moonglade
        biomes = { "forest", "enchanted" },
        cultures = { "nightelf", "wild" },
        moods = { "sacred", "calm", "mysterious", "melancholy", "grand" },
    },
    [1451] = { -- Silithus
        biomes = { "desert", "barrens", "ruins" },
        cultures = { "nerubian", "dragon", "wild" },
        moods = { "ominous", "eerie", "mysterious", "somber", "tense", "grand" },
    },
    [1452] = { -- Winterspring
        biomes = { "snow", "mountain", "forest", "cave" },
        cultures = { "nightelf", "dwarf", "tuskarr", "earthen", "wild" },
        moods = { "calm", "mysterious", "melancholy", "grand", "sacred" },
    },
    [1454] = { -- Orgrimmar
        capital = true,
        biomes = { "city", "plains", "desert", "mountain", "arcane" },
        cultures = { "orc", "troll", "tauren", "goblin", "undead" },
        moods = { "grand", "heroic", "tense", "festive", "calm", "playful" },
    },
    [1456] = { -- Thunder Bluff
        capital = true,
        biomes = { "city", "plains", "mountain" },
        cultures = { "tauren", "centaur", "wild" },
        moods = { "calm", "grand", "sacred", "melancholy", "mysterious", "festive" },
    },
    [1457] = { -- Darnassus
        capital = true,
        biomes = { "city", "forest", "enchanted" },
        cultures = { "nightelf", "highelf" },
        moods = { "sacred", "calm", "grand", "mysterious", "melancholy" },
    },
    [2482] = { -- Mount Hyjal (new in Forever)
        biomes = { "forest", "mountain", "enchanted", "snow" },
        cultures = { "nightelf", "demon", "wild" },
        moods = { "sacred", "calm", "grand", "mysterious", "melancholy", "heroic" },
    },
    [2652] = { -- Shen'dralas (new in Forever)
        biomes = { "forest", "enchanted", "ruins" },
        cultures = { "nightelf", "highelf", "wild" },
        moods = { "mysterious", "sacred", "calm", "melancholy", "grand", "eerie" },
    },
    [2524] = { -- Darkspear Islands (new in Forever)
        biomes = { "jungle", "coast", "sea" },
        cultures = { "troll", "naga", "wild" },
        moods = { "tense", "mysterious", "ominous", "calm", "grand" },
    },

    -- Zephras Isle (new in Forever).  2521 is the zone under Azeroth, 2665 the
    -- standalone continent-level map; both can come back from
    -- GetBestMapForUnit depending on where you are, so both are listed.
    -- These tags are a guess from the name -- check them in game and edit.
    [2521] = {
        biomes = { "coast", "sea", "plains", "sky", "ruins" },
        cultures = { "naga", "kultiran", "tuskarr", "wild" },
        moods = { "calm", "mysterious", "grand", "tense", "melancholy" },
    },
    [2665] = {
        biomes = { "coast", "sea", "plains", "sky", "ruins" },
        cultures = { "naga", "kultiran", "tuskarr", "wild" },
        moods = { "calm", "mysterious", "grand", "tense", "melancholy" },
    },
}

-- Dungeons, raids and battlegrounds are left entirely to the game: FAME
-- releases the music channel the moment you step into an instance.

-- Goblin towns, attached after the fact so town() can copy the zone.
ns.zones[1413].towns = ns.zones[1413].towns or {}
ns.zones[1413].towns[392] = town(ns.zones[1413])   -- Ratchet
ns.zones[1434].towns = ns.zones[1434].towns or {}
ns.zones[1434].towns[35] = town(ns.zones[1434])   -- Booty Bay
ns.zones[1446].towns = ns.zones[1446].towns or {}
ns.zones[1446].towns[976] = town(ns.zones[1446])   -- Gadgetzan
ns.zones[1446].towns = ns.zones[1446].towns or {}
ns.zones[1446].towns[977] = town(ns.zones[1446])   -- Steamwheedle Port
ns.zones[1452].towns = ns.zones[1452].towns or {}
ns.zones[1452].towns[2255] = town(ns.zones[1452])   -- Everlook
ns.zones[1434].towns[43] = cove(ns.zones[1434])     -- Wild Shore
ns.zones[1434].towns[312] = cove(ns.zones[1434])    -- Janeiro's Point
ns.zones[1434].towns[1739] = cove(ns.zones[1434])   -- Bloodsail Compound
ns.zones[1413].towns[391] = cove(ns.zones[1413])    -- The Merchant Coast
ns.zones[1446].towns[1336] = cove(ns.zones[1446])   -- Lost Rigger Cove

-- --------------------------------------------------------------------------
-- Inns
-- --------------------------------------------------------------------------
--
-- Inside an inn FAME plays that tavern's own race, and nothing else: the
-- game's tavern music set for that race as the "original" share, and only
-- tavern tracks of that race from the extended pool.
--
-- Which inn you are in comes from the building's name, as GetMinimapZoneText()
-- shows it inside.  The race has to be written down here by hand: the game's
-- own data names almost no inn's race -- nearly every inn it knows plays the
-- generic Alliance or Horde tavern set, and most Horde and Kalimdor inns have
-- no named building at all.  So this lists only inns whose race is certain.
--
-- Any other inn -- resting, indoors, outside a capital, and not on this list
-- -- is left to the game, which plays its own music there.
--
-- Names are English, as the client shows them on an English client.  On
-- another language they will not match, and every inn falls back to the game.
ns.inns = {
    ["Lion's Pride Inn"] = "human",          -- Goldshire, Elwynn Forest
    ["Scarlet Raven Tavern"] = "human",      -- Darkshire, Duskwood
    ["Lakeshire Inn"] = "human",             -- Lakeshire, Redridge Mountains
    ["Stoutlager Inn"] = "dwarf",            -- Thelsamar, Loch Modan
    ["Thunderbrew Distillery"] = "dwarf",    -- Kharanos, Dun Morogh
    ["Deepwater Tavern"] = "dwarf",          -- Menethil Harbor, Wetlands
    ["The Stonefire Tavern"] = "dwarf",      -- Ironforge
    ["Gallows' End Tavern"] = "undead",      -- Brill, Tirisfal Glades
    ["The Salty Sailor Tavern"] = "pirate",  -- Booty Bay, Stranglethorn Vale
}

-- One extended-pool profile per race: tavern music of that race only.
ns.innProfiles = {}
for _, race in pairs(ns.inns) do
    ns.innProfiles[race] = ns.innProfiles[race] or restPool({ race })
end
