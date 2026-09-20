# =====================================================================
#  QuickAccess - Schnellzugriff aus dem Infobereich
#
#  Tim, 03.09.2026: „tray tool aufrufen, öffnet sich mit overlay dann klick
#  excel und schon öffnet file oder sogar nur drüber hovern … max easy",
#  „oder aber auch http links etc.", „zeige dateinamen als namen des
#  shortcuts an", „finde cooles icon e.g. eselchen mit zauberstab".
#
#  Maus über das Symbol -> Overlay klappt auf. Klick auf eine Zeile öffnet
#  Datei, Ordner oder Link. Maus weg -> Overlay schließt von allein.
# =====================================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------------
#  🔴 ZUSTAND GLOBAL HALTEN, NICHT ÜBER $script: IN CLOSURES.
#     Der erste Wurf legte die Klick-Aktion als .GetNewClosure() an und
#     griff darin auf $script:overlay zu. Beim Klick auf eine Zeile kam
#     „Es ist nicht möglich, eine Methode für einen Ausdruck aufzurufen,
#     der den NULL hat" - der Closure sah die Variable nicht mehr, weil er
#     in einer Funktion erzeugt wurde und dort einen eigenen Scope bekam.
#     Jetzt: alles in $global:QA, und das Ziel hängt als .Tag am Control.
# ---------------------------------------------------------------------
$global:QA = @{
    Basis  = Split-Path -Parent $MyInvocation.MyCommand.Path
    Symbole = @{}
    ReiterZiel = $null
}
# 🔴 Programm und Arbeitsdaten trennen (DA-20260913-144004296-42e6).
#    Ein Programm, das in sein eigenes Verzeichnis schreibt, scheitert,
#    sobald es unter C:\Program Files liegt -- dort darf ein normaler
#    Benutzer nicht schreiben. $QA.Basis ist ab hier NUR noch der Ort des
#    Programms; alles Geschriebene steht unter $QA.Daten.
$global:QA.Daten = Join-Path $env:LOCALAPPDATA 'QuickAccess'
if (-not (Test-Path -LiteralPath $global:QA.Daten)) {
    New-Item -ItemType Directory -Force -Path $global:QA.Daten | Out-Null
}
$global:QA.Konfig = Join-Path $global:QA.Daten 'quickaccess.txt'

# Übernahme älterer Stände: bis zum 13.09.2026 lag die Liste neben dem
# Skript. Ohne diesen Schritt stünde der Benutzer nach einem Update vor
# einem leeren Fenster.
$qa_alt = Join-Path $global:QA.Basis 'quickaccess.txt'
if ((Test-Path -LiteralPath $qa_alt) -and
    -not (Test-Path -LiteralPath $global:QA.Konfig) -and
    ($qa_alt -ne $global:QA.Konfig)) {
    # Kopieren, nicht verschieben: geht der Umzug schief, ist nichts weg.
    Copy-Item -LiteralPath $qa_alt -Destination $global:QA.Konfig
    # Das Original umbenennen -- sonst liest eine ältere Fassung des
    # Programms weiter die alte Datei, und es gäbe ZWEI Listen, die
    # auseinanderlaufen.
    Rename-Item -LiteralPath $qa_alt -NewName (
        'quickaccess.txt.uebernommen_' + (Get-Date -Format 'yyyyMMdd'))
}

$sperre = New-Object System.Threading.Mutex($false, 'Global\QuickAccessTray')
if (-not $sperre.WaitOne(0, $false)) { return }

# 🔴 ExtractAssociatedIcon KANN KEINEN ICON-INDEX. Verknüpfungen zeigen ihr
#    Symbol aber fast immer als „datei.dll,44" an - ohne Index bekommt man
#    das erste Symbol der Datei, also etwas völlig anderes. ExtractIconEx aus
#    der Shell32 nimmt den Index und liefert genau das Symbol, das auch der
#    Explorer zeigt.
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
            # Kopieren, bevor das Handle freigegeben wird - sonst zeigt das
            # Bild später ins Leere.
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
    # ⚠️ Ausnahmen in WinForms-Ereignissen laufen nirgends auf - ohne
    #    Protokoll steht man bei „passiert nichts" völlig im Dunkeln.
    try {
        $datei = Join-Path $global:QA.Daten 'quickaccess.log'
        Add-Content -Path $datei -Encoding UTF8 -Value (
            (Get-Date).ToString('dd.MM. HH:mm:ss') + '  ' + $text)
    } catch { }
}

function global:QA-Oeffne($ziel) {
    if (-not $ziel) { QA-Log 'Klick ohne Ziel'; return }
    QA-Log ('öffne: ' + $ziel)
    # 🔴 %VARIABLEN% auflösen, BEVOR irgendetwas geprüft wird. Ohne das
    #    scheitert Test-Path an '%USERPROFILE%\Documents' und jeder Eintrag
    #    der mitgelieferten Beispielliste meldet „Nicht gefunden" -- die
    #    Liste MUSS ohne feste Pfade auskommen, sonst trägt sie wieder die
    #    Ziele eines bestimmten Rechners (DA-20260913-143955698-e77e).
    $ziel = [Environment]::ExpandEnvironmentVariables($ziel)
    try {
        # Sonderorte der Shell (Papierkorb, Autostart, Systemsteuerung)
        # sind keine Dateisystempfade -- Test-Path findet sie nie. Der
        # Explorer nimmt sie dagegen unverändert entgegen.
        if ($ziel -like 'shell:*') {
            Start-Process explorer.exe -ArgumentList ('"' + $ziel + '"') -ErrorAction Stop
            QA-Log '  -> Shell-Ort im Explorer'
            return
        }
        if (QA-IstLink $ziel) {
            Start-Process $ziel -ErrorAction Stop
            QA-Log '  -> Link gestartet'
            return
        }
        if (-not (Test-Path -LiteralPath $ziel)) {
            QA-Log '  -> NICHT GEFUNDEN'
            [System.Windows.Forms.MessageBox]::Show(
                "Nicht gefunden:`n$ziel`n`nLiegt das Netzlaufwerk an?",
                "Donkey's Apprentice", 'OK', 'Warning') | Out-Null
            return
        }
        # 🔴 -WorkingDirectory MIT ANGEBEN. Ohne das erbt der neue Prozess
        #    das Arbeitsverzeichnis des Tray-Tools; Excel stolpert dann
        #    über Pfade mit „&" im Namen und öffnet kommentarlos nichts.
        if ((Get-Item -LiteralPath $ziel).PSIsContainer) {
            # 🔴 ORDNER LASSEN SICH NICHT MIT Start-Process -FilePath OEFFNEN.
            #    Windows antwortet mit „Dieser Befehl kann nicht vollständig
            #    ausgeführt werden, da das System nicht alle erforderlichen
            #    Informationen finden kann" - ein Verzeichnis ist eben kein
            #    ausführbares Ziel. Der Explorer nimmt es dagegen anstandslos.
            Start-Process explorer.exe -ArgumentList ('"' + $ziel + '"') -ErrorAction Stop
            QA-Log '  -> Ordner im Explorer'
        } else {
            # ⚠️ -WorkingDirectory mitgeben: ohne das erbt der neue Prozess das
            #    Arbeitsverzeichnis des Tray-Tools, und Office öffnete Dateien
            #    aus Pfaden mit „&" im Namen kommentarlos nicht.
            Start-Process -FilePath $ziel -WorkingDirectory (Split-Path -Parent $ziel) -ErrorAction Stop
            QA-Log '  -> gestartet'
        }
    } catch {
        QA-Log ('  -> FEHLER: ' + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show(
            "Konnte nicht geöffnet werden:`n$ziel`n`n" + $_.Exception.Message,
            "Donkey's Apprentice", 'OK', 'Error') | Out-Null
    }
}

# ---------------------------------------------------------------------
#  Konfiguration
#     [Gruppe]        -> Überschrift
#     Name = Ziel     -> eigener Anzeigename
#     Ziel            -> ohne "=": der DATEINAME wird zum Anzeigenamen
# ---------------------------------------------------------------------
function global:QA-LiesKonfig {
    $pfad = $global:QA.Konfig
    if (-not (Test-Path $pfad)) { return @() }
    $liste = @(); $gruppe = ''
    # ⚠️ Ohne -Encoding UTF8 liest PowerShell 5.1 die Datei als ANSI -
    #    aus „Zählerstände" wird Buchstabensalat.
    foreach ($zeile in (Get-Content $pfad -Encoding UTF8)) {
        $z = $zeile.Trim()
        if ($z -eq '' -or $z.StartsWith('#')) { continue }
        if ($z -match '^\[(.+)\]$') { $gruppe = $Matches[1].Trim(); continue }
        $i = $z.IndexOf('=')
        # Ein Laufwerksbuchstabe („T:\...") ist kein Trenner - deshalb
        # zählt nur ein Gleichheitszeichen, und zwar das erste.
        if ($i -ge 1) {
            $name = $z.Substring(0, $i).Trim()
            $ziel = $z.Substring($i + 1).Trim()
        } else {
            $ziel = $z
            $name = ''
        }
        if (-not $ziel) { continue }
        # Eigenes Symbol, durch " | " vom Ziel getrennt.
        # ⚠️ Der senkrechte Strich ist in Windows-Pfaden verboten, kann also
        #    nie Teil eines Ziels sein - deshalb taugt er als Trenner.
        $symbol = ''
        $strich = $ziel.IndexOf(' | ')
        if ($strich -ge 0) {
            $symbol = $ziel.Substring($strich + 3).Trim()
            $ziel = $ziel.Substring(0, $strich).Trim()
        }
        # Tim, 03.09.2026: „zeige dateinamen als namen des shortcuts an" -
        # der Dateiname gewinnt IMMER; ein Name links vom = bleibt nur
        # Rückfall für Links, die keinen Dateinamen haben.
        if (QA-IstLink $ziel) {
            if (-not $name) { $name = ($ziel -replace '^\w+://', '') }
        } else {
            $dateiname = [IO.Path]::GetFileName($ziel.TrimEnd(''))
            # ⚠️ Bei einer Verknüpfung stört die Endung „.lnk" in der Liste -
            #    sie sagt nichts über den Inhalt, nur über die Bauart.
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
    # 🔴 Hier stand bis zum 13.09.2026 eine Vorlage mit Tims ECHTEN Zielen:
    #    NAS-Adresse, T:-Pfade, Trello-Kennung -- fest im Quelltext, also in
    #    genau der Datei, die mit jedem Paket ausgeliefert wird. Eine
    #    Nutzdatei fällt beim Packen auf; eine Vorlage im Skript nicht.
    #    Jetzt kommt der Erstinhalt aus quickaccess.beispiel.txt, und die
    #    enthält nur Windows-Standardorte und öffentliche Adressen.
    $beispiel = Join-Path $global:QA.Basis 'quickaccess.beispiel.txt'
    if (Test-Path -LiteralPath $beispiel) {
        # Kopieren statt Schreiben: so bleibt die Kodierung erhalten, und es
        # gibt nur EINE Stelle, an der der Erstinhalt steht.
        Copy-Item -LiteralPath $beispiel -Destination $global:QA.Konfig
        QA-Log 'Erststart: quickaccess.txt aus quickaccess.beispiel.txt angelegt'
        # DA-20260913-144047595-f616: dieselbe Bedingung wie oben, kein
        # zweiter Merker -- es gab keine quickaccess.txt, also ist das
        # der allererste Start.
        $global:QA.Erstmals = $true
    } else {
        # Auch ohne Beispieldatei darf das Fenster nicht leer bleiben --
        # ein leeres Fenster ohne Hinweis ist der schlechteste Erststart.
        $notfall = @'
# Donkey's Apprentice -- die Beispieldatei fehlte, deshalb nur das Nötigste.
# Einträge stehen als "Name = Ziel" unter einer Gruppe in eckigen Klammern.

[Start]
Dokumente = %USERPROFILE%\Documents
Downloads = %USERPROFILE%\Downloads
'@
        # ⚠️ UTF-8 MIT Stückliste - sonst kommen Umlaute in Pfaden beim
        #    Zurücklesen falsch an.
        [IO.File]::WriteAllText($global:QA.Konfig, $notfall,
                                (New-Object Text.UTF8Encoding $true))
        QA-Log 'Erststart: quickaccess.beispiel.txt fehlt - Notfallliste angelegt'
        $global:QA.Erstmals = $true
    }
}

# ---------------------------------------------------------------------
#  Symbole - gemerkt, weil ExtractAssociatedIcon über das Netz bummelt
# ---------------------------------------------------------------------
function global:QA-BrowserSymbol {
    # Symbol des Browsers, der wirklich benutzt wird.
    #
    # 🔴 Tim, 07.09.: „zeigt DA Edge-Icon für http-Link, wenn Chrome
    #    Standardbrowser". Windows führt hier für http, https und
    #    .html tatsächlich MSEdgeHTM - Edge hat sich die Zuordnung
    #    zurückgeholt. Wonach der Rechner benutzt wird, sagt die
    #    Registry damit nicht. Also zählt zuerst, welcher Browser
    #    LAEUFT; erst wenn keiner offen ist, gilt die Zuordnung.
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
                    QA-Log ('Browsersymbol vom laufenden ' + $b.Name)
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
                # Der Befehl steht in Anführungszeichen, dahinter Parameter
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
#  Seitensymbol (Favicon)
#
#  Ohne das bekommen ALLE Links dasselbe Browsersymbol - Trello, Grafana
#  und die drei NAS sehen dann gleich aus. Geholt wird einmal pro Host,
#  danach liegt das Bild lokal. Auch ein Fehlschlag wird vermerkt, sonst
#  bremst jeder Aufbau erneut am Netz.
# ---------------------------------------------------------------------
function global:QA-FaviconOrdner {
    $p = Join-Path (Split-Path $global:QA.Konfig -Parent) 'symbole'
    if (-not (Test-Path -LiteralPath $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
    return $p
}

function global:QA-PngAusIco([byte[]]$daten) {
    # Schneidet das größte Einzelbild aus einem ICO-Container heraus.
    # Aufbau: 6 Byte Kopf, dann je 16 Byte Verzeichniseintrag; Länge steht
    # bei +8, Versatz bei +12.
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
    # GDI+ kann kein SVG. Die eigenen Seiten benutzen aber nur zwei simple
    # Spielarten, die sich von Hand zeichnen lassen:
    #   1. Emoji-Favicon: <text ...>🏠</text>  (Cockpit, KODI, HM-Protokoll)
    #   2. Pixel-Icon aus <rect>-Kacheln        (JD-Prozessor /favicon.svg)
    # Echte Pfad-SVG fällt auf $null zurück -> dann greift das Browsersymbol.
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

        # 1. Emoji aus <text>
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

        # 2. Rechteck-Kacheln (in Dokumentreihenfolge, damit Deckung stimmt)
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
    # SVG kann GDI+ nicht rendern - die eigenen Seiten (Cockpit, Protokolle)
    # benutzen Emoji- oder Pixel-SVG. Zuerst prüfen, sonst fällt es stumm
    # durch und die Kachel bleibt ohne Symbol. (Tim, 08.09.2026)
    try {
        $kopf = [Text.Encoding]::UTF8.GetString($daten, 0, [Math]::Min(300, $daten.Length))
        if ($kopf -match '(?i)<svg') {
            $s = QA-SvgSymbol ([Text.Encoding]::UTF8.GetString($daten))
            if ($s) { return $s }
        }
    } catch { }
    # ICO direkt, alles andere (PNG, GIF) über eine Bitmap.
    #
    # ⚠️ Der Icon-Konstruktor GELINGT auch dann, wenn im ICO ein
    #    PNG steckt -- erst das spätere ToBitmap() wirft
    #    „Der angeforderte Bereich geht über das Arrayende hinaus“.
    #    Der Rückfall unten lief deshalb nie an, und das Symbol fehlte
    #    stillschweigend in der Liste (so bei trello.com: ein einzelnes
    #    256x256-PNG in einer ICO-Hülle). Darum wird hier einmal
    #    probegezeichnet, statt dem Konstruktor zu glauben.
    $strom = New-Object IO.MemoryStream(, $daten)
    try {
        $versuch = New-Object System.Drawing.Icon($strom)
        $probe = $versuch.ToBitmap()
        $probe.Dispose()
        return $versuch
    } catch {
        # Zwei Wege, in dieser Reihenfolge:
        #   1. Die Bytes sind selbst ein Bild (PNG, GIF) -> direkt lesen.
        #   2. Es ist ein ICO mit PNG darin -> das größte Bild aus dem
        #      Container ausschneiden und das lesen. Bei trello.com steckt
        #      ein einzelnes 256x256-PNG in der Hülle; ohne das Ausschneiden
        #      scheitern beide Wege und das Symbol fehlt kommentarlos.
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
    # ⚠️ Port gehört in den Namen: auf der NAS liegen DSM, Grafana,
    #    Node-RED und Eselcockpit alle unter derselben Adresse und würden
    #    sich sonst gegenseitig das Symbol überschreiben.
    $name   = (($adresse.Host + '_' + $adresse.Port) -replace '[^A-Za-z0-9\.\-]', '_')
    $bild   = Join-Path $ordner ($name + '.ico')
    $nichts = Join-Path $ordner ($name + '.keins')

    if (Test-Path -LiteralPath $bild) {
        # Direkt über QA-BildAlsSymbol: Die Prüfung auf Zeichenbarkeit
        # steckt dort. Ein Icon aus der Datei zu bauen und es ungeprüft
        # zurückzugeben, war genau der Weg, auf dem das Trello-Symbol
        # jedes Mal aufs Neue durchfiel.
        try {
            $aus_datei = QA-BildAlsSymbol ([IO.File]::ReadAllBytes($bild))
            if ($aus_datei) { return $aus_datei }
        } catch { }
    }
    # DA-20260914-093332250-030d: Der Vermerk galt pauschal 14 Tage.
    # Am 14.09. hiess das: um 08:05 scheiterte das Symbol der Netzkarte,
    # um 08:06:57 wurde der Dienst geändert und lieferte eins -- und DA
    # hätte bis zum 28.09. nicht mehr nachgesehen. Der Vermerk war
    # älter als die Tatsache, die er beschrieb.
    #
    # Zwei Riegel dagegen:
    #   a) Wurde quickaccess.txt seither angefasst, ist jeder Vermerk
    #      hinfällig -- ein neu eingetragenes Ziel hat noch nie
    #      funktioniert, ein Fehlschlag von vorher gehört nicht dazu.
    #   b) Die Frist wächst erst mit der Zahl der Fehlschläge: ein Tag,
    #      und erst ab dem dritten Mal die vollen 14. So kostet ein
    #      hoffnungsloser Fall weiter keine Zeit, ein frisch gebautes
    #      Symbol wird aber am nächsten Tag gefunden.
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
            QA-Log ('Symbolvermerk verfallen (Liste neuer): ' + $name)
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

    # ⚠️ PowerShell 5.1 spricht ohne diese Zeile noch TLS 1.0 - moderne
    #    Seiten wie trello.com brechen die Verbindung dann sofort ab.
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
    } catch { }

    $versuche = @(
        ('{0}://{1}/favicon.ico' -f $adresse.Scheme, $adresse.Authority)
    )
    # Aus der Startseite das angegebene Symbol lesen, falls es nicht an
    # der Standardstelle liegt.
    try {
        $seite = Invoke-WebRequest -Uri ('{0}://{1}/' -f $adresse.Scheme, $adresse.Authority) `
                                   -UseBasicParsing -TimeoutSec 4 -ErrorAction Stop
        foreach ($m in [regex]::Matches([string]$seite.Content,
                       '<link[^>]+rel\s*=\s*["''][^"'']*icon[^"'']*["''][^>]*>')) {
            # 🔴 Tim, 08.09.: Nicht [^"']+ verwenden - eine data:-URI enthält
            #    intern die ANDERE Anführungssorte (svg mit xmlns='...'), und
            #    die Klasse bricht dort ab. Das Emoji-SVG von HM-Protokoll/KODI
            #    wurde so auf „data:image/svg+xml,<svg xmlns=" verstümmelt.
            #    Darum: das öffnende Zeichen merken und per Rückverweis \1
            #    bis zum passenden schliessen lesen.
            $h = [regex]::Match($m.Value, 'href\s*=\s*(["''])(.*?)\1')
            if ($h.Success) {
                $u = $h.Groups[2].Value
                # 🔴 Tim, 08.09.: Eselcockpit & die eigenen Protokollseiten legen
                #    ihr Favicon als „data:image/png;base64,..." direkt in den
                #    <link>. Das ist KEIN Pfad - vorher hat der elseif-Zweig unten
                #    ihm „http://host:port/" vorangestellt und die URL zerstört,
                #    darum fehlte das Symbol. data: bleibt unangetastet.
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
                # data:[<typ>][;base64],<nutzlast> - direkt dekodieren, kein Netz.
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
                # 🔴 Ein als Text ausgeliefertes Favicon (z.B. /favicon.svg mit
                #    Content-Type image/svg+xml) kommt bei IWR als String, nicht
                #    als Byte-Feld - vorher fiel es durch die Prüfung unten und
                #    das JD-Prozessor-Symbol fehlte. In Bytes umsetzen.
                if ($daten -is [string]) { $daten = [Text.Encoding]::UTF8.GetBytes($daten) }
            }
            if ($daten -isnot [byte[]]) { continue }
            if ($daten.Length -lt 32) { continue }
            $symbol = QA-BildAlsSymbol $daten
            if ($symbol) {
                [IO.File]::WriteAllBytes($bild, $daten)
                if (Test-Path -LiteralPath $nichts) { Remove-Item -LiteralPath $nichts -Force }
                QA-Log ('Seitensymbol geholt: ' + $adresse.Host)
                return $symbol
            }
        } catch { }
    }

    # DA-20260914-093332250-030d: Der Vermerk zählt jetzt mit, wie oft
    # es schon fehlschlug -- davon hängt die Frist oben ab. Vorher war
    # die Datei leer und jeder Fehlschlag sah aus wie der erste.
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
            # Erst das Symbol der Seite selbst - damit sieht Trello nach
            # Trello aus und nicht nach Edge.
            $s = QA-Favicon $ziel
            # 🔴 ExtractAssociatedIcon auf shell32.dll liefert immer Symbol
            #    NUMMER 0 - ein leeres Blatt ohne Aussage. Sprechender ist
            #    das Symbol des Standardbrowsers: genau das Programm, das
            #    beim Klick auch aufgeht.
            if (-not $s) { $s = QA-BrowserSymbol }
            if (-not $s) {
                # Weltkugel aus shell32.dll, Nummer 14
                $s = QA-SymbolMitIndex (Join-Path $env:SystemRoot 'System32\shell32.dll') 14
            }
            if (-not $s) {
                $s = [System.Drawing.Icon]::ExtractAssociatedIcon("$env:SystemRoot\system32\shell32.dll")
            }
        } elseif (Test-Path -LiteralPath $ziel) {
            if ((Get-Item -LiteralPath $ziel).PSIsContainer) {
                $s = [System.Drawing.SystemIcons]::WinLogo
            } elseif ($ziel -like '*.lnk') {
                # 🔴 Bei einer Verknüpfung liefert ExtractAssociatedIcon nur
                #    das generische Verknüpfungssymbol. Aussagekräftig ist
                #    das hinterlegte IconLocation, sonst das Symbol des Ziels.
                $w = New-Object -ComObject WScript.Shell
                $v = $w.CreateShortcut($ziel)
                $quelle = $null; $index = 0
                if ($v.IconLocation) {
                    $teile = $v.IconLocation -split ','
                    $quelle = $teile[0].Trim('"')
                    if ($teile.Count -gt 1) { [int]::TryParse($teile[1].Trim(), [ref]$index) | Out-Null }
                    # „shell32.dll" steht ohne Pfad da - im Systemverzeichnis suchen
                    # 🔴 Join-Path setzt den Trenner nur VOR das Argument, nicht
                    #    hinein: 'System32' + 'shell32.dll' ergab bisher
                    #    „System32shell32.dll" und damit nie einen Treffer.
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

# Drei Zonen untereinander: Reiter (oben), Einträge (Mitte, scrollt),
# Fuss (unten). Tim, 07.09.: „stärker nach Gruppen ... als Tabs ... keine
# Klicks" - die Gruppen werden Reiter, über die man nur fährt.
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

# Absichts-Verzögerung für die Reiter (DA-20260913-101000444-35d3).
# 250 ms: unter 150 rutschen schnelle Mausbewegungen durch, über 350
# fühlt sich das Umschalten träge an. Wer den Wert ändern will,
# ändert genau diese eine Zahl.
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
# Reiter an der Overlay-Breite umbrechen, damit PreferredSize stimmt.
$reiter.MaximumSize = New-Object System.Drawing.Size(($BREITE - 6), 0)

# Ein einziger Satz Handler für alle Zeilen - das Ziel steht im .Tag.
$global:QA_Klick = {
    $ziel = $this.Tag
    if (-not $ziel -and $this.Parent) { $ziel = $this.Parent.Tag }
    $global:QA.Overlay.Hide()
    QA-Oeffne $ziel
}
$global:QA_Rein = {
    $panel = if ($this -is [System.Windows.Forms.Panel]) { $this } else { $this.Parent }
    if (-not $panel) { return }
    # 🔴 ZUERST ALLE ANDEREN ZEILEN ZURUECKSETZEN. MouseLeave feuert nicht
    #    verlässlich, wenn der Zeiger von einer Beschriftung direkt in die
    #    nächste Zeile wandert - dann blieben mehrere Zeilen markiert.
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
    # Nur zurücksetzen, wenn der Zeiger die Zeile wirklich verlassen hat -
    # sonst flackert es beim Wechsel zwischen Symbol und Beschriftung.
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
    # Ein ausdrücklich gewähltes Symbol (| Quelle,Nummer) schlägt das
    # Favicon/Standardsymbol - Tim: „Favicon ... wenn keins überschrieben".
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
        catch { QA-Log ('Symbol nicht darstellbar (' + $e.Name + '): ' + $_.Exception.Message) }
    } else {
        QA-Log ('kein Symbol für ' + $e.Name + ' -> ' + $e.Ziel)
    }
    $bild.Tag = $e.Ziel
    $bild.Cursor = [System.Windows.Forms.Cursors]::Hand
    $zeile.Controls.Add($bild)

    $text = New-Object System.Windows.Forms.Label
    $text.Text = $e.Name
    # & wörtlich zeigen - sonst deutet WinForms es als Zugriffstaste
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

    # Aktiven Reiter hervorheben
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
    # DA-20260913-222957620-81a8: die Nummer entsteht beim PAKETBAU und
    # steht in version.txt. Fehlt die Datei, läuft DA aus dem
    # Arbeitsordner -- dann ist es kein gebauter Stand, und das soll man
    # sehen, statt eine Zahl zu erfinden.
    $v = Join-Path $global:QA.Basis 'version.txt'
    if (Test-Path -LiteralPath $v) {
        $z = (Get-Content $v -Encoding UTF8 -TotalCount 1).Trim()
        if ($z) { return $z }
    }
    $ps1 = Join-Path $global:QA.Basis 'QuickAccess.ps1'
    if (Test-Path -LiteralPath $ps1) {
        return 'unveröffentlicht (' +
               (Get-Item -LiteralPath $ps1).LastWriteTime.ToString('yyyy-MM-dd') + ')'
    }
    return 'unbekannt'
}

function global:QA-ZeigeUeber {
    # DA-20260913-144056185-c031. Bewusst eine MessageBox: sie ist das
    # einzige Fenster, das ohne eigene Ereignisschleife auskommt und die
    # Tray-Schleife nicht blockiert.
    #
    # 🔴 Sie bleibt HELL. WinForms kann Systemdialoge nicht einfärben
    # (DA-20260913-163439041-83d7) -- das ist die Grenze der Bibliothek,
    # keine vergessene Stelle.
    $global:QA.Overlay.Hide()
    $text = @"
Donkey's Apprentice
Fassung $(QA-Version)

Eselchen Labs - MIT-Lizenz
github.com/eselchenlabs/donkeys-apprentice

Der volle Lizenztext liegt als LICENSE im Programmordner.
"@
    QA-Log 'Über-Fenster geöffnet'
    [System.Windows.Forms.MessageBox]::Show(
        $text, "Über Donkey's Apprentice", 'OK', 'Information') | Out-Null
}

# DA-20260917-174940488-ae95: Das Overlay schliesst sich, sobald die
# Maus es verlässt -- wer etwas nachlesen oder eine Adresse kopieren
# will, verliert es dabei. Angeheftet bleibt es stehen.
#
# Kein Rahmen, keine Titelleiste: ein FormBorderStyle am Overlay macht
# aus dem Popup ein Fenster mit ganz anderer Anmutung. Ein Knopf in der
# vorhandenen Fussleiste reicht.
function global:QA-ZeichneAnheften {
    $pin = $global:QA.PinKnopf
    if (-not $pin) { return }
    if ($global:QA.Angeheftet) {
        $pin.Text = 'Angeheftet'
        $pin.ForeColor = $global:FARBE_TEXT
    } else {
        $pin.Text = 'Anheften'
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
        # Lösen heisst nicht schliessen: die Wache uebernimmt wieder,
        # sobald die Maus den Rahmen verlässt. Der Zähler fängt bei
        # 0 an, damit nicht ein alter Stand sofort zuschlägt.
        $global:QA.Draussen = 0
    })
    $pin.Add_MouseEnter({ $this.ForeColor = $global:FARBE_TEXT })
    # Nicht fest auf FARBE_GRUPPE zuruecksetzen -- im angehefteten
    # Zustand ist der Knopf hell, und ein Mauszeiger, der darueber
    # hinwegstreift, darf das nicht löschen.
    $pin.Add_MouseLeave({ QA-ZeichneAnheften })
    [void]$fuss.Controls.Add($pin)
    $global:QA.PinKnopf = $pin
    QA-ZeichneAnheften

    foreach ($paar in @(
        @('Verwalten', {
            # Verwaltung als eigener Prozess (sonst blockiert das modale
            # Fenster die Ereignisschleife des Tray-Symbols). Nicht mit
            # -WindowStyle Hidden - der wscript-Starter blendet nur die
            # Konsole aus, nicht das Fenster.
            $global:QA.Overlay.Hide()
            Start-Process wscript.exe -ArgumentList (
                '"' + (Join-Path $global:QA.Basis 'QuickAccessAdmin.vbs') + '"')
        }),
        @('Autostart', { QA-SchalteAutostart }),
        # DA-20260913-144056185-c031: die Urheberangabe muss JEDERZEIT
        # erreichbar sein. Eine Sprechblase verschwindet wieder, ein
        # Menüpunkt nicht. Keine Versionsnummer -- DA hat heute keine,
        # und eine einzuführen ist eine eigene Sache.
        @('Über',     { QA-ZeigeUeber }),
        @('Beenden',   { $global:QA.Tray.Visible = $false
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
    # Einträge nach Gruppen ordnen; die Reihenfolge der Datei bleibt.
    $nach = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($e in (QA-LiesKonfig)) {
        $g = if ($e.Gruppe) { $e.Gruppe } else { 'Ohne Gruppe' }
        if (-not $nach.Contains($g)) { $nach[$g] = New-Object System.Collections.ArrayList }
        [void]$nach[$g].Add($e)
    }
    $global:QA.NachGruppe = $nach
    $gruppen = @($nach.Keys)

    # Reiter (Gruppen) bauen - Hover schaltet um, kein Klick nötig.
    $reiter = $global:QA.Reiter
    $reiter.SuspendLayout()
    $reiter.Controls.Clear()
    foreach ($g in $gruppen) {
        $tab = New-Object System.Windows.Forms.Label
        $tab.Text = $g
        # Gruppen wie "Heizung & Energie" sollen das & zeigen und nicht
        # als Zugriffstaste deuten - sonst stimmt auch der Vergleich in
        # QA-ZeigeGruppe nicht mehr und der aktive Reiter bleibt blass.
        $tab.UseMnemonic = $false
        $tab.AutoSize = $true
        $tab.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
        $tab.ForeColor = [System.Drawing.Color]::FromArgb(185, 185, 195)
        $tab.BackColor = $global:FARBE_FELD
        $tab.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
        $tab.Margin = New-Object System.Windows.Forms.Padding(2, 2, 2, 2)
        $tab.Cursor = [System.Windows.Forms.Cursors]::Hand
        # 🔴 NICHT sofort schalten. Bei sechs Gruppen brechen die Reiter
        # in zwei Zeilen um (WrapContents, 354 px). Der Weg von einem
        # Reiter der ersten Zeile hinunter zum Inhalt kreuzt dann
        # zwangsläufig die zweite Zeile - und jedes Kreuzen schaltete
        # bisher die Gruppe um. Man landete verlässlich im Inhalt der
        # zuletzt überquerten Gruppe.
        #
        # Wer wählen will, bleibt stehen; wer nur durchfährt, ist in
        # 40-80 ms wieder draussen und MouseLeave stoppt die Uhr.
        # Der KLICK schaltet weiterhin sofort - die Verzögerung ist ein
        # Filter, keine Bremse.
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

    # Höhe EINMAL aus der größten Gruppe festlegen - so springt und rollt das
    # Overlay beim Umschalten der Reiter nicht (war „unbenutzbar, zu viele
    # Scrollbars").
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

    # Aktive Gruppe: gemerkte, sonst die erste.
    $aktiv = $global:QA.AktiveGruppe
    if (-not $aktiv -or -not ($gruppen -contains $aktiv)) {
        $aktiv = if ($gruppen.Count) { $gruppen[0] } else { $null }
    }
    if ($aktiv) { QA-ZeigeGruppe $aktiv }
}

function global:QA-Zeige {
    # Jedes Öffnen fängt unangeheftet an. Ein Zustand, der ein Fenster
    # dauerhaft offen hält, darf keinen Aufruf ueberleben -- sonst
    # steht das Overlay irgendwann da und niemand weiss, warum.
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
        # Über wscript, sonst blitzt bei jeder Anmeldung ein Konsolenfenster auf.
        $v.TargetPath = 'wscript.exe'
        $v.Arguments = '"' + (Join-Path $global:QA.Basis 'QuickAccess.vbs') + '"'
        $v.WorkingDirectory = $global:QA.Basis
        $v.Save()
        $global:QA.Tray.ShowBalloonTip(1500, "Donkey's Apprentice", 'Startet künftig mit Windows.', 'Info')
    }
}

# ---------------------------------------------------------------------
#  Tray-Symbol - das Eselchen, falls vorhanden
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
$tray.Text = "Donkey's Apprentice - Maus drüber genügt"
$tray.Visible = $true
$global:QA.Tray = $tray

$tray.Add_MouseMove({ if (-not $global:QA.Overlay.Visible) { QA-Zeige } })
$tray.Add_MouseClick({
    if ($global:QA.Overlay.Visible) {
        # Angeheftet: ein Klick auf den Esel löst und schliesst. Damit
        # gibt es immer einen Weg zurueck, auch ohne den Knopf zu
        # treffen. ⚠ Bewusst NICHT bei MouseMove -- das Overlay sitzt
        # dicht am Infobereich, und jeder Weg der Maus dorthin würde es
        # wegreissen.
        if ($global:QA.Angeheftet) {
            $global:QA.Angeheftet = $false
            QA-ZeichneAnheften
            $global:QA.Overlay.Hide()
        }
        return
    }
    QA-Zeige
})

# ⚠️ Nicht über Deactivate schließen: das Overlay bekommt gar keinen Fokus,
#    sonst müsste man ja doch klicken. Stattdessen die Mausposition prüfen,
#    mit Nachlauf für den Weg vom Symbol zum Overlay.
$global:QA.Draussen = 0
$wache = New-Object System.Windows.Forms.Timer
$wache.Interval = 250
$wache.Add_Tick({
    $ov = $global:QA.Overlay
    if (-not $ov.Visible) { $global:QA.Draussen = 0; return }
    # Angeheftet: die Wache zählt nicht mit.
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

# Einmal beim Start aufbauen (ohne zu zeigen) - dann steht schon im
# Protokoll, ob die Symbole ankommen, ohne dass jemand das Overlay
# geöffnet haben muss.
QA-Log '--- Aufbau beim Start ---'
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
    QA-Log ("Zeilen mit Symbol: $mitBild, ohne: $ohneBild")
} catch {
    QA-Log ('Aufbau fehlgeschlagen: ' + $_.Exception.Message)
}

# DA-20260913-144047595-f616: beim ALLERERSTEN Start sagt die Blase, wo
# es weitergeht -- ein leeres Fenster ohne Hinweis ist der Punkt, an dem
# die meisten ein Werkzeug wieder löschen. Danach wieder die kurze.
#
# 🔴 EINE Blase, nicht zwei. Zwei Meldungen hintereinander sind eine
# Meldung zu viel, und die zweite verdeckt die erste.
if ($global:QA.Erstmals) {
    $tray.ShowBalloonTip(7000, "Donkey's Apprentice",
        'Rechtsklick auf das Eselsymbol -> "Verwalten".' + [char]10 +
        'Dort stehen die Einträge, die Beispiele und der Autostart.', 'Info')
    QA-Log 'Erststart: Hinweisblase gezeigt'
} else {
    $tray.ShowBalloonTip(2500, "Donkey's Apprentice",
        'Maus über das Symbol - der Rest geht von allein.', 'Info')
}

[System.Windows.Forms.Application]::Run()
$tray.Dispose()
$sperre.ReleaseMutex()
