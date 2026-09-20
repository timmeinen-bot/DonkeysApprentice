# =====================================================================
#  QuickAccess - quick access from the notification area
#
#  Tim, 2026-09-03: "call up a tray tool, it opens with an overlay, then
#  click excel and the file opens, or even just hover over it ... max easy",
#  "or http links as well", "show file names as the shortcut names",
#  "find a cool icon e.g. a little donkey with a magic wand".
#
#  Mouse over the icon -> the overlay opens. A click on a row opens the
#  file, folder or link. Mouse away -> the overlay closes by itself.
# =====================================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------------
#  🔴 KEEP STATE GLOBAL, NOT VIA $script: INSIDE CLOSURES.
#     The first attempt created the click action with .GetNewClosure() and
#     accessed $script:overlay inside it. Clicking a row then produced
#     "You cannot call a method on a null-valued expression" - the closure
#     no longer saw the variable, because it had been created inside a
#     function and got its own scope there.
#     Now: everything lives in $global:QA, and the target hangs off the
#     control as .Tag.
# ---------------------------------------------------------------------
$global:QA = @{
    Basis  = Split-Path -Parent $MyInvocation.MyCommand.Path
    Symbole = @{}
    ReiterZiel = $null
}
# 🔴 Separate the program from its working data
#    (DA-20260913-144004296-42e6). A program that writes into its own
#    directory fails as soon as it sits under C:\Program Files -- an
#    ordinary user may not write there. From here on $QA.Basis is ONLY the
#    location of the program; everything written lives under $QA.Daten.
$global:QA.Daten = Join-Path $env:LOCALAPPDATA 'QuickAccess'
if (-not (Test-Path -LiteralPath $global:QA.Daten)) {
    New-Item -ItemType Directory -Force -Path $global:QA.Daten | Out-Null
}
$global:QA.Konfig = Join-Path $global:QA.Daten 'quickaccess.txt'

# Adopting older states: until 2026-09-13 the list sat next to the
# script. Without this step the user would face an empty window after an
# update.
$qa_alt = Join-Path $global:QA.Basis 'quickaccess.txt'
if ((Test-Path -LiteralPath $qa_alt) -and
    -not (Test-Path -LiteralPath $global:QA.Konfig) -and
    ($qa_alt -ne $global:QA.Konfig)) {
    # Copy, do not move: if the migration fails, nothing is lost.
    Copy-Item -LiteralPath $qa_alt -Destination $global:QA.Konfig
    # Rename the original -- otherwise an older build of the program keeps
    # reading the old file and there would be TWO lists drifting apart.
    Rename-Item -LiteralPath $qa_alt -NewName (
        'quickaccess.txt.uebernommen_' + (Get-Date -Format 'yyyyMMdd'))
}

$sperre = New-Object System.Threading.Mutex($false, 'Global\QuickAccessTray')
if (-not $sperre.WaitOne(0, $false)) { return }

# 🔴 ExtractAssociatedIcon CANNOT TAKE AN ICON INDEX. Shortcuts,
#    however, almost always state their icon as "file.dll,44" - without the
#    index you get the first icon of the file, which is something entirely
#    different. ExtractIconEx from shell32 takes the index and returns
#    exactly the icon Explorer shows.
Add-Type -Namespace QA -Name Shell -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern int ExtractIconExW(string datei, int index, out IntPtr gross, out IntPtr klein, int anzahl);
[DllImport("user32.dll")]
public static extern bool DestroyIcon(IntPtr handle);
'@

function global:QA-SymbolMitIndex($datei, $index) {
    $gross = [IntPtr]::Zero; $klein = [IntPtr]::Zero
    try {
        $n = [QA.Shell]::ExtractIconExW($datei, $index, [ref]$gross, [ref]$klein, 1)
        if ($n -gt 0 -and $gross -ne [IntPtr]::Zero) {
            # Copy before the handle is released - otherwise the image
            # later points at nothing.
            $symbol = [System.Drawing.Icon]::FromHandle($gross)
            $kopie = $symbol.Clone()
            [void][QA.Shell]::DestroyIcon($gross)
            if ($klein -ne [IntPtr]::Zero) { [void][QA.Shell]::DestroyIcon($klein) }
            return $kopie
        }
    } catch { }
    return $null
}

function global:QA-IstLink($ziel) { return $ziel -match '^(https?|mailto|ftp)://|^mailto:' }

function global:QA-Log($text) {
    # ⚠️ Exceptions in WinForms events surface nowhere - without a log
    #    you are completely in the dark when "nothing happens".
    try {
        $datei = Join-Path $global:QA.Daten 'quickaccess.log'
        Add-Content -Path $datei -Encoding UTF8 -Value (
            (Get-Date).ToString('dd.MM. HH:mm:ss') + '  ' + $text)
    } catch { }
}

function global:QA-Oeffne($ziel) {
    if (-not $ziel) { QA-Log 'click with no target'; return }
    QA-Log ('opening: ' + $ziel)
    # 🔴 Expand %VARIABLES% BEFORE anything is checked. Without that,
    #    Test-Path fails on '%USERPROFILE%\Documents' and every entry of the
    #    shipped example list reports "not found" -- the list MUST work
    #    without hard paths, otherwise it carries one particular machine's
    #    targets again (DA-20260913-143955698-e77e).
    $ziel = [Environment]::ExpandEnvironmentVariables($ziel)
    try {
        # Shell special locations (recycle bin, startup, control panel)
        # are not file system paths -- Test-Path never finds them.
        # Explorer, by contrast, accepts them unchanged.
        if ($ziel -like 'shell:*') {
            Start-Process explorer.exe -ArgumentList ('"' + $ziel + '"') -ErrorAction Stop
            QA-Log '  -> shell location in Explorer'
            return
        }
        if (QA-IstLink $ziel) {
            Start-Process $ziel -ErrorAction Stop
            QA-Log '  -> link started'
            return
        }
        if (-not (Test-Path -LiteralPath $ziel)) {
            QA-Log '  -> NOT FOUND'
            [System.Windows.Forms.MessageBox]::Show(
                "Not found:`n$ziel`n`nIs the network drive connected?",
                "Donkey's Apprentice", 'OK', 'Warning') | Out-Null
            return
        }
        # 🔴 PASS -WorkingDirectory. Without it the new process inherits
        #    the tray tool's working directory; Excel then trips over paths
        #    with "&" in the name and opens nothing, without comment.
        if ((Get-Item -LiteralPath $ziel).PSIsContainer) {
            # 🔴 FOLDERS CANNOT BE OPENED WITH Start-Process -FilePath.
            #    Windows answers "This command cannot be run completely
            #    because the system cannot find all the information
            #    required" - a directory simply is not an executable
            #    target. Explorer takes it without complaint.
            Start-Process explorer.exe -ArgumentList ('"' + $ziel + '"') -ErrorAction Stop
            QA-Log '  -> folder in Explorer'
        } else {
            # ⚠️ Pass -WorkingDirectory: without it the new process
            #    inherits the tray tool's working directory, and Office
            #    silently failed to open files from paths with "&" in the
            #    name.
            Start-Process -FilePath $ziel -WorkingDirectory (Split-Path -Parent $ziel) -ErrorAction Stop
            QA-Log '  -> started'
        }
    } catch {
        QA-Log ('  -> ERROR: ' + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show(
            "Could not be opened:`n$ziel`n`n" + $_.Exception.Message,
            "Donkey's Apprentice", 'OK', 'Error') | Out-Null
    }
}

# ---------------------------------------------------------------------
#  Configuration
#     [Group]         -> heading
#     Name = Target   -> custom display name
#     Target          -> without "=": the FILE NAME becomes the display name
# ---------------------------------------------------------------------
function global:QA-LiesKonfig {
    $pfad = $global:QA.Konfig
    if (-not (Test-Path $pfad)) { return @() }
    $liste = @(); $gruppe = ''
    # ⚠️ Without -Encoding UTF8, PowerShell 5.1 reads the file as ANSI -
    #    any non-ASCII name turns into garbage.
    foreach ($zeile in (Get-Content $pfad -Encoding UTF8)) {
        $z = $zeile.Trim()
        if ($z -eq '' -or $z.StartsWith('#')) { continue }
        if ($z -match '^\[(.+)\]$') { $gruppe = $Matches[1].Trim(); continue }
        $i = $z.IndexOf('=')
        # A drive letter ("T:\...") is not a separator - so only one
        # equals sign counts, and that is the first one.
        if ($i -ge 1) {
            $name = $z.Substring(0, $i).Trim()
            $ziel = $z.Substring($i + 1).Trim()
        } else {
            $ziel = $z
            $name = ''
        }
        if (-not $ziel) { continue }
        # Custom icon, separated from the target by " | ".
        # ⚠️ The vertical bar is forbidden in Windows paths and can
        #    therefore never be part of a target - which is why it works
        #    as the separator.
        $symbol = ''
        $strich = $ziel.IndexOf(' | ')
        if ($strich -ge 0) {
            $symbol = $ziel.Substring($strich + 3).Trim()
            $ziel = $ziel.Substring(0, $strich).Trim()
        }
        # Tim, 2026-09-03: "show file names as the shortcut names" - the
        # file name ALWAYS wins; a name left of the = remains only a
        # fallback for links that have no file name.
        if (QA-IstLink $ziel) {
            if (-not $name) { $name = ($ziel -replace '^\w+://', '') }
        } else {
            $dateiname = [IO.Path]::GetFileName($ziel.TrimEnd(''))
            # ⚠️ For a shortcut the ".lnk" extension is noise in the list -
            #    it says nothing about the content, only about the form.
            if ($dateiname -like '*.lnk') {
                $dateiname = [IO.Path]::GetFileNameWithoutExtension($dateiname)
            }
            if ($dateiname) { $name = $dateiname }
        }
        if (-not $name) { $name = $ziel }
        $liste += [PSCustomObject]@{ Gruppe = $gruppe; Name = $name; Ziel = $ziel; Symbol = $symbol }
    }
    return $liste
}

if (-not (Test-Path $global:QA.Konfig)) {
    # 🔴 Until 2026-09-13 a template with the owner's REAL targets sat
    #    here: NAS address, T: paths, Trello id -- hard-coded in the source,
    #    that is, in exactly the file that ships with every package. A data
    #    file gets noticed when packing; a template inside the script does
    #    not. The initial content now comes from quickaccess.beispiel.txt,
    #    which contains only Windows standard locations and public links.
    $beispiel = Join-Path $global:QA.Basis 'quickaccess.beispiel.txt'
    if (Test-Path -LiteralPath $beispiel) {
        # Copy instead of write: that preserves the encoding, and there is
        # only ONE place where the initial content lives.
        Copy-Item -LiteralPath $beispiel -Destination $global:QA.Konfig
        QA-Log 'First run: quickaccess.txt created from quickaccess.beispiel.txt'
        # DA-20260913-144047595-f616: the same condition as above, no
        # second flag -- there was no quickaccess.txt, so this is the very
        # first start.
        $global:QA.Erstmals = $true
    } else {
        # Even without the example file the window must not stay empty --
        # an empty window with no hint is the worst possible first run.
        $notfall = @'
# Donkey's Apprentice -- the example file was missing, so only the bare
# minimum. Entries read "Name = Target" under a group in square brackets.

[Start]
Dokumente = %USERPROFILE%\Documents
Downloads = %USERPROFILE%\Downloads
'@
        # ⚠️ UTF-8 WITH a byte order mark - otherwise non-ASCII
        #    characters in paths come back wrong when read again.
        [IO.File]::WriteAllText($global:QA.Konfig, $notfall,
                                (New-Object Text.UTF8Encoding $true))
        QA-Log 'First run: quickaccess.beispiel.txt missing - emergency list created'
        $global:QA.Erstmals = $true
    }
}

# ---------------------------------------------------------------------
#  Icons - cached, because ExtractAssociatedIcon dawdles over the network
# ---------------------------------------------------------------------
function global:QA-BrowserSymbol {
    # Icon of the browser that is actually being used.
    #
    # 🔴 Tim, 09-07: "DA shows the Edge icon for an http link although
    #    Chrome is the default browser". Windows really does list MSEdgeHTM
    #    for http, https and .html here - Edge has taken the association
    #    back. So the registry does not tell you what the machine is
    #    actually used with. Therefore what counts first is which browser
    #    is RUNNING; only if none is open does the association apply.
    if ($global:QA.ContainsKey('BrowserSymbol')) { return $global:QA.BrowserSymbol }
    $ergebnis = $null

    try {
        $offen = Get-Process chrome, firefox, msedge, opera, brave -ErrorAction SilentlyContinue |
                 Group-Object ProcessName |
                 ForEach-Object {
                     [PSCustomObject]@{
                         Name   = $_.Name
                         Bytes  = ($_.Group | Measure-Object WorkingSet64 -Sum).Sum
                         Pfad   = ($_.Group | Where-Object { $_.Path } |
                                   Select-Object -First 1 -ExpandProperty Path)
                     }
                 } | Sort-Object Bytes -Descending
        foreach ($b in $offen) {
            if ($b.Pfad -and (Test-Path -LiteralPath $b.Pfad)) {
                $ergebnis = [System.Drawing.Icon]::ExtractAssociatedIcon($b.Pfad)
                if ($ergebnis) {
                    QA-Log ('browser icon from the running ' + $b.Name)
                    break
                }
            }
        }
    } catch { }
    if ($ergebnis) {
        $global:QA.BrowserSymbol = $ergebnis
        return $ergebnis
    }

    try {
        $schluessel = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice'
        $progId = (Get-ItemProperty -Path $schluessel -ErrorAction Stop).ProgId
        if ($progId) {
            $befehl = (Get-ItemProperty -Path ('Registry::HKEY_CLASSES_ROOT\' + $progId + '\shell\open\command') -ErrorAction Stop).'(default)'
            if ($befehl) {
                # The command is in quotes, parameters follow it
                $exe = $befehl
                if ($exe.StartsWith('"')) { $exe = $exe.Substring(1, $exe.IndexOf('"', 1) - 1) }
                else { $exe = ($exe -split ' ')[0] }
                if (Test-Path -LiteralPath $exe) {
                    $ergebnis = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
                }
            }
        }
    } catch { }
    $global:QA.BrowserSymbol = $ergebnis
    return $ergebnis
}


# ---------------------------------------------------------------------
#  Site icon (favicon)
#
#  Without this, ALL links get the same browser icon - Trello, Grafana and
#  the three NAS boxes would look identical. It is fetched once per host,
#  after which the image is local. A failure is recorded too, otherwise
#  every rebuild stalls on the network again.
# ---------------------------------------------------------------------
function global:QA-FaviconOrdner {
    $p = Join-Path (Split-Path $global:QA.Konfig -Parent) 'symbole'
    if (-not (Test-Path -LiteralPath $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
    return $p
}

function global:QA-PngAusIco([byte[]]$daten) {
    # Cuts the largest single image out of an ICO container.
    # Layout: 6-byte header, then 16 bytes per directory entry; the length
    # is at +8, the offset at +12.
    try {
        if ($daten.Length -lt 22) { return $null }
        if ([BitConverter]::ToUInt16($daten, 0) -ne 0 -or
            [BitConverter]::ToUInt16($daten, 2) -ne 1) { return $null }
        $anzahl = [BitConverter]::ToUInt16($daten, 4)
        if ($anzahl -lt 1) { return $null }
        $besteLaenge = 0; $besterVersatz = 0
        for ($i = 0; $i -lt $anzahl; $i++) {
            $e = 6 + $i * 16
            if ($e + 16 -gt $daten.Length) { break }
            $laenge  = [BitConverter]::ToUInt32($daten, $e + 8)
            $versatz = [BitConverter]::ToUInt32($daten, $e + 12)
            if ($versatz + $laenge -le $daten.Length -and $laenge -gt $besteLaenge) {
                $besteLaenge = $laenge; $besterVersatz = $versatz
            }
        }
        if ($besteLaenge -lt 64) { return $null }
        $teil = New-Object byte[] $besteLaenge
        [Array]::Copy($daten, $besterVersatz, $teil, 0, $besteLaenge)
        return $teil
    } catch { return $null }
}

function global:QA-SvgSymbol([string]$svg) {
    # GDI+ cannot do SVG. Our own pages, however, use only two simple
    # variants that can be drawn by hand:
    #   1. emoji favicon: <text ...>🏠</text>  (cockpit, KODI, HM log)
    #   2. pixel icon from <rect> tiles        (JD processor /favicon.svg)
    # A real path-based SVG falls back to $null -> then the browser icon
    # applies.
    try {
        $vw = 16.0; $vh = 16.0
        $vb = [regex]::Match($svg, 'viewBox\s*=\s*["'']\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)')
        if ($vb.Success) { $vw = [double]$vb.Groups[3].Value; $vh = [double]$vb.Groups[4].Value }
        if ($vw -le 0) { $vw = 16 }
        if ($vh -le 0) { $vh = 16 }
        $bmp = New-Object System.Drawing.Bitmap(32, 32)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([System.Drawing.Color]::Transparent)
        $etwas = $false

        # 1. emoji from <text>
        $t = [regex]::Match($svg, '<text[^>]*>(.+?)</text>',
                            [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($t.Success) {
            $emoji = [System.Net.WebUtility]::HtmlDecode($t.Groups[1].Value).Trim()
            if ($emoji) {
                $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
                $font = New-Object System.Drawing.Font('Segoe UI Emoji', 22, [System.Drawing.GraphicsUnit]::Pixel)
                $fmt = New-Object System.Drawing.StringFormat
                $fmt.Alignment = [System.Drawing.StringAlignment]::Center
                $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
                $g.DrawString($emoji, $font, [System.Drawing.Brushes]::Black,
                              (New-Object System.Drawing.RectangleF(0, 0, 32, 32)), $fmt)
                $etwas = $true
            }
        }

        # 2. rectangle tiles (in document order, so the overlap is right)
        if (-not $etwas) {
            $sx = 32.0 / $vw; $sy = 32.0 / $vh
            foreach ($r in [regex]::Matches($svg, '<rect\b[^>]*>')) {
                $hol = { param($a) $mm = [regex]::Match($r.Value, $a + '\s*=\s*["'']([^"'']+)["'']'); if ($mm.Success) { $mm.Groups[1].Value } else { $null } }
                $fw = (& $hol 'width'); $fh = (& $hol 'height'); $fill = (& $hol 'fill')
                if (-not $fw -or -not $fh) { continue }
                if (-not $fill -or $fill -eq 'none') { continue }
                try { $c = [System.Drawing.ColorTranslator]::FromHtml($fill) } catch { continue }
                $fx = [double](& $hol 'x'); $fy = [double](& $hol 'y')
                $br = New-Object System.Drawing.SolidBrush($c)
                $g.FillRectangle($br, [float]($fx * $sx), [float]($fy * $sy),
                                 [float]([double]$fw * $sx), [float]([double]$fh * $sy))
                $br.Dispose(); $etwas = $true
            }
        }
        $g.Dispose()
        if (-not $etwas) { $bmp.Dispose(); return $null }
        $sym = [System.Drawing.Icon]::FromHandle($bmp.GetHicon()).Clone()
        $bmp.Dispose()
        return $sym
    } catch { return $null }
}

function global:QA-BildAlsSymbol([byte[]]$daten) {
    # GDI+ cannot render SVG - our own pages (cockpit, logs) use emoji or
    # pixel SVG. Check first, otherwise it falls through silently and the
    # tile stays without an icon. (Tim, 2026-09-08)
    try {
        $kopf = [Text.Encoding]::UTF8.GetString($daten, 0, [Math]::Min(300, $daten.Length))
        if ($kopf -match '(?i)<svg') {
            $s = QA-SvgSymbol ([Text.Encoding]::UTF8.GetString($daten))
            if ($s) { return $s }
        }
    } catch { }
    # ICO directly, everything else (PNG, GIF) through a bitmap.
    #
    # ⚠️ The Icon constructor SUCCEEDS even when the ICO contains a
    #    PNG -- only the later ToBitmap() throws "The requested range
    #    extends past the end of the array". The fallback below therefore
    #    never kicked in, and the icon was silently missing from the list
    #    (trello.com is such a case: a single 256x256 PNG inside an ICO
    #    shell). So we draw a test here once instead of trusting the
    #    constructor.
    $strom = New-Object IO.MemoryStream(, $daten)
    try {
        $versuch = New-Object System.Drawing.Icon($strom)
        $probe = $versuch.ToBitmap()
        $probe.Dispose()
        return $versuch
    } catch {
        # Two routes, in this order:
        #   1. the bytes are an image themselves (PNG, GIF) -> read directly
        #   2. it is an ICO with a PNG inside -> cut the largest image out
        #      of the container and read that. trello.com has a single
        #      256x256 PNG in the shell; without the extraction both routes
        #      fail and the icon is missing without comment.
        foreach ($rohdaten in @($daten, (QA-PngAusIco $daten))) {
            if (-not $rohdaten) { continue }
            try {
                $s2 = New-Object IO.MemoryStream(, $rohdaten)
                $bild = [System.Drawing.Image]::FromStream($s2)
                $klein = New-Object System.Drawing.Bitmap($bild, 32, 32)
                $griff = $klein.GetHicon()
                $symbol = [System.Drawing.Icon]::FromHandle($griff).Clone()
                $bild.Dispose(); $klein.Dispose()
                return $symbol
            } catch { }
        }
        return $null
    }
}

function global:QA-Favicon($ziel) {
    try { $adresse = [Uri]$ziel } catch { return $null }
    if (-not $adresse.Host) { return $null }

    $ordner = QA-FaviconOrdner
    # ⚠️ The port belongs in the name: on the NAS, DSM, Grafana,
    #    Node-RED and the cockpit all live at the same address and would
    #    otherwise overwrite each other's icon.
    $name   = (($adresse.Host + '_' + $adresse.Port) -replace '[^A-Za-z0-9\.\-]', '_')
    $bild   = Join-Path $ordner ($name + '.ico')
    $nichts = Join-Path $ordner ($name + '.keins')

    if (Test-Path -LiteralPath $bild) {
        # Straight through QA-BildAlsSymbol: the drawability check lives
        # there. Building an icon from the file and returning it unchecked
        # was exactly the route on which the Trello icon failed again and
        # again.
        try {
            $aus_datei = QA-BildAlsSymbol ([IO.File]::ReadAllBytes($bild))
            if ($aus_datei) { return $aus_datei }
        } catch { }
    }
    # DA-20260914-093332250-030d: the record used to last a flat 14 days.
    # On 09-14 that meant: at 08:05 the network map's icon failed, at
    # 08:06:57 the service was changed and started serving one -- and DA
    # would not have looked again until 09-28. The record was older than
    # the fact it described.
    #
    # Two safeguards against that:
    #   a) if quickaccess.txt has been touched since, every record is void
    #      -- a newly entered target has never worked, and an earlier
    #      failure does not belong to it.
    #   b) the interval only grows with the number of failures: one day,
    #      and the full 14 only from the third time on. That way a
    #      hopeless case still costs no time, while a freshly built icon
    #      is found the next day.
    if (Test-Path -LiteralPath $nichts) {
        $vermerk = Get-Item -LiteralPath $nichts
        $verfallen = $false

        $liste = Join-Path (Split-Path -Parent $ordner) 'quickaccess.txt'
        if (Test-Path -LiteralPath $liste) {
            if ((Get-Item -LiteralPath $liste).LastWriteTime -gt $vermerk.LastWriteTime) {
                $verfallen = $true
            }
        }

        if ($verfallen) {
            Remove-Item -LiteralPath $nichts -Force -ErrorAction SilentlyContinue
            QA-Log ('icon note expired (list is newer): ' + $name)
        } else {
            $wieoft = 0
            try {
                $roh = (Get-Content -LiteralPath $nichts -Raw -ErrorAction Stop)
                if ($roh) { $wieoft = [int]($roh.Trim()) }
            } catch { $wieoft = 0 }
            $frist = if ($wieoft -ge 3) { 14.0 } else { 1.0 }
            $alter = (Get-Date) - $vermerk.LastWriteTime
            if ($alter.TotalDays -lt $frist) { return $null }
        }
    }

    # ⚠️ Without this line PowerShell 5.1 still speaks TLS 1.0 - modern
    #    sites such as trello.com drop the connection immediately.
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
    } catch { }

    $versuche = @(
        ('{0}://{1}/favicon.ico' -f $adresse.Scheme, $adresse.Authority)
    )
    # Read the declared icon from the home page, in case it is not at the
    # default location.
    try {
        $seite = Invoke-WebRequest -Uri ('{0}://{1}/' -f $adresse.Scheme, $adresse.Authority) `
                                   -UseBasicParsing -TimeoutSec 4 -ErrorAction Stop
        foreach ($m in [regex]::Matches([string]$seite.Content,
                       '<link[^>]+rel\s*=\s*["''][^"'']*icon[^"'']*["''][^>]*>')) {
            # 🔴 Tim, 09-08: do not use [^"']+ - a data: URI contains the
            #    OTHER kind of quote internally (svg with xmlns='...'), and
            #    the character class stops there. The emoji SVG of the HM
            #    log / KODI was truncated to "data:image/svg+xml,<svg
            #    xmlns=" that way. So: remember the opening character and
            #    read up to the matching one via back-reference \1.
            $h = [regex]::Match($m.Value, 'href\s*=\s*(["''])(.*?)\1')
            if ($h.Success) {
                $u = $h.Groups[2].Value
                # 🔴 Tim, 09-08: the cockpit and our own log pages put
                #    their favicon straight into the <link> as
                #    "data:image/png;base64,...". That is NOT a path -
                #    the elseif branch below used to prefix it with
                #    "http://host:port/" and destroy the URL, which is why
                #    the icon was missing. data: is now left alone.
                if ($u -match '^data:')   { }
                elseif ($u -match '^//')  { $u = $adresse.Scheme + ':' + $u }
                elseif ($u -match '^/')   { $u = ('{0}://{1}{2}' -f $adresse.Scheme, $adresse.Authority, $u) }
                elseif ($u -notmatch '^https?://') { $u = ('{0}://{1}/{2}' -f $adresse.Scheme, $adresse.Authority, $u) }
                $versuche += $u
            }
        }
    } catch { }

    foreach ($u in $versuche) {
        try {
            if ($u -match '^data:') {
                # data:[<type>][;base64],<payload> - decode directly, no network.
                $komma = $u.IndexOf(',')
                if ($komma -lt 0) { continue }
                $kopf = $u.Substring(5, $komma - 5)
                $roh  = $u.Substring($komma + 1)
                if ($kopf -match 'base64') {
                    $daten = [Convert]::FromBase64String($roh.Trim())
                } else {
                    $daten = [Text.Encoding]::UTF8.GetBytes([Uri]::UnescapeDataString($roh))
                }
            } else {
                $antwort = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 4 -ErrorAction Stop
                $daten = $antwort.Content
                # 🔴 A favicon served as text (e.g. /favicon.svg with
                #    Content-Type image/svg+xml) arrives from IWR as a
                #    string, not as a byte array - it used to fall through
                #    the check below and the JD processor icon was missing.
                #    Convert it to bytes.
                if ($daten -is [string]) { $daten = [Text.Encoding]::UTF8.GetBytes($daten) }
            }
            if ($daten -isnot [byte[]]) { continue }
            if ($daten.Length -lt 32) { continue }
            $symbol = QA-BildAlsSymbol $daten
            if ($symbol) {
                [IO.File]::WriteAllBytes($bild, $daten)
                if (Test-Path -LiteralPath $nichts) { Remove-Item -LiteralPath $nichts -Force }
                QA-Log ('site icon fetched: ' + $adresse.Host)
                return $symbol
            }
        } catch { }
    }

    # DA-20260914-093332250-030d: the record now counts how often it has
    # already failed -- the interval above depends on that. The file used
    # to be empty and every failure looked like the first.
    $bisher = 0
    try {
        if (Test-Path -LiteralPath $nichts) {
            $r = (Get-Content -LiteralPath $nichts -Raw -ErrorAction Stop)
            if ($r) { $bisher = [int]($r.Trim()) }
        }
    } catch { $bisher = 0 }
    Set-Content -LiteralPath $nichts -Value ([string]($bisher + 1)) -Encoding ASCII
    return $null
}


function global:QA-Symbol($ziel) {
    if ($global:QA.Symbole.ContainsKey($ziel)) { return $global:QA.Symbole[$ziel] }
    $s = $null
    try {
        if (QA-IstLink $ziel) {
            # The site's own icon first - so Trello looks like Trello and
            # not like Edge.
            $s = QA-Favicon $ziel
            # 🔴 ExtractAssociatedIcon on shell32.dll always returns icon
            #    NUMBER 0 - a blank sheet that says nothing. The default
            #    browser's icon is more telling: exactly the program that
            #    opens on a click.
            if (-not $s) { $s = QA-BrowserSymbol }
            if (-not $s) {
                # Globe from shell32.dll, index 14
                $s = QA-SymbolMitIndex (Join-Path $env:SystemRoot 'System32\shell32.dll') 14
            }
            if (-not $s) {
                $s = [System.Drawing.Icon]::ExtractAssociatedIcon("$env:SystemRoot\system32\shell32.dll")
            }
        } elseif (Test-Path -LiteralPath $ziel) {
            if ((Get-Item -LiteralPath $ziel).PSIsContainer) {
                $s = [System.Drawing.SystemIcons]::WinLogo
            } elseif ($ziel -like '*.lnk') {
                # 🔴 For a shortcut, ExtractAssociatedIcon only returns the
                #    generic shortcut icon. What is meaningful is the stored
                #    IconLocation, otherwise the target's own icon.
                $w = New-Object -ComObject WScript.Shell
                $v = $w.CreateShortcut($ziel)
                $quelle = $null; $index = 0
                if ($v.IconLocation) {
                    $teile = $v.IconLocation -split ','
                    $quelle = $teile[0].Trim('"')
                    if ($teile.Count -gt 1) { [int]::TryParse($teile[1].Trim(), [ref]$index) | Out-Null }
                    # "shell32.dll" appears without a path - look in the
                    # system directory.
                    # 🔴 Join-Path puts the separator only BEFORE the
                    #    argument, not inside it: 'System32' +
                    #    'shell32.dll' used to give "System32shell32.dll"
                    #    and therefore never matched.
                    if ($quelle -and -not (Test-Path -LiteralPath $quelle)) {
                        $imSystem = Join-Path (Join-Path $env:SystemRoot 'System32') $quelle
                        if (Test-Path -LiteralPath $imSystem) { $quelle = $imSystem } else { $quelle = $null }
                    }
                }
                if ($quelle) { $s = QA-SymbolMitIndex $quelle $index }
                if (-not $s -and $v.TargetPath -and (Test-Path -LiteralPath $v.TargetPath)) {
                    $s = [System.Drawing.Icon]::ExtractAssociatedIcon($v.TargetPath)
                }
            } else {
                $s = [System.Drawing.Icon]::ExtractAssociatedIcon($ziel)
            }
        }
    } catch { }
    if (-not $s) { $s = [System.Drawing.SystemIcons]::Application }
    $global:QA.Symbole[$ziel] = $s
    return $s
}

. "$PSScriptRoot\QA-Stil.ps1"   # DA-20260913-163439041-83d7: eine Stilquelle
$global:QA.FarbeNormal = $FARBE_HG
$global:QA.FarbeHover  = $FARBE_HOVER

$overlay = New-Object System.Windows.Forms.Form
$overlay.FormBorderStyle = 'None'
$overlay.ShowInTaskbar = $false
$overlay.TopMost = $true
$overlay.StartPosition = 'Manual'
$overlay.BackColor = $FARBE_HG
$overlay.Padding = New-Object System.Windows.Forms.Padding(1)
$global:QA.Overlay = $overlay

# Three zones stacked: tabs (top), entries (middle, scrolls), footer
# (bottom). Tim, 09-07: "more by groups ... as tabs ... no clicks" - the
# groups become tabs that you only hover over.
$wrap = New-Object System.Windows.Forms.TableLayoutPanel
$wrap.Dock = 'Fill'
$wrap.ColumnCount = 1
$wrap.RowCount = 3
$wrap.BackColor = $FARBE_HG
[void]$wrap.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$wrap.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$wrap.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$overlay.Controls.Add($wrap)

$reiter = New-Object System.Windows.Forms.FlowLayoutPanel
$reiter.FlowDirection = 'LeftToRight'
$reiter.WrapContents = $true
$reiter.AutoSize = $true
$reiter.AutoSizeMode = 'GrowAndShrink'
$reiter.Dock = 'Fill'
$reiter.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 28)
$reiter.Padding = New-Object System.Windows.Forms.Padding(4, 4, 4, 2)
$wrap.Controls.Add($reiter, 0, 0)
$global:QA.Reiter = $reiter

# Intent delay for the tabs (DA-20260913-101000444-35d3).
# 250 ms: below 150 fast mouse movements slip through, above 350 the
# switching feels sluggish. Anyone who wants to change the value changes
# exactly this one number.
$global:QA.ReiterUhr = New-Object System.Windows.Forms.Timer
$global:QA.ReiterUhr.Interval = 250
$global:QA.ReiterUhr.Add_Tick({
    $global:QA.ReiterUhr.Stop()
    if ($global:QA.ReiterZiel) { QA-ZeigeGruppe $global:QA.ReiterZiel }
})

$inhalt = New-Object System.Windows.Forms.FlowLayoutPanel
$inhalt.FlowDirection = 'TopDown'
$inhalt.WrapContents = $false
$inhalt.AutoScroll = $true
$inhalt.Dock = 'Fill'
$inhalt.BackColor = $FARBE_HG
$wrap.Controls.Add($inhalt, 0, 1)
$global:QA.Inhalt = $inhalt

$fuss = New-Object System.Windows.Forms.FlowLayoutPanel
$fuss.FlowDirection = 'LeftToRight'
$fuss.WrapContents = $false
$fuss.AutoSize = $true
$fuss.Dock = 'Fill'
$fuss.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 28)
$fuss.Padding = New-Object System.Windows.Forms.Padding(6, 4, 6, 4)
$wrap.Controls.Add($fuss, 0, 2)
$global:QA.Fuss = $fuss

$BREITE = 360
$global:QA.Breite = $BREITE
# Wrap the tabs at the overlay width so PreferredSize is correct.
$reiter.MaximumSize = New-Object System.Drawing.Size(($BREITE - 6), 0)

# A single set of handlers for all rows - the target lives in .Tag.
$global:QA_Klick = {
    $ziel = $this.Tag
    if (-not $ziel -and $this.Parent) { $ziel = $this.Parent.Tag }
    $global:QA.Overlay.Hide()
    QA-Oeffne $ziel
}
$global:QA_Rein = {
    $panel = if ($this -is [System.Windows.Forms.Panel]) { $this } else { $this.Parent }
    if (-not $panel) { return }
    # 🔴 RESET ALL OTHER ROWS FIRST. MouseLeave does not fire reliably
    #    when the pointer moves from one label straight into the next row -
    #    several rows would then stay highlighted.
    foreach ($c in $global:QA.Inhalt.Controls) {
        if ($c -is [System.Windows.Forms.Panel] -and $c -ne $panel) {
            if ($c.BackColor -ne $global:QA.FarbeNormal) {
                $c.BackColor = $global:QA.FarbeNormal
                foreach ($k in $c.Controls) { $k.BackColor = $global:QA.FarbeNormal }
            }
        }
    }
    $panel.BackColor = $global:QA.FarbeHover
    foreach ($k in $panel.Controls) { $k.BackColor = $global:QA.FarbeHover }
}
$global:QA_Raus = {
    $panel = if ($this -is [System.Windows.Forms.Panel]) { $this } else { $this.Parent }
    if (-not $panel) { return }
    # Only reset when the pointer has really left the row - otherwise it
    # flickers when moving between icon and label.
    $ecke = $panel.PointToClient([System.Windows.Forms.Cursor]::Position)
    if ($ecke.X -lt 0 -or $ecke.Y -lt 0 -or
        $ecke.X -ge $panel.Width -or $ecke.Y -ge $panel.Height) {
        $panel.BackColor = $global:QA.FarbeNormal
        foreach ($k in $panel.Controls) { $k.BackColor = $global:QA.FarbeNormal }
    }
}

function global:QA-BaueZeile($e) {
    $fehlt = (-not (QA-IstLink $e.Ziel)) -and (-not (Test-Path -LiteralPath $e.Ziel))
    $breite = $global:QA.Breite

    $zeile = New-Object System.Windows.Forms.Panel
    $zeile.Size = New-Object System.Drawing.Size(($breite - 34), 30)
    $zeile.BackColor = $global:QA.FarbeNormal
    $zeile.Margin = New-Object System.Windows.Forms.Padding(6, 1, 6, 1)
    $zeile.Cursor = [System.Windows.Forms.Cursors]::Hand
    $zeile.Tag = $e.Ziel

    $bild = New-Object System.Windows.Forms.PictureBox
    $bild.Size = New-Object System.Drawing.Size(18, 18)
    $bild.Location = New-Object System.Drawing.Point(8, 6)
    $bild.SizeMode = 'StretchImage'
    # An explicitly chosen icon (| source,index) beats the favicon or the
    # default icon - Tim: "favicon ... when none is overridden".
    $sym = $null
    if ($e.Symbol) {
        $teile = $e.Symbol -split ','
        $quelle = $teile[0].Trim('"').Trim()
        $index = 0
        if ($teile.Count -gt 1) { [int]::TryParse($teile[1].Trim(), [ref]$index) | Out-Null }
        if ($quelle -and -not (Test-Path -LiteralPath $quelle)) {
            $imSystem = Join-Path $env:SystemRoot ('System32\' + $quelle)
            if (Test-Path -LiteralPath $imSystem) { $quelle = $imSystem }
        }
        if ($quelle -and (Test-Path -LiteralPath $quelle)) { $sym = QA-SymbolMitIndex $quelle $index }
    }
    if (-not $sym) { $sym = QA-Symbol $e.Ziel }
    if ($sym) {
        try { $bild.Image = $sym.ToBitmap() }
        catch { QA-Log ('icon cannot be shown (' + $e.Name + '): ' + $_.Exception.Message) }
    } else {
        QA-Log ('no icon for ' + $e.Name + ' -> ' + $e.Ziel)
    }
    $bild.Tag = $e.Ziel
    $bild.Cursor = [System.Windows.Forms.Cursors]::Hand
    $zeile.Controls.Add($bild)

    $text = New-Object System.Windows.Forms.Label
    $text.Text = $e.Name
    # Show & literally - otherwise WinForms reads it as an access key
    $text.UseMnemonic = $false
    $text.ForeColor = if ($fehlt) { $global:FARBE_FEHLT }
                      else { $global:FARBE_TEXT }
    $text.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $text.AutoSize = $false
    $text.Size = New-Object System.Drawing.Size(($breite - 62), 30)
    $text.Location = New-Object System.Drawing.Point(34, 0)
    $text.TextAlign = 'MiddleLeft'
    $text.Tag = $e.Ziel
    $text.Cursor = [System.Windows.Forms.Cursors]::Hand
    $zeile.Controls.Add($text)

    $hinweis = New-Object System.Windows.Forms.ToolTip
    $hinweis.SetToolTip($zeile, $e.Ziel)
    $hinweis.SetToolTip($text, $e.Ziel)

    foreach ($c in @($zeile, $text, $bild)) {
        $c.Add_Click($global:QA_Klick)
        $c.Add_MouseEnter($global:QA_Rein)
        $c.Add_MouseLeave($global:QA_Raus)
    }
    return $zeile
}

function global:QA-ZeigeGruppe($name) {
    $global:QA.AktiveGruppe = $name
    $inhalt = $global:QA.Inhalt
    $inhalt.SuspendLayout()
    $inhalt.Controls.Clear()
    $hoehe = 8
    $liste = $global:QA.NachGruppe[$name]
    if ($liste) {
        foreach ($e in $liste) {
            $inhalt.Controls.Add((QA-BaueZeile $e))
            $hoehe += 32
        }
    }
    $inhalt.ResumeLayout()

    # Highlight the active tab
    foreach ($t in $global:QA.Reiter.Controls) {
        if ($t.Text -eq $name) {
            $t.BackColor = $global:QA.FarbeHover
            $t.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 255)
        } else {
            $t.BackColor = $global:FARBE_FELD
            $t.ForeColor = [System.Drawing.Color]::FromArgb(185, 185, 195)
        }
    }

}

function global:QA-Version {
    # DA-20260913-222957620-81a8: the number is produced by the PACKAGE
    # BUILD and lives in version.txt. If the file is missing, DA is running
    # from the working folder -- then it is not a built release, and that
    # should be visible instead of inventing a number.
    $v = Join-Path $global:QA.Basis 'version.txt'
    if (Test-Path -LiteralPath $v) {
        $z = (Get-Content $v -Encoding UTF8 -TotalCount 1).Trim()
        if ($z) { return $z }
    }
    $ps1 = Join-Path $global:QA.Basis 'QuickAccess.ps1'
    if (Test-Path -LiteralPath $ps1) {
        return 'unreleased (' +
               (Get-Item -LiteralPath $ps1).LastWriteTime.ToString('yyyy-MM-dd') + ')'
    }
    return 'unknown'
}

function global:QA-ZeigeUeber {
    # DA-20260913-144056185-c031. A MessageBox on purpose: it is the only
    # window that needs no message loop of its own and does not block the
    # tray loop.
    #
    # 🔴 It stays LIGHT. WinForms cannot colour system dialogs
    # (DA-20260913-163439041-83d7) -- that is the library's limit, not a
    # forgotten spot.
    $global:QA.Overlay.Hide()
    $text = @"
Donkey's Apprentice
Fassung $(QA-Version)

Eselchen Labs - MIT-Lizenz
github.com/eselchenlabs/donkeys-apprentice

Der volle Lizenztext liegt als LICENSE im Programmordner.
"@
    QA-Log 'About window opened'
    [System.Windows.Forms.MessageBox]::Show(
        $text, "About Donkey's Apprentice", 'OK', 'Information') | Out-Null
}

# DA-20260917-174940488-ae95: the overlay closes as soon as the mouse
# leaves it -- anyone wanting to read something or copy an address loses
# it in the process. Pinned, it stays open.
#
# No border, no title bar: a FormBorderStyle on the overlay turns the
# popup into a window with an entirely different feel. A button in the
# existing footer is enough.
function global:QA-ZeichneAnheften {
    $pin = $global:QA.PinKnopf
    if (-not $pin) { return }
    if ($global:QA.Angeheftet) {
        $pin.Text = 'Pinned'
        $pin.ForeColor = $global:FARBE_TEXT
    } else {
        $pin.Text = 'Pin'
        $pin.ForeColor = $global:FARBE_GRUPPE
    }
}

function global:QA-BaueFuss {
    $fuss = $global:QA.Fuss
    $fuss.Controls.Clear()

    $pin = New-Object System.Windows.Forms.Label
    $pin.UseMnemonic = $false
    $pin.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $pin.AutoSize = $true
    $pin.Margin = New-Object System.Windows.Forms.Padding(0, 4, 16, 4)
    $pin.Cursor = [System.Windows.Forms.Cursors]::Hand
    $pin.Add_Click({
        $global:QA.Angeheftet = -not $global:QA.Angeheftet
        QA-ZeichneAnheften
        # Unpinning is not closing: the watcher takes over again as soon
        # as the mouse leaves the frame. The counter starts at 0 so an old
        # value does not strike immediately.
        $global:QA.Draussen = 0
    })
    $pin.Add_MouseEnter({ $this.ForeColor = $global:FARBE_TEXT })
    # Do not hard-reset to FARBE_GRUPPE -- while pinned the button is
    # light, and a pointer brushing over it must not clear that.
    $pin.Add_MouseLeave({ QA-ZeichneAnheften })
    [void]$fuss.Controls.Add($pin)
    $global:QA.PinKnopf = $pin
    QA-ZeichneAnheften

    foreach ($paar in @(
        @('Manage', {
            # The management window as its own process (otherwise the
            # modal window blocks the tray icon's message loop). Not with
            # -WindowStyle Hidden - the wscript launcher only hides the
            # console, not the window.
            $global:QA.Overlay.Hide()
            Start-Process wscript.exe -ArgumentList (
                '"' + (Join-Path $global:QA.Basis 'QuickAccessAdmin.vbs') + '"')
        }),
        @('Autostart', { QA-SchalteAutostart }),
        # DA-20260913-144056185-c031: the attribution must be reachable AT
        # ANY TIME. A balloon tip disappears again, a menu item does not.
        # No version number -- DA has none today, and introducing one is a
        # separate matter.
        @('About',     { QA-ZeigeUeber }),
        @('Quit',   { $global:QA.Tray.Visible = $false
                         [System.Windows.Forms.Application]::Exit() }))) {
        $knopf = New-Object System.Windows.Forms.Label
        $knopf.Text = $paar[0]
        $knopf.UseMnemonic = $false
        $knopf.ForeColor = $global:FARBE_GRUPPE
        $knopf.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $knopf.AutoSize = $true
        $knopf.Margin = New-Object System.Windows.Forms.Padding(0, 4, 16, 4)
        $knopf.Cursor = [System.Windows.Forms.Cursors]::Hand
        $knopf.Add_Click($paar[1])
        $knopf.Add_MouseEnter({ $this.ForeColor = $global:FARBE_TEXT })
        $knopf.Add_MouseLeave({ $this.ForeColor = $global:FARBE_GRUPPE })
        [void]$fuss.Controls.Add($knopf)
    }
}

function global:QA-BaueOverlay {
    # Order entries by group; the file's own order is preserved.
    $nach = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($e in (QA-LiesKonfig)) {
        $g = if ($e.Gruppe) { $e.Gruppe } else { 'Ungrouped' }
        if (-not $nach.Contains($g)) { $nach[$g] = New-Object System.Collections.ArrayList }
        [void]$nach[$g].Add($e)
    }
    $global:QA.NachGruppe = $nach
    $gruppen = @($nach.Keys)

    # Build the tabs (groups) - hovering switches, no click needed.
    $reiter = $global:QA.Reiter
    $reiter.SuspendLayout()
    $reiter.Controls.Clear()
    foreach ($g in $gruppen) {
        $tab = New-Object System.Windows.Forms.Label
        $tab.Text = $g
        # Groups such as "Heating & Energy" should show the & rather than
        # read it as an access key - otherwise the comparison in
        # QA-ZeigeGruppe no longer matches either and the active tab stays
        # pale.
        $tab.UseMnemonic = $false
        $tab.AutoSize = $true
        $tab.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
        $tab.ForeColor = [System.Drawing.Color]::FromArgb(185, 185, 195)
        $tab.BackColor = $global:FARBE_FELD
        $tab.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
        $tab.Margin = New-Object System.Windows.Forms.Padding(2, 2, 2, 2)
        $tab.Cursor = [System.Windows.Forms.Cursors]::Hand
        # 🔴 DO NOT switch immediately. With six groups the tabs wrap
        # onto two rows (WrapContents, 354 px). The path from a tab in the
        # first row down to the content then inevitably crosses the second
        # row - and every crossing used to switch the group. You reliably
        # landed in the content of the group you crossed last.
        #
        # Whoever wants to choose stops moving; whoever is just passing
        # through is out again in 40-80 ms and MouseLeave stops the clock.
        # A CLICK still switches at once - the delay is a filter, not a
        # brake.
        $tab.Add_MouseEnter({
            $global:QA.ReiterZiel = $this.Text
            $global:QA.ReiterUhr.Stop()
            $global:QA.ReiterUhr.Start()
        })
        $tab.Add_MouseLeave({ $global:QA.ReiterUhr.Stop() })
        $tab.Add_Click({
            $global:QA.ReiterUhr.Stop()
            QA-ZeigeGruppe $this.Text
        })
        [void]$reiter.Controls.Add($tab)
    }
    $reiter.ResumeLayout()

    QA-BaueFuss

    # Fix the height ONCE from the largest group - that way the overlay
    # does not jump and scroll when switching tabs (it was "unusable, too
    # many scrollbars").
    $maxItems = 0
    foreach ($k in $nach.Keys) { if ($nach[$k].Count -gt $maxItems) { $maxItems = $nach[$k].Count } }
    $reiterH = $reiter.PreferredSize.Height
    $fussH = $global:QA.Fuss.PreferredSize.Height
    $itemsH = $maxItems * 32 + 10
    $max = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 80
    $gesamt = $reiterH + $itemsH + $fussH + 16
    if ($gesamt -gt $max) { $gesamt = $max }
    if ($gesamt -lt 90) { $gesamt = 90 }
    $global:QA.Overlay.Size = New-Object System.Drawing.Size($global:QA.Breite, $gesamt)

    # Active group: the remembered one, otherwise the first.
    $aktiv = $global:QA.AktiveGruppe
    if (-not $aktiv -or -not ($gruppen -contains $aktiv)) {
        $aktiv = if ($gruppen.Count) { $gruppen[0] } else { $null }
    }
    if ($aktiv) { QA-ZeigeGruppe $aktiv }
}

function global:QA-Zeige {
    # Every opening starts unpinned. A state that keeps a window open
    # permanently must not survive a call -- otherwise the overlay ends up
    # sitting there and nobody knows why.
    $global:QA.Angeheftet = $false
    QA-BaueOverlay
    $ov = $global:QA.Overlay
    $flaeche = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $maus = [System.Windows.Forms.Cursor]::Position
    $x = [Math]::Min($maus.X - 40, $flaeche.Right - $ov.Width - 8)
    if ($x -lt $flaeche.Left + 8) { $x = $flaeche.Left + 8 }
    $ov.Location = New-Object System.Drawing.Point($x, ($flaeche.Bottom - $ov.Height - 8))
    $ov.Show()
    $ov.BringToFront()
}

$global:QA.Autostart = Join-Path ([Environment]::GetFolderPath('Startup')) 'QuickAccess.lnk'
function global:QA-SchalteAutostart {
    if (Test-Path $global:QA.Autostart) {
        Remove-Item $global:QA.Autostart -Force
        $global:QA.Tray.ShowBalloonTip(1500, "Donkey's Apprentice", 'Autostart aus.', 'Info')
    } else {
        $w = New-Object -ComObject WScript.Shell
        $v = $w.CreateShortcut($global:QA.Autostart)
        # Via wscript, otherwise a console window flashes at every logon.
        $v.TargetPath = 'wscript.exe'
        $v.Arguments = '"' + (Join-Path $global:QA.Basis 'QuickAccess.vbs') + '"'
        $v.WorkingDirectory = $global:QA.Basis
        $v.Save()
        $global:QA.Tray.ShowBalloonTip(1500, "Donkey's Apprentice", 'Startet künftig mit Windows.', 'Info')
    }
}

# ---------------------------------------------------------------------
#  Tray icon - the little donkey, if present
# ---------------------------------------------------------------------
$tray = New-Object System.Windows.Forms.NotifyIcon
$eigenes = Join-Path $global:QA.Basis 'esel.ico'
if (Test-Path $eigenes) {
    $tray.Icon = New-Object System.Drawing.Icon($eigenes)
} else {
    $excel = @('C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE',
               'C:\Program Files (x86)\Microsoft Office\root\Office16\EXCEL.EXE') |
             Where-Object { Test-Path $_ } | Select-Object -First 1
    $tray.Icon = if ($excel) { [System.Drawing.Icon]::ExtractAssociatedIcon($excel) }
                 else { [System.Drawing.SystemIcons]::Application }
}
$tray.Text = "Donkey's Apprentice - just hover"
$tray.Visible = $true
$global:QA.Tray = $tray

$tray.Add_MouseMove({ if (-not $global:QA.Overlay.Visible) { QA-Zeige } })
$tray.Add_MouseClick({
    if ($global:QA.Overlay.Visible) {
        # While pinned: a click on the donkey unpins and closes. That
        # always leaves a way back, even without hitting the button.
        # ⚠ Deliberately NOT on MouseMove -- the overlay sits close to
        # the notification area, and every path of the mouse towards it
        # would tear the overlay away.
        if ($global:QA.Angeheftet) {
            $global:QA.Angeheftet = $false
            QA-ZeichneAnheften
            $global:QA.Overlay.Hide()
        }
        return
    }
    QA-Zeige
})

# ⚠️ Do not close via Deactivate: the overlay never takes focus at all,
#    otherwise you would have to click after all. Check the mouse position
#    instead, with a grace period for the path from icon to overlay.
$global:QA.Draussen = 0
$wache = New-Object System.Windows.Forms.Timer
$wache.Interval = 250
$wache.Add_Tick({
    $ov = $global:QA.Overlay
    if (-not $ov.Visible) { $global:QA.Draussen = 0; return }
    # While pinned: the watcher does not count.
    # DA-20260917-174940488-ae95
    if ($global:QA.Angeheftet) { $global:QA.Draussen = 0; return }
    $maus = [System.Windows.Forms.Cursor]::Position
    $rahmen = New-Object System.Drawing.Rectangle(
        ($ov.Left - 12), ($ov.Top - 12), ($ov.Width + 24), ($ov.Height + 40))
    if ($rahmen.Contains($maus)) { $global:QA.Draussen = 0 }
    else {
        $global:QA.Draussen++
        if ($global:QA.Draussen -ge 5) { $ov.Hide(); $global:QA.Draussen = 0 }
    }
})
$wache.Start()

# Build once at startup (without showing it) - then the log already says
# whether the icons arrive, without anyone having had to open the
# overlay.
QA-Log '--- build at startup ---'
try {
    QA-BaueOverlay
    $mitBild = 0; $ohneBild = 0
    foreach ($c in $global:QA.Inhalt.Controls) {
        if ($c -is [System.Windows.Forms.Panel]) {
            foreach ($k in $c.Controls) {
                if ($k -is [System.Windows.Forms.PictureBox]) {
                    if ($k.Image) { $mitBild++ } else { $ohneBild++ }
                }
            }
        }
    }
    QA-Log ("rows with icon: $mitBild, without: $ohneBild")
} catch {
    QA-Log ('build failed: ' + $_.Exception.Message)
}

# DA-20260913-144047595-f616: on the VERY FIRST start the balloon says
# where to go next -- an empty window with no hint is the point at which
# most people delete a tool again. After that, the short one.
#
# 🔴 ONE balloon, not two. Two messages in a row are one message too
# many, and the second hides the first.
if ($global:QA.Erstmals) {
    $tray.ShowBalloonTip(7000, "Donkey's Apprentice",
        'Right-click the donkey icon -> "Manage".' + [char]10 +
        'That is where the entries, the examples and the autostart live.', 'Info')
    QA-Log 'first run: balloon tip shown'
} else {
    $tray.ShowBalloonTip(2500, "Donkey's Apprentice",
        'Hover over the icon - the rest happens by itself.', 'Info')
}

[System.Windows.Forms.Application]::Run()
$tray.Dispose()
$sperre.ReleaseMutex()
