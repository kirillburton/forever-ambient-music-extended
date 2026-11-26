#!/usr/bin/env python3
"""Generate ForeverAmbientMusicExtended/Originals.lua -- the game's own music rules.

    python3 tools/make_originals.py

FAME runs the music schedule itself in mapped zones, so it needs to know what
the game would have done: which tracks each area plays, how long the game
stays silent between them, and which areas open with an intro fanfare.  All of
that is client data, read here from the Forever beta's own DB2 tables via
wago.tools:

  AreaTable            area/subzone -> ZoneMusic set, intro, parent area
  ZoneMusic            set -> SilenceIntervalMin/Max (day, night), SoundKits
  ZoneIntroMusicTable  intro -> SoundKit, MinDelayMinutes
  SoundKitEntry        SoundKit -> fileDataIDs
  UiMap                uiMapID -> name, to find each zone's AreaTable row

Durations come from the same cache as tools/probe_durations.py; anything not
yet measured is downloaded, measured and deleted.
"""

import csv
import json
import os
import re
import sys
import urllib.request
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wagolib
import probe_durations

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON_DIR = os.path.join(ROOT, "ForeverAmbientMusicExtended")
DB2_DIR = os.path.join(wagolib.CACHE_DIR, "db2")
TABLES = ["UiMap", "AreaTable", "ZoneMusic", "ZoneIntroMusicTable", "SoundKitEntry", "WMOAreaTable"]

# Inn music has no dependable link to the area you are standing in: inns are
# building interiors (WMOAreaTable), and most of those rows carry no parent
# area at all.  Zones.lua picks one of these per zone instead.
TAVERN_SETS = {
    "human": 3563,      # Zone-HumanTavern
    "dwarf": 3562,      # Zone-DwavesTavern
    "undead": 3565,     # Zone-UndeadTavern
    "orc": 3566,        # Zone-OrcRestArea
    "pirate": 3564,     # Zone-PirateTavern
    "alliance": 156,    # Zone-TavernAlliance
    "horde": 185,       # Zone-TavernHorde
}


# Ironforge and Undercity are single giant interiors: their AreaTable rows
# carry no ZoneMusic, and the music is attached to the building instead
# (WMOAreaTable).  These are the sets those buildings use.
INTERIOR_CITIES = {
    1455: 232,      # Zone-Ironforge
    1458: 182,      # Zone-Undercity
}


def fetch_tables(refresh=False):
    os.makedirs(DB2_DIR, exist_ok=True)
    out = {}
    for name in TABLES:
        path = os.path.join(DB2_DIR, name + ".csv")
        if refresh or not os.path.exists(path):
            url = "https://wago.tools/db2/%s/csv?branch=%s" % (name, wagolib.BRANCH)
            req = urllib.request.Request(url, headers=wagolib.UA)
            with urllib.request.urlopen(req, timeout=180) as r, open(path, "wb") as f:
                f.write(r.read())
        with open(path, newline="") as f:
            out[name] = list(csv.DictReader(f))
    return out


def town_areas_from_zones_lua():
    """{uiMapID: {areaID, ...}} for every `ns.zones[X].towns[Y] = ...` line."""
    text = open(os.path.join(ADDON_DIR, "Zones.lua")).read()
    out = defaultdict(set)
    for map_id, area_id in re.findall(r"ns\.zones\[(\d+)\]\.towns\[(\d+)\]\s*=", text):
        out[int(map_id)].add(area_id)
    return out


def zone_ids_from_zones_lua():
    text = open(os.path.join(ADDON_DIR, "Zones.lua")).read()
    body = text.split("ns.zones = {", 1)[1].split("\nns.instances", 1)[0]
    return [int(m) for m in re.findall(r"^\s*\[(\d+)\] = \{", body, re.M)]


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    refresh = "--refresh" in sys.argv
    t = fetch_tables(refresh)
    uimap = {r["ID"]: r for r in t["UiMap"]}
    areas = {r["ID"]: r for r in t["AreaTable"]}
    sets = {r["ID"]: r for r in t["ZoneMusic"]}
    intros = {r["ID"]: r for r in t["ZoneIntroMusicTable"]}
    kit_files = defaultdict(list)
    for r in t["SoundKitEntry"]:
        kit_files[r["SoundKitID"]].append(r["FileDataID"])

    wmo_by_area = defaultdict(list)
    for w in t["WMOAreaTable"]:
        wmo_by_area[w["AreaTableID"]].append(w)

    def wmo_by_area_id_in(area_ids):
        return [w for a in area_ids for w in wmo_by_area.get(a, [])]

    children = defaultdict(list)
    for a in areas.values():
        children[a["ParentAreaID"]].append(a)

    def descendants(area_id):
        out, stack = [], [area_id]
        while stack:
            for child in children.get(stack.pop(), []):
                out.append(child)
                stack.append(child["ID"])
        return out

    top_by_name = defaultdict(list)
    for a in areas.values():
        if a["ParentAreaID"] == "0":
            top_by_name[a["AreaName_lang"]].append(a)

    towns = town_areas_from_zones_lua()
    used_sets, used_intros = set(TAVERN_SETS.values()), set()
    zones, missing = {}, []
    for map_id in zone_ids_from_zones_lua():
        name = uimap.get(str(map_id), {}).get("Name_lang")
        candidates = [a for a in top_by_name.get(name, []) if a["ZoneMusic"] != "0"]
        if not candidates and map_id in INTERIOR_CITIES:
            # The zone row carries no music; it all lives on the building.
            area = next(a for a in top_by_name.get(name, []))
            candidates = [dict(area, ZoneMusic=str(INTERIOR_CITIES[map_id]))]
        if not candidates:
            missing.append((map_id, name))
            continue
        # Several areas can share a zone's name (old prototypes, phased
        # copies); the one with the most subzones is the real zone.
        zone = max(candidates, key=lambda a: len(descendants(a["ID"])))
        zone_set = zone["ZoneMusic"]
        used_sets.add(int(zone_set))
        entry = {"name": name, "area": int(zone["ID"]), "set": int(zone_set),
                 "intro": int(zone["IntroSound"]), "sub": []}
        if zone["IntroSound"] != "0":
            used_intros.add(zone["IntroSound"])
        # A subzone with no music of its own plays its parent's: The Eventide
        # is a street of Dalaran, so it plays Dalaran's music, not the zone's.
        def music_of(a):
            while a["ID"] != zone["ID"]:
                if a["ZoneMusic"] != "0":
                    return a["ZoneMusic"], a["IntroSound"]
                a = areas.get(a["ParentAreaID"])
                if a is None:
                    break
            return zone_set, "0"

        inside = descendants(zone["ID"])
        effective = {zone["ID"]: zone_set}
        for sub in inside:
            own, own_intro_id = sub["ZoneMusic"], sub["IntroSound"]
            if own == "0":
                own, inherited_intro = music_of(sub)
                if own_intro_id == "0":
                    own_intro_id = inherited_intro
            effective[sub["ID"]] = own
            own_set = own != zone_set
            own_intro = own_intro_id != "0"
            is_town = sub["ID"] in towns.get(map_id, ())
            if not (own_set or own_intro or is_town):
                continue
            s = int(own) if own_set else 0
            if s:
                used_sets.add(s)
            if own_intro:
                used_intros.add(own_intro_id)
            entry["sub"].append((int(sub["ID"]), sub["AreaName_lang"], s, int(own_intro_id)))

        # Interiors -- caves, mines, buildings, a city's districts -- are not
        # areas but parts of a model (WMOAreaTable), and the game gives many
        # of them music of their own: Jasperlode Mine plays cave music, not
        # Elwynn's.  The client only says where you are by name, so they are
        # keyed by name, and a name stands for whatever most of its rows do.
        listed = {a for a, *_ in entry["sub"]}
        area_names = {zone["AreaName_lang"]} | {a["AreaName_lang"] for a in inside}
        rows = defaultdict(list)
        for w in wmo_by_area_id_in(effective):
            name = w["AreaName_lang"].strip()
            if name:
                rows[name].append((w["ZoneMusic"], w["AreaTableID"]))
        entry["interiors"] = {}
        for name, group in rows.items():
            with_music = Counter(m for m, _ in group if m != "0" and m in sets)
            if 2 * sum(with_music.values()) > len(group):
                s = max(with_music, key=lambda m: (with_music[m], not sets[m]["SetName"].startswith("Moment"), -int(m)))
                area = Counter(a for m, a in group if m == s).most_common(1)[0][0]
                if s == effective[area]:
                    s = None             # what its area plays anyway
            else:
                s = None
                area = Counter(a for m, a in group if m == "0").most_common(1)[0][0] \
                    if any(m == "0" for m, _ in group) else group[0][1]
            if s is None and (name in area_names or int(area) not in listed):
                continue                 # the name already says it all
            # A name an outdoor area shares only counts indoors.
            entry["interiors"][name] = (int(s) if s else 0, int(area), name in area_names)
            if s:
                used_sets.add(int(s))
        zones[map_id] = entry

    # The game's tables can name files the client does not ship: set 3161
    # (New Avalon) lists three that are not in the live build.  Playing one is
    # minutes of silence, so keep only files the client has -- judged by the
    # installed client's own root manifest (tools/casc_scan.py --ids-out).
    root_path = os.path.join(wagolib.CACHE_DIR, "wowf_root.txt")
    in_client = None
    if os.path.exists(root_path):
        in_client = {int(l) for l in open(root_path) if l.strip()}
    else:
        print("note: no %s -- run tools/casc_scan.py --ids-out %s to drop files the "
              "client does not have" % (root_path, root_path))
    dropped = []

    def files_of(kit):
        ids = [int(f) for f in kit_files.get(kit, [])]
        if in_client is None:
            return ids
        dropped.extend(i for i in ids if i not in in_client)
        return [i for i in ids if i in in_client]

    set_rows = {}
    for sid in sorted(used_sets):
        r = sets.get(str(sid))
        if not r:
            continue
        set_rows[sid] = {
            "name": r["SetName"],
            "silence": [int(r[k]) // 1000 for k in ("SilenceIntervalMin_0", "SilenceIntervalMax_0",
                                                    "SilenceIntervalMin_1", "SilenceIntervalMax_1")],
            "day": files_of(r["Sounds_0"]),
            "night": files_of(r["Sounds_1"]),
        }
    intro_rows = {}
    for iid in sorted(used_intros, key=int):
        r = intros.get(iid)
        if r:
            intro_rows[int(iid)] = {"name": r["Name"], "files": files_of(r["SoundID"]),
                                    "delay": int(r["MinDelayMinutes"]) * 60}

    # Durations: reuse and extend the shared cache.
    all_ids = sorted({f for s in set_rows.values() for f in s["day"] + s["night"]} |
                     {f for i in intro_rows.values() for f in i["files"]})
    cache = probe_durations.load_cache()
    todo = [f for f in all_ids if str(f) not in cache]
    if todo:
        print("measuring %d new files..." % len(todo))
        import concurrent.futures
        def work(fid):
            try:
                return fid, probe_durations.probe_uncached(fid)
            except Exception as exc:                     # noqa: BLE001
                print("  FAILED %s: %s" % (fid, exc))
                return fid, None
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
            for fid, secs in pool.map(work, todo):
                if secs is not None:
                    cache[str(fid)] = secs
        probe_durations.save_cache(cache)

    names = {}
    music_csv = os.path.join(wagolib.CACHE_DIR, "music_list.csv")
    if os.path.exists(music_csv):
        with open(music_csv, newline="") as f:
            for row in csv.DictReader(f):
                names[int(row["fileDataID"])] = os.path.splitext(os.path.basename(row["path"]))[0]

    def entry(f):
        name = names.get(f)
        if name:
            return '{ id = %d, len = %d, name = %s }' % (f, round(cache[str(f)]), lua_str(name))
        return "{ id = %d, len = %d }" % (f, round(cache[str(f)]))

    def tracklist(ids):
        parts = [entry(f) for f in ids if str(f) in cache]
        return "{ " + ", ".join(parts) + " }" if parts else "{}"

    L = ["-- Originals.lua -- generated by tools/make_originals.py.  Do not hand-edit.",
         "--",
         "-- The game's own music rules for every zone in Zones.lua, read from the",
         "-- Forever client's DB2 tables (AreaTable, ZoneMusic, ZoneIntroMusicTable,",
         "-- SoundKitEntry).  FAME plays these itself for the share of tracks that",
         "-- stay original, and uses `silence` -- the game's own gap between tracks,",
         "-- in seconds, as { dayMin, dayMax, nightMin, nightMax } -- for every",
         "-- silence, whichever kind of track came before it.",
         "",
         "local ADDON, ns = ...",
         "",
         "ns.musicSets = {"]
    for sid, s in set_rows.items():
        L.append("    [%d] = { name = %s, silence = { %s }," % (sid, lua_str(s["name"]), ", ".join(map(str, s["silence"]))))
        L.append("        day = %s," % tracklist(s["day"]))
        L.append("        night = %s }," % tracklist(s["night"]))
    L += ["}", "", "ns.intros = {"]
    for iid, i in intro_rows.items():
        L.append("    [%d] = { name = %s, delay = %d, tracks = %s }," % (iid, lua_str(i["name"]), i["delay"], tracklist(i["files"])))
    L += ["}", "",
          "-- uiMapID -> the zone's own area.  `name` is the area's English name,",
          "-- used only when the client cannot name the area itself: FAME checks",
          "-- GetZoneText() against it, and steps aside when the game says you are",
          "-- somewhere else -- out at sea on a ship, for instance.",
          "-- `sub` lists only the subzones whose",
          "-- music differs from the zone's, that open with an intro, or that are a",
          "-- town in Zones.lua: { areaID,",
          "-- English name, set (0 = same as the zone), intro (0 = none) }.  The",
          "-- English name is a fallback; at load FAME asks C_Map.GetAreaInfo for the",
          "-- client's own spelling, so subzone matching works in any locale.",
          "ns.zoneMusic = {"]
    for map_id in sorted(zones):
        z = zones[map_id]
        L.append("    [%d] = { area = %d, name = %s, set = %d, intro = %d," % (map_id, z["area"], lua_str(z["name"]), z["set"], z["intro"]))
        if z["sub"]:
            L.append("        sub = {")
            for aid, nm, s, i in sorted(z["sub"], key=lambda x: x[1]):
                L.append("            { %d, %s, %d, %d }," % (aid, lua_str(nm), s, i))
            L.append("        } },")
        else:
            L.append("        sub = {} },")
    L += ["}", "",
          "-- Interiors whose music is not their area's, by zone and by the English",
          "-- name the client reports inside them: { set (0 = its area's), area,",
          "-- indoors }.  `set` is the interior's own music; `area` is the subzone",
          "-- it belongs to.  `indoors`: an outdoor area has the same name, so it",
          "-- only counts while IsIndoors().  The client has no other way to name",
          "-- an interior, so this only matches on English clients.",
          "ns.interiors = {"]
    for map_id in sorted(zones):
        rows = zones[map_id]["interiors"]
        if not rows:
            continue
        L.append("    [%d] = {" % map_id)
        for nm, (s, a, indoors) in sorted(rows.items()):
            L.append("        [%s] = { %d, %d%s }," % (lua_str(nm), s, a, ", true" if indoors else ""))
        L.append("    },")
    L += ["}", "",
          "-- Inn music, by the `inn` key Zones.lua gives each zone.",
          "ns.tavernSets = {"]
    for key, sid in TAVERN_SETS.items():
        L.append("    %s = %d," % (key, sid))
    L += ["}", ""]
    with open(os.path.join(ADDON_DIR, "Originals.lua"), "w") as f:
        f.write("\n".join(L))

    n_tracks = len({f for s in set_rows.values() for f in s["day"] + s["night"]})
    print("Originals.lua: %d zones, %d music sets, %d intros, %d distinct tracks, %d subzone overrides, %d interiors"
          % (len(zones), len(set_rows), len(intro_rows), n_tracks, sum(len(z["sub"]) for z in zones.values()),
             sum(len(z["interiors"]) for z in zones.values())))
    if missing:
        print("no AreaTable match (FAME leaves these to the game):", missing)
    if dropped:
        print("dropped %d file(s) the game's tables list but the client lacks: %s"
              % (len(set(dropped)), " ".join(map(str, sorted(set(dropped))))))


if __name__ == "__main__":
    main()
