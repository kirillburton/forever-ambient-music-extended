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
# On Linux and the Steam Deck it finds the game inside Steam's Proton
# prefixes (SD cards included), Lutris, Bottles or ~/.wine; --wow also takes
# a prefix folder.  Run it as yourself, not with sudo.
#
# Safe to stop and run again: tracks already in place are skipped.
# Needs only what macOS and Linux ship with: bash, curl, od, awk, md5 or md5sum;
# perl, where present, makes copying from the retail game much faster.
#
# Instructions and the latest version: https://kirillburton.github.io/forever-ambient-music-extended/import/

set -u
# Plain C conventions for every tool: ls columns, decimal points, sorting.
export LC_ALL=C

SCRIPT_VERSION=3
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

# Files made by root inside the user's game folder couldn't be changed or
# removed by them afterwards.
[ "$(id -u)" != 0 ] || die "Please run this as yourself, without sudo: it only writes into your own game folder."

for tool in curl od awk head tail fold; do
    command -v "$tool" >/dev/null 2>&1 || die "This script needs '$tool', which isn't installed."
done
if command -v md5 >/dev/null 2>&1; then md5of() { md5 -q "$1"; }
elif command -v md5sum >/dev/null 2>&1; then md5of() { md5sum "$1" | cut -d' ' -f1; }
else die "This script needs 'md5' or 'md5sum'."
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/fame-import.XXXXXX") || die "Couldn't create a temporary folder."
trap 'rm -rf "$WORK"; [ -z "${PART:-}" ] || rm -f "$PART"' EXIT
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

# On Linux, Battle.net runs under Wine or Proton, and the folders inside a
# prefix are case-sensitive while the game isn't: a hand-made "Addons" is the
# same folder to the game as "AddOns".  So every path below the game folder is
# looked up without regard to case, and an existing folder is always used
# rather than a second one made beside it.
ci_path() {  # ci_path DIR NAME -> DIR/<NAME as it exists on disk>, or DIR/NAME
    local e want
    if [ -e "$1/$2" ]; then printf '%s' "$1/$2"; return; fi
    want=$(printf '%s' "$2" | tr 'A-Z' 'a-z')
    for e in "$1"/* "$1"/.[!.]*; do
        [ -e "$e" ] || continue
        if [ "$(basename "$e" | tr 'A-Z' 'a-z')" = "$want" ]; then printf '%s' "$e"; return; fi
    done
    printf '%s' "$1/$2"
}
is_wow() { [ -f "$1/.build.info" ] && [ -d "$(ci_path "$1" _forever_)" ]; }

# Every World of Warcraft folder with WoW: Forever in it, one per line.
find_wow() {
    local roots="" r lib prefix d
    # Steam (native, Debian, Flatpak, Snap): Battle.net added as a non-Steam
    # game runs in a Proton prefix, steamapps/compatdata/<number>/pfx.  Every
    # library Steam knows, which is how an SD card is found on the Deck.
    for r in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/debian-installation" \
             "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
             "$HOME/.var/app/com.valvesoftware.Steam/data/Steam" \
             "$HOME/snap/steam/common/.local/share/Steam"; do
        [ -d "$r/steamapps" ] || continue
        roots="$roots$r"$'\n'
        for lib in "$r/steamapps/libraryfolders.vdf" "$r/config/libraryfolders.vdf"; do
            [ -f "$lib" ] && roots="$roots$(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$lib")"$'\n'
        done
    done
    # Libraries on removable drives Steam may not list (an SD card on the Deck).
    for r in /run/media/*/steamapps /run/media/*/*/steamapps /media/*/*/steamapps; do
        [ -d "$r" ] && roots="$roots$(dirname "$r")"$'\n'
    done
    {
        printf '%s' "$roots" | while IFS= read -r r; do
            [ -n "$r" ] || continue
            for prefix in "$r"/steamapps/compatdata/*/pfx; do printf '%s\n' "$prefix"; done
        done
        # Lutris (~/Games/<name>), Bottles (native or Flatpak), plain Wine.
        for prefix in "$HOME"/Games/* "$HOME/.wine" "$HOME"/.local/share/bottles/bottles/* \
                      "$HOME"/.var/app/com.usebottles.bottles/data/bottles/bottles/*; do
            printf '%s\n' "$prefix"
        done
    } | while IFS= read -r prefix; do
        for d in "$prefix/drive_c/Program Files (x86)/World of Warcraft" \
                 "$prefix/drive_c/Program Files/World of Warcraft"; do
            is_wow "$d" && (cd "$d" && pwd -P)
        done
    done
    # macOS.
    for d in "/Applications/World of Warcraft" "$HOME/Applications/World of Warcraft" \
             "$HOME/Games/World of Warcraft"; do
        is_wow "$d" && (cd "$d" && pwd -P)
    done
}

# --wow may name the game folder, or a Wine/Proton prefix holding it.
if [ -n "$WOW" ] && ! is_wow "$WOW"; then
    for d in "$WOW/drive_c/Program Files (x86)/World of Warcraft" "$WOW/drive_c/Program Files/World of Warcraft" \
             "$WOW/pfx/drive_c/Program Files (x86)/World of Warcraft" "$WOW/pfx/drive_c/Program Files/World of Warcraft"; do
        if is_wow "$d"; then WOW="$d"; break; fi
    done
fi
if [ -z "$WOW" ]; then
    # Run from inside the game folder (e.g. from FAME's own folder)?  Walk up.
    d=$(cd "$(dirname "$0")" && pwd)
    while [ "$d" != "/" ]; do
        if is_wow "$d"; then WOW="$d"; break; fi
        d=$(dirname "$d")
    done
fi
if [ -z "$WOW" ]; then
    FOUND=$(find_wow | awk '!seen[$0]++')
    count=$(printf '%s' "$FOUND" | awk 'NF' | wc -l | tr -d ' ')
    if [ "$count" = 1 ]; then
        WOW="$FOUND"
    elif [ "$count" -gt 1 ]; then
        say "World of Warcraft: Forever is installed in more than one place:"
        printf '%s\n' "$FOUND" | awk 'NF { printf "  %d  %s\n", NR, $0 }'
        [ "$ASSUME_YES" = 1 ] && die "Say which with --wow \"/path/to/World of Warcraft\"."
        printf 'Which one should the music go into? Its number: '
        read -r pick || pick=""
        WOW=$(printf '%s\n' "$FOUND" | awk -v n="$pick" 'NF && NR == n')
        [ -n "$WOW" ] || die "No such number. Run again, or say which with --wow \"/path/to/World of Warcraft\"."
        say ""
    fi
fi
[ -n "$WOW" ] || die "Couldn't find World of Warcraft: Forever. Tell the script where it is:
  bash import-retail.sh --wow \"/path/to/World of Warcraft\"
On Linux that's inside the Wine or Proton prefix Battle.net runs in, e.g.
  ~/.local/share/Steam/steamapps/compatdata/<number>/pfx/drive_c/Program Files (x86)/World of Warcraft"
is_wow "$WOW" || die "\"$WOW\" doesn't look like the World of Warcraft folder (no _forever_ or .build.info in it)."
FOREVER_DIR=$(ci_path "$WOW" _forever_)
INTERFACE_DIR=$(ci_path "$FOREVER_DIR" Interface)
ADDONS=$(ci_path "$INTERFACE_DIR" AddOns)
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

FAST=0
[ "$USE_LOCAL" = 1 ] && perl -MDigest::MD5 -e 1 2>/dev/null && FAST=1
if [ "$USE_LOCAL" = 1 ]; then
    printf '  reading the retail archive index…'
fi
if [ "$FAST" = 1 ]; then
    perl -e '
        my ($dir, $list) = @ARGV; my (%want, %best, %seen);
        open my $l, "<", $list or die; while (<$l>) { next if /^#/; my @f = split /\t/; $want{substr($f[3], 0, 18)} = 1 }
        opendir my $d, $dir or die;
        for (readdir $d) { $best{$1} = $_ if /^([0-9a-f]{2})([0-9a-f]{8})\.idx$/ && (!$best{$1} || $2 gt substr($best{$1}, 2, 8)) }
        for my $idx (values %best) {
            open my $fh, "<:raw", "$dir/$idx" or next; local $/; my $x = <$fh>;
            my $pos = int((8 + unpack("V", $x) + 15) / 16) * 16;
            my $end = $pos + 8 + unpack("V", substr($x, $pos, 4));
            $end = length $x if $end > length $x;
            for (my $i = $pos + 8; $i + 18 <= $end; $i += 18) {
                # 9-byte key, 5-byte big-endian archive/offset, 4-byte LE size
                my ($k, $hi, $lo, $size) = unpack "H18 C N V", substr($x, $i, 18);
                next unless $want{$k} && !$seen{$k}++;
                print "$k\t", ($hi << 2) | ($lo >> 30), "\t", $lo & 0x3fffffff, "\t$size\n";
            }
        }' "$WOW/Data/data" "$LIST" > "$LOCAL"
elif [ "$USE_LOCAL" = 1 ]; then
    le32() {  # little-endian uint32 at byte $2 of file $1
        local h; h=$(od -An -v -tx1 -j "$2" -N 4 "$1" | tr -d ' \n')
        printf '%d' "$((16#${h:6:2}${h:4:2}${h:2:2}${h:0:2}))"
    }
    for idx in $(ls "$WOW/Data/data" | awk 'length($0) == 14 && /^[0-9a-f]+\.idx$/ {
                     b = substr($0, 1, 2); v = substr($0, 3, 8)
                     if (!(b in best) || v > best[b]) { best[b] = v; name[b] = $0 } }
                 END { for (b in name) print name[b] }'); do
        f="$WOW/Data/data/$idx"
        hs=$(le32 "$f" 0)
        pos=$(( (8 + hs + 15) / 16 * 16 ))
        len=$(le32 "$f" "$pos")
        # 18-byte records: 9-byte key, 5-byte big-endian archive/offset, 4-byte LE size
        od -An -v -tx1 -j $((pos + 8)) -N "$len" "$f" | tr -d ' \n' | fold -w 36
        echo
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
fi
if [ "$USE_LOCAL" = 1 ]; then
    printf '\r'
    say "  $(wc -l < "$LOCAL" | tr -d ' ') of the pack's tracks are in the retail install       "
fi

# --------------------------------------------------------------------------
# Which expansions
# --------------------------------------------------------------------------

PACK=$(ci_path "$ADDONS" "$PACK_NAME")
MUSIC=$(ci_path "$PACK" Music)
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
    END { for (i = 1; i <= n; i++) printf "%d\t%s\t%s\t%d\t%.0f\t%.1f\t%d\n", i, key[i], label[i], t[i], b[i], s[i] / 3600, a[i] }
' "$LIST" > "$ERA_TABLE"

say ""
say "${B}Music by expansion${R}"
while IFS=$'\t' read -r n key label tracks bytes hours already; do
    mark=""; [ "$already" -gt 0 ] && mark=" ${GRN}($already already imported)${R}"
    printf '  %2d  %-24s %5d tracks  %5s h  %9s%s\n' "$n" "$label" "$tracks" "$hours" "$(human "$bytes")" "$mark"
done < "$ERA_TABLE"
# Byte counts pass 2 GB: printed with %.0f, which every awk keeps whole.
total_bytes=$(awk -F'\t' '{ s += $5 } END { printf "%.0f", s }' "$ERA_TABLE")
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
todo_bytes=$(awk -F'\t' '{ s += $5 } END { printf "%.0f", s }' "$TODO")

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
PART="$MUSIC/.partial.mp3"  # beside the tracks, so the final rename never crosses disks

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
# without its first byte, in order.  Each chunk is checked against its own MD5
# in the header (24-byte entries from byte 12, the MD5 at +8), which the
# encoding key vouches for; with no header, the key covers the whole blob.
unwrap() {  # chunks ("start:size,size,..."), out -> fails on a damaged chunk
    local start="${1%%:*}" sizes="${1#*:}" pos c i=0 sums=""
    pos=$start
    : > "$2"
    [ "$start" = 8 ] || sums=$(od -An -v -tx1 -j 12 -N $((start - 12)) "$BLOB" | tr -d ' \n')
    for c in $(printf '%s' "$sizes" | tr ',' ' '); do
        tail -c +$((pos + 1)) "$BLOB" | head -c "$c" > "$WORK/chunk"
        [ -z "$sums" ] || [ "$(md5of "$WORK/chunk")" = "${sums:$((i * 48 + 16)):32}" ] || return 1
        tail -c +2 "$WORK/chunk" >> "$2"
        pos=$((pos + c)); i=$((i + 1))
    done
}

done_n=0; fail_n=0; from_local_n=0; from_cdn_n=0
FAILED="$WORK/failed.txt"; : > "$FAILED"

if [ "$FAST" = 1 ] && [ "$todo_n" -gt 0 ]; then
    perl -MDigest::MD5=md5_hex -e '
        my ($local, $todo, $rest, $data, $music, $part, $total) = @ARGV; my (%at, $n);
        open my $l, "<", $local or die; while (<$l>) { chomp; my ($k, @v) = split /\t/; $at{$k} = \@v }
        open my $t, "<", $todo or die; open my $r, ">", $rest or die;
        $| = 1;
        while (my $line = <$t>) {
            my ($fid, $era, $sec, $ekey, $bytes, $stored, $cdn, $chunks) = split /\t/, $line; chomp $chunks;
            my ($archive, $offset, $size) = @{ $at{substr($ekey, 0, 18)} || [] };
            my ($blob, $out) = ("", "");
            if (defined $size && $size > 30 && open my $fh, "<:raw", sprintf("%s/data.%03d", $data, $archive)) {
                # 30-byte local header before the blob
                seek $fh, $offset + 30, 0; read $fh, $blob, $size - 30;
            }
            # Valid if the MD5 of its header (all of it, when the chunks start at byte 8) is the key.
            my ($start, $sizes) = split /:/, $chunks;
            if (length $blob && md5_hex($start == 8 ? $blob : substr($blob, 0, $start)) eq $ekey) {
                # Every chunk is stored as-is behind a one-byte N, and checked against its MD5 in the header.
                my ($pos, $i) = ($start, 0);
                for (split /,/, $sizes) {
                    if ($start > 8 && md5_hex(substr($blob, $pos, $_)) ne unpack("H32", substr($blob, 20 + 24 * $i++, 16))) { $out = ""; last }
                    $out .= substr($blob, $pos + 1, $_ - 1); $pos += $_;
                }
            }
            # A track that cannot be written is left for the loop below, like a missing one.
            if (length $out == $bytes && open my $o, ">:raw", $part) {
                my $ok = print $o $out; $ok = close($o) && $ok;
                if ($ok && rename $part, "$music/$fid.mp3") { printf "\r  %d / %d", ++$n, $total; next }
                unlink $part;
            }
            print $r $line or die "$rest: $!\n";
        }
        close $r or die "$rest: $!\n";' "$LOCAL" "$TODO" "$WORK/rest.tsv" "$WOW/Data/data" "$MUSIC" "$PART" "$todo_n" \
        && FAST_OK=1 || FAST_OK=0
    if [ "$FAST_OK" = 1 ]; then
        TODO="$WORK/rest.tsv"
        from_local_n=$((todo_n - $(wc -l < "$TODO" | tr -d ' ')))
        done_n=$from_local_n
        USE_LOCAL=0
    else
        say ""; warn "The fast copy stopped; going on track by track."
    fi
fi
while IFS=$'\t' read -r fid era seconds ekey bytes stored cdn chunks; do
    got=""
    if [ "$USE_LOCAL" = 1 ] && from_local "$ekey" && blob_ok "$ekey" "${chunks%%:*}"; then
        got=local
    elif [ "$USE_CDN" = 1 ] && from_cdn "$ekey" "$stored" "$cdn" && blob_ok "$ekey" "${chunks%%:*}"; then
        got=cdn
    fi
    if [ -n "$got" ]; then
        if unwrap "$chunks" "$PART" && [ "$(wc -c < "$PART" | tr -d ' ')" = "$bytes" ]; then
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
            printf "    bytes = %.0f,\n    tracks = {\n", bytes
            for (i = 1; i <= n; i++) print line[i]
            print "    },"
        }' "$LIST"
    say "}"
} > "$PACK/Pack.lua"
cat > "$PACK/$PACK_NAME.toc" <<EOF
## Interface: $INTERFACE
## Title: FAME Retail Music Pack
## Notes: Music from modern World of Warcraft, imported from your own computer for Forever Ambient Music Extended. Made by import-retail.sh; run it again to change what's in it.
## IconTexture: Interface\AddOns\ForeverAmbientMusicExtended\Media\logo
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
