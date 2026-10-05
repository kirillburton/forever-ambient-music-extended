#!/usr/bin/env python3
"""Measure the real length of client music files, for Tracks.lua `len` values.

`PlayMusic()` loops forever and fires no "track ended" event, so every track
entry needs a duration the addon can set a timer against.  There is no API to
ask the client, so the lengths are measured out of band here: download the
file from wago.tools, run ffprobe, keep only the number of seconds.

    python3 tools/probe_durations.py --from-csv tools/cache/music_list.csv
    python3 tools/probe_durations.py 4872416 625753

Results are cached in tools/cache/durations.json, so re-runs are cheap and
only new IDs cost bandwidth.  The audio itself is deleted immediately after
probing -- nothing Blizzard-owned is kept or redistributed.

Requires ffprobe (brew install ffmpeg).
"""

import argparse
import concurrent.futures
import csv
import json
import os
import subprocess
import sys
import tempfile
import threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wagolib

CACHE = os.path.join(wagolib.CACHE_DIR, "durations.json")


def load_cache():
    if os.path.exists(CACHE):
        with open(CACHE) as f:
            return json.load(f)
    return {}


def save_cache(cache):
    os.makedirs(wagolib.CACHE_DIR, exist_ok=True)
    tmp = CACHE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cache, f, indent=0, sort_keys=True)
    os.replace(tmp, CACHE)


def ffprobe_seconds(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", path],
        capture_output=True, text=True, check=True).stdout.strip()
    return float(out)


def probe_uncached(fdid):
    """Download, measure, delete.  Returns seconds rounded to 0.1."""
    fd, tmp = tempfile.mkstemp(suffix=".audio")
    os.close(fd)
    try:
        wagolib.download(fdid, tmp)
        return round(ffprobe_seconds(tmp), 1)
    finally:
        os.unlink(tmp)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*", type=int)
    ap.add_argument("--from-csv", help="read fileDataIDs from a music_list.csv")
    ap.add_argument("--pool", action="store_true",
                    help="with --from-csv, keep only extension-pool rows")
    ap.add_argument("-j", "--jobs", type=int, default=8)
    args = ap.parse_args()

    ids = list(args.ids)
    if args.from_csv:
        with open(args.from_csv) as f:
            for row in csv.DictReader(f):
                if args.pool and not wagolib.in_extension_pool(row["path"]):
                    continue
                if not args.pool and row["skip"]:
                    continue
                ids.append(int(row["fileDataID"]))
    if not ids:
        ap.error("give some fileDataIDs or --from-csv")

    cache = load_cache()
    lock = threading.Lock()
    todo = [i for i in ids if str(i) not in cache]
    print("%d ids, %d already cached, %d to download" % (len(ids), len(ids) - len(todo), len(todo)))
    done = [0]
    failed = []

    def work(fdid):
        try:
            secs = probe_uncached(fdid)
        except Exception as exc:                      # noqa: BLE001 - keep going
            with lock:
                failed.append((fdid, exc))
            return
        with lock:
            cache[str(fdid)] = secs
            done[0] += 1
            if done[0] % 25 == 0:
                print("  %d/%d" % (done[0], len(todo)))
                save_cache(cache)

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        list(pool.map(work, todo))
    save_cache(cache)
    for fdid, exc in failed:
        print("  FAILED %s: %s" % (fdid, exc))
    print("cache: %s (%d entries, %d failures)" % (CACHE, len(cache), len(failed)))


if __name__ == "__main__":
    main()
