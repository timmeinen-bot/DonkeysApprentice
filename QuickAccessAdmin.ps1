# =====================================================================
#  Donkey's Apprentice - Verwaltung
#
#  Einträge anlegen, ändern, sortieren, löschen und mit eigenem Symbol
#  versehen. Die Textdatei bleibt das Format der Wahrheit; dieses Fenster
#  ist nur ein bequemer Weg dorthin.
#
#  Fallen, die hier schon zugeschlagen haben:
#  🔴 KEINE FESTEN KOORDINATEN FÜR KNÖPFE. Mit festen x-Werten lagen drei
#     Knöpfe übereinander. Ein FlowLayoutPanel ordnet sie selbst.
#  🔴 NICHT MIT -WindowStyle Hidden STARTEN - das versteckt auch das
#     Formular. Die Konsole blendet das Skript selbst aus.
#  🔴 Application::Run BRAUCHT DAS FORMULAR ALS ARGUMENT, sonst endet die
#     Schleife sofort und das Fenster verschwindet im selben Moment.
#  🔴 StartPosition = CenterScreen landete außerhalb des sichtbaren
#     Bereichs - feste Position ist verlässlicher.
# =====================================================================
$ErrorActionPreference = 'Stop'

# PSScriptRoot ist bei -File zuverlässiger als MyInvocation.
$BASIS = $PSScriptRoot
if (-not $BASIS) { $BASIS = Split-Path -Parent $MyInvocation.MyCommand.Path }
# 🔴 Kein fester Benutzerpfad als Rückfall -- der trug bis zum
#    13.09.2026 Tims Profilnamen im Quelltext aus (DA 2/9) und wäre auf
#    jedem anderen Rechner falsch gewesen.
if (-not $BASIS) { $BASIS = Join-Path $env:LOCALAPPDATA 'QuickAccess' }
# Geschrieben wird nur unter %LOCALAPPDATA% (DA-20260913-144004296-42e6).
$DATEN = Join-Path $env:LOCALAPPDATA 'QuickAccess'
if (-not (Test-Path -LiteralPath $DATEN)) {
    New-Item -ItemType Directory -Force -Path $DATEN | Out-Null
}
$KONFIG = Join-Path $DATEN 'quickaccess.txt'
$script:TITEL = 'Donkey' + [char]39 + 's Apprentice'

function Spur($text) {
    try {
        Add-Content -Path (Join-Path $DATEN 'admin.log') -Encoding UTF8 -Value (
            (Get-Date).ToString('HH:mm:ss') + '  ' + $text)
    } catch { }
}
Spur 'Start'

# Nur das Konsolenfenster ausblenden, nicht den ganzen Prozess.
Add-Type -Namespace QA -Name Fenster -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr handle, int zustand);
'@
$konsole = [QA.Fenster]::GetConsoleWindow()
if ($konsole -ne [IntPtr]::Zero) { [void][QA.Fenster]::ShowWindow($konsole, 0) }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# Für die einfache Eingabebox beim Umbenennen einer Gruppe.
Add-Type -AssemblyName Microsoft.VisualBasic

# ExtractAssociatedIcon kann KEINEN Index und liefert immer nur das erste
# Symbol einer Datei. Für "shell32.dll,44" braucht es ExtractIconEx.
Add-Type -Namespace QA -Name Symbole -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern int ExtractIconExW(string datei, int index, out IntPtr gross, out IntPtr klein, int anzahl);
[DllImport("user32.dll")]
public static extern bool DestroyIcon(IntPtr handle);
'@

function Hol-Symbol($quelle, $index) {
    # Gibt ein Bitmap zurück oder $null. Das Handle wird immer freigegeben.
    $gross = [IntPtr]::Zero; $klein = [IntPtr]::Zero
    try {
        $n = [QA.Symbole]::ExtractIconExW($quelle, [int]$index, [ref]$gross, [ref]$klein, 1)
        if ($n -gt 0 -and $gross -ne [IntPtr]::Zero) {
            return ([System.Drawing.Icon]::FromHandle($gross)).ToBitmap()
        }
    } catch { }
    finally {
        if ($gross -ne [IntPtr]::Zero) { [void][QA.Symbole]::DestroyIcon($gross) }
        if ($klein -ne [IntPtr]::Zero) { [void][QA.Symbole]::DestroyIcon($klein) }
    }
    return $null
}

# ---------------------------------------------------------------------
#  Lesen und Schreiben
#  Format:  Name = Ziel                    (Symbol des Dokuments)
#           Name = Ziel | Quelle,Index     (eigenes Symbol)
# ---------------------------------------------------------------------
function Ist-Link($ziel) { return $ziel -match '^(https?|mailto|ftp)://|^mailto:' }

function Lies-Eintraege {
    $liste = New-Object System.Collections.ArrayList
    if (-not (Test-Path $KONFIG)) { return $liste }
    $gruppe = ''
    # ⚠️ Ohne -Encoding UTF8 liest PowerShell 5.1 die Datei als ANSI.
    foreach ($zeile in (Get-Content $KONFIG -Encoding UTF8)) {
        $z = $zeile.Trim()
        if ($z -eq '' -or $z.StartsWith('#')) { continue }
        if ($z -match '^\[(.+)\]$') { $gruppe = $Matches[1].Trim(); continue }
        $i = $z.IndexOf('=')
        if ($i -ge 1) {
            $name = $z.Substring(0, $i).Trim()
            $ziel = $z.Substring($i + 1).Trim()
        } else { $name = ''; $ziel = $z }
        if (-not $ziel) { continue }
        # Der senkrechte Strich ist in Windows-Pfaden verboten und taugt
        # deshalb als Trenner zum Symbol.
        $symbol = ''
        $strich = $ziel.IndexOf(' | ')
        if ($strich -ge 0) {
            $symbol = $ziel.Substring($strich + 3).Trim()
            $ziel = $ziel.Substring(0, $strich).Trim()
        }
        [void]$liste.Add([PSCustomObject]@{
            Gruppe = $gruppe; Name = $name; Ziel = $ziel; Symbol = $symbol })
    }
    return $liste
}

function Schreib-Eintraege($liste) {
    $text = New-Object System.Text.StringBuilder
    [void]$text.AppendLine('# ' + $script:TITEL + ' - Name = Ziel')
    [void]$text.AppendLine('#   [Gruppe] macht eine Überschrift')
    [void]$text.AppendLine('#   Ziel darf Datei, Ordner oder Link sein')
    [void]$text.AppendLine('#   Eigenes Symbol dahinter:  ... | quelle.dll,5')
    $letzte = $null
    foreach ($e in $liste) {
        if ($e.Gruppe -ne $letzte) {
            [void]$text.AppendLine('')
            if ($e.Gruppe) { [void]$text.AppendLine('[' + $e.Gruppe + ']') }
            $letzte = $e.Gruppe
        }
        $zeile = $e.Name + ' = ' + $e.Ziel
        if ($e.Symbol) { $zeile += ' | ' + $e.Symbol }
        [void]$text.AppendLine($zeile)
    }
    # ⚠️ UTF-8 MIT Stückliste, sonst kommen die Umlaute falsch zurück.
    [IO.File]::WriteAllText($KONFIG, $text.ToString(), (New-Object Text.UTF8Encoding $true))
}

# ---------------------------------------------------------------------
#  Prüfung einer Zeile. Rückgabe: Meldung oder $null.
# ---------------------------------------------------------------------
function Pruefe($name, $ziel, $liste, $ausser = -1) {
    if (-not $name -or -not $name.Trim()) { return 'Der Name darf nicht leer sein.' }
    if (-not $ziel -or -not $ziel.Trim()) { return 'Das Ziel darf nicht leer sein.' }
    if ($name -match '^\s*\[') { return 'Der Name darf nicht mit einer eckigen Klammer beginnen - die kennzeichnet Gruppen.' }
    if ($name.Contains('=')) { return 'Der Name darf kein Gleichheitszeichen enthalten - daran wird die Zeile getrennt.' }
    if ($name.Contains('|')) { return 'Der Name darf keinen senkrechten Strich enthalten - der trennt das Symbol ab.' }
    if (Ist-Link $ziel) {
        if ($ziel -notmatch '^(https?://[^\s/]+|mailto:[^\s@]+@[^\s@]+|ftp://[^\s/]+)') {
            return 'Die Adresse sieht unvollständig aus, erwartet wird etwa http://rechner:port'
        }
    } else {
        if ($ziel -match '[<>|?*]') { return 'Der Pfad enthält Zeichen, die Windows nicht erlaubt.' }
        if (-not (Test-Path -LiteralPath $ziel)) {
            return 'HINWEIS: Das Ziel ist gerade nicht erreichbar. Bei Netzlaufwerken ist das in Ordnung.'
        }
    }
    for ($i = 0; $i -lt $liste.Count; $i++) {
        if ($i -eq $ausser) { continue }
        if ($liste[$i].Name -eq $name.Trim()) { return 'Ein Eintrag mit diesem Namen besteht bereits.' }
    }
    return $null
}

# 🔴 PowerShell entrollt eine aus einer Funktion zurückgegebene ArrayList
#    zu einem FESTEN object[] - dann wirft .Add()/.Clear()/.RemoveAt()
#    „Die Liste hatte eine feste Größe". Darum hier wieder in eine echte
#    ArrayList fassen, sonst sind Hinzufügen, Löschen und die
#    Gruppen-Knöpfe unzuverlässig.
$eintraege = [System.Collections.ArrayList]@(Lies-Eintraege)
Spur ('Einträge: ' + $eintraege.Count)

# ---------------------------------------------------------------------
#  Fenster
# ---------------------------------------------------------------------
. "$PSScriptRoot\QA-Stil.ps1"   # DA-20260913-163439041-83d7: eine Stilquelle
$f = New-Object System.Windows.Forms.Form
$f.Text = $script:TITEL + ' - Verwaltung'
$f.Size = New-Object System.Drawing.Size(1020, 680)
$f.MinimumSize = New-Object System.Drawing.Size(880, 600)
$f.StartPosition = 'Manual'
$f.Location = New-Object System.Drawing.Point(140, 70)
$f.ShowInTaskbar = $true
$eigenes = Join-Path $BASIS 'esel.ico'
if (Test-Path $eigenes) { $f.Icon = New-Object System.Drawing.Icon($eigenes) }

$liste = New-Object System.Windows.Forms.ListView
$liste.View = 'Details'
$liste.FullRowSelect = $true
$liste.GridLines = $true
$liste.HideSelection = $false
$liste.AllowDrop = $true
$liste.Location = New-Object System.Drawing.Point(12, 12)
$liste.Size = New-Object System.Drawing.Size(980, 350)
$liste.Anchor = 'Top,Left,Right,Bottom'
[void]$liste.Columns.Add('Gruppe', 120)
[void]$liste.Columns.Add('Name', 205)
[void]$liste.Columns.Add('Ziel', 395)
[void]$liste.Columns.Add('Zustand', 70)
[void]$liste.Columns.Add('Symbol', 165)
$f.Controls.Add($liste)

# DA-20260914-093332250-030d: Woran sieht man, warum ein Symbol fehlt?
# Bis heute gar nicht -- der Grund lag als leere Datei im Dateisystem.
function QA-SymbolZustand($ziel) {
    if (-not $ziel) { return '' }
    if ($ziel -notmatch '^https?://') { return '' }
    try {
        $u = [Uri]$ziel
    } catch { return '' }
    $ordner = Join-Path $env:LOCALAPPDATA 'QuickAccess\symbole'
    $name = (($u.Host + '_' + $u.Port) -replace '[^A-Za-z0-9\.\-]', '_')
    $bild = Join-Path $ordner ($name + '.ico')
    $nichts = Join-Path $ordner ($name + '.keins')
    if (Test-Path -LiteralPath $bild) { return 'Favicon' }
    if (Test-Path -LiteralPath $nichts) {
        $v = Get-Item -LiteralPath $nichts
        $wieoft = 0
        try {
            $r = (Get-Content -LiteralPath $nichts -Raw -ErrorAction Stop)
            if ($r) { $wieoft = [int]($r.Trim()) }
        } catch { }
        return ('keins seit ' + $v.LastWriteTime.ToString('dd.MM. HH:mm') +
                $(if ($wieoft -gt 1) { ' (' + $wieoft + 'x)' } else { '' }))
    }
    return 'noch nicht geholt'
}

function Fuelle-Liste($auswahl = -1) {
    $liste.BeginUpdate()
    $liste.Items.Clear()
    foreach ($e in $eintraege) {
        $zeile = New-Object System.Windows.Forms.ListViewItem($e.Gruppe)
        [void]$zeile.SubItems.Add($e.Name)
        [void]$zeile.SubItems.Add($e.Ziel)
        if (Ist-Link $e.Ziel) { [void]$zeile.SubItems.Add('Link') }
        elseif (Test-Path -LiteralPath $e.Ziel) {
            [void]$zeile.SubItems.Add($(if ((Get-Item -LiteralPath $e.Ziel).PSIsContainer) { 'Ordner' } else { 'Datei' }))
        } else {
            [void]$zeile.SubItems.Add('fehlt')
            $zeile.ForeColor = $FARBE_WARNUNG
        }
        # DA-20260914-093332250-030d: Steht ein eigenes Symbol da, gilt es.
        # Sonst zeigt die Spalte, was mit dem Favicon los ist -- statt
        # pauschal "(Standard)", was drei verschiedene Lagen verdeckte:
        # geholt, nie versucht, und fehlgeschlagen samt Datum.
        if ($e.Symbol) {
            [void]$zeile.SubItems.Add([IO.Path]::GetFileName(($e.Symbol -split ',')[0]))
        } else {
            $zustand = QA-SymbolZustand $e.Ziel
            if (-not $zustand) { $zustand = '(Standard)' }
            [void]$zeile.SubItems.Add($zustand)
            if ($zustand -like 'keins seit*') { $zeile.ForeColor = $FARBE_WARNUNG }
        }
        [void]$liste.Items.Add($zeile)
    }
    $liste.EndUpdate()
    if ($auswahl -ge 0 -and $auswahl -lt $liste.Items.Count) {
        $liste.Items[$auswahl].Selected = $true
        $liste.Items[$auswahl].EnsureVisible()
    }
}

# ─── Eingabefelder ───────────────────────────────────────────────────
function Beschriftung($text, $x, $y, $breite) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($breite, 18)
    $l.Anchor = 'Left,Bottom'
    $f.Controls.Add($l)
}
Beschriftung 'Gruppe' 12 374 120
Beschriftung 'Name' 140 374 210
Beschriftung 'Ziel (Datei, Ordner oder Link)' 356 374 380

$fGruppe = New-Object System.Windows.Forms.ComboBox
$fGruppe.Location = New-Object System.Drawing.Point(12, 394)
$fGruppe.Size = New-Object System.Drawing.Size(120, 24)
$fGruppe.Anchor = 'Left,Bottom'
$f.Controls.Add($fGruppe)

$fName = New-Object System.Windows.Forms.TextBox
$fName.Location = New-Object System.Drawing.Point(140, 394)
$fName.Size = New-Object System.Drawing.Size(210, 24)
$fName.Anchor = 'Left,Bottom'
$f.Controls.Add($fName)

$fZiel = New-Object System.Windows.Forms.TextBox
$fZiel.Location = New-Object System.Drawing.Point(356, 394)
$fZiel.Size = New-Object System.Drawing.Size(448, 24)
$fZiel.Anchor = 'Left,Right,Bottom'
$f.Controls.Add($fZiel)

$knopfDatei = New-Object System.Windows.Forms.Button
$knopfDatei.Text = 'Datei ...'
$knopfDatei.Location = New-Object System.Drawing.Point(812, 393)
$knopfDatei.Size = New-Object System.Drawing.Size(86, 26)
$knopfDatei.Anchor = 'Right,Bottom'
$f.Controls.Add($knopfDatei)

$knopfOrdner = New-Object System.Windows.Forms.Button
$knopfOrdner.Text = 'Ordner ...'
$knopfOrdner.Location = New-Object System.Drawing.Point(904, 393)
$knopfOrdner.Size = New-Object System.Drawing.Size(88, 26)
$knopfOrdner.Anchor = 'Right,Bottom'
$f.Controls.Add($knopfOrdner)

# ─── Symbolbereich ───────────────────────────────────────────────────
$symbolFeld = New-Object System.Windows.Forms.GroupBox
$symbolFeld.Text = 'Symbol dieses Eintrags'
$symbolFeld.Location = New-Object System.Drawing.Point(12, 430)
$symbolFeld.Size = New-Object System.Drawing.Size(330, 66)
$symbolFeld.Anchor = 'Left,Bottom'
$f.Controls.Add($symbolFeld)

$vorschau = New-Object System.Windows.Forms.PictureBox
$vorschau.Size = New-Object System.Drawing.Size(32, 32)
$vorschau.Location = New-Object System.Drawing.Point(14, 24)
$vorschau.SizeMode = 'CenterImage'
$vorschau.BorderStyle = 'FixedSingle'
$vorschau.BackColor = [System.Drawing.Color]::White
$symbolFeld.Controls.Add($vorschau)

$symbolText = New-Object System.Windows.Forms.Label
$symbolText.Text = '(Standard des Dokuments)'
$symbolText.Location = New-Object System.Drawing.Point(56, 32)
$symbolText.Size = New-Object System.Drawing.Size(262, 18)
$symbolText.ForeColor = [System.Drawing.Color]::DimGray
$symbolFeld.Controls.Add($symbolText)

$script:aktuellesSymbol = ''

function Zeige-Vorschau($ziel, $symbol) {
    # Immer zeigen, was tatsächlich gilt: eigenes Symbol, sonst das des Dokuments.
    $bild = $null
    try {
        if ($symbol) {
            $quelle = ($symbol -split ',')[0].Trim('"').Trim()
            if ($quelle -and -not (Test-Path -LiteralPath $quelle)) {
                $imSystem = Join-Path $env:SystemRoot ('System32\' + $quelle)
                if (Test-Path -LiteralPath $imSystem) { $quelle = $imSystem }
            }
            $index = 0
            $teile = $symbol -split ','
            if ($teile.Count -gt 1) { [void][int]::TryParse($teile[1].Trim(), [ref]$index) }
            if ($quelle -and (Test-Path -LiteralPath $quelle)) {
                # Hier NICHT ExtractAssociatedIcon nehmen - das zeigt sonst
                # immer Symbol 0 statt des gewählten.
                $bild = Hol-Symbol $quelle $index
                if (-not $bild) {
                    $bild = ([System.Drawing.Icon]::ExtractAssociatedIcon($quelle)).ToBitmap()
                }
            }
        }
        if (-not $bild -and $ziel) {
            $shell = Join-Path $env:SystemRoot 'System32\shell32.dll'
            if (Ist-Link $ziel) {
                $bild = Hol-Symbol $shell 14          # Weltkugel
            } elseif (Test-Path -LiteralPath $ziel) {
                if ((Get-Item -LiteralPath $ziel).PSIsContainer) {
                    $bild = Hol-Symbol $shell 3       # Ordner
                } else {
                    $bild = ([System.Drawing.Icon]::ExtractAssociatedIcon($ziel)).ToBitmap()
                }
            }
        }
    } catch { Spur ('Vorschau: ' + $_.Exception.Message) }
    # 🔴 AUCH DAS HIER MUSS IN EIN try. GetFileName wirft bei ungültigen
    #    Zeichen im Pfad, und eine Ausnahme aus einem Ereignishandler
    #    beendet mit ErrorActionPreference=Stop die ganze Nachrichtenschleife
    #    - das Fenster ist dann einfach weg, ohne Meldung.
    try {
        $vorschau.Image = $bild
        if ($symbol) {
            $teile = $symbol -split ','
            $roh = $teile[0].Trim('"').Trim()
            $t = $roh
            try { $t = [IO.Path]::GetFileName($roh) } catch { }
            if ($teile.Count -gt 1) { $t = $t + ', Nummer ' + $teile[1].Trim() }
            $symbolText.Text = $t
        } else { $symbolText.Text = '(Standard des Dokuments)' }
    } catch { Spur ('Vorschau anzeigen: ' + $_.Exception.Message) }
}

$meldung = New-Object System.Windows.Forms.Label
$meldung.Location = New-Object System.Drawing.Point(356, 436)
$meldung.Size = New-Object System.Drawing.Size(636, 50)
$meldung.Anchor = 'Left,Right,Bottom'
$meldung.ForeColor = $FARBE_WARNUNG
$f.Controls.Add($meldung)

# ─── Knopfleiste: ordnet sich selbst, kann nicht überlappen ──────────
$leiste = New-Object System.Windows.Forms.FlowLayoutPanel
$leiste.FlowDirection = 'LeftToRight'
$leiste.WrapContents = $true
$leiste.Location = New-Object System.Drawing.Point(12, 506)
$leiste.Size = New-Object System.Drawing.Size(985, 80)
$leiste.Anchor = 'Left,Right,Bottom'
$f.Controls.Add($leiste)

function Leistenknopf($text, $breite, $aktion) {
    $k = New-Object System.Windows.Forms.Button
    $k.Text = $text
    $k.Size = New-Object System.Drawing.Size($breite, 30)
    $k.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 8)
    $k.Add_Click($aktion)
    $leiste.Controls.Add($k)
}

$script:aktuellerIndex = -1

function Pruefe-Eingabe {
    $fehler = Pruefe $fName.Text $fZiel.Text $eintraege $script:aktuellerIndex
    if ($fehler) {
        $meldung.Text = $fehler
        $meldung.ForeColor = if ($fehler.StartsWith('HINWEIS')) {
            [System.Drawing.Color]::DarkGoldenrod } else { $FARBE_WARNUNG }
        # Ein Hinweis blockiert nicht - ein Netzlaufwerk darf gerade fehlen.
        return $fehler.StartsWith('HINWEIS')
    }
    $meldung.Text = ''
    return $true
}

Leistenknopf 'Hinzufügen' 105 {
    Spur ('Hinzufügen gedrückt: Name=[' + $fName.Text + '] Ziel=[' + $fZiel.Text +
          '] Symbol=[' + $script:aktuellesSymbol + ']')
    if (-not (Pruefe-Eingabe)) { Spur ('  abgelehnt: ' + $meldung.Text); return }
    [void]$eintraege.Add([PSCustomObject]@{
        Gruppe = $fGruppe.Text.Trim(); Name = $fName.Text.Trim()
        Ziel = $fZiel.Text.Trim(); Symbol = $script:aktuellesSymbol })
    Aktualisiere-Gruppen
    Fuelle-Liste ($eintraege.Count - 1)
    $fName.Clear(); $fZiel.Clear()
    $script:aktuellesSymbol = ''
    Zeige-Vorschau '' ''
}

Leistenknopf 'Übernehmen' 105 {
    Spur ('Übernehmen gedrückt: Index=' + $script:aktuellerIndex +
          ' Name=[' + $fName.Text + '] Symbol=[' + $script:aktuellesSymbol + ']')
    # 🔴 Tim, 07.09.: „DA kann keinen neuen Eintrag speichern, alle Felder
    #    ausgefüllt, immer noch ,Erst einen Eintrag in der Liste wählen'".
    #    Wer die Felder ausfüllt und Übernehmen drückt, will speichern -
    #    ob die Zeile schon existiert oder neu ist, ist seine Sache nicht.
    #    Ohne Auswahl wird jetzt ein neuer Eintrag angelegt, statt eine
    #    Meldung zu zeigen, die niemandem weiterhilft.
    if ($script:aktuellerIndex -lt 0) {
        if (-not (Pruefe-Eingabe)) { Spur ('  abgelehnt: ' + $meldung.Text); return }
        [void]$eintraege.Add([PSCustomObject]@{
            Gruppe = $fGruppe.Text.Trim(); Name = $fName.Text.Trim()
            Ziel = $fZiel.Text.Trim(); Symbol = $script:aktuellesSymbol })
        Aktualisiere-Gruppen
        Fuelle-Liste ($eintraege.Count - 1)
        $meldung.ForeColor = [System.Drawing.Color]::DarkGreen
        $meldung.Text = 'Neuer Eintrag angelegt.'
        Spur '  ohne Auswahl -> neuer Eintrag angelegt'
        return
    }
    if (-not (Pruefe-Eingabe)) { Spur ('  abgelehnt: ' + $meldung.Text); return }
    $i = $script:aktuellerIndex
    $eintraege[$i].Gruppe = $fGruppe.Text.Trim()
    $eintraege[$i].Name = $fName.Text.Trim()
    $eintraege[$i].Ziel = $fZiel.Text.Trim()
    $eintraege[$i].Symbol = $script:aktuellesSymbol
    Aktualisiere-Gruppen
    Fuelle-Liste $i
}

Leistenknopf 'Löschen' 88 {
    if ($script:aktuellerIndex -lt 0) { $meldung.Text = 'Erst einen Eintrag wählen.'; return }
    $e = $eintraege[$script:aktuellerIndex]
    $frage = 'Soll der Eintrag ' + [char]8222 + $e.Name + [char]8220 + ' entfernt werden?'
    if ([System.Windows.Forms.MessageBox]::Show($frage, $script:TITEL, 'YesNo', 'Question') -eq 'Yes') {
        $i = $script:aktuellerIndex
        $eintraege.RemoveAt($i)
        $script:aktuellerIndex = -1
        Fuelle-Liste ([Math]::Min($i, $eintraege.Count - 1))
        $fName.Clear(); $fZiel.Clear()
    }
}

# ─── Gruppen verwalten (Tim, 07.09.: anlegen/umbenennen/löschen) ──────
# Neue Gruppe entsteht durch Eintippen im Feld „Gruppe" beim Hinzufügen.
# Umbenennen und Löschen wirken auf ALLE Einträge der Gruppe auf einmal;
# Hoch/Runter verschiebt den ganzen Gruppenblock (= Reiter-Reihenfolge im
# Overlay). Gesichert wird erst mit „Speichern und schließen".
function Aktuelle-Gruppe {
    if ($script:aktuellerIndex -ge 0 -and $script:aktuellerIndex -lt $eintraege.Count) {
        return $eintraege[$script:aktuellerIndex].Gruppe
    }
    return $fGruppe.Text.Trim()
}
function Keine-Gruppe {
    $meldung.ForeColor = $FARBE_WARNUNG
    $meldung.Text = 'Erst eine Gruppe wählen (Eintrag anklicken oder Gruppe ins Feld schreiben).'
}
function Verschiebe-Gruppe($richtung) {
    $g = Aktuelle-Gruppe
    if (-not $g) { Keine-Gruppe; return }
    $reihen = @(); foreach ($e in $eintraege) { if ($reihen -notcontains $e.Gruppe) { $reihen += $e.Gruppe } }
    $pos = [Array]::IndexOf($reihen, $g); $neu = $pos + $richtung
    if ($neu -lt 0 -or $neu -ge $reihen.Count) { return }
    $t = $reihen[$neu]; $reihen[$neu] = $reihen[$pos]; $reihen[$pos] = $t
    $neuList = New-Object System.Collections.ArrayList
    foreach ($gr in $reihen) { foreach ($e in $eintraege) { if ($e.Gruppe -eq $gr) { [void]$neuList.Add($e) } } }
    $eintraege.Clear(); foreach ($e in $neuList) { [void]$eintraege.Add($e) }
    $script:aktuellerIndex = -1
    Fuelle-Liste; Aktualisiere-Gruppen
    $meldung.ForeColor = [System.Drawing.Color]::DarkGreen
    $meldung.Text = 'Gruppe ' + [char]8222 + $g + [char]8220 + ' verschoben. Mit Speichern sichern.'
}

Leistenknopf 'Gruppe umbenennen' 150 {
    $g = Aktuelle-Gruppe
    if (-not $g) { Keine-Gruppe; return }
    $neu = ([Microsoft.VisualBasic.Interaction]::InputBox(
        'Gruppe ' + [char]8222 + $g + [char]8220 + ' umbenennen in:', $script:TITEL, $g)).Trim()
    if (-not $neu -or $neu -eq $g) { return }
    $anz = 0; foreach ($e in $eintraege) { if ($e.Gruppe -eq $g) { $e.Gruppe = $neu; $anz++ } }
    Aktualisiere-Gruppen; $fGruppe.Text = $neu; Fuelle-Liste $script:aktuellerIndex
    $meldung.ForeColor = [System.Drawing.Color]::DarkGreen
    $meldung.Text = ('' + $anz + ' Eintrag/Einträge auf ') + [char]8222 + $neu + [char]8220 + ' umbenannt. Mit Speichern sichern.'
}

Leistenknopf 'Gruppe löschen' 130 {
    $g = Aktuelle-Gruppe
    if (-not $g) { Keine-Gruppe; return }
    $betroffen = @($eintraege | Where-Object { $_.Gruppe -eq $g })
    $frage = 'Gruppe ' + [char]8222 + $g + [char]8220 + ' mit ' + $betroffen.Count + ' Eintrag/Einträgen löschen?'
    if ([System.Windows.Forms.MessageBox]::Show($frage, $script:TITEL, 'YesNo', 'Warning') -eq 'Yes') {
        for ($i = $eintraege.Count - 1; $i -ge 0; $i--) {
            if ($eintraege[$i].Gruppe -eq $g) { $eintraege.RemoveAt($i) }
        }
        $script:aktuellerIndex = -1
        Aktualisiere-Gruppen; Fuelle-Liste; $fName.Clear(); $fZiel.Clear()
        $meldung.ForeColor = [System.Drawing.Color]::DarkGreen
        $meldung.Text = 'Gruppe ' + [char]8222 + $g + [char]8220 + ' gelöscht. Mit Speichern sichern.'
    }
}

Leistenknopf 'Gruppe ▲' 92 { Verschiebe-Gruppe -1 }
Leistenknopf 'Gruppe ▼' 92 { Verschiebe-Gruppe 1 }

Leistenknopf 'Symbol wählen ...' 140 {
    # Die Galerie läuft als eigener Prozess und gibt ihr Ergebnis über
    # eine kleine Datei zurück - eine Variable kann sie nicht teilen.
    $galerieSkript = Join-Path $BASIS 'Symbolauswahl.ps1'
    $ablage = Join-Path $BASIS 'symbolauswahl.txt'
    if (-not (Test-Path $galerieSkript)) {
        $meldung.ForeColor = $FARBE_WARNUNG
        $meldung.Text = 'Symbolauswahl.ps1 fehlt neben diesem Skript.'
        return
    }
    if (Test-Path $ablage) { Remove-Item $ablage -Force }
    # ⚠️ NICHT das ganze Fenster sperren. Die Galerie braucht ein paar
    #    Sekunden bis sie sichtbar ist, und ein gesperrtes Fenster ohne
    #    sichtbaren Grund wirkt wie ein abgestürztes Programm. Es reicht,
    #    die Knopfleiste zu sperren.
    $meldung.ForeColor = [System.Drawing.Color]::DimGray
    $meldung.Text = 'Symbolgalerie wird geöffnet, das dauert einen Moment ...'
    $leiste.Enabled = $false
    $f.Cursor = [System.Windows.Forms.Cursors]::AppStarting
    $f.Refresh()
    try {
        $argumente = @('-NoProfile', '-ExecutionPolicy', 'Bypass',
                       '-File', ('"' + $galerieSkript + '"'))
        # Das bereits eingestellte Symbol mitgeben, damit die Galerie es
        # markiert öffnet statt bei Null anzufangen.
        if ($script:aktuellesSymbol) {
            $argumente += @('-Vorgabe', ('"' + $script:aktuellesSymbol + '"'))
        }
        Start-Process -FilePath 'powershell.exe' -Wait -ArgumentList $argumente
    } finally {
        $leiste.Enabled = $true
        $f.Cursor = [System.Windows.Forms.Cursors]::Default
        $f.Activate()
    }
    try {
        if (Test-Path $ablage) {
            $script:aktuellesSymbol = (Get-Content $ablage -Raw -Encoding UTF8).Trim()
            Remove-Item $ablage -Force
            Spur ('Symbol gewählt: ' + $script:aktuellesSymbol)
            Zeige-Vorschau $fZiel.Text $script:aktuellesSymbol

            # 🔴 Das Symbol SOFORT in den markierten Eintrag schreiben.
            #    Vorher landete es nur in einer Variablen und war weg, wenn
            #    jemand direkt auf Speichern ging statt auf Übernehmen -
            #    genau so ist es am 06.09. passiert, ohne jede Meldung.
            if ($script:aktuellerIndex -ge 0 -and $script:aktuellerIndex -lt $eintraege.Count) {
                $eintraege[$script:aktuellerIndex].Symbol = $script:aktuellesSymbol
                $merke = $script:aktuellerIndex
                Fuelle-Liste $merke
                $script:aktuellerIndex = $merke
                Spur ('  sofort übernommen für: ' + $eintraege[$merke].Name)
                $meldung.ForeColor = [System.Drawing.Color]::DarkGreen
                $meldung.Text = 'Symbol übernommen für „' + $eintraege[$merke].Name +
                                '". Mit Speichern sichern.'
            } else {
                $meldung.ForeColor = [System.Drawing.Color]::DarkGoldenrod
                $meldung.Text = 'Symbol gewählt. Es gilt für den nächsten Eintrag, den du hinzufügst.'
            }
        } else {
            Spur 'Symbolauswahl abgebrochen'
            $meldung.ForeColor = [System.Drawing.Color]::DimGray
            $meldung.Text = 'Symbolauswahl abgebrochen, nichts geändert.'
        }
    } catch {
        Spur ('nach der Galerie: ' + $_.Exception.Message)
        $meldung.ForeColor = $FARBE_WARNUNG
        $meldung.Text = 'Das Symbol liess sich nicht übernehmen: ' + $_.Exception.Message
    }
}

Leistenknopf 'Symbol zurücksetzen' 155 {
    $script:aktuellesSymbol = ''
    Zeige-Vorschau $fZiel.Text ''
    $meldung.ForeColor = [System.Drawing.Color]::DarkGreen
    $meldung.Text = 'Wieder das Standardsymbol des Dokuments.'
}

Leistenknopf 'Nach oben' 95 {
    $i = $script:aktuellerIndex
    if ($i -lt 1) { return }
    $e = $eintraege[$i]; $eintraege.RemoveAt($i); $eintraege.Insert($i - 1, $e)
    $script:aktuellerIndex = $i - 1
    Fuelle-Liste ($i - 1)
}

Leistenknopf 'Nach unten' 95 {
    $i = $script:aktuellerIndex
    if ($i -lt 0 -or $i -ge $eintraege.Count - 1) { return }
    $e = $eintraege[$i]; $eintraege.RemoveAt($i); $eintraege.Insert($i + 1, $e)
    $script:aktuellerIndex = $i + 1
    Fuelle-Liste ($i + 1)
}

Leistenknopf 'Textdatei öffnen' 130 { Start-Process notepad.exe $KONFIG }

Leistenknopf 'Speichern und schließen' 180 {
    # Vor dem Schreiben ALLE Zeilen prüfen, nicht nur die zuletzt bearbeitete.
    $probleme = @()
    for ($i = 0; $i -lt $eintraege.Count; $i++) {
        $pr = Pruefe $eintraege[$i].Name $eintraege[$i].Ziel $eintraege $i
        if ($pr -and -not $pr.StartsWith('HINWEIS')) { $probleme += ($eintraege[$i].Name + ': ' + $pr) }
    }
    if ($probleme.Count) {
        [System.Windows.Forms.MessageBox]::Show(
            ("So kann die Liste nicht gespeichert werden:`n`n" + ($probleme -join "`n")),
            $script:TITEL, 'OK', 'Warning') | Out-Null
        return
    }
    # ⚠️ Zwei offene Verwaltungsfenster überschreiben sich beim Speichern
    #    gegenseitig - der zuletzt Speichernde gewinnt, der andere Stand ist weg.
    $andere = @(Get-Process powershell -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -like '*Apprentice*' -and $_.Id -ne $PID })
    if ($andere.Count -gt 0) {
        $frage = 'Es ist noch ' + $andere.Count + ' weiteres Verwaltungsfenster offen.' + "`n`n" +
                 'Wenn dort auch gespeichert wird, überschreibt es diesen Stand.' + "`n" +
                 'Trotzdem speichern?'
        if ([System.Windows.Forms.MessageBox]::Show($frage, $script:TITEL, 'YesNo', 'Warning') -ne 'Yes') {
            Spur 'Speichern abgebrochen wegen zweitem Fenster'
            return
        }
    }
    # ⚠️ Wer im Formular etwas ändert und direkt auf Speichern geht, hat
    #    sonst umsonst getippt. Deshalb den markierten Eintrag vorher
    #    stillschweigend nachziehen - aber nur, wenn die Eingaben gültig sind.
    if ($script:aktuellerIndex -ge 0 -and $script:aktuellerIndex -lt $eintraege.Count) {
        $i = $script:aktuellerIndex
        $e = $eintraege[$i]
        $nameNeu = $fName.Text.Trim()
        $zielNeu = $fZiel.Text.Trim()
        $gruppeNeu = $fGruppe.Text.Trim()
        if ($nameNeu -and $zielNeu -and
            ($e.Name -ne $nameNeu -or $e.Ziel -ne $zielNeu -or
             $e.Gruppe -ne $gruppeNeu -or $e.Symbol -ne $script:aktuellesSymbol)) {
            $e.Name = $nameNeu
            $e.Ziel = $zielNeu
            $e.Gruppe = $gruppeNeu
            $e.Symbol = $script:aktuellesSymbol
            Spur ('  offene Änderung am Eintrag ' + $i + ' vor dem Speichern übernommen')
        }
    }
    $mitSymbol = @($eintraege | Where-Object { $_.Symbol }).Count
    Spur ('Speichern: ' + $eintraege.Count + ' Einträge, davon ' + $mitSymbol + ' mit eigenem Symbol')
    Schreib-Eintraege $eintraege
    Spur 'gespeichert'
    $f.Close()
}

Leistenknopf 'Abbrechen' 95 { $f.Close() }

# ─── Auswahl, Dateidialoge, Prüfung bei jeder Eingabe ────────────────
$knopfDatei.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Title = 'Welche Datei soll in den Schnellzugriff?'
    $d.Filter = 'Alle Dateien (*.*)|*.*'
    if ($d.ShowDialog() -eq 'OK') {
        $fZiel.Text = $d.FileName
        if (-not $fName.Text.Trim()) { $fName.Text = [IO.Path]::GetFileName($d.FileName) }
    }
})
$knopfOrdner.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Welcher Ordner soll in den Schnellzugriff?'
    if ($d.ShowDialog() -eq 'OK') {
        $fZiel.Text = $d.SelectedPath
        if (-not $fName.Text.Trim()) { $fName.Text = Split-Path $d.SelectedPath -Leaf }
    }
})

$fName.Add_TextChanged({ [void](Pruefe-Eingabe) })
$fZiel.Add_TextChanged({ [void](Pruefe-Eingabe); Zeige-Vorschau $fZiel.Text $script:aktuellesSymbol })

$liste.Add_SelectedIndexChanged({
    if ($liste.SelectedIndices.Count -eq 0) { $script:aktuellerIndex = -1; return }
    $i = $liste.SelectedIndices[0]
    $script:aktuellerIndex = $i
    $fGruppe.Text = $eintraege[$i].Gruppe
    $fName.Text = $eintraege[$i].Name
    $fZiel.Text = $eintraege[$i].Ziel
    $script:aktuellesSymbol = $eintraege[$i].Symbol
    Zeige-Vorschau $eintraege[$i].Ziel $eintraege[$i].Symbol
})

# ─── Sortieren mit gedrückter Maus ───────────────────────────────────
$script:gezogen = -1
$liste.Add_ItemDrag({
    if ($liste.SelectedIndices.Count -eq 0) { return }
    $script:gezogen = $liste.SelectedIndices[0]
    [void]$liste.DoDragDrop($liste.SelectedItems[0], [System.Windows.Forms.DragDropEffects]::Move)
})
$liste.Add_DragEnter({ $_.Effect = [System.Windows.Forms.DragDropEffects]::Move })
$liste.Add_DragOver({ $_.Effect = [System.Windows.Forms.DragDropEffects]::Move })
$liste.Add_DragDrop({
    if ($script:gezogen -lt 0) { return }
    $punkt = $liste.PointToClient((New-Object System.Drawing.Point($_.X, $_.Y)))
    $ziel = $liste.GetItemAt($punkt.X, $punkt.Y)
    $neuerPlatz = if ($ziel) { $ziel.Index } else { $eintraege.Count - 1 }
    if ($neuerPlatz -eq $script:gezogen) { $script:gezogen = -1; return }
    $e = $eintraege[$script:gezogen]
    $eintraege.RemoveAt($script:gezogen)
    if ($neuerPlatz -gt $eintraege.Count) { $neuerPlatz = $eintraege.Count }
    $eintraege.Insert($neuerPlatz, $e)
    # Gruppe des neuen Nachbarn übernehmen, sonst springt der Eintrag beim
    # Speichern optisch woanders hin.
    if ($neuerPlatz -gt 0) { $e.Gruppe = $eintraege[$neuerPlatz - 1].Gruppe }
    $script:gezogen = -1
    $script:aktuellerIndex = $neuerPlatz
    Fuelle-Liste $neuerPlatz
})

function Aktualisiere-Gruppen {
    $vorhanden = $fGruppe.Text
    $fGruppe.Items.Clear()
    foreach ($g in ($eintraege | Select-Object -ExpandProperty Gruppe -Unique)) {
        if ($g) { [void]$fGruppe.Items.Add($g) }
    }
    $fGruppe.Text = $vorhanden
}

Aktualisiere-Gruppen
Fuelle-Liste
Spur 'Fenster anzeigen'
$f.Add_Shown({
    Spur ('erschienen, Größe=' + $f.Size + ' Ort=' + $f.Location)
    $f.WindowState = 'Normal'
    $f.Activate()
})
# Wer schliesst das Fenster? CloseReason nennt den Verursacher.
$f.Add_FormClosing({
    Spur ('schliesst, Grund=' + $_.CloseReason + ' DialogResult=' + $f.DialogResult)
    Spur ('  Aufrufkette: ' + ((Get-PSCallStack | Select-Object -First 4 |
        ForEach-Object { $_.Command + ':' + $_.ScriptLineNumber }) -join ' < '))
})
# Unbehandelte Fehler in Ereignissen beenden sonst stumm die Schleife.
[System.Windows.Forms.Application]::add_ThreadException({
    param($absender, $daten)
    Spur ('THREAD-FEHLER: ' + $daten.Exception.Message)
})
[AppDomain]::CurrentDomain.add_UnhandledException({
    param($absender, $daten)
    Spur ('UNBEHANDELT: ' + $daten.ExceptionObject)
})
# DA-20260913-163439041-83d7: erst färben, dann zeigen --
# nach dem vollständigen Aufbau, damit jedes Bauteil steht.
QA-Dunkel $f

# Application::Run BRAUCHT das Formular als Argument.
[System.Windows.Forms.Application]::Run($f)
Spur 'geschlossen'
