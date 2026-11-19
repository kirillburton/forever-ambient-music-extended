#!/usr/bin/env python3
"""Catalogue the retail client's ambient music that Forever does not have.

    python3 tools/retail_catalog.py              # scan, measure, tag -> tools/retail_catalog.csv
    python3 tools/retail_catalog.py --no-probe   # skip measuring durations
    python3 tools/retail_catalog.py --refresh    # re-download listfile and DB2 tables

Groundwork for "import music from modern WoW": it lists what a player with
retail installed could extract and add through the Music folder
(tools/local_tracks.py), and tags each track with FAME's own vocabulary.  It
does not touch Tracks.lua or Zones.lua.

Sources, all for the installed retail build (product `wow`):

  local CASC (tools/casc_scan.py)   which FileDataIDs retail and Forever ship,
                                    whether the file is on this disk, encrypted
  community listfile (wowdev)       FileDataID -> path, for sound/music/
  retail DB2 via wago.tools         ZoneMusic -> SoundKitEntry: the tracks the
                                    game itself plays as zone music;
                                    AreaTable / WMOAreaTable -> Map: where, and
                                    whether that place is open world

Status of each row, first match wins:

  skip       cinematic, event, stinger, title, PvP, battle cue (wagolib.SKIP_RE)
  absent     not on this disk, or encrypted -- cannot be extracted from here
  short      under 30 seconds
  instance   the game plays it only in dungeons, raids, scenarios or PvP maps
  world      the game plays it as zone music somewhere in the open world
  reused     open world, but only through a dungeon, delve, event or housing set
  battle     only ever in combat / boss sets
  sibling    unplaced, but another take of a piece placed in the open world;
             it borrows that piece's home and tags
  cue        unplaced, and named like a scripted cue (sting, scene, intro...)
  unlinked   in sound/music but no zone-music set uses it (quest, scripted)

Tags: retail_zone_tags.csv gives each open-world zone a tag set, and a track
gets the union over its zones.  Unlinked tracks fall back to the path keywords
in wagolib.  tools/retail_tag_overrides.csv has the final word, per track.

Durations: each file is decoded from the local CASC archives into a temp file,
measured with ffprobe and deleted at once.  Cached in tools/cache/durations.json.
No audio is kept, and nothing Blizzard-owned is written to the repo.
"""

import argparse
import collections
import concurrent.futures
import csv
import os
import re
import subprocess
import sys
import tempfile
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import casc_scan
import probe_durations
import wagolib

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = wagolib.CACHE_DIR
DB2_DIR = os.path.join(CACHE, "db2_retail")
LISTFILE = os.path.join(CACHE, "community-listfile.csv")
LISTFILE_URL = "https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv"
TABLES = ["ZoneMusic", "SoundKitEntry", "AreaTable", "WMOAreaTable", "Map"]
ZONE_TAGS = os.path.join(HERE, "retail_zone_tags.csv")
OVERRIDES = os.path.join(HERE, "retail_tag_overrides.csv")
OUT = os.path.join(HERE, "retail_catalog.csv")
MIN_SECONDS = 30

# Map.ExpansionID -> FAME era key.  tbc and wrath are new: Forever has no
# Outland or Northrend music in rotation, so they had no era of their own yet.
ERA_BY_EXPANSION = ["classic", "tbc", "wrath", "cata", "mop", "wod", "legion", "bfa",
                    "sl", "df", "tww", "midnight"]
ERA_BY_DIR = dict(wagolib.ERA_BY_DIR)
OPEN_WORLD = {"0"}          # Map.InstanceType 0; 1 party, 2 raid, 3 pvp, 4 arena, 5 scenario

TAG_ORDER = {t: i for i, t in enumerate(
    "forest darkforest enchanted jungle swamp plains barrens desert mountain snow volcanic "
    "coast sea cave underground ruins blighted void arcane elemental sky city town tavern "
    "human dwarf gnome nightelf highelf orc tauren troll undead goblin naga draenei pandaren "
    "dragon demon centaur tuskarr earthen arathi kultiran drust vrykul nerubian pirate wild "
    "calm melancholy mysterious eerie ominous heroic sacred festive somber tense grand playful "
    "day night".split())}


# --------------------------------------------------------------------------
# Inputs
# --------------------------------------------------------------------------

def fetch(url, dest, timeout=600):
    req = urllib.request.Request(url, headers=wagolib.UA)
    with urllib.request.urlopen(req, timeout=timeout) as r, open(dest + ".tmp", "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(dest + ".tmp", dest)


def load_inputs(refresh):
    os.makedirs(DB2_DIR, exist_ok=True)
    if refresh or not os.path.exists(LISTFILE):
        print("downloading the community listfile...")
        fetch(LISTFILE_URL, LISTFILE)
    names = {}
    with open(LISTFILE, encoding="utf-8", errors="replace") as f:
        for line in f:
            fid, _, path = line.rstrip("\n").partition(";")
            if path[:12].lower() == "sound/music/":
                names[int(fid)] = path.lower()
    tables = {}
    for t in TABLES:
        path = os.path.join(DB2_DIR, t + ".csv")
        if refresh or not os.path.exists(path):
            print("downloading %s (retail)..." % t)
            fetch("https://wago.tools/db2/%s/csv?branch=wow" % t, path)
        with open(path, newline="", encoding="utf-8") as f:
            tables[t] = list(csv.DictReader(f))
    return names, tables


def read_csv_rows(path):
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8") as f:
        return [r for r in csv.reader(f) if r and not r[0].startswith("#")]


# --------------------------------------------------------------------------
# Where the game plays each file
# --------------------------------------------------------------------------

def zone_usage(tables):
    """{fdid: {"sets": {setName}, "world": {zone}, "instance": {zone}, "exp": {expansionID}}}"""
    kit_files = collections.defaultdict(set)
    for r in tables["SoundKitEntry"]:
        kit_files[r["SoundKitID"]].add(int(r["FileDataID"]))
    set_files, set_name = {}, {}
    for r in tables["ZoneMusic"]:
        set_files[r["ID"]] = kit_files.get(r["Sounds_0"], set()) | kit_files.get(r["Sounds_1"], set())
        set_name[r["ID"]] = r["SetName"]
    maps = {r["ID"]: r for r in tables["Map"]}
    areas = {r["ID"]: r for r in tables["AreaTable"]}

    def top_zone(area):
        seen = 0
        while area and area["ParentAreaID"] not in ("0", "") and seen < 10:
            parent = areas.get(area["ParentAreaID"])
            if not parent:
                break
            area, seen = parent, seen + 1
        return area

    # (set, zone name, map row) for every area and building that plays a set.
    uses = []
    for a in areas.values():
        if a["ZoneMusic"] not in ("0", ""):
            uses.append((a["ZoneMusic"], top_zone(a), maps.get(a["ContinentID"])))
    for w in tables["WMOAreaTable"]:
        if w["ZoneMusic"] not in ("0", ""):
            a = areas.get(w["AreaTableID"])
            m = maps.get(a["ContinentID"]) if a else None
            uses.append((w["ZoneMusic"], top_zone(a) if a else None, m))

    out = collections.defaultdict(lambda: {"sets": set(), "world": set(), "instance": set(),
                                           "exp": set(), "homes": collections.Counter()})
    for sid, zone, m in uses:
        files = set_files.get(sid)
        if not files:
            continue
        open_world = m is not None and m["InstanceType"] in OPEN_WORLD
        zname = (zone or {}).get("AreaName_lang") or (m or {}).get("MapName_lang") or "?"
        for fid in files:
            u = out[fid]
            u["sets"].add(set_name[sid])
            (u["world"] if open_world else u["instance"]).add(zname)
            if open_world:
                u["homes"][(set_name[sid], zname)] += 1
            if m is not None:
                u["exp"].add(int(m["ExpansionID"]))
    # Files in a set that no area uses at all still count as zone music.
    for sid, files in set_files.items():
        for fid in files:
            out[fid]["sets"].add(set_name[sid])
    return out


# --------------------------------------------------------------------------
# Local files: present, encrypted, duration
# --------------------------------------------------------------------------

def local_state(root, encoding, index, fid):
    """'ok', 'missing' or 'encrypted', plus the encoding key to read it with."""
    for ckey, _, _ in root.get(fid, []):
        ekey = encoding.get(ckey)
        if ekey is None or ekey[:9] not in index:
            continue
        return "ok", ekey.hex()
    return "missing", None


def probe_local(install, index, ekey_hex):
    raw = casc_scan.read_local(install, index, ekey_hex)
    if raw is None:
        return "missing", None
    try:
        data = casc_scan.blte(raw)
    except casc_scan.Encrypted:
        return "encrypted", None
    fd, tmp = tempfile.mkstemp(suffix=".audio")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        return "ok", round(probe_durations.ffprobe_seconds(tmp), 1)
    finally:
        os.remove(tmp)


# --------------------------------------------------------------------------
# Tags
# --------------------------------------------------------------------------

# Music sets that are not the zone's own walking music: a dungeon, raid or
# delve set reused at an entrance, a holiday or housing event, a scenario.
# Fine music, but a weaker claim about where the track belongs, so a track's
# home is taken from one of these only when it has nothing else.
SIDE_SET_RE = re.compile(
    r"\b(dgn|dungeon|raid|delve|labyrinth|scenario|housing|event|pvp|arena|islands|"
    r"warfront|brawl|plunderstorm|lorewalking|test|artif|moment|heritage|alliedrace)", re.I)
# Sets that are fight music: a track only ever used by these is a combat cue.
BATTLE_SET_RE = re.compile(r"(battle|combat|boss|stinger|encounter|fight)", re.I)
# Unlinked files are not placed by any zone set, so the file name is all
# there is.  These name patterns are scripted cues rather than walking music.
UNLINKED_SKIP_RE = re.compile(
    r"(sting|scene|combat|battle|boss|_rtc|intro|_moment|cutscene|victory|defeat|"
    r"_vo_|fanfare|_end\b|outro|_ending|cin_|_finale|_choice_)")

# Set or area name keyword -> tags it adds to the home zone's.  `!tag` takes
# a tag away (an inn in a forest zone is not forest music).
SET_KEYWORDS = [
    (r"tavern|\binn\b|_inn_|brewhall|divebar|dive.?bar|rest.?area|pub\b", "tavern festive !forest !darkforest !jungle !plains !mountain !snow !swamp !desert !coast !barrens !ominous !tense !eerie"),
    (r"cave|cavern|\bmines?\b|underground|tunnel|grotto|burrow|depths|crypt|sewer", "cave underground"),
    (r"forest|woods|\bgrove|glade|thicket", "forest"),
    (r"plains|fields|\bfarm|meadow|steppe|countryside", "plains"),
    (r"mountain|\bpeaks?\b|cliffs|summit|highlands|foothills", "mountain"),
    (r"\bnight\b|_night", "night"),
    (r"\bday\b|_day", "day"),
    (r"\bnaga\b|_naga", "naga coast"),
    (r"pirate|bloodsail|freehold", "pirate coast"),
    (r"goblin|bilgewater|steamwheedle", "goblin"),
    (r"hozen|grummle|vulpera|tortollan|quilboar|niffen|gnoll|kobold|ogre", "wild"),
    (r"tuskarr", "tuskarr coast"),
    (r"centaur", "centaur"),
    (r"\bfel\b|_fel|demon|felblood", "demon ominous"),
    (r"\bvoid|shadow.?enclave", "void"),
    (r"scourge|undead|forsaken|plague", "undead blighted"),
    (r"nerubian|spider|arachn", "nerubian"),
    (r"\bdrust", "drust"),
    (r"kultiran|kultiras|boralus|proudmoore|tiragarde", "kultiran"),
    (r"human(?!_?tavern)|gilnean|stormwind|lordaeronalliance|theramore", "human"),
    (r"vrykul", "vrykul"),
    (r"dwarf|bronzebeard|wildhammer|darkiron|irondwarf", "dwarf"),
    (r"\bgnome|gnomish", "gnome"),
    (r"\borc\b|_orc|horde", "orc"),
    (r"tauren|highmountain", "tauren"),
    (r"troll|zandalari|amani|loa\b", "troll"),
    (r"nightelf|night.?elf|kaldorei", "nightelf"),
    (r"bloodelf|blood.?elf|highelf|quel.?thalas|sindorei", "highelf"),
    (r"draenei|exodar|lightforged", "draenei"),
    (r"temple|shrine|monaster|sanctum|cathedral|chapel|sacred|holy", "sacred"),
    (r"ruins|ruin\b", "ruins"),
    (r"coast|shore|beach|harbor|harbour|port\b|docks|wharf|bay\b", "coast"),
    (r"\bsea\b|ocean|underwater|abyss", "sea"),
    (r"village|town|hamlet|outpost|garrison", "town"),
    (r"snow|frost|ice\b|winter|frozen", "snow"),
    (r"volcan|lava|molten|fire\b|ember", "volcanic"),
    (r"swamp|marsh|bog\b|mire", "swamp"),
    (r"jungle", "jungle"),
    (r"desert|dunes|sand\b", "desert"),
]
SET_KEYWORDS = [(re.compile(p, re.I), t.split()) for p, t in SET_KEYWORDS]


BIOMES = set("forest darkforest enchanted jungle swamp plains barrens desert mountain snow volcanic "
             "coast sea cave underground ruins blighted void arcane elemental sky city town tavern".split())
# Biomes that say what kind of place a zone is rather than its ground; a set
# naming its own ground (a forest, a cave) keeps these.
CULTURES = set("human dwarf gnome nightelf highelf orc tauren troll undead goblin naga draenei pandaren "
               "dragon demon centaur tuskarr earthen arathi kultiran drust vrykul nerubian pirate wild".split())
KEEP_BIOMES = {"blighted", "void", "arcane", "elemental", "enchanted", "darkforest", "city", "ruins"}


def keyword_tags(text, tags):
    """Zone tags refined by a set or file name.  A biome the name gives
    replaces the zone's ground biomes: a cave in Isle of Dorn is a cave, not
    plains and coast as well.  A people it names replaces the zone's."""
    tags = set(tags)
    named, people = set(), set()
    for rx, change in SET_KEYWORDS:
        if rx.search(text):
            named.update(t for t in change if t in BIOMES)
            people.update(t for t in change if t in CULTURES)
    if named:
        tags = {t for t in tags if t not in BIOMES or t in KEEP_BIOMES} | named
    # Likewise a people: the Iron Dwarf music in Howling Fjord is dwarven,
    # not vrykul.  Demons stay -- they say what happened to a place.
    if people - {"demon", "wild"}:
        tags = {t for t in tags if t not in CULTURES or t == "demon"}
    for rx, change in SET_KEYWORDS:
        if rx.search(text):
            for t in change:
                if t.startswith("!"):
                    tags.discard(t[1:])
                else:
                    tags.add(t)
    if "darkforest" in tags:
        tags.discard("forest")
    if "night" in tags and "day" in tags:
        tags -= {"night", "day"}
    return tags


def stem(path):
    """mus_80_ataldazar_h.mp3 -> mus_80_ataldazar: the piece, without its take."""
    name = os.path.splitext(os.path.basename(path))[0]
    return re.sub(r"(_(?:[a-z]\d?|\d+|night|day)){1,2}$", "", name)


def home_of(u):
    """(set, zone) where the game plays this track most, its own zone sets first."""
    if not u or not u["homes"]:
        return None
    def named_after(set_name, zone):
        # "Zone 101 - Zaralek - Hub - Loamm" is Zaralek Cavern's, whichever
        # zone reuses it most.
        key = re.sub(r"[^a-z]", "", set_name.lower())
        words = [re.sub(r"[^a-z]", "", w.lower()) for w in zone.split()]
        return any(len(w) >= 4 and w not in ("the", "isle", "city", "valley") and w in key
                   for w in words)
    ranked = sorted(u["homes"].items(),
                    key=lambda kv: (bool(SIDE_SET_RE.search(kv[0][0])),
                                    bool(BATTLE_SET_RE.search(kv[0][0])),
                                    not named_after(*kv[0]), -kv[1], kv[0]))
    return ranked[0][0]


def sort_tags(tags):
    return sorted(set(tags), key=lambda t: (TAG_ORDER.get(t, 999), t))


def era_for(path, usage):
    era = ERA_BY_DIR.get(path.split("/")[2], "other")
    if era == "classic" and usage and usage["exp"]:
        # sound/music/zonemusic is Classic, Burning Crusade and Wrath together;
        # the maps that play a track tell them apart.
        era = ERA_BY_EXPANSION[min(usage["exp"])] if min(usage["exp"]) < len(ERA_BY_EXPANSION) else era
    return era


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--install", default=casc_scan.INSTALL)
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--no-probe", action="store_true")
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    names, tables = load_inputs(args.refresh)
    info, index, encoding, root = casc_scan.open_build(args.install, "wow")
    _, _, _, forever_root = casc_scan.open_build(args.install, "wowf")
    print("retail %s, forever build in the same install" % info["Version"])

    usage = zone_usage(tables)
    candidates = {f for f in names if f in root and f not in forever_root}
    candidates |= {f for f in usage if f in root and f not in forever_root}

    zone_tags = {r[0]: r[1].split() for r in read_csv_rows(ZONE_TAGS) if len(r) >= 2}
    overrides = {int(r[0]): (r[1].split() if len(r) > 1 else []) for r in read_csv_rows(OVERRIDES)}

    cache = probe_durations.load_cache()
    rows = {}
    for fid in sorted(candidates):
        path = names.get(fid, "")
        u = usage.get(fid)
        state, ekey = local_state(root, encoding, index, fid)
        rows[fid] = {"fid": fid, "path": path, "u": u, "state": state, "ekey": ekey,
                     "len": cache.get(str(fid))}

    if not args.no_probe:
        todo = [r for r in rows.values() if r["state"] == "ok" and r["len"] is None
                and not wagolib.should_skip(r["path"])]
        if todo:
            print("measuring %d files from the local archives..." % len(todo))

        def work(r):
            try:
                return r, probe_local(args.install, index, r["ekey"])
            except Exception as exc:                     # noqa: BLE001
                return r, ("error: %s" % exc, None)
        done = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            for r, (state, secs) in pool.map(work, todo):
                if secs is not None:
                    r["len"] = cache[str(r["fid"])] = secs
                elif state != "ok":
                    r["state"] = "encrypted" if state == "encrypted" else "missing"
                done += 1
                if done % 250 == 0:
                    probe_durations.save_cache(cache)
                    print("  %d / %d" % (done, len(todo)))
        probe_durations.save_cache(cache)

    counts = collections.Counter()
    untagged_zones = collections.Counter()
    out_rows = []
    if True:
        for fid, r in sorted(rows.items(), key=lambda kv: (kv[1]["path"] or "~", kv[0])):
            path, u = r["path"], r["u"]
            world = sorted(u["world"]) if u else []
            inst = sorted(u["instance"]) if u else []
            sets = sorted(u["sets"]) if u else []
            home = home_of(u)
            # The part of the path that says something: subfolders and file
            # name, without sound/music/<expansion>/ ("legion" is not demons).
            tail = "/".join(path.split("/")[3:]) if path.count("/") > 2 else path
            if wagolib.should_skip(path):
                status = "skip"
            elif r["state"] != "ok":
                status = "absent"
            elif r["len"] is not None and r["len"] < MIN_SECONDS:
                status = "short"
            elif (sets and all(BATTLE_SET_RE.search(s) for s in sets)) or \
                    (home and BATTLE_SET_RE.search(home[0])):
                status = "battle"
            elif home and not SIDE_SET_RE.search(home[0]):
                status = "world"
            elif home:
                status = "reused"
            elif inst:
                status = "instance"
            elif UNLINKED_SKIP_RE.search(tail):
                status = "cue"
            else:
                status = "unlinked"

            tags = set()
            if home:
                if home[1] in zone_tags:
                    tags.update(zone_tags[home[1]])
                else:
                    untagged_zones[home[1]] += 1
                tags = keyword_tags(home[0] + " " + tail, tags)
            if not tags and status in ("world", "reused", "unlinked"):
                tags = keyword_tags(tail, wagolib.guess_tags(path))
            if fid in overrides:
                tags = set(overrides[fid])
            tags = sort_tags(tags)
            out_rows.append([fid, path, era_for(path, u) if path else "other",
                             "" if r["len"] is None else int(round(r["len"])), status,
                             "%s @ %s" % (home[0], home[1]) if home else "",
                             " | ".join(world or inst), " | ".join(sets), " ".join(tags)])

    # An unlinked file is often one more take of a piece the game does place:
    # mus_80_ataldazar_h next to the mus_80_ataldazar_a that Zuldazar plays.
    # Those borrow the placed sibling's home and tags.
    placed = collections.defaultdict(list)
    for row in out_rows:
        if row[4] == "world":
            placed[stem(row[1])].append(row)
    for row in out_rows:
        if row[4] == "unlinked" and placed.get(stem(row[1])) and row[0] not in overrides:
            sib = collections.Counter((s[5], s[8]) for s in placed[stem(row[1])]).most_common(1)[0][0]
            row[5], row[8] = "sibling of " + sib[0], sib[1]
            row[4] = "sibling"
    with open(OUT, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["fileDataID", "path", "era", "len", "status", "home", "zones", "sets", "tags"])
        for row in out_rows:
            counts[row[4]] += 1
            w.writerow(row)

    print("%d retail-only music files -> %s" % (len(rows), os.path.relpath(OUT)))
    for k in ("world", "sibling", "reused", "unlinked", "instance", "battle", "cue", "short", "skip", "absent"):
        print("  %-9s %d" % (k, counts[k]))
    if untagged_zones:
        print("open-world zones with no row in %s (%d):" % (os.path.basename(ZONE_TAGS), len(untagged_zones)))
        for z, n in untagged_zones.most_common():
            print("  %4d  %s" % (n, z))


if __name__ == "__main__":
    main()
