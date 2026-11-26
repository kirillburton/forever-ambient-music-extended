#!/usr/bin/env python3
"""Measure how loud every track FAME can play is, and write Loudness.lua.

    python3 tools/loudness.py              # measure what isn't cached yet, then write
    python3 tools/loudness.py --report     # per-era summary only

Some eras are mastered much louder than the music Forever ships: The War
Within's tracks sit several dB above the game's own.  Played one after the
other, a loud track jumps out.  This measures each track's integrated
loudness (EBU R128, ffmpeg's ebur128 filter) and gives each one that is
clearly louder than the game's own a cut, in dB, which FAME applies by holding
the music slider down while it plays.

The baseline is the median of the game's own tracks -- the ones Originals.lua
lists, the music the Forever client plays without FAME.  Nothing is ever made
louder: FAME can only turn the slider down, never past where the player set it.

Sources, all local:
  * the game's own tracks and FAME's built-in ones: the Forever client's own
    storage, read the way casc_scan.py does (no network)
  * the retail pack: the imported mp3s in the pack addon's Music folder
Results are cached in tools/cache/loudness.json, keyed by FileDataID.
"""

import argparse
import json
import os
import re
import statistics
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import casc_scan

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ADDON = os.path.join(ROOT, "ForeverAmbientMusicExtended")
CACHE = os.path.join(HERE, "cache", "loudness.json")
PACK_MUSIC = os.path.join(casc_scan.INSTALL, "_forever_", "Interface", "AddOns",
                          "ForeverAmbientMusicExtended_RetailPack", "Music")
OUT = os.path.join(ADDON, "Loudness.lua")

# The game's own music spreads over a few dB, and evening that out is not the
# point: a track is only brought down to this much above the baseline (about
# the loudest quarter of the game's own), never further.  Cutting just the
# excess keeps it smooth: a track a little louder gets a little cut.
TOLERANCE = 1.5
# Never cut more than this, whatever the measurement says.
MAX_CUT = 12.0


def ids_in(name, pattern):
    return [int(m) for m in re.findall(pattern, open(os.path.join(ADDON, name)).read())]


def measure(data):
    """Integrated loudness (LUFS) of an mp3 given as bytes, or None."""
    p = subprocess.run(["ffmpeg", "-nostats", "-hide_banner", "-i", "pipe:0",
                        "-filter_complex", "ebur128", "-f", "null", "-"],
                       input=data, capture_output=True)
    found = re.findall(rb"I:\s+(-?[\d.]+) LUFS", p.stderr)
    return float(found[-1]) if found else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()

    cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    originals = set(ids_in("Originals.lua", r"id = (\d+)"))
    builtin = {}
    for m in re.finditer(r'id = (\d+),\s+len = +\d+, era = "(\w+)"', open(os.path.join(ADDON, "Tracks.lua")).read()):
        builtin[int(m.group(1))] = m.group(2)
    retail = {}
    for m in re.finditer(r'rid = (\d+), len = +\d+, era = "(\w+)"', open(os.path.join(ADDON, "RetailTracks.lua")).read()):
        retail[int(m.group(1))] = m.group(2)

    if not args.report:
        todo_casc = [f for f in sorted(originals | set(builtin)) if str(f) not in cache]
        todo_pack = [f for f in sorted(retail) if str(f) not in cache
                     and os.path.exists(os.path.join(PACK_MUSIC, "%d.mp3" % f))]
        print("to measure: %d from the Forever client, %d from the retail pack" % (len(todo_casc), len(todo_pack)))

        def save():
            with open(CACHE, "w") as f:
                json.dump(cache, f, indent=0, sort_keys=True)

        if todo_casc:
            info, index, encoding, root = casc_scan.open_build(casc_scan.INSTALL, "wowf")

            def from_casc(fid):
                for ckey, _, _ in root.get(fid, []):
                    ekey = encoding.get(ckey)
                    raw = ekey and casc_scan.read_local(casc_scan.INSTALL, index, ekey.hex())
                    if raw:
                        try:
                            return measure(casc_scan.blte(raw))
                        except (casc_scan.Encrypted, ValueError):
                            return None
                return None
            with ThreadPoolExecutor(8) as pool:
                for n, (fid, lufs) in enumerate(zip(todo_casc, pool.map(from_casc, todo_casc)), 1):
                    if lufs is not None:
                        cache[str(fid)] = lufs
                    if n % 100 == 0:
                        print("  client %d / %d" % (n, len(todo_casc)), flush=True)
                        save()
            save()

        if todo_pack:
            def from_pack(fid):
                with open(os.path.join(PACK_MUSIC, "%d.mp3" % fid), "rb") as f:
                    return measure(f.read())
            with ThreadPoolExecutor(8) as pool:
                for n, (fid, lufs) in enumerate(zip(todo_pack, pool.map(from_pack, todo_pack)), 1):
                    if lufs is not None:
                        cache[str(fid)] = lufs
                    if n % 200 == 0:
                        print("  pack %d / %d" % (n, len(todo_pack)), flush=True)
                        save()
            save()

    base_values = [cache[str(f)] for f in originals if str(f) in cache]
    if not base_values:
        sys.exit("no baseline: none of the game's own tracks could be measured")
    base = statistics.median(base_values)
    print("baseline: %.1f LUFS, the median of %d of the game's own tracks (IQR %.1f to %.1f)"
          % (base, len(base_values), *statistics.quantiles(base_values, n=4)[::2]))

    def cut(fid):
        lufs = cache.get(str(fid))
        if lufs is None or lufs < base + TOLERANCE + 0.5:     # under half a dB: not worth a slider move
            return 0.0
        return round(min(MAX_CUT, lufs - base - TOLERANCE), 1)

    eras = {}
    for table in (builtin, retail):
        for fid, era in table.items():
            if str(fid) in cache:
                eras.setdefault(era, []).append((cache[str(fid)], cut(fid)))
    print("%-9s %5s %8s %8s %6s" % ("era", "n", "median", "vs base", "cut"))
    for era, rows in sorted(eras.items(), key=lambda kv: statistics.median(r[0] for r in kv[1])):
        med = statistics.median(r[0] for r in rows)
        print("%-9s %5d %8.1f %+8.1f %5d%%" % (era, len(rows), med, med - base,
                                             100 * sum(1 for r in rows if r[1]) // len(rows)))
    if args.report:
        return

    cuts = {}
    # The game's own tracks are the baseline and play as the game has them,
    # even where FAME's pool holds the same file.
    for fid in sorted((set(builtin) | set(retail)) - originals):
        c = cut(fid)
        if c:
            cuts[fid] = c
    with open(OUT, "w") as f:
        f.write("-- Generated by tools/loudness.py.  Do not edit by hand.\n")
        f.write("--\n-- Tracks mastered clearly louder than the game's own music (baseline %.1f LUFS,\n" % base)
        f.write("-- the median of the tracks in Originals.lua), and how many dB FAME turns the\n")
        f.write("-- music slider down while each one plays.  Keyed by FileDataID.\n\n")
        f.write("local _, ns = ...\n\nns.loudness = {\n")
        items = sorted(cuts.items())
        for i in range(0, len(items), 6):
            f.write("    " + " ".join("[%d] = %.1f," % kv for kv in items[i:i + 6]) + "\n")
        f.write("}\n")
    print("-> %s: %d tracks cut" % (os.path.relpath(OUT, ROOT), len(cuts)))


if __name__ == "__main__":
    main()
