#!/usr/bin/env python3
"""Build the distributable zip for ForeverAmbientMusicExtended.

    python3 tools/package.py              # -> dist/ForeverAmbientMusicExtended-<version>.zip
    python3 tools/package.py --check X.zip   # validate an existing zip, build nothing

Why not Finder's "Compress" or `zip -r`: on macOS both add a `__MACOSX/`
folder of AppleDouble `._*` files and pick up `.DS_Store`, and CurseForge
rejects the upload for both.  This builds the archive from an explicit file
list instead -- only what the addon needs, under a single top-level
ForeverAmbientMusicExtended/ folder -- and then runs the same kind of check
CurseForge does before it will write anything.

The version comes from `## Version:` in the .toc.  Entries get a fixed
timestamp and permissions, so the same source always gives the same zip.
"""

import argparse
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = "ForeverAmbientMusicExtended"
ADDON_DIR = os.path.join(ROOT, ADDON)
DIST = os.path.join(ROOT, "dist")

# What ships.  Music/ ships with only its README: audio people extract from
# their own install must never end up in a distributed package.
SHIP_PATTERNS = [
    r"[^/]+\.toc",
    r"[^/]+\.lua",
    r"Media/[^/]+\.(mp3|ogg|tga)",
    r"Music/README\.txt",
]
SHIP_RE = re.compile("^(?:%s)$" % "|".join(SHIP_PATTERNS))

FIXED_TIME = (2026, 1, 1, 0, 0, 0)


def toc_version():
    toc = os.path.join(ADDON_DIR, ADDON + ".toc")
    m = re.search(r"^## Version:\s*(\S+)", open(toc).read(), re.M)
    if not m:
        sys.exit("no '## Version:' line in %s" % toc)
    return m.group(1)


def problems_in(names):
    """What CurseForge (and WoW) would object to in a list of zip entry names."""
    out = []
    top = ADDON + "/"
    for name in names:
        parts = [p for p in name.split("/") if p]
        if not name.startswith(top):
            out.append("outside the %s folder: %s" % (top, name))
        for p in parts:
            if p == "__MACOSX":
                out.append("blacklisted directory: %s" % name)
            elif p.startswith("."):
                out.append("hidden or blacklisted file: %s" % name)
            elif p.lower() in ("thumbs.db", "desktop.ini"):
                out.append("blacklisted file name: %s" % name)
        if "\\" in name:
            out.append("backslash in path: %s" % name)
    if top + ADDON + ".toc" not in names:
        out.append("missing %s%s.toc" % (top, ADDON))
    return sorted(set(out))


def collect():
    files = []
    for dirpath, dirnames, filenames in os.walk(ADDON_DIR):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for f in sorted(filenames):
            rel = os.path.relpath(os.path.join(dirpath, f), ADDON_DIR).replace(os.sep, "/")
            if SHIP_RE.match(rel):
                files.append(rel)
    return files


def build(out_path):
    files = collect()
    names = [ADDON + "/" + rel for rel in files]
    bad = problems_in(names)
    if bad:
        sys.exit("refusing to package:\n  " + "\n  ".join(bad))

    # Every .lua file the .toc loads must be in the package.
    toc_text = open(os.path.join(ADDON_DIR, ADDON + ".toc")).read()
    listed = [l.strip() for l in toc_text.splitlines() if l.strip() and not l.startswith("#")]
    missing = [l for l in listed if l.replace("\\", "/") not in files]
    if missing:
        sys.exit("the .toc loads files that would not be packaged: %s" % ", ".join(missing))

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    tmp = out_path + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for rel in files:
            info = zipfile.ZipInfo(ADDON + "/" + rel, date_time=FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            with open(os.path.join(ADDON_DIR, rel), "rb") as f:
                z.writestr(info, f.read())
    os.replace(tmp, out_path)
    return files


def check(path):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
    bad = problems_in(names)
    for b in bad:
        print("  " + b)
    print("%s: %d entries, %s" % (path, len(names), "OK" if not bad else "%d problems" % len(bad)))
    return not bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", metavar="ZIP", help="validate an existing zip instead of building")
    ap.add_argument("-o", "--out", help="output path (default dist/%s-<version>.zip)" % ADDON)
    args = ap.parse_args()

    if args.check:
        sys.exit(0 if check(args.check) else 1)

    version = toc_version()
    out = args.out or os.path.join(DIST, "%s-%s.zip" % (ADDON, version))
    files = build(out)
    print("%s  (%d files, %.0f KB)" % (os.path.relpath(out, ROOT), len(files), os.path.getsize(out) / 1024))
    for rel in files:
        print("  %s/%s" % (ADDON, rel))
    if not check(out):
        sys.exit(1)


if __name__ == "__main__":
    main()
