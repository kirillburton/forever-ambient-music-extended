#!/usr/bin/env python3
"""Read an installed WoW client's own file manifest from local CASC storage.

    python3 tools/casc_scan.py                       # the Forever client (product wowf)
    python3 tools/casc_scan.py --product wow_classic_beta   # the beta, while installed
    python3 tools/casc_scan.py --ids-out tools/cache/wowf_root.txt
    python3 tools/casc_scan.py --check-addon         # every track FAME ships is in the client

The authoritative answer to "what can this client play?" is its root
manifest: every FileDataID in the build, with its content key.  This walks
the same chain the client does, from the install's own files -- no network:

  .build.info          product -> build key
  Data/config/..       build config -> root content key, encoding key
  Data/data/*.idx      encoding key -> archive, offset, size
  Data/data/data.NNN   BLTE-wrapped files
  encoding             content key -> encoding key
  root (MFST)          FileDataID -> content key, locale and content flags

It also reports, per file, whether its data is actually on this disk (the
client streams anything missing from the CDN, so absent locally is still
playable) and, for local files, whether the payload is encrypted.

Format references: wowdev.wiki/CASC, /TACT, /BLTE.
"""

import argparse
import glob
import hashlib
import os
import re
import struct
import sys
import zlib

INSTALL = "/Applications/World of Warcraft"


# --------------------------------------------------------------------------
# .build.info and build config
# --------------------------------------------------------------------------

def build_info(install, product):
    rows = [l.rstrip("\n").split("|") for l in open(os.path.join(install, ".build.info"))]
    hdr = [h.split("!")[0] for h in rows[0]]
    for r in rows[1:]:
        d = dict(zip(hdr, r))
        if d.get("Product") == product:
            return d
    sys.exit("product %s not in .build.info" % product)


def config(install, key):
    path = os.path.join(install, "Data", "config", key[0:2], key[2:4], key)
    out = {}
    for line in open(path):
        if " = " in line:
            k, v = line.strip().split(" = ", 1)
            out[k] = v.split()
    return out


# --------------------------------------------------------------------------
# Local index: encoding key (first 9 bytes) -> (archive, offset, size)
# --------------------------------------------------------------------------

def load_indexes(install):
    data_dir = os.path.join(install, "Data", "data")
    newest = {}
    for path in glob.glob(os.path.join(data_dir, "*.idx")):
        name = os.path.basename(path)
        bucket, version = int(name[0:2], 16), int(name[2:10], 16)
        if bucket not in newest or version > newest[bucket][0]:
            newest[bucket] = (version, path)
    index = {}
    for _, path in newest.values():
        raw = open(path, "rb").read()
        header_size = struct.unpack_from("<I", raw, 0)[0]
        # header: version u16, bucket u8, extra u8, spanSize u8, spanOffset u8, ekeySize u8, ...
        _, _, _, size_len, offset_len, key_len = struct.unpack_from("<HBBBBB", raw, 8)
        pos = (8 + header_size + 0x0F) & ~0x0F
        entries_size = struct.unpack_from("<I", raw, pos)[0]
        pos += 8
        rec = key_len + offset_len + size_len
        for i in range(entries_size // rec):
            o = pos + i * rec
            ekey = raw[o:o + key_len]
            packed = int.from_bytes(raw[o + key_len:o + key_len + offset_len], "big")
            size = int.from_bytes(raw[o + key_len + offset_len:o + rec], "little")
            archive, offset = packed >> 30, packed & 0x3FFFFFFF
            index.setdefault(ekey, (archive, offset, size))
    return index


def read_local(install, index, ekey_hex):
    """Raw BLTE bytes for an encoding key, or None if not on this disk."""
    ekey = bytes.fromhex(ekey_hex)[:9]
    hit = index.get(ekey)
    if not hit:
        return None
    archive, offset, size = hit
    path = os.path.join(install, "Data", "data", "data.%03d" % archive)
    with open(path, "rb") as f:
        f.seek(offset + 30)           # 30-byte local header before the BLTE payload
        return f.read(size - 30)


# --------------------------------------------------------------------------
# BLTE
# --------------------------------------------------------------------------

class Encrypted(Exception):
    pass


def blte(data):
    if data[:4] != b"BLTE":
        raise ValueError("not BLTE")
    header_size = struct.unpack_from(">I", data, 4)[0]
    if header_size == 0:
        chunks, pos = [(len(data) - 8, None)], 8
    else:
        count = int.from_bytes(data[9:12], "big")
        chunks, p = [], 12
        for _ in range(count):
            comp, decomp = struct.unpack_from(">II", data, p)
            chunks.append((comp, decomp))
            p += 24
        pos = header_size
    out = bytearray()
    for comp, _ in chunks:
        chunk = data[pos:pos + comp]
        pos += comp
        mode = chunk[:1]
        if mode == b"N":
            out += chunk[1:]
        elif mode == b"Z":
            out += zlib.decompress(chunk[1:])
        elif mode == b"E":
            raise Encrypted()
        else:
            raise ValueError("BLTE mode %r" % mode)
    return bytes(out)


def blte_modes(data):
    """The chunk modes of a BLTE blob, without decoding it."""
    header_size = struct.unpack_from(">I", data, 4)[0]
    if header_size == 0:
        return {data[8:9]}
    count = int.from_bytes(data[9:12], "big")
    sizes = [struct.unpack_from(">I", data, 12 + 24 * i)[0] for i in range(count)]
    modes, pos = set(), header_size
    for s in sizes:
        modes.add(data[pos:pos + 1])
        pos += s
    return modes


# --------------------------------------------------------------------------
# Encoding: content key -> encoding key
# --------------------------------------------------------------------------

def parse_encoding(raw):
    if raw[:2] != b"EN":
        raise ValueError("not an encoding file")
    ckey_size, ekey_size = raw[3], raw[4]
    ce_page_kb = struct.unpack_from(">H", raw, 5)[0]
    ce_pages = struct.unpack_from(">I", raw, 9)[0]
    espec_size = struct.unpack_from(">I", raw, 18)[0]
    pos = 22 + espec_size + ce_pages * (ckey_size + 16)
    page_len = ce_page_kb * 1024
    table = {}
    for page in range(ce_pages):
        p, end = pos + page * page_len, pos + (page + 1) * page_len
        while p < end:
            n = raw[p]
            if n == 0:
                break
            ckey = raw[p + 6:p + 6 + ckey_size]
            ekey = raw[p + 6 + ckey_size:p + 6 + ckey_size + ekey_size]
            table[ckey] = ekey
            p += 6 + ckey_size + n * ekey_size
    return table


# --------------------------------------------------------------------------
# Root (MFST): FileDataID -> content key
# --------------------------------------------------------------------------

NO_NAME_HASH = 0x10000000


def parse_root(raw):
    if raw[:4] != b"TSFM":
        raise ValueError("root is not MFST")
    total, named = struct.unpack_from("<II", raw, 4)
    version, pos = 1, 12
    if total in (0x18, 0x14):           # newer header: size, version, total, named
        header_size, version, total, named = struct.unpack_from("<IIII", raw, 4)
        pos = header_size
    allow_unnamed = total != named
    files = {}
    while pos < len(raw):
        count = struct.unpack_from("<I", raw, pos)[0]
        if version >= 2:
            locale, f1, f2 = struct.unpack_from("<III", raw, pos + 4)
            f3 = raw[pos + 16]
            content = f1 | f2 | (f3 << 17)
            pos += 17
        else:
            content, locale = struct.unpack_from("<II", raw, pos + 4)
            pos += 12
        deltas = struct.unpack_from("<%di" % count, raw, pos)
        pos += 4 * count
        ckeys = [raw[pos + 16 * i:pos + 16 * i + 16] for i in range(count)]
        pos += 16 * count
        if not (allow_unnamed and content & NO_NAME_HASH):
            pos += 8 * count
        fdid = -1
        for d, ck in zip(deltas, ckeys):
            fdid += d + 1
            files.setdefault(fdid, []).append((ck, locale, content))
    return files


# --------------------------------------------------------------------------

def open_build(install, product):
    info = build_info(install, product)
    cfg = config(install, info["Build Key"])
    index = load_indexes(install)
    enc_ekey = cfg["encoding"][1]
    encoding = parse_encoding(blte(read_local(install, index, enc_ekey)))
    root_ekey = encoding[bytes.fromhex(cfg["root"][0])]
    root = parse_root(blte(read_local(install, index, root_ekey.hex())))
    return info, index, encoding, root


ENUS = 0x2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--install", default=INSTALL)
    ap.add_argument("--product", default="wowf")
    ap.add_argument("--ids-out", help="write every FileDataID in the root, one per line")
    ap.add_argument("--check-addon", action="store_true",
                    help="verify every track FAME ships is in this client (a release check)")
    args = ap.parse_args()
    info, index, encoding, root = open_build(args.install, args.product)
    print("%s %s: %d files in root, %d local index entries"
          % (args.product, info["Version"], len(root), len(index)))
    if args.check_addon:
        addon = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                             "ForeverAmbientMusicExtended")
        failed = False
        for name in ("Tracks.lua", "Originals.lua"):
            ids = {int(m) for m in re.findall(r"id = (\d+)", open(os.path.join(addon, name)).read())}
            missing = sorted(i for i in ids if i not in root)
            print("%-14s %4d tracks, %d not in this client%s" % (name, len(ids), len(missing),
                  (": " + " ".join(map(str, missing[:20]))) if missing else ""))
            failed = failed or bool(missing)
        sys.exit(1 if failed else 0)
    if args.ids_out:
        with open(args.ids_out, "w") as f:
            for fdid in sorted(root):
                f.write("%d\n" % fdid)
        print("-> %s" % args.ids_out)


if __name__ == "__main__":
    main()
