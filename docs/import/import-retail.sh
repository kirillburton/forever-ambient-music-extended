#!/bin/bash
# import-retail.sh -- add music from modern World of Warcraft to FAME.
#
# Forever Ambient Music Extended can play music from the retail game's later
# expansions, but it can't ship that music: it belongs to Blizzard.  This
# script fetches it onto your own computer, into a separate addon folder that
# FAME finds by itself:
#
#   World of Warcraft/_forever_/Interface/AddOns/ForeverAmbientMusicExtended_RetailPack
#
# Each track comes from your installed retail game if you have it, and from
# Blizzard's own download servers (the ones the Battle.net app uses) if not.
# Every file is checked against Blizzard's checksum before it is kept.
#
#   bash import-retail.sh                    asks which expansions you want
#   bash import-retail.sh --eras cata,mop    no questions
#   bash import-retail.sh --all
#   bash import-retail.sh --wow "/path/to/World of Warcraft"
#   bash import-retail.sh --local-only       never download; retail must be installed
#   bash import-retail.sh --cdn-only         ignore an installed retail game
#
# Safe to stop and run again: tracks already in place are skipped.
# Needs only what macOS ships with: bash, curl, xxd, awk, md5.
#
# Instructions and the latest version: https://kirillburton.github.io/forever-ambient-music-extended/import/

set -u

SCRIPT_VERSION=1
LIST_FORMAT=1
PAGE="https://kirillburton.github.io/forever-ambient-music-extended/import/"
PACK_NAME="ForeverAmbientMusicExtended_RetailPack"
INTERFACE=16001

# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------

if [ -t 1 ]; then
    B=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; R=$'\033[0m'
else
    B=; DIM=; RED=; GRN=; YEL=; R=
fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$GRN" "$R" "$*"; }
warn() { printf '%s!%s %s\n' "$YEL" "$R" "$*"; }
latest() {
    say ""
    say "Get the latest version of this script, with instructions, at:"
    say "  ${B}${PAGE}${R}"
}
die() {
    printf '%s✗ %s%s\n' "$RED" "$*" "$R" >&2
    latest >&2
    exit 1
}

# --------------------------------------------------------------------------
# Arguments
# --------------------------------------------------------------------------

WOW=""; ERAS=""; MODE="auto"; ASSUME_YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        --wow) WOW="${2:-}"; shift ;;
        --eras) ERAS=$(printf '%s' "${2:-}" | tr ',' ' '); shift ;;
        --all) ERAS="all" ;;
        --local-only) MODE="local" ;;
        --cdn-only) MODE="cdn" ;;
        --yes|-y) ASSUME_YES=1 ;;
        -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

for tool in curl xxd awk head tail; do
    command -v "$tool" >/dev/null 2>&1 || die "This script needs '$tool', which isn't installed."
done
if command -v md5 >/dev/null 2>&1; then md5of() { md5 -q "$1"; }
elif command -v md5sum >/dev/null 2>&1; then md5of() { md5sum "$1" | cut -d' ' -f1; }
else die "This script needs 'md5' or 'md5sum'."
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/fame-import.XXXXXX") || die "Couldn't create a temporary folder."
trap 'rm -rf "$WORK"' EXIT
trap 'say ""; warn "Stopped. Run the script again to continue where it left off."; exit 130' INT TERM

say "${B}FAME retail music import${R} ${DIM}(script version $SCRIPT_VERSION)${R}"
say ""

# --------------------------------------------------------------------------
# Is this script up to date?  The page publishes the current version.
# --------------------------------------------------------------------------

remote_version=$(curl -fsSL --max-time 10 "${PAGE}VERSION" 2>/dev/null | tr -dc '0-9')
if [ -n "$remote_version" ] && [ "$remote_version" -gt "$SCRIPT_VERSION" ]; then
    warn "A newer version of this script is available (version $remote_version)."
    latest
    say ""
fi

# --------------------------------------------------------------------------
# Find World of Warcraft
# --------------------------------------------------------------------------

is_wow() { [ -f "$1/.build.info" ] && [ -d "$1/_forever_" ]; }
if [ -z "$WOW" ]; then
    # Run from inside the game folder (e.g. from FAME's own folder)?  Walk up.
    d=$(cd "$(dirname "$0")" && pwd)
    while [ "$d" != "/" ]; do
        if is_wow "$d"; then WOW="$d"; break; fi
        d=$(dirname "$d")
    done
fi
if [ -z "$WOW" ]; then
    for d in "/Applications/World of Warcraft" "$HOME/Applications/World of Warcraft" \
             "$HOME/Games/World of Warcraft"; do
        if is_wow "$d"; then WOW="$d"; break; fi
    done
fi
[ -n "$WOW" ] || die "Couldn't find World of Warcraft. Tell the script where it is:
  bash import-retail.sh --wow \"/path/to/World of Warcraft\""
is_wow "$WOW" || die "\"$WOW\" doesn't look like the World of Warcraft folder (no _forever_ or .build.info in it)."
ADDONS="$WOW/_forever_/Interface/AddOns"
[ -d "$ADDONS" ] || die "No _forever_/Interface/AddOns folder. Start WoW: Forever once, then run this again."
ok "World of Warcraft: $WOW"

# Products installed here: .build.info is a pipe-separated table.
product_version() {
    awk -F'|' -v want="$1" '
        NR == 1 { for (i = 1; i <= NF; i++) { split($i, h, "!"); col[h[1]] = i }; next }
        $col["Product"] == want { print $col["Version"]; exit }' "$WOW/.build.info"
}
FOREVER_VERSION=$(product_version wowf)
RETAIL_VERSION=$(product_version wow)
[ -n "$FOREVER_VERSION" ] && ok "WoW: Forever $FOREVER_VERSION"

# --------------------------------------------------------------------------
# The track list, fresh from the page; the copy beside the script if offline.
# --------------------------------------------------------------------------

LIST="$WORK/retail-pack.tsv"
if curl -fsSL --max-time 60 "${PAGE}retail-pack.tsv" -o "$LIST" 2>/dev/null && [ -s "$LIST" ]; then
    :
elif [ -f "$(dirname "$0")/retail-pack.tsv" ]; then
    cp "$(dirname "$0")/retail-pack.tsv" "$LIST"
    warn "Couldn't reach the project page; using the track list next to this script."
else
    die "Couldn't download the track list, and there's no retail-pack.tsv next to this script."
fi
meta() { awk -F'\t' -v k="$1" '$1 == "# " k { print $2; exit }' "$LIST"; }
[ "$(meta format)" = "$LIST_FORMAT" ] || die "This script is too old for the current track list."
LIST_RETAIL=$(meta retail)
CDN_PATH=$(awk -F'\t' '$1 == "# cdn" { print $2; exit }' "$LIST")
CDN_HOSTS=$(awk -F'\t' '$1 == "# cdn" { print $3; exit }' "$LIST")

# --------------------------------------------------------------------------
# Where tracks can come from
# --------------------------------------------------------------------------

USE_LOCAL=0; USE_CDN=1
case "$MODE" in
    local) USE_CDN=0 ;;
    cdn) RETAIL_VERSION="" ;;
esac
if [ -n "$RETAIL_VERSION" ]; then
    USE_LOCAL=1
    ok "Retail game $RETAIL_VERSION: tracks are copied from it"
    [ "$RETAIL_VERSION" = "$LIST_RETAIL" ] || \
        say "  ${DIM}(the list was made for $LIST_RETAIL; anything that no longer matches is downloaded instead)${R}"
    [ "$USE_CDN" = 1 ] && say "  ${DIM}anything missing from it is downloaded from Blizzard's servers${R}"
elif [ "$MODE" = "local" ]; then
    die "The retail game isn't installed here, and --local-only was given.
Install World of Warcraft (retail) in the Battle.net app, or run without --local-only
to download the music from Blizzard's servers instead."
else
    ok "Tracks are downloaded from Blizzard's servers (the ones the Battle.net app uses)"
fi

# Local archive index: encoding key (first 9 bytes, hex) -> archive, offset, size.
# One .idx per bucket is current: the newest version of each.
LOCAL="$WORK/local.tsv"
: > "$LOCAL"
if [ "$USE_LOCAL" = 1 ]; then
    printf '  reading the retail archive index…'
    le32() {  # little-endian uint32 at byte $2 of file $1
        local h; h=$(xxd -p -s "$2" -l 4 "$1")
        printf '%d' "$((16#${h:6:2}${h:4:2}${h:2:2}${h:0:2}))"
    }
    for idx in $(ls "$WOW/Data/data" | awk '/^[0-9a-f]{10}\.idx$/ {
                     b = substr($0, 1, 2); v = substr($0, 3, 8)
                     if (!(b in best) || v > best[b]) { best[b] = v; name[b] = $0 } }
                 END { for (b in name) print name[b] }'); do
        f="$WOW/Data/data/$idx"
        hs=$(le32 "$f" 0)
        pos=$(( (8 + hs + 15) / 16 * 16 ))
        len=$(le32 "$f" "$pos")
        # 18-byte records: 9-byte key, 5-byte big-endian archive/offset, 4-byte LE size
        xxd -p -c 18 -s $((pos + 8)) -l "$len" "$f"
    done | awk -v want_file="$LIST" '
        function hex(s,   i, n) { n = 0; for (i = 1; i <= length(s); i++) n = n * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1; return n }
        BEGIN { while ((getline line < want_file) > 0) if (line !~ /^#/) { split(line, f, "\t"); w[substr(f[4], 1, 18)] = 1 } }
        length($0) == 36 && (substr($0, 1, 18) in w) && !(substr($0, 1, 18) in seen) {
            k = substr($0, 1, 18); seen[k] = 1
            packed = hex(substr($0, 19, 10))
            archive = int(packed / 1073741824)
            s = substr($0, 29, 8)
            print k "\t" archive "\t" (packed - archive * 1073741824) "\t" hex(substr(s, 7, 2) substr(s, 5, 2) substr(s, 3, 2) substr(s, 1, 2))
        }' > "$LOCAL"
    printf '\r'
    say "  $(wc -l < "$LOCAL" | tr -d ' ') of the pack's tracks are in the retail install       "
fi

# --------------------------------------------------------------------------
# Which expansions
# --------------------------------------------------------------------------

PACK="$ADDONS/$PACK_NAME"
MUSIC="$PACK/Music"
mkdir -p "$MUSIC" || die "Couldn't create $MUSIC"

# What's already there: "<fileDataID> <bytes>" for every finished track.
HAVE="$WORK/have.txt"
ls -ln "$MUSIC" 2>/dev/null | awk '$9 ~ /^[0-9]+\.mp3$/ { sub(/\.mp3$/, "", $9); print $9, $5 }' > "$HAVE"

human() { awk -v b="$1" 'BEGIN { if (b >= 1073741824) printf "%.1f GB", b / 1073741824; else printf "%d MB", b / 1048576 }'; }

ERA_TABLE="$WORK/eras.tsv"   # n, key, label, tracks, bytes, hours, already
awk -F'\t' -v have_file="$HAVE" '
    BEGIN { while ((getline l < have_file) > 0) { split(l, h, " "); have[h[1]] = h[2] } }
    $1 == "# era" { n++; key[n] = $2; label[n] = $3; idx[$2] = n; next }
    /^#/ { next }
    { e = idx[$2]; t[e]++; b[e] += $5; s[e] += $3; if (have[$1] == $5) a[e]++ }
    END { for (i = 1; i <= n; i++) printf "%d\t%s\t%s\t%d\t%d\t%.1f\t%d\n", i, key[i], label[i], t[i], b[i], s[i] / 3600, a[i] }
' "$LIST" > "$ERA_TABLE"

say ""
say "${B}Music by expansion${R}"
while IFS=$'\t' read -r n key label tracks bytes hours already; do
    mark=""; [ "$already" -gt 0 ] && mark=" ${GRN}($already already imported)${R}"
    printf '  %2d  %-24s %5d tracks  %5s h  %9s%s\n' "$n" "$label" "$tracks" "$hours" "$(human "$bytes")" "$mark"
done < "$ERA_TABLE"
total_bytes=$(awk -F'\t' '{ s += $5 } END { print s }' "$ERA_TABLE")
say "      ${DIM}all of them: $(human "$total_bytes")${R}"
say ""

if [ -z "$ERAS" ]; then
    printf 'Which do you want? Numbers separated by spaces, or "all": '
    read -r answer || exit 1
    ERAS="$answer"
fi
SELECTED=" "
for word in $ERAS; do
    if [ "$word" = "all" ]; then
        SELECTED=" $(cut -f2 "$ERA_TABLE" | tr '\n' ' ')"
        break
    fi
    key=$(awk -F'\t' -v w="$word" '$1 == w || $2 == w { print $2 }' "$ERA_TABLE")
    [ -n "$key" ] || die "\"$word\" isn't one of the numbers above."
    SELECTED="$SELECTED$key "
done
[ "$SELECTED" != " " ] || die "Nothing chosen."

# Tracks of expansions not chosen this time, already on disk: offer to remove.
STALE="$WORK/stale.txt"
awk -F'\t' -v sel="$SELECTED" -v have_file="$HAVE" '
    BEGIN { while ((getline l < have_file) > 0) { split(l, h, " "); have[h[1]] = 1 } }
    /^#/ { next }
    index(sel, " " $2 " ") == 0 && ($1 in have) { print $1 }' "$LIST" > "$STALE"
if [ -s "$STALE" ]; then
    n=$(wc -l < "$STALE" | tr -d ' ')
    answer=n
    if [ "$ASSUME_YES" = 1 ]; then answer=y
    else printf '%s tracks from expansions you didn'"'"'t choose are already imported. Remove them? [y/N] ' "$n"; read -r answer || answer=n
    fi
    case "$answer" in
        y|Y|yes) while read -r fid; do rm -f "$MUSIC/$fid.mp3"; done < "$STALE"; ok "Removed $n tracks." ;;
    esac
fi

TODO="$WORK/todo.tsv"
awk -F'\t' -v sel="$SELECTED" -v have_file="$HAVE" '
    BEGIN { while ((getline l < have_file) > 0) { split(l, h, " "); have[h[1]] = h[2] } }
    /^#/ { next }
    index(sel, " " $2 " ") > 0 && have[$1] != $5' "$LIST" > "$TODO"
todo_n=$(wc -l < "$TODO" | tr -d ' ')
todo_bytes=$(awk -F'\t' '{ s += $5 } END { print s + 0 }' "$TODO")

if [ "$todo_n" = 0 ]; then
    ok "Everything you chose is already imported."
else
    free_kb=$(df -Pk "$ADDONS" | awk 'NR == 2 { print $4 }')
    if [ -n "$free_kb" ] && [ $((free_kb * 1024)) -lt $((todo_bytes + 104857600)) ]; then
        die "Not enough free disk space: this needs $(human "$todo_bytes"), and the disk has $(human $((free_kb * 1024)))."
    fi
    say ""
    say "Importing $todo_n tracks ($(human "$todo_bytes"))…"
fi

# --------------------------------------------------------------------------
# Fetch, check, unwrap
# --------------------------------------------------------------------------

BLOB="$WORK/blob"
PART="$PACK/.partial.mp3"

# The blob is valid if the MD5 of its header (or of all of it, when it has
# none: a chunk layout starting at byte 8) equals its encoding key.
blob_ok() {  # ekey, start
    local sum
    if [ "$2" = 8 ]; then sum=$(md5of "$BLOB")
    else head -c "$2" "$BLOB" > "$WORK/header"; sum=$(md5of "$WORK/header")
    fi
    [ "$sum" = "$1" ]
}

from_local() {  # ekey -> $BLOB, or fail
    local hit archive offset size
    hit=$(awk -F'\t' -v k="${1:0:18}" '$1 == k { print $2, $3, $4; exit }' "$LOCAL")
    [ -n "$hit" ] || return 1
    read -r archive offset size <<< "$hit"
    # 30-byte local header before the blob
    tail -c +$((offset + 31)) "$WOW/Data/data/data.$(printf '%03d' "$archive")" 2>/dev/null \
        | head -c $((size - 30)) > "$BLOB"
}

from_cdn() {  # ekey, stored size, cdn location -> $BLOB, or fail
    local host url range=""
    if [ "$3" = "-" ]; then
        url="data/${1:0:2}/${1:2:2}/$1"
    else
        local archive="${3%%:*}" offset="${3##*:}"
        url="data/${archive:0:2}/${archive:2:2}/$archive"
        range="$offset-$((offset + $2 - 1))"
    fi
    for host in $CDN_HOSTS; do
        if [ -n "$range" ]; then
            curl -fsS --max-time 120 -r "$range" "http://$host/$CDN_PATH/$url" -o "$BLOB" 2>/dev/null && return 0
        else
            curl -fsS --max-time 120 "http://$host/$CDN_PATH/$url" -o "$BLOB" 2>/dev/null && return 0
        fi
    done
    return 1
}

# Every chunk is stored as-is behind a one-byte 'N': the audio is each chunk
# without its first byte, in order.
unwrap() {  # chunks ("start:size,size,..."), out
    local start="${1%%:*}" sizes="${1#*:}" pos c
    pos=$start
    : > "$2"
    for c in $(printf '%s' "$sizes" | tr ',' ' '); do
        tail -c +$((pos + 2)) "$BLOB" | head -c $((c - 1)) >> "$2"
        pos=$((pos + c))
    done
}

done_n=0; fail_n=0; from_local_n=0; from_cdn_n=0
FAILED="$WORK/failed.txt"; : > "$FAILED"
while IFS=$'\t' read -r fid era seconds ekey bytes stored cdn chunks; do
    got=""
    if [ "$USE_LOCAL" = 1 ] && from_local "$ekey" && blob_ok "$ekey" "${chunks%%:*}"; then
        got=local
    elif [ "$USE_CDN" = 1 ] && from_cdn "$ekey" "$stored" "$cdn" && blob_ok "$ekey" "${chunks%%:*}"; then
        got=cdn
    fi
    if [ -n "$got" ]; then
        unwrap "$chunks" "$PART"
        if [ "$(wc -c < "$PART" | tr -d ' ')" = "$bytes" ]; then
            mv -f "$PART" "$MUSIC/$fid.mp3"
            done_n=$((done_n + 1))
            if [ "$got" = local ]; then from_local_n=$((from_local_n + 1)); else from_cdn_n=$((from_cdn_n + 1)); fi
        else
            got=""
        fi
    fi
    if [ -z "$got" ]; then
        fail_n=$((fail_n + 1))
        printf '%s\t%s\n' "$fid" "$era" >> "$FAILED"
    fi
    n=$((done_n + fail_n))
    printf '\r  %d / %d%s' "$n" "$todo_n" "$([ "$fail_n" -gt 0 ] && printf ', %d failed' "$fail_n")"
done < "$TODO"
rm -f "$PART"
[ "$todo_n" -gt 0 ] && say ""

# --------------------------------------------------------------------------
# The pack addon: a .toc so the game loads it, and Pack.lua listing what is
# actually on disk, so FAME knows exactly what it can play.
# --------------------------------------------------------------------------

ls -ln "$MUSIC" | awk '$9 ~ /^[0-9]+\.mp3$/ { sub(/\.mp3$/, "", $9); print $9, $5 }' > "$HAVE"
{
    say "-- Generated by FAME's import-retail.sh. Do not edit: run the script again instead."
    say "-- Lists the music in this folder that matches FAME's track list exactly."
    say "FAMERetailPack = {"
    say "    format = $LIST_FORMAT,"
    say "    script = $SCRIPT_VERSION,"
    say "    retail = \"$LIST_RETAIL\","
    say "    list = \"$(meta generated)\","
    say "    imported = \"$(date +%Y-%m-%d)\","
    awk -F'\t' -v have_file="$HAVE" '
        BEGIN { while ((getline l < have_file) > 0) { split(l, h, " "); have[h[1]] = h[2] } }
        /^#/ { next }
        have[$1] == $5 { n++; bytes += $5; line[n] = "        [" $1 "] = \"" $2 "\"," }
        END {
            printf "    bytes = %d,\n    tracks = {\n", bytes
            for (i = 1; i <= n; i++) print line[i]
            print "    },"
        }' "$LIST"
    say "}"
} > "$PACK/Pack.lua"
cat > "$PACK/$PACK_NAME.toc" <<EOF
## Interface: $INTERFACE
## Title: FAME Retail Music Pack
## Notes: Music from modern World of Warcraft, imported from your own computer for Forever Ambient Music Extended. Made by import-retail.sh; run it again to change what's in it.
## Version: $(meta generated)
## X-Generated-By: import-retail.sh $SCRIPT_VERSION

Pack.lua
EOF

in_pack=$(awk '/^        \[/' "$PACK/Pack.lua" | wc -l | tr -d ' ')
pack_bytes=$(awk '$1 == "bytes" { gsub(/,/, "", $3); print $3 }' "$PACK/Pack.lua")
say ""
[ "$todo_n" -gt 0 ] && ok "Imported $done_n tracks ($from_local_n from the retail game, $from_cdn_n downloaded)."
ok "The pack holds $in_pack tracks, $(human "${pack_bytes:-0}")."
if [ "$fail_n" -gt 0 ]; then
    if [ "$fail_n" = 1 ]; then warn "1 track couldn't be fetched or didn't pass the checksum."
    else warn "$fail_n tracks couldn't be fetched or didn't pass the checksum."; fi
    say "  Running the script again retries them. If they still fail, Blizzard has"
    say "  probably moved them since this list was made."
    latest
fi
say ""
say "${B}Restart World of Warcraft: Forever${R} to hear them (a /reload isn't enough: the game"
say "only finds new addon files when it starts)."
[ "$fail_n" -gt 0 ] && exit 2
exit 0
