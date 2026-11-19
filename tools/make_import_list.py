#!/usr/bin/env python3
"""Write docs/import/retail-pack.tsv: what the retail music import fetches.

    python3 tools/make_import_list.py

The import scripts (docs/import/) download this list from the project page
every time they run, so when Blizzard repacks its CDN or retail patches,
re-running this and publishing the page fixes every player's next import.

For each track in the pack (the `world` and `sibling` rows of
tools/retail_catalog.csv) it records everything a script needs to get the
file without understanding Blizzard's formats:

  ekey     the track's encoding key in the installed retail build.  It is
           also a checksum: the MD5 of the stored blob's header (or of the
           whole blob, when it has none) equals it.  A local install looks
           the key up in its own Data/data/*.idx; the CDN is addressed by it.
  where    on the CDN: "<archive>:<offset>" for a track inside an archive,
           or "-" for one stored as a file of its own (data/xx/yy/<ekey>).
  chunks   the blob's layout: "<start>:<size>,<size>,...".  Every chunk is
           stored uncompressed ('N'), so the audio is each chunk minus its
           first byte, in order.  A track that is not would need a real
           decoder, and is left out.

Sources: the installed retail client (product `wow`) and the launcher's copy
of the CDN archive indexes in Data/indices.  Run it with retail installed and
up to date.  No audio is kept; the two or three tracks missing from this disk
are read from the CDN to learn their layout and then discarded.
"""

import csv
import datetime
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import casc_scan

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "tools", "retail_catalog.csv")
OUT = os.path.join(ROOT, "docs", "import", "retail-pack.tsv")
STATUSES = ("world", "sibling")
FORMAT = 1
CDN_HOSTS = ["level3.blizzard.com", "us.cdn.blizzard.com", "eu.cdn.blizzard.com"]
CDN_PATH = "tpr/wow"

ERAS = [
    ("classic", "Classic"), ("tbc", "The Burning Crusade"), ("wrath", "Wrath of the Lich King"),
    ("cata", "Cataclysm"), ("mop", "Mists of Pandaria"), ("wod", "Warlords of Draenor"),
    ("legion", "Legion"), ("bfa", "Battle for Azeroth"), ("sl", "Shadowlands"),
    ("df", "Dragonflight"), ("tww", "The War Within"), ("midnight", "Midnight"),
]


def cdn_get(path, rng=None):
    for host in CDN_HOSTS:
        headers = {"User-Agent": "fame-import-list"}
        if rng:
            headers["Range"] = "bytes=%d-%d" % rng
        try:
            url = "http://%s/%s/%s" % (host, CDN_PATH, path)
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as r:
                return r.read()
        except Exception as exc:                          # noqa: BLE001
            last = exc
    raise last


def main():
    install = casc_scan.INSTALL
    info, index, encoding, root = casc_scan.open_build(install, "wow")
    build_cfg = casc_scan.config(install, info["Build Key"])
    sizes = {}
    casc_scan.parse_encoding(casc_scan.blte(casc_scan.read_local(
        install, index, build_cfg["encoding"][1])), sizes)
    cdn_cfg = casc_scan.config(install, info["CDN Key"])

    rows = []
    with open(CATALOG, newline="") as f:
        for r in csv.DictReader(f):
            if r["status"] in STATUSES:
                rows.append(r)
    wanted = {}
    for r in rows:
        ckey = root[int(r["fileDataID"])][0][0]
        wanted[encoding[ckey]] = ckey

    # Where each blob sits on the CDN.
    where = {}
    for archive in cdn_cfg["archives"]:
        path = os.path.join(install, "Data", "indices", archive + ".index")
        if not os.path.exists(path):
            continue
        entries = casc_scan.parse_cdn_index(open(path, "rb").read())
        for ekey in wanted.keys() & entries.keys():
            size, offset = entries[ekey]
            where.setdefault(ekey, (archive, offset, size))
    loose_path = os.path.join(install, "Data", "indices", cdn_cfg["file-index"][0] + ".index")
    loose = casc_scan.parse_cdn_index(open(loose_path, "rb").read())

    out, skipped = [], []
    for r in rows:
        fid = int(r["fileDataID"])
        ckey = root[fid][0][0]
        ekey = encoding[ckey]
        if ekey in where:
            archive, offset, enc_size = where[ekey]
            loc = "%s:%d" % (archive, offset)
        elif ekey in loose:
            enc_size, loc = loose[ekey][0], "-"
        else:
            skipped.append((fid, "not on the CDN"))
            continue
        blob = casc_scan.read_local(install, index, ekey.hex())
        if blob is None:
            blob = (cdn_get("data/%s/%s/%s" % (archive[:2], archive[2:4], archive),
                            (offset, offset + enc_size - 1)) if loc != "-" else
                    cdn_get("data/%s/%s/%s" % (ekey.hex()[:2], ekey.hex()[2:4], ekey.hex())))
        if casc_scan.blte_modes(blob) != {b"N"}:
            skipped.append((fid, "compressed or encrypted"))
            continue
        start, chunks = casc_scan.blte_layout(blob)
        out.append([fid, r["era"], int(r["len"] or 0), ekey.hex(), sizes[ckey], enc_size, loc,
                    "%d:%s" % (start, ",".join(map(str, chunks)))])

    order = [k for k, _ in ERAS]
    out.sort(key=lambda t: (order.index(t[1]), t[0]))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write("# FAME retail music pack -- generated by tools/make_import_list.py, do not edit.\n")
        f.write("# format\t%d\n" % FORMAT)
        f.write("# retail\t%s\n" % info["Version"])
        f.write("# generated\t%s\n" % datetime.date.today().isoformat())
        f.write("# cdn\t%s\t%s\n" % (CDN_PATH, " ".join(CDN_HOSTS)))
        for key, label in ERAS:
            f.write("# era\t%s\t%s\n" % (key, label))
        f.write("# fileDataID\tera\tseconds\tekey\tbytes\tstored\tcdn\tchunks\n")
        for row in out:
            f.write("\t".join(map(str, row)) + "\n")
    print("%d tracks -> %s" % (len(out), os.path.relpath(OUT, ROOT)))
    print("  inside CDN archives: %d, own files: %d" % (
        sum(1 for t in out if t[6] != "-"), sum(1 for t in out if t[6] == "-")))
    for fid, why in skipped:
        print("  left out %d: %s" % (fid, why))


if __name__ == "__main__":
    main()
