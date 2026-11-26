#!/usr/bin/env python3
"""Generate ForeverAmbientMusicExtended/RetailTracks.lua from the catalogue.

    python3 tools/make_retail_tracks.py

The tracks of the retail music pack (the `world` and `sibling` rows of
tools/retail_catalog.csv, the same ones tools/make_import_list.py lists for
the import script), as FAME needs them to play: retail fileDataID, length,
era, name and tags.  No audio -- the music itself only ever comes from the
player's own ForeverAmbientMusicExtended_RetailPack folder, and FAME only
uses a track whose ID that pack's Pack.lua lists.

Keeping the tags here rather than in the pack means a retagging ships with a
FAME update, without anyone re-running the import.

Where retail itself plays a track
---------------------------------
Cataclysm rebuilt the old world's music area by area, and most of those areas
kept their IDs in Forever (Stonetalon Peak is 467 in both).  So for every
Forever zone and every area inside it, this follows retail's AreaTable to the
music set retail plays there (an area with none inherits its parent's, as in
the game), and records each pack track's Forever areas as `at`.  FAME plays a
track at its own areas whatever its tags say: the zone's own area means the
whole zone, a subzone means only that subzone.  ns.retailAreas names those
subzones so FAME can recognise them from GetSubZoneText().

Chosen by hand
--------------
tools/retail_places.csv adds places retail never had: the ruined Highborne
cities of Kalimdor get Legion's Requiem for the Lost Cities, for one.  Each
row names Forever subzones and the tracks (file names, * allowed) that
belong there; they are added to those subzones' `at` the same way.

Buildings (WMOAreaTable) are left out: retail fills them with borrowed sets
(Westfall's houses play Utgarde's), and inside, the game's own music rules
anyway.
"""

import collections
import csv
import fnmatch
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "tools", "retail_catalog.csv")
PLACES = os.path.join(ROOT, "tools", "retail_places.csv")
OUT = os.path.join(ROOT, "ForeverAmbientMusicExtended", "RetailTracks.lua")
STATUSES = ("world", "sibling")
CACHE = os.path.join(ROOT, "tools", "cache")
ORIGINALS = os.path.join(ROOT, "ForeverAmbientMusicExtended", "Originals.lua")
ERAS = ["classic", "tbc", "wrath", "cata", "mop", "wod", "legion", "bfa", "sl", "df", "tww", "midnight"]


def read(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def native_areas(pack_names, builtin=()):
    """{fid: set(Forever area IDs)} and {subzone area: (mapID, name)}.

    `builtin`: IDs of FAME's own tracks (the Forever client's files) to place
    the same way -- Cataclysm music the client ships goes where Cataclysm
    plays it."""
    forever = {int(r["ID"]): r for r in read(os.path.join(CACHE, "db2", "AreaTable.csv"))}
    retail = {int(r["ID"]): r for r in read(os.path.join(CACHE, "db2_retail", "AreaTable.csv"))}
    music = {int(r["ID"]): r for r in read(os.path.join(CACHE, "db2_retail", "ZoneMusic.csv"))}
    kits = collections.defaultdict(set)
    for r in read(os.path.join(CACHE, "db2_retail", "SoundKitEntry.csv")):
        kits[int(r["SoundKitID"])].add(int(r["FileDataID"]))
    pack = set(pack_names) | set(builtin)
    zones = {int(a): int(m) for m, a in
             re.findall(r"\[(\d+)\] = \{ area = (\d+),", open(ORIGINALS).read())}

    def retail_set(area):
        for _ in range(10):
            if area not in retail:
                return 0
            if int(retail[area]["ZoneMusic"]):
                return int(retail[area]["ZoneMusic"])
            area = int(retail[area]["ParentAreaID"])
        return 0

    def tracks(set_id):
        if set_id not in music:
            return set()
        out = set()
        for col in ("Sounds_0", "Sounds_1"):
            out |= kits[int(music[set_id][col])] & pack
        return out

    def zone_of(area):
        for _ in range(10):
            parent = int(forever[area]["ParentAreaID"]) if area in forever else 0
            if not parent:
                return area
            area = parent
        return area

    # Retail rebuilt some areas under new IDs (Feathermoon Stronghold is 1116
    # in Forever, 5072 in retail): a retail area Forever doesn't have, in the
    # same zone and with the same name as one it does, stands for that one.
    # Later expansions' reworks of a place (Silithus after the sword) are
    # not the place Forever has, so only sets from before Legion count.
    def retail_zone(area):
        for _ in range(10):
            parent = int(retail[area]["ParentAreaID"]) if area in retail else 0
            if not parent:
                return area
            area = parent
        return area
    later = re.compile(r"(?i)zone[-_ ]*(7|8|9|1\d)\d|prototype|memory|event|scenario|housing")
    alias = collections.defaultdict(set)          # Forever area -> retail stand-ins
    by_name = {}
    for area in forever:
        by_name.setdefault((zone_of(area), forever[area]["AreaName_lang"]), area)
    for area, row in retail.items():
        if area in forever or not int(row["ZoneMusic"]):
            continue
        twin = by_name.get((retail_zone(area), row["AreaName_lang"]))
        set_name = music.get(int(row["ZoneMusic"]), {}).get("SetName", "")
        if twin and not later.search(set_name):
            alias[twin].add(area)

    at, subzones = collections.defaultdict(set), {}

    # By hand: tools/retail_places.csv.
    names = {fid: name for fid, name in pack_names.items()}
    for row in read(PLACES):
        patterns = row["tracks"].split()
        chosen = {fid for fid, name in names.items() if any(fnmatch.fnmatch(name, p) for p in patterns)}
        if not chosen:
            raise SystemExit("retail_places.csv: no pack track matches %r" % row["tracks"])
        for area in map(int, row["areas"].split()):
            zone_area = zone_of(area)
            if area not in forever or zone_area not in zones:
                raise SystemExit("retail_places.csv: area %d is not in a FAME zone" % area)
            if area != zone_area:
                subzones[area] = (zones[zone_area], forever[area]["AreaName_lang"])
            for fid in chosen:
                at[fid].add(area)

    for area in forever:
        zone_area = zone_of(area)
        # "Orgrimmar UNUSED" and the like: areas nobody can stand in.
        if zone_area not in zones or "UNUSED" in forever[area]["AreaName_lang"]:
            continue
        here = tracks(retail_set(area))
        for twin in alias.get(area, ()):
            here |= tracks(retail_set(twin))
        if area != zone_area:
            # A subzone playing what its zone plays adds nothing.
            here -= tracks(retail_set(zone_area))
            if not here:
                continue
            subzones[area] = (zones[zone_area], forever[area]["AreaName_lang"])
        for fid in here:
            at[fid].add(area)
    return at, subzones


def builtin_tracks():
    """{fid: name} of FAME's own tracks that retail may place: the Cataclysm
    music the Forever client ships, and older files retail still uses
    (the Caverns of Time's Tarren Mill music in Hillsbrad).  Forever's own
    remasters are placed by Forever itself (ForeverPlaces.lua)."""
    text = open(os.path.join(ROOT, "ForeverAmbientMusicExtended", "Tracks.lua")).read()
    return {int(f): n for f, era, n in
            re.findall(r'id = (\d+),\s+len = +\d+, era = "(\w+)",\s+name = "([^"]+)"', text)
            if era != "forever"}


def lua_string(text):
    return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')


def main():
    rows = [r for r in csv.DictReader(open(CATALOG, newline=""))
            if r["status"] in STATUSES]
    rows.sort(key=lambda r: (ERAS.index(r["era"]), int(r["fileDataID"])))
    builtin = builtin_tracks()
    at, subzones = native_areas({int(r["fileDataID"]): os.path.splitext(os.path.basename(r["path"]))[0]
                                 for r in rows}, builtin)
    lines = [
        "-- RetailTracks.lua -- generated by tools/make_retail_tracks.py.  Do not hand-edit:",
        "-- fix tags in tools/retail_zone_tags.csv or tools/retail_tag_overrides.csv,",
        "-- then run tools/retail_catalog.py and this.",
        "--",
        "-- The music of the optional retail pack: tracks from modern WoW that FAME",
        "-- can't ship, which a script on the project page fetches onto the player's",
        "-- own computer, into the ForeverAmbientMusicExtended_RetailPack addon.",
        "-- Nothing here plays unless that pack's Pack.lua lists the track's retail",
        "-- fileDataID (`rid`); its file is then Music\\<rid>.mp3 in the pack.",
        "--",
        "-- `at`: the Forever areas where retail itself plays the track (a zone's",
        "-- own area for all of it, or a subzone); FAME plays it there regardless",
        "-- of tags.  Everywhere else a track has to fit a zone's strict list in",
        "-- Zones.lua (ns.retailFit) to be considered.",
        "--",
        "-- %d tracks." % len(rows),
        "",
        "local ADDON, ns = ...",
        "",
        "ns.retailTracks = {",
    ]
    era = None
    for r in rows:
        if r["era"] != era:
            era = r["era"]
            lines.append("    -- %s" % era)
        name = os.path.splitext(os.path.basename(r["path"]))[0]
        tags = ", ".join('"%s"' % t for t in r["tags"].split())
        where = sorted(at.get(int(r["fileDataID"]), ()))
        lines.append('    { rid = %s, len = %d, era = "%s", name = "%s", tags = { %s }%s },' % (
            r["fileDataID"], int(r["len"]), r["era"], name, tags,
            (", at = { %s }" % ", ".join(map(str, where))) if where else ""))
    lines.append("}")
    lines.append("")
    lines.append("-- FAME's own tracks (in the Forever client) that retail plays in these zones:")
    lines.append("-- [fileDataID] = { areas }, merged into their `at` at load.")
    lines.append("ns.builtinRetailAt = {")
    for fid in sorted(f for f in builtin if f in at):
        lines.append("    [%d] = { %s },   -- %s" % (fid, ", ".join(map(str, sorted(at[fid]))), builtin[fid]))
    lines.append("}")
    lines.append("")
    lines.append("-- Subzones with retail music of their own: [areaID] = { uiMapID, English name }.")
    lines.append("-- FAME asks the client for each one's name in its own language.")
    lines.append("ns.retailAreas = {")
    for area in sorted(subzones):
        mapID, name = subzones[area]
        lines.append("    [%d] = { %d, %s }," % (area, mapID, lua_string(name)))
    lines.append("}")
    with open(OUT, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("%d tracks -> %s" % (len(rows), os.path.relpath(OUT, ROOT)))
    print("  %d played by retail somewhere in Forever's zones, %d subzones" % (len(at), len(subzones)))


if __name__ == "__main__":
    main()
