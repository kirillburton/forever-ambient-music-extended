"""Shared helpers for talking to wago.tools and for tagging music file paths.

wago.tools endpoints used (both verified working 2026-10-05):

  GET https://wago.tools/api/files?search=<substring>&branch=<branch>
      -> JSON object { "<fileDataID>": "<lowercase/path.mp3", ... }
      The `branch` filter is real: a retail-only path returns [] for
      branch=wow_classic_beta.  Spot-checked against the client: the ten IDs
      tested in game matched this list exactly (625753 + 4872416 present, the
      other eight absent).

  GET https://wago.tools/api/casc/<fileDataID>?download
      -> the raw file bytes.  No Range or Content-Length support, so a
      duration probe has to pull the whole file.

Branch for World of Warcraft: Forever beta is `wow_classic_beta`.
"""

import json
import os
import re
import urllib.parse
import urllib.request

BRANCH = "wow_classic_beta"
FILES_URL = "https://wago.tools/api/files"
CASC_URL = "https://wago.tools/api/casc/{fdid}?download"
UA = {"User-Agent": "extended-ambient-music-forever/0.1 (addon build tool)"}

CACHE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cache")


def fetch_file_list(search="sound/music", branch=BRANCH, timeout=120):
    """Return {fileDataID:int -> path:str} for every file whose path contains `search`."""
    url = "%s?%s" % (FILES_URL, urllib.parse.urlencode({"search": search, "branch": branch}))
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.load(r)
    if isinstance(data, list):  # wago returns [] rather than {} for "no matches"
        return {}
    return {int(k): v for k, v in data.items()}


def download(fdid, dest, timeout=180):
    req = urllib.request.Request(CASC_URL.format(fdid=fdid), headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r, open(dest, "wb") as f:
        while True:
            chunk = r.read(1 << 18)
            if not chunk:
                break
            f.write(chunk)
    return os.path.getsize(dest)


# --------------------------------------------------------------------------
# Tagging
# --------------------------------------------------------------------------

# Anything matching these is not ambient zone music.  The handoff asks to skip
# cinematic/event material; stingers, main titles and jukebox pop are the same
# problem for different reasons.
SKIP_PATTERNS = [
    r"\brtc[_/]", r"cinematic", r"/event/", r"worldevents", r"gluescreen",
    r"maintitle", r"stinger", r"jukebox", r"plunderstorm", r"musical moments",
    r"darkmoonfaire", r"darkmoon_faire", r"dmf_", r"_moment", r"/pvp/", r"_pvp_", r"zfbigbattle", r"zfmedbattle",
    r"zfstinger", r"zfrally", r"gnomeregan_event", r"firepole", r"dragonrace",
    r"race_intro", r"_battle_", r"battle_boss", r"warfrontsbattle", r"classicbattle",
    r"void_combat", r"domination_battle", r"freeholdcombat", r"arenastart",
    r"_intro\b", r"_intro\.", r"intro_moment", r"_intro_", r"nerubian_raid",
    r"raid_91", r"_beta\b",
]
SKIP_RE = re.compile("|".join(SKIP_PATTERNS))

# path keyword -> tags.  Longest-first application; order here is irrelevant.
KEYWORD_TAGS = {
    # --- time of day -----------------------------------------------------
    "dayforest": ["forest", "day"], "nightforest": ["forest", "night"],
    "dayevilforest": ["darkforest", "day"], "nightevilforest": ["darkforest", "night"],
    "dayjungle": ["jungle", "day"], "nightjungle": ["jungle", "night"],
    "daydesert": ["desert", "day"], "nightdesert": ["desert", "night"],
    "daymountain": ["mountain", "day"], "nightmountain": ["mountain", "night"],
    "dayplains": ["plains", "day"], "nightplains": ["plains", "night"],
    "dayvolcanic": ["volcanic", "day"], "nightvolcanic": ["volcanic", "night"],
    "daybarrendry": ["barrens", "day"], "nightbarrendry": ["barrens", "night"],
    "day_forest": ["forest", "day"], "night_forest": ["forest", "night"],
    "day_evil_forest": ["darkforest", "day"], "night_evil_forest": ["darkforest", "night"],
    "day_jungle": ["jungle", "day"], "night_jungle": ["jungle", "night"],
    "day_desert": ["desert", "day"], "night_desert": ["desert", "night"],
    "day_mountain": ["mountain", "day"], "night_mountain": ["mountain", "night"],
    "day_plains": ["plains", "day"], "night_plains": ["plains", "night"],
    "day_volcanic": ["volcanic", "day"], "night_volcanic": ["volcanic", "night"],
    "day_barren_dry": ["barrens", "day"], "night_barren_dry": ["barrens", "night"],
    "walkday": ["day"], "walknight": ["night"],
    "walk_day": ["day"], "walk_night": ["night"],
    "_night_": ["night"], "_night\\b": ["night"], "_day\\b": ["day"],
    # --- biomes ----------------------------------------------------------
    "enchantedforest": ["forest", "enchanted", "nightelf", "mysterious"],
    "enchanted_forest": ["forest", "enchanted", "nightelf", "mysterious"],
    "druid_grove": ["forest", "enchanted", "nightelf", "sacred"],
    "soggyplace": ["swamp", "eerie"], "soggy_place": ["swamp", "eerie"],
    "swamp": ["swamp"], "mire": ["swamp", "eerie"],
    "cursedland": ["blighted", "undead", "ominous"],
    "cursed_land": ["blighted", "undead", "ominous"],
    "ghostmusic": ["blighted", "eerie"], "haunted": ["blighted", "eerie"],
    "ghost_music": ["blighted", "eerie"],
    "gloomy": ["darkforest", "melancholy"],
    "sholazar": ["jungle", "wild", "calm"],
    "terokkar": ["forest", "ruins", "somber"], "bone_wastes": ["ruins", "somber"],
    "bonewalk": ["forest", "ruins", "somber"],
    "tundra": ["snow", "calm"], "coldmountain": ["snow", "mountain", "melancholy"],
    "skywall": ["sky", "elemental", "grand"], "stormrider": ["sky", "grand"],
    "firelands": ["volcanic", "elemental", "ominous"],
    "fire_uu": ["volcanic", "elemental", "tense"],
    "riplash": ["coast", "sea", "naga"],
    "highseas": ["sea", "coast", "heroic"], "kultiras_sky": ["coast", "sea", "kultiran"],
    "stormsong": ["coast", "plains", "kultiran", "calm"],
    "shrineofstorms": ["coast", "sea", "ominous"],
    "naga_incursion": ["coast", "naga", "tense"],
    "underground": ["underground", "cave"], "cavernsoflife": ["cave", "underground"],
    "ringing_deeps": ["underground", "cave", "earthen"],
    "gnomeragon": ["underground", "gnome"], "gnomeregon": ["underground", "gnome"],
    "nerubian_nest": ["underground", "nerubian", "eerie"],
    "weavers_lair": ["underground", "nerubian", "eerie"],
    "silken_path": ["underground", "nerubian", "mysterious"],
    "ruins": ["ruins", "mysterious"],
    "alpine": ["mountain", "snow"],
    "wetlands": ["swamp", "coast"],
    "mountain": ["mountain"], "foothills": ["mountain"],
    "plains": ["plains"], "countryside": ["plains", "calm"],
    "groves": ["plains", "forest", "calm"],
    "jungle": ["jungle"], "desert": ["desert"],
    "volcanic": ["volcanic"], "forest": ["forest"],
    # --- cultures --------------------------------------------------------
    "stormwind": ["city", "human", "grand"], "human": ["human"],
    "ironforge": ["city", "dwarf", "grand"], "dwarf": ["dwarf"],
    "tinkertown": ["city", "gnome"],
    "darnass": ["city", "nightelf", "sacred"], "nightelves": ["nightelf"],
    "nightelf": ["nightelf"], "teldrassil": ["forest", "nightelf", "calm"],
    "templeofthemoon": ["nightelf", "sacred"],
    "orgrimmar": ["city", "orc", "grand"], "orc": ["orc"],
    "thunder_bluff": ["city", "tauren", "calm"], "thunderbluff": ["city", "tauren", "calm"],
    "tauren": ["tauren"],
    "undercity": ["city", "undead", "ominous"], "undead": ["undead"],
    "zalazanes_fall": ["jungle", "troll", "tense"],
    "stranglethorn": ["jungle", "troll"], "zuldazar": ["jungle", "troll", "grand"],
    "zulaman": ["jungle", "troll", "ominous"], "zulgurub": ["jungle", "troll", "ominous"],
    "atalaman": ["jungle", "troll", "mysterious"], "akilzon": ["jungle", "troll", "ominous"],
    "loa_bwonsamdi": ["jungle", "troll", "eerie"],
    "troll": ["troll"],
    "goblin": ["goblin", "playful"],
    "eversong": ["forest", "highelf", "calm"], "silvermoon": ["city", "highelf", "grand"],
    "lake_eldrendar": ["forest", "highelf", "calm"],
    "exodar": ["city", "draenei", "arcane"], "azuremyst": ["forest", "draenei", "calm"],
    "shadowmoon": ["sky", "nightelf", "sacred"],
    "dalaran": ["city", "arcane", "mysterious"], "magic_1": ["arcane", "mysterious"],
    "mystery": ["mysterious"],
    "suramar": ["city", "nightelf", "arcane", "mysterious"],
    "highmountain": ["mountain", "tauren", "grand"],
    "stormheim": ["mountain", "coast", "vrykul", "heroic"],
    "drustvar": ["darkforest", "drust", "eerie"],
    "lordaeron": ["blighted", "undead", "somber"],
    "windrunner": ["forest", "undead", "melancholy"],
    "arathi": ["plains", "arathi"], "ashvane": ["coast", "kultiran", "tense"],
    "kultiran": ["coast", "kultiran"],
    "sethrak": ["desert", "mysterious"],
    "ohnahran": ["plains", "centaur", "calm"], "centaur": ["plains", "centaur"],
    "tuskarr": ["snow", "coast", "tuskarr", "calm"],
    "azurespan": ["snow", "forest", "calm"],
    "thaldraszus": ["mountain", "dragon", "grand"],
    "valdrakken": ["city", "dragon", "grand"],
    "wakingshore": ["coast", "dragon"], "forbiddenreach": ["coast", "ruins", "dragon"],
    "lifepools": ["mountain", "dragon", "calm"],
    "djaradin": ["mountain", "ominous"],
    "brackenhide": ["swamp", "wild", "eerie"],
    "dragon": ["dragon"],
    "earthen": ["underground", "earthen"], "dornogal": ["city", "earthen", "grand"],
    "isle_of_dorn": ["plains", "coast", "earthen", "calm"],
    "cinderwold": ["darkforest", "ominous"],
    "mereldar": ["plains", "arathi", "sacred"],
    "sacred_flame": ["sacred", "arathi"], "the_light": ["sacred", "grand"],
    "proscenium": ["arcane", "mysterious"],
    "aegis_wall": ["mountain", "arathi", "grand"],
    "alleria": ["melancholy", "void"],
    "xalatath": ["void", "ominous"], "voidstorm": ["void", "ominous"],
    "shadowguard_void": ["void", "eerie"], "devouring_host": ["void", "ominous"],
    "locus_point": ["void", "arcane", "mysterious"],
    "world_soul_cradle": ["sacred", "grand"], "lightbloom": ["forest", "sacred", "calm"],
    "harandar": ["desert", "highelf", "mysterious"],
    "teldrassil_roots": ["forest", "nightelf", "melancholy"],
    "arator": ["sacred", "heroic"],
    "pandaria": ["forest", "pandaren", "calm"], "heartland": ["plains", "pandaren", "calm"],
    "wanderingisle": ["forest", "pandaren", "calm"],
    "mistweaver": ["pandaren", "calm"], "liulang": ["pandaren", "melancholy"],
    "serpentriders": ["pandaren", "sky"], "templeofthefivedawns": ["pandaren", "sacred"],
    "spiritpath": ["pandaren", "mysterious"], "veb_b": ["pandaren", "calm"],
    "balloonride": ["pandaren", "playful"],
    "nagrand": ["plains", "orc", "grand"], "herdingclans": ["plains", "orc"],
    "chieftansgather": ["plains", "orc", "heroic"],
    "traversingthespires": ["mountain", "grand"],
    "quietheart": ["melancholy", "calm"], "etherealembers": ["mysterious", "arcane"],
    "proudmoore": ["heroic", "human"], "bfreedom": ["heroic"],
    "aherossacrifice": ["somber", "heroic"], "alightinthedarkness": ["sacred", "melancholy"],
    "malach": ["ominous"], "mandown": ["somber"], "risetothedark": ["ominous"],
    "tshaveit": ["playful"], "worldexpo": ["playful", "goblin"],
    "nightfae": ["forest", "enchanted", "mysterious"],
    "nocturne_celestial": ["enchanted", "sacred", "night"],
    "nocturne_melancholy": ["enchanted", "melancholy", "night"],
    "choice_rebirth": ["enchanted", "sacred"], "choice_oblivion": ["enchanted", "somber"],
    "kyrian": ["sacred", "grand"], "aspirantsjourney": ["sacred", "heroic"],
    "oribos": ["city", "arcane", "mysterious"], "broker_opulence": ["city", "playful"],
    "decadence": ["city", "ominous"], "venthyr": ["city", "ominous"],
    "rd_ritual": ["ominous", "eerie"],
    "necrolord": ["blighted", "undead", "ominous"],
    "sansprimus": ["blighted", "somber"], "seatoftheprimus": ["blighted", "grand"],
    "hopeabandoned": ["void", "somber"],
    "shadow_revelation": ["void", "mysterious"],
    "nossharah": ["desert", "ruins", "ominous"],
    "emeraldnightmare": ["darkforest", "eerie", "ominous"],
    "tempest": ["sea", "coast", "tense"],
    "twilightshammer": ["ominous", "eerie"], "shattering": ["ominous", "grand"],
    "rift_uu": ["arcane", "eerie"], "alliancehero": ["heroic", "human"],
    "westplaguea": ["blighted", "undead", "somber"],
    "arathihighlandsa": ["plains", "arathi", "calm"],
    "freehold": ["coast", "festive", "playful"],
    "riverglades": ["forest", "human", "calm"],
    "hyjal": ["forest", "mountain", "nightelf", "sacred"],
    "malornes_retreat": ["forest", "nightelf", "sacred"],
    "shrine_of_aviana": ["forest", "nightelf", "sacred"],
    "cradle_of_tranquility": ["forest", "enchanted", "calm"],
    "shendar": ["forest", "nightelf", "mysterious"],
    "shen'dralas": ["forest", "nightelf", "mysterious"],
    "elderwild": ["forest", "wild", "mysterious"],
    "shadowgale_forest": ["darkforest", "eerie"],
    "twilights_shroud": ["darkforest", "ominous"],
    "tainted_foothills": ["mountain", "blighted", "ominous"],
    "felblood_scar": ["blighted", "demon", "ominous"],
    "mournings_rest": ["blighted", "somber"],
    "eastwind_shore": ["coast", "calm"],
    "gustberry_lowlands": ["plains", "calm"],
    "sunnyglade": ["forest", "calm"], "wheelers_grange": ["plains", "human", "calm"],
    "thendal_village": ["forest", "nightelf", "calm"],
    "valanaar": ["ruins", "mysterious"],
    "shrine_of_akir": ["ruins", "sacred", "mysterious"],
    "summit_of_eternity": ["mountain", "sky", "grand"],
    "rogmar_outpost": ["mountain", "orc"], "bolderok": ["mountain", "underground"],
    "daegun": ["mountain", "mysterious"], "farholde_keep": ["mountain", "human"],
    "skyborne": ["sky", "grand"], "warrior_terrace": ["heroic"],
    "angelic": ["sacred", "calm"], "sacred_": ["sacred"],
    "spooky": ["eerie"], "horror": ["eerie", "ominous"],
    # --- taverns ---------------------------------------------------------
    "tavernalliance": ["tavern", "human", "festive"],
    "tavern_alliance": ["tavern", "human", "festive"],
    "tavernhorde": ["tavern", "orc", "festive"],
    "tavern_horde": ["tavern", "orc", "festive"],
    "taverndwarf": ["tavern", "dwarf", "festive"],
    "dwarves_tavern": ["tavern", "dwarf", "festive"],
    "tavernhuman": ["tavern", "human", "festive"],
    "human_tavern": ["tavern", "human", "festive"],
    "tavernnightelf": ["tavern", "nightelf", "calm"],
    "tavernorc": ["tavern", "orc", "festive"],
    "orc_rest_area": ["tavern", "orc", "festive"],
    "taverntauren": ["tavern", "tauren", "calm"],
    "tauren_rest_area": ["tavern", "tauren", "calm"],
    "tavernundead": ["tavern", "undead", "eerie"],
    "undead_tavern": ["tavern", "undead", "eerie"],
    "undead_dance": ["tavern", "undead", "festive"],
    "tavernpirate": ["tavern", "pirate", "festive", "playful"],
    "pirate_tavern": ["tavern", "pirate", "festive", "playful"],
    "khaz_algar_inn": ["tavern", "earthen", "calm"],
    "tavern": ["tavern"], "_inn_": ["tavern"],
}

ERA_BY_DIR = {
    "zonemusic": "classic", "citymusic": "classic", "forever": "forever",
    "cataclysm": "cata", "pandaria": "mop", "draenor": "wod", "legion": "legion",
    "battleforazeroth": "bfa", "shadowlands": "sl", "dragonflight": "df",
    "warwithin": "tww", "midnight": "midnight",
}


def should_skip(path):
    return bool(SKIP_RE.search(path))


def guess_tags(path):
    """First-pass tag guess from a file path.  Returns a sorted list."""
    p = path.lower()
    tags = set()
    for kw, tg in KEYWORD_TAGS.items():
        pat = kw if "\\b" in kw else re.escape(kw)
        if re.search(pat, p):
            tags.update(tg)
    # Day/night are mutually exclusive; an explicit "night" keyword wins.
    if "night" in tags and "day" in tags:
        tags.discard("day")
    # darkforest is a narrower claim than forest, and a zone that asks for
    # plain forest should not get Duskwood music.
    if "darkforest" in tags:
        tags.discard("forest")
    return sorted(tags)


def era_of(path):
    parts = path.split("/")
    return ERA_BY_DIR.get(parts[2] if len(parts) > 2 else "", "other")


# --------------------------------------------------------------------------
# Which files belong in the extension pool
# --------------------------------------------------------------------------

# The point of the addon is to widen the rotation, so the tracks the client
# already plays by itself in these zones add nothing.  These are the stock
# Classic biome/city sets and their Forever remasters.
ALREADY_IN_ROTATION = [
    r"zonemusic/(forest|evilforest|jungle|desert|mountain|plains|volcanic|barrendry)/",
    r"zonemusic/soggyplace/",
    r"/citymusic/",
    r"forever/mus_c_(day|night)_",
    r"forever/mus_c_(stormwind|ironforge|orgrimmar|thunder_bluff|darnasssus|undercity)",
]

# Interior/encounter music for a specific raid or dungeon.  Dropping these into
# an open-world rotation is exactly the "sounds out of place" failure.
INSTANCE_ONLY = [
    r"zonemusic/(cavernsoftime|naxxramas|ahnqiraj)/",
    r"forever/mus_c_(naxxramas|ahnqiraj)",
    r"forever/mus_c60_dungeons_",
    r"zonemusic/os\d\.mp3",
    r"forever/mus_c_(gnomeragon|warrior_terrace|zulgurub_voodoo)",
]

_POOL_EXCLUDE_RE = re.compile("|".join(ALREADY_IN_ROTATION + INSTANCE_ONLY))


def in_extension_pool(path):
    """True if `path` is a candidate for the addon's extended rotation."""
    return not should_skip(path) and not _POOL_EXCLUDE_RE.search(path)
