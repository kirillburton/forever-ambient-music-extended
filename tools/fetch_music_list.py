#!/usr/bin/env python3
"""Dump the music file list for a WoW branch from wago.tools.

    python3 tools/fetch_music_list.py                      # wow_classic_beta
    python3 tools/fetch_music_list.py --branch wow         # retail
    python3 tools/fetch_music_list.py -o out.csv

Writes CSV: fileDataID,path,era,skip,tags
`tags` is the first-pass keyword guess from the path -- a starting point to
hand-edit, not an answer.  `skip` marks cinematic / event / stinger / main
title / jukebox material.

The branch filter is enforced server side, so every row is a file the client
on that branch can actually play.  That matches what PlaySoundFile() reports
in game (verified on ten IDs).
"""

import argparse
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wagolib


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--branch", default=wagolib.BRANCH)
    ap.add_argument("--search", default="sound/music")
    ap.add_argument("-o", "--out", default=os.path.join(wagolib.CACHE_DIR, "music_list.csv"))
    args = ap.parse_args()

    files = wagolib.fetch_file_list(args.search, args.branch)
    rows = sorted(files.items(), key=lambda kv: kv[1])
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["fileDataID", "path", "era", "skip", "tags"])
        for fdid, path in rows:
            w.writerow([fdid, path, wagolib.era_of(path),
                        "1" if wagolib.should_skip(path) else "",
                        " ".join(wagolib.guess_tags(path))])
    print("%d files -> %s" % (len(rows), args.out))


if __name__ == "__main__":
    main()
