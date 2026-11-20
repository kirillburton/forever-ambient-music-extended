# import-retail.ps1 -- add music from modern World of Warcraft to FAME, on Windows.
#
# Forever Ambient Music Extended can play music from the retail game's later
# expansions, but it can't ship that music: it belongs to Blizzard.  This
# script fetches it onto your own computer, into a separate addon folder that
# FAME finds by itself:
#
#   World of Warcraft\_forever_\Interface\AddOns\ForeverAmbientMusicExtended_RetailPack
#
# Each track comes from your installed retail game if you have it, and from
# Blizzard's own download servers (the ones the Battle.net app uses) if not.
# Every file is checked against Blizzard's checksum before it is kept.
#
# In PowerShell:
#   powershell -ExecutionPolicy Bypass -File import-retail.ps1                  asks which expansions
#   powershell -ExecutionPolicy Bypass -File import-retail.ps1 --eras cata,mop  no questions
#   ... --all
#   ... --wow "D:\Games\World of Warcraft"
#   ... --local-only        never download; retail must be installed
#   ... --cdn-only          ignore an installed retail game
#
# "-ExecutionPolicy Bypass" lets this one script run without changing any
# setting on your computer.  Safe to stop and run again: tracks already in
# place are skipped.  Needs only Windows PowerShell 5.1, which Windows 10 and
# 11 come with.  The Mac and Linux version is import-retail.sh.
#
# Instructions and the latest version: https://kirillburton.github.io/forever-ambient-music-extended/import/

$SCRIPT_VERSION = 2
$LIST_FORMAT = 1
$PAGE = "https://kirillburton.github.io/forever-ambient-music-extended/import/"
$PACK_NAME = "ForeverAmbientMusicExtended_RetailPack"
$INTERFACE = 16001

# --------------------------------------------------------------------------
# Output.  Plain ASCII throughout: Windows PowerShell 5.1 misreads anything
# else in a script file saved without a byte-order mark.
# --------------------------------------------------------------------------

function Say([string]$text = "") { Write-Host $text }
function Ok([string]$text) { Write-Host -NoNewline -ForegroundColor Green "OK "; Write-Host $text }
function Warn([string]$text) { Write-Host -NoNewline -ForegroundColor Yellow "!  "; Write-Host $text }
function Dim([string]$text) { Write-Host -ForegroundColor DarkGray $text }
function Show-Latest {
    Say ""
    Say "Get the latest version of this script, with instructions, at:"
    Write-Host -ForegroundColor White "  $PAGE"
}
# Stops the import.  Never "exit": that would close the PowerShell window too.
function Stop-Import([string]$text) {
    Write-Host -ForegroundColor Red "X  $text"
    Show-Latest
    throw "FAME-STOP"
}
function Format-Size([double]$bytes) {
    if ($bytes -ge 1073741824) { return ("{0:0.0} GB" -f ($bytes / 1073741824)).Replace(",", ".") }
    return "{0} MB" -f [math]::Floor($bytes / 1048576)
}

# --------------------------------------------------------------------------
# Network.  HttpWebRequest, because it does byte ranges in Windows
# PowerShell 5.1 (Invoke-WebRequest refuses a Range header there).
# --------------------------------------------------------------------------

function Get-Bytes([string]$url, [long]$from = -1, [long]$to = -1, [int]$timeout = 120000) {
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Timeout = $timeout
    $req.ReadWriteTimeout = $timeout
    $req.UserAgent = "fame-import"
    if ($from -ge 0) { $req.AddRange($from, $to) }
    $resp = $req.GetResponse()
    try {
        # A server that ignored the range would send a whole archive: refuse.
        if ($from -ge 0 -and [int]$resp.StatusCode -ne 206) { throw "no range support" }
        $stream = $resp.GetResponseStream()
        $mem = New-Object System.IO.MemoryStream
        $stream.CopyTo($mem)
        return ,$mem.ToArray()
    } finally {
        $resp.Close()
    }
}

function Get-Text([string]$url, [int]$timeout = 60000) {
    $bytes = Get-Bytes $url -1 -1 $timeout
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

# --------------------------------------------------------------------------
# Finding World of Warcraft
# --------------------------------------------------------------------------

function Test-Wow([string]$dir) {
    if (-not $dir) { return $false }
    return (Test-Path -LiteralPath (Join-Path $dir ".build.info") -PathType Leaf) -and
           (Test-Path -LiteralPath (Join-Path $dir "_forever_") -PathType Container)
}

# The World of Warcraft folder for a path that may point inside it
# ("...\World of Warcraft\_retail_\"), or $null.
function Resolve-Wow([string]$path) {
    if (-not $path) { return $null }
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $d = $path.Trim().Trim('"')
    if ($sep -eq [char]'\') { $d = $d.Replace("/", "\") }
    $d = $d.TrimEnd($sep)
    for ($i = 0; $i -lt 3 -and $d; $i++) {
        if (Test-Wow $d) { return (Get-Item -LiteralPath $d).FullName.TrimEnd($sep) }
        $d = Split-Path -Parent $d
    }
    return $null
}

# Every World of Warcraft folder with WoW: Forever in it.
function Find-Wow {
    $paths = New-Object System.Collections.Generic.List[string]
    # Battle.net's own record of where each game is installed.
    $db = if ($env:ProgramData) { Join-Path (Join-Path (Join-Path $env:ProgramData "Battle.net") "Agent") "product.db" } else { "" }
    if ($db -and (Test-Path -LiteralPath $db)) {
        $text = [System.Text.Encoding]::GetEncoding(28591).GetString([System.IO.File]::ReadAllBytes($db))
        foreach ($m in [regex]::Matches($text, '[A-Za-z]:[\\/][^\x00-\x1f"]*?World of Warcraft')) { $paths.Add($m.Value) }
    }
    # The registry: Blizzard's own keys and the uninstall entries.
    foreach ($root in "HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment", "HKLM:\SOFTWARE\Blizzard Entertainment") {
        if (Test-Path $root) {
            Get-ChildItem $root -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                foreach ($name in "InstallPath", "GamePath") {
                    if ($p -and $p.$name) { $paths.Add([string]$p.$name) }
                }
            }
        }
    }
    foreach ($root in "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                      "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall") {
        if (Test-Path $root) {
            Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
                $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if ($p -and $p.DisplayName -like "*World of Warcraft*" -and $p.InstallLocation) {
                    $paths.Add([string]$p.InstallLocation)
                }
            }
        }
    }
    # The usual places, on every drive.
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -ne "Fixed" -or -not $drive.IsReady) { continue }
        foreach ($sub in "Program Files (x86)", "Program Files", "", "Games", "Blizzard", "Battle.net") {
            $paths.Add((Join-Path (Join-Path $drive.RootDirectory.FullName $sub) "World of Warcraft"))
        }
    }
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($p in $paths) {
        $w = Resolve-Wow $p
        if ($w -and -not ($found | Where-Object { $_ -eq $w })) { $found.Add($w) }
    }
    return ,$found
}

# --------------------------------------------------------------------------
# The import
# --------------------------------------------------------------------------

function Invoke-Import([string[]]$argv) {
    $ErrorActionPreference = "Stop"
    $wow = ""; $eras = ""; $mode = "auto"; $assumeYes = $false
    for ($i = 0; $i -lt $argv.Count; $i++) {
        switch -Regex ($argv[$i]) {
            '^--?wow$'        { $i++; $wow = $argv[$i] }
            '^--?eras$'       { $i++; $eras = ($argv[$i] -replace ",", " ") }
            '^--?all$'        { $eras = "all" }
            '^--?local-only$' { $mode = "local" }
            '^--?cdn-only$'   { $mode = "cdn" }
            '^(--?yes|-y)$'   { $assumeYes = $true }
            '^(--?help|-h|/\?)$' {
                Get-Content -LiteralPath $PSCommandPath -TotalCount 26 | ForEach-Object { Say ($_ -replace '^# ?', '') }
                return
            }
            default { Stop-Import "Unknown option: $($argv[$i])" }
        }
    }

    # GitHub Pages only speaks TLS 1.2+, which 5.1 doesn't always offer.
    try {
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    } catch { }

    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("fame-import-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        Write-Host -NoNewline -ForegroundColor White "FAME retail music import"
        Dim " (script version $SCRIPT_VERSION)"
        Say ""

        # Is this script up to date?  The page publishes the current version.
        try {
            $remote = (Get-Text "$($PAGE)VERSION" 10000) -replace '[^0-9]', ''
            if ($remote -and [int]$remote -gt $SCRIPT_VERSION) {
                Warn "A newer version of this script is available (version $remote)."
                Show-Latest
                Say ""
            }
        } catch { }

        # ------------------------------------------------------------------
        # Find World of Warcraft
        # ------------------------------------------------------------------
        if ($wow) {
            $resolved = Resolve-Wow $wow
            if (-not $resolved) { Stop-Import "`"$wow`" doesn't look like the World of Warcraft folder (no _forever_ or .build.info in it)." }
            $wow = $resolved
        }
        if (-not $wow -and $PSCommandPath) {
            # Run from inside the game folder (e.g. from FAME's own folder)?
            $d = Split-Path -Parent $PSCommandPath
            while ($d) {
                if (Test-Wow $d) { $wow = $d; break }
                $d = Split-Path -Parent $d
            }
        }
        if (-not $wow) {
            $found = Find-Wow
            if ($found.Count -eq 1) {
                $wow = $found[0]
            } elseif ($found.Count -gt 1) {
                Say "World of Warcraft: Forever is installed in more than one place:"
                for ($i = 0; $i -lt $found.Count; $i++) { Say ("  {0}  {1}" -f ($i + 1), $found[$i]) }
                if ($assumeYes) { Stop-Import "Say which with --wow `"X:\path\to\World of Warcraft`"." }
                $pick = Read-Host "Which one should the music go into? Its number"
                $n = 0
                if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 1 -or $n -gt $found.Count) {
                    Stop-Import "No such number. Run again, or say which with --wow `"X:\path\to\World of Warcraft`"."
                }
                $wow = $found[$n - 1]
                Say ""
            }
        }
        if (-not $wow) {
            Stop-Import ("Couldn't find World of Warcraft: Forever. Tell the script where it is:`n" +
                "  powershell -ExecutionPolicy Bypass -File import-retail.ps1 --wow `"X:\path\to\World of Warcraft`"`n" +
                "(In the Battle.net app: the gear next to Play, then Show in Explorer.)")
        }
        $addons = Join-Path (Join-Path (Join-Path $wow "_forever_") "Interface") "AddOns"
        if (-not (Test-Path -LiteralPath $addons -PathType Container)) {
            Stop-Import "No _forever_\Interface\AddOns folder. Start WoW: Forever once, then run this again."
        }
        Ok "World of Warcraft: $wow"

        # Products installed here: .build.info is a pipe-separated table.
        $info = [System.IO.File]::ReadAllLines((Join-Path $wow ".build.info"))
        $cols = @{}
        $head = $info[0].Split("|")
        for ($i = 0; $i -lt $head.Count; $i++) { $cols[$head[$i].Split("!")[0]] = $i }
        $foreverVersion = ""; $retailVersion = ""
        foreach ($line in ($info | Select-Object -Skip 1)) {
            $f = $line.Split("|")
            if ($f.Count -le $cols["Version"]) { continue }
            if ($f[$cols["Product"]] -eq "wowf" -and -not $foreverVersion) { $foreverVersion = $f[$cols["Version"]] }
            if ($f[$cols["Product"]] -eq "wow" -and -not $retailVersion) { $retailVersion = $f[$cols["Version"]] }
        }
        if ($foreverVersion) { Ok "WoW: Forever $foreverVersion" }

        # ------------------------------------------------------------------
        # The track list, fresh from the page; the copy beside the script if offline.
        # ------------------------------------------------------------------
        $listText = $null
        try { $listText = Get-Text "$($PAGE)retail-pack.tsv" 60000 } catch { }
        if (-not $listText) {
            $beside = if ($PSCommandPath) { Join-Path (Split-Path -Parent $PSCommandPath) "retail-pack.tsv" } else { "" }
            if ($beside -and (Test-Path -LiteralPath $beside)) {
                $listText = [System.IO.File]::ReadAllText($beside)
                Warn "Couldn't reach the project page; using the track list next to this script."
            } else {
                Stop-Import "Couldn't download the track list, and there's no retail-pack.tsv next to this script."
            }
        }
        $meta = @{}; $eraKeys = New-Object System.Collections.Generic.List[string]; $eraLabel = @{}
        $tracks = New-Object System.Collections.Generic.List[object]
        foreach ($line in ($listText -split "`r?`n")) {
            if (-not $line) { continue }
            $f = $line.Split("`t")
            if ($f[0] -eq "# era") { $eraKeys.Add($f[1]); $eraLabel[$f[1]] = $f[2]; continue }
            if ($f[0].StartsWith("# ")) { if ($f.Count -gt 1) { $meta[$f[0].Substring(2)] = $f[1]; if ($f[0] -eq "# cdn") { $meta["cdnhosts"] = $f[2] } }; continue }
            $start, $sizes = $f[7].Split(":")
            $tracks.Add([pscustomobject]@{
                fid = $f[0]; era = $f[1]; seconds = [double]$f[2]; ekey = $f[3]; bytes = [long]$f[4]
                stored = [long]$f[5]; cdn = $f[6]; start = [int]$start; chunks = $sizes.Split(",")
            })
        }
        if ($meta["format"] -ne "$LIST_FORMAT") { Stop-Import "This script is too old for the current track list." }
        $listRetail = $meta["retail"]
        $cdnPath = $meta["cdn"]
        $cdnHosts = $meta["cdnhosts"].Split(" ")

        # ------------------------------------------------------------------
        # Where tracks can come from
        # ------------------------------------------------------------------
        $useLocal = $false; $useCdn = $true
        if ($mode -eq "local") { $useCdn = $false }
        if ($mode -eq "cdn") { $retailVersion = "" }
        if ($retailVersion) {
            $useLocal = $true
            Ok "Retail game $($retailVersion): tracks are copied from it"
            if ($retailVersion -ne $listRetail) { Dim "  (the list was made for $listRetail; anything that no longer matches is downloaded instead)" }
            if ($useCdn) { Dim "  anything missing from it is downloaded from Blizzard's servers" }
        } elseif ($mode -eq "local") {
            Stop-Import ("The retail game isn't installed here, and --local-only was given.`n" +
                "Install World of Warcraft (retail) in the Battle.net app, or run without --local-only`n" +
                "to download the music from Blizzard's servers instead.")
        } else {
            Ok "Tracks are downloaded from Blizzard's servers (the ones the Battle.net app uses)"
        }

        # Local archive index: encoding key -> archive, offset, size.  One
        # .idx per bucket is current: the newest version of each.  Records are
        # 18 bytes: 9-byte key, 5-byte big-endian archive/offset, 4-byte LE size.
        $local = @{}
        if ($useLocal) {
            Write-Host -NoNewline "  reading the retail archive index..."
            $want = New-Object 'System.Collections.Generic.Dictionary[UInt64,string]'
            foreach ($t in $tracks) {
                $kb = New-Object byte[] 8
                for ($j = 0; $j -lt 8; $j++) { $kb[$j] = [Convert]::ToByte($t.ekey.Substring($j * 2, 2), 16) }
                $want[[BitConverter]::ToUInt64($kb, 0)] = $t.ekey.Substring(0, 18)
            }
            $dataDir = Join-Path (Join-Path $wow "Data") "data"
            $best = @{}
            Get-ChildItem -LiteralPath $dataDir -Filter "*.idx" -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -match '^([0-9a-f]{2})([0-9a-f]{8})\.idx$') {
                    if (-not $best.ContainsKey($Matches[1]) -or $Matches[2] -gt $best[$Matches[1]].v) {
                        $best[$Matches[1]] = @{ v = $Matches[2]; path = $_.FullName }
                    }
                }
            }
            foreach ($b in $best.Values) {
                $bytes = [System.IO.File]::ReadAllBytes($b.path)
                $hs = [BitConverter]::ToUInt32($bytes, 0)
                $pos = [int]([math]::Floor((8 + $hs + 15) / 16) * 16)
                $len = [BitConverter]::ToUInt32($bytes, $pos)
                $end = $pos + 8 + $len
                for ($p = $pos + 8; $p + 18 -le $end; $p += 18) {
                    $k = [BitConverter]::ToUInt64($bytes, $p)
                    if (-not $want.ContainsKey($k)) { continue }
                    $key = $want[$k]
                    if ([Convert]::ToByte($key.Substring(16, 2), 16) -ne $bytes[$p + 8]) { continue }
                    if ($local.ContainsKey($key)) { continue }
                    $packed = ([long]$bytes[$p + 9] -shl 32) -bor ([long]$bytes[$p + 10] -shl 24) -bor
                              ([long]$bytes[$p + 11] -shl 16) -bor ([long]$bytes[$p + 12] -shl 8) -bor [long]$bytes[$p + 13]
                    $local[$key] = @{ archive = [int]($packed -shr 30); offset = [long]($packed -band 0x3FFFFFFF)
                                      size = [long][BitConverter]::ToUInt32($bytes, $p + 14) }
                }
            }
            Write-Host "`r  $($local.Count) of the pack's tracks are in the retail install          "
        }

        # ------------------------------------------------------------------
        # Which expansions
        # ------------------------------------------------------------------
        $pack = Join-Path $addons $PACK_NAME
        $music = Join-Path $pack "Music"
        try { New-Item -ItemType Directory -Force -Path $music | Out-Null }
        catch {
            Stop-Import ("Windows won't let this script write into`n  $addons`n" +
                "Close this window, open PowerShell with 'Run as administrator', and run the script again.")
        }

        # What's already there: fileDataID -> bytes, for every finished track.
        function Get-Have {
            $have = @{}
            Get-ChildItem -LiteralPath $music -Filter "*.mp3" -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -match '^(\d+)\.mp3$') { $have[$Matches[1]] = $_.Length }
            }
            return $have
        }
        $have = Get-Have

        $rows = @()
        $n = 0
        foreach ($key in $eraKeys) {
            $n++
            $mine = @($tracks | Where-Object { $_.era -eq $key })
            $already = @($mine | Where-Object { $have.ContainsKey($_.fid) -and $have[$_.fid] -eq $_.bytes }).Count
            $bytes = 0; $secs = 0
            foreach ($t in $mine) { $bytes += $t.bytes; $secs += $t.seconds }
            $rows += [pscustomobject]@{ n = $n; key = $key; label = $eraLabel[$key]; tracks = $mine.Count
                                        bytes = $bytes; hours = $secs / 3600; already = $already }
        }
        Say ""
        Write-Host -ForegroundColor White "Music by expansion"
        $total = 0
        foreach ($r in $rows) {
            $total += $r.bytes
            $line = "  {0,2}  {1,-24} {2,5} tracks  {3,5} h  {4,9}" -f $r.n, $r.label, $r.tracks,
                ("{0:0.0}" -f $r.hours).Replace(",", "."), (Format-Size $r.bytes)
            Write-Host -NoNewline $line
            if ($r.already -gt 0) { Write-Host -ForegroundColor Green " ($($r.already) already imported)" } else { Say "" }
        }
        Dim "      all of them: $(Format-Size $total)"
        Say ""

        if (-not $eras) { $eras = Read-Host 'Which do you want? Numbers separated by spaces, or "all"' }
        $selected = @{}
        foreach ($word in ($eras -split '\s+' | Where-Object { $_ })) {
            if ($word -eq "all") { foreach ($r in $rows) { $selected[$r.key] = $true }; break }
            $match = $rows | Where-Object { "$($_.n)" -eq $word -or $_.key -eq $word }
            if (-not $match) { Stop-Import "`"$word`" isn't one of the numbers above." }
            $selected[$match.key] = $true
        }
        if ($selected.Count -eq 0) { Stop-Import "Nothing chosen." }

        # Tracks of expansions not chosen this time, already on disk: offer to remove.
        $stale = @($tracks | Where-Object { -not $selected.ContainsKey($_.era) -and $have.ContainsKey($_.fid) })
        if ($stale.Count -gt 0) {
            $answer = "n"
            if ($assumeYes) { $answer = "y" }
            else { $answer = Read-Host "$($stale.Count) tracks from expansions you didn't choose are already imported. Remove them? [y/N]" }
            if ($answer -match '^(y|yes)$') {
                foreach ($t in $stale) { Remove-Item -LiteralPath (Join-Path $music "$($t.fid).mp3") -Force -ErrorAction SilentlyContinue }
                Ok "Removed $($stale.Count) tracks."
            }
        }

        $todo = @($tracks | Where-Object { $selected.ContainsKey($_.era) -and -not ($have.ContainsKey($_.fid) -and $have[$_.fid] -eq $_.bytes) })
        $todoBytes = 0
        foreach ($t in $todo) { $todoBytes += $t.bytes }
        if ($todo.Count -eq 0) {
            Ok "Everything you chose is already imported."
        } else {
            $free = (New-Object System.IO.DriveInfo ([System.IO.Path]::GetPathRoot($addons))).AvailableFreeSpace
            if ($free -lt $todoBytes + 104857600) {
                Stop-Import "Not enough free disk space: this needs $(Format-Size $todoBytes), and the disk has $(Format-Size $free)."
            }
            Say ""
            Say "Importing $($todo.Count) tracks ($(Format-Size $todoBytes))..."
        }

        # ------------------------------------------------------------------
        # Fetch, check, unwrap
        # ------------------------------------------------------------------
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $part = Join-Path $pack ".partial.mp3"
        $dataDir = Join-Path (Join-Path $wow "Data") "data"

        # The blob is valid if the MD5 of its header (or of all of it, when it
        # has none: a chunk layout starting at byte 8) equals its encoding key.
        function Test-Blob($blob, $t) {
            if ($null -eq $blob) { return $false }
            $count = if ($t.start -eq 8) { $blob.Length } else { $t.start }
            if ($blob.Length -lt $count) { return $false }
            $sum = -join ($md5.ComputeHash($blob, 0, $count) | ForEach-Object { $_.ToString("x2") })
            return $sum -eq $t.ekey
        }
        function Get-FromLocal($t) {
            $hit = $local[$t.ekey.Substring(0, 18)]
            if (-not $hit) { return $null }
            $file = Join-Path $dataDir ("data.{0:000}" -f $hit.archive)
            if (-not (Test-Path -LiteralPath $file)) { return $null }
            $fs = [System.IO.File]::Open($file, "Open", "Read", "ReadWrite")
            try {
                # 30-byte local header before the blob
                [void]$fs.Seek($hit.offset + 30, "Begin")
                $buf = New-Object byte[] ($hit.size - 30)
                $read = 0
                while ($read -lt $buf.Length) {
                    $got = $fs.Read($buf, $read, $buf.Length - $read)
                    if ($got -le 0) { return $null }
                    $read += $got
                }
                return ,$buf
            } finally { $fs.Close() }
        }
        function Get-FromCdn($t) {
            foreach ($h in $cdnHosts) {
                try {
                    if ($t.cdn -eq "-") {
                        $e = $t.ekey
                        return ,(Get-Bytes "http://$h/$cdnPath/data/$($e.Substring(0,2))/$($e.Substring(2,2))/$e")
                    }
                    $archive, $offset = $t.cdn.Split(":")
                    $offset = [long]$offset
                    return ,(Get-Bytes "http://$h/$cdnPath/data/$($archive.Substring(0,2))/$($archive.Substring(2,2))/$archive" $offset ($offset + $t.stored - 1))
                } catch { }
            }
            return $null
        }
        # Every chunk is stored as-is behind a one-byte 'N': the audio is each
        # chunk without its first byte, in order.
        function Write-Audio($blob, $t, $out) {
            $fs = [System.IO.File]::Create($out)
            try {
                $pos = $t.start
                foreach ($c in $t.chunks) {
                    $c = [int]$c
                    $fs.Write($blob, $pos + 1, $c - 1)
                    $pos += $c
                }
            } finally { $fs.Close() }
        }

        $done = 0; $fail = 0; $fromLocal = 0; $fromCdn = 0
        foreach ($t in $todo) {
            $got = ""
            if ($useLocal) {
                $blob = Get-FromLocal $t
                if (Test-Blob $blob $t) { $got = "local" }
            }
            if (-not $got -and $useCdn) {
                $blob = Get-FromCdn $t
                if (Test-Blob $blob $t) { $got = "cdn" }
            }
            if ($got) {
                Write-Audio $blob $t $part
                # .NET directly: a file starting with a dot is hidden to the
                # cmdlets on some systems.
                if ((New-Object System.IO.FileInfo $part).Length -eq $t.bytes) {
                    $dest = Join-Path $music "$($t.fid).mp3"
                    if ([System.IO.File]::Exists($dest)) { [System.IO.File]::Delete($dest) }
                    [System.IO.File]::Move($part, $dest)
                    $done++
                    if ($got -eq "local") { $fromLocal++ } else { $fromCdn++ }
                } else {
                    $got = ""
                }
            }
            if (-not $got) { $fail++ }
            $line = "`r  {0} / {1}" -f ($done + $fail), $todo.Count
            if ($fail -gt 0) { $line += ", $fail failed" }
            Write-Host -NoNewline $line
        }
        if ([System.IO.File]::Exists($part)) { [System.IO.File]::Delete($part) }
        if ($todo.Count -gt 0) { Say "" }

        # ------------------------------------------------------------------
        # The pack addon: a .toc so the game loads it, and Pack.lua listing
        # what is actually on disk, so FAME knows exactly what it can play.
        # ------------------------------------------------------------------
        $have = Get-Have
        $inPack = 0; $packBytes = [long]0
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($t in $tracks) {
            if ($have.ContainsKey($t.fid) -and $have[$t.fid] -eq $t.bytes) {
                $inPack++; $packBytes += $t.bytes
                $lines.Add("        [$($t.fid)] = `"$($t.era)`",")
            }
        }
        $lua = New-Object System.Text.StringBuilder
        [void]$lua.Append("-- Generated by FAME's import-retail.ps1. Do not edit: run the script again instead.`n")
        [void]$lua.Append("-- Lists the music in this folder that matches FAME's track list exactly.`n")
        [void]$lua.Append("FAMERetailPack = {`n")
        [void]$lua.Append("    format = $LIST_FORMAT,`n")
        [void]$lua.Append("    script = $SCRIPT_VERSION,`n")
        [void]$lua.Append("    retail = `"$listRetail`",`n")
        [void]$lua.Append("    list = `"$($meta['generated'])`",`n")
        [void]$lua.Append("    imported = `"$(Get-Date -Format 'yyyy-MM-dd')`",`n")
        [void]$lua.Append("    bytes = $packBytes,`n")
        [void]$lua.Append("    tracks = {`n")
        foreach ($l in $lines) { [void]$lua.Append("$l`n") }
        [void]$lua.Append("    },`n}`n")
        # UTF-8 without a byte-order mark, as the game expects.
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText((Join-Path $pack "Pack.lua"), $lua.ToString(), $utf8)
        $toc = "## Interface: $INTERFACE`n" +
               "## Title: FAME Retail Music Pack`n" +
               "## Notes: Music from modern World of Warcraft, imported from your own computer for Forever Ambient Music Extended. Made by import-retail.ps1; run it again to change what's in it.`n" +
               "## Version: $($meta['generated'])`n" +
               "## X-Generated-By: import-retail.ps1 $SCRIPT_VERSION`n`nPack.lua`n"
        [System.IO.File]::WriteAllText((Join-Path $pack "$PACK_NAME.toc"), $toc, $utf8)

        Say ""
        if ($todo.Count -gt 0) { Ok "Imported $done tracks ($fromLocal from the retail game, $fromCdn downloaded)." }
        Ok "The pack holds $inPack tracks, $(Format-Size $packBytes)."
        if ($fail -gt 0) {
            if ($fail -eq 1) { Warn "1 track couldn't be fetched or didn't pass the checksum." }
            else { Warn "$fail tracks couldn't be fetched or didn't pass the checksum." }
            Say "  Running the script again retries them. If they still fail, Blizzard has"
            Say "  probably moved them since this list was made."
            Show-Latest
        }
        Say ""
        Write-Host -NoNewline -ForegroundColor White "Restart World of Warcraft: Forever"
        Say " to hear them (a /reload isn't enough: the game"
        Say "only finds new addon files when it starts)."
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

try {
    Invoke-Import $args
} catch {
    if ("$_" -ne "FAME-STOP") {
        Write-Host -ForegroundColor Red "X  Something went wrong: $_"
        Show-Latest
    }
}
