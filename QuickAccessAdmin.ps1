# =====================================================================
#  Donkey's Apprentice - management window
#
#  Create, edit, reorder and delete entries and give them a custom icon.
#  The text file remains the authoritative format; this window is only a
#  convenient way to get there.
#
#  Traps that have already caught us here:
#  🔴 NO FIXED COORDINATES FOR BUTTONS. With fixed x values three
#     buttons ended up stacked on each other. A FlowLayoutPanel arranges
#     them by itself.
#  🔴 DO NOT START WITH -WindowStyle Hidden - that hides the form too.
#     The script hides the console itself.
#  🔴 Application::Run NEEDS THE FORM AS ITS ARGUMENT, otherwise the
#     loop ends at once and the window vanishes in the same moment.
#  🔴 StartPosition = CenterScreen ended up outside the visible area -
#     a fixed position is more reliable.
# =====================================================================
$ErrorActionPreference = 'Stop'

# With -File, PSScriptRoot is more reliable than MyInvocation.
$BASIS = $PSScriptRoot
if (-not $BASIS) { $BASIS = Split-Path -Parent $MyInvocation.MyCommand.Path }
# 🔴 No hard-coded user path as a fallback -- until 2026-09-13 it
#    carried the owner's profile name in the source (DA 2/9) and would
#    have been wrong on any other machine.
if (-not $BASIS) { $BASIS = Join-Path $env:LOCALAPPDATA 'QuickAccess' }
# Writing happens only under %LOCALAPPDATA% (DA-20260913-144004296-42e6).
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

# Hide only the console window, not the whole process.
Add-Type -Namespace QA -Name Fenster -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr handle, int zustand);
'@
$konsole = [QA.Fenster]::GetConsoleWindow()
if ($konsole -ne [IntPtr]::Zero) { [void][QA.Fenster]::ShowWindow($konsole, 0) }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# For the simple input box used when renaming a group.
Add-Type -AssemblyName Microsoft.VisualBasic

# ExtractAssociatedIcon cannot take an index and always returns only the
# first icon of a file. "shell32.dll,44" needs ExtractIconEx.
Add-Type -Namespace QA -Name Symbole -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern int ExtractIconExW(string datei, int index, out IntPtr gross, out IntPtr klein, int anzahl);
[DllImport("user32.dll")]
public static extern bool DestroyIcon(IntPtr handle);
'@

function Hol-Symbol($quelle, $index) {
    # Returns a bitmap or $null. The handle is always released.
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
#  Reading and writing
#  Format:  Name = Target                  (the document's own icon)
#           Name = Target | Source,Index   (custom icon)
# ---------------------------------------------------------------------
function Ist-Link($ziel) { return $ziel -match '^(https?|mailto|ftp)://|^mailto:' }

function Lies-Eintraege {
    $liste = New-Object System.Collections.ArrayList
    if (-not (Test-Path $KONFIG)) { return $liste }
    $gruppe = ''
    # ⚠️ Without -Encoding UTF8, PowerShell 5.1 reads the file as ANSI.
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
        # The vertical bar is forbidden in Windows paths, which is why it
        # works as the separator before the icon.
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
    [void]$text.AppendLine('# ' + $script:TITEL + ' - name = target')
    [void]$text.AppendLine('#   [Group] makes a heading')
    [void]$text.AppendLine('#   the target may be a file, a folder or a link')
    [void]$text.AppendLine('#   own icon after it:        ... | source.dll,5')
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
    # ⚠️ UTF-8 WITH a byte order mark, otherwise non-ASCII comes back wrong.
    [IO.File]::WriteAllText($KONFIG, $text.ToString(), (New-Object Text.UTF8Encoding $true))
}

# ---------------------------------------------------------------------
#  Validation of one line. Returns: a message or $null.
# ---------------------------------------------------------------------
function Pruefe($name, $ziel, $liste, $ausser = -1) {
    if (-not $name -or -not $name.Trim()) { return 'The name must not be empty.' }
    if (-not $ziel -or -not $ziel.Trim()) { return 'The target must not be empty.' }
    if ($name -match '^\s*\[') { return 'The name must not start with a square bracket - that marks a group.' }
    if ($name.Contains('=')) { return 'The name must not contain an equals sign - the line is split on it.' }
    if ($name.Contains('|')) { return 'The name must not contain a vertical bar - that separates the icon.' }
    if (Ist-Link $ziel) {
        if ($ziel -notmatch '^(https?://[^\s/]+|mailto:[^\s@]+@[^\s@]+|ftp://[^\s/]+)') {
            return 'The address looks incomplete; something like http://host:port is expected'
        }
    } else {
        if ($ziel -match '[<>|?*]') { return 'The path contains characters Windows does not allow.' }
        if (-not (Test-Path -LiteralPath $ziel)) {
            return 'NOTE: the target is not reachable right now. For network drives that is fine.'
        }
    }
    for ($i = 0; $i -lt $liste.Count; $i++) {
        if ($i -eq $ausser) { continue }
        if ($liste[$i].Name -eq $name.Trim()) { return 'An entry with this name already exists.' }
    }
    return $null
}

# 🔴 PowerShell unrolls an ArrayList returned from a function into a
#    FIXED object[] - after that .Add()/.Clear()/.RemoveAt() throw
#    "Collection was of a fixed size". So wrap it back into a real
#    ArrayList here, otherwise adding, deleting and the group buttons
#    are unreliable.
$eintraege = [System.Collections.ArrayList]@(Lies-Eintraege)
Spur ('entries: ' + $eintraege.Count)

# ---------------------------------------------------------------------
#  Fenster
# ---------------------------------------------------------------------
. "$PSScriptRoot\QA-Stil.ps1"   # DA-20260913-163439041-83d7: eine Stilquelle
$f = New-Object System.Windows.Forms.Form
$f.Text = $script:TITEL + ' - management'
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
[void]$liste.Columns.Add('Group', 120)
[void]$liste.Columns.Add('Name', 205)
[void]$liste.Columns.Add('Target', 395)
[void]$liste.Columns.Add('state', 70)
[void]$liste.Columns.Add('Symbol', 165)
$f.Controls.Add($liste)

# DA-20260914-093332250-030d: how do you tell why an icon is missing?
# Until today you could not -- the reason sat in the file system as an
# empty file.
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
        return ('none since ' + $v.LastWriteTime.ToString('dd.MM. HH:mm') +
                $(if ($wieoft -gt 1) { ' (' + $wieoft + 'x)' } else { '' }))
    }
    return 'not fetched yet'
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
            [void]$zeile.SubItems.Add($(if ((Get-Item -LiteralPath $e.Ziel).PSIsContainer) { 'Folder' } else { 'File' }))
        } else {
            [void]$zeile.SubItems.Add('missing')
            $zeile.ForeColor = $FARBE_WARNUNG
        }
        # DA-20260914-093332250-030d: if a custom icon is set, it wins.
        # Otherwise the column shows what is going on with the favicon --
        # instead of a blanket "(default)", which hid three different
        # states: fetched, never attempted, and failed with a date.
        if ($e.Symbol) {
            [void]$zeile.SubItems.Add([IO.Path]::GetFileName(($e.Symbol -split ',')[0]))
        } else {
            $zustand = QA-SymbolZustand $e.Ziel
            if (-not $zustand) { $zustand = '(default)' }
            [void]$zeile.SubItems.Add($zustand)
            if ($zustand -like 'none since*') { $zeile.ForeColor = $FARBE_WARNUNG }
        }
        [void]$liste.Items.Add($zeile)
    }
    $liste.EndUpdate()
    if ($auswahl -ge 0 -and $auswahl -lt $liste.Items.Count) {
        $liste.Items[$auswahl].Selected = $true
        $liste.Items[$auswahl].EnsureVisible()
    }
}

# ─── Input fields ─────────────────────────────────────────────────────
function Beschriftung($text, $x, $y, $breite) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($breite, 18)
    $l.Anchor = 'Left,Bottom'
    $f.Controls.Add($l)
}
Beschriftung 'Group' 12 374 120
Beschriftung 'Name' 140 374 210
Beschriftung 'Target (file, folder or link)' 356 374 380

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
$knopfDatei.Text = 'File ...'
$knopfDatei.Location = New-Object System.Drawing.Point(812, 393)
$knopfDatei.Size = New-Object System.Drawing.Size(86, 26)
$knopfDatei.Anchor = 'Right,Bottom'
$f.Controls.Add($knopfDatei)

$knopfOrdner = New-Object System.Windows.Forms.Button
$knopfOrdner.Text = 'Folder ...'
$knopfOrdner.Location = New-Object System.Drawing.Point(904, 393)
$knopfOrdner.Size = New-Object System.Drawing.Size(88, 26)
$knopfOrdner.Anchor = 'Right,Bottom'
$f.Controls.Add($knopfOrdner)

# ─── Icon area ────────────────────────────────────────────────────────
$symbolFeld = New-Object System.Windows.Forms.GroupBox
$symbolFeld.Text = 'Icon for this entry'
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
$symbolText.Text = '(the document default)'
$symbolText.Location = New-Object System.Drawing.Point(56, 32)
$symbolText.Size = New-Object System.Drawing.Size(262, 18)
$symbolText.ForeColor = [System.Drawing.Color]::DimGray
$symbolFeld.Controls.Add($symbolText)

$script:aktuellesSymbol = ''

function Zeige-Vorschau($ziel, $symbol) {
    # Always show what actually applies: the custom icon, otherwise the document's.
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
                # Do NOT use ExtractAssociatedIcon here - it would always
                # show icon 0 instead of the chosen one.
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
    } catch { Spur ('preview: ' + $_.Exception.Message) }
    # 🔴 THIS NEEDS A try AS WELL. GetFileName throws on invalid
    #    characters in a path, and an exception from an event handler ends
    #    the entire message loop under ErrorActionPreference=Stop - the
    #    window is then simply gone, without a message.
    try {
        $vorschau.Image = $bild
        if ($symbol) {
            $teile = $symbol -split ','
            $roh = $teile[0].Trim('"').Trim()
            $t = $roh
            try { $t = [IO.Path]::GetFileName($roh) } catch { }
            if ($teile.Count -gt 1) { $t = $t + ', Nummer ' + $teile[1].Trim() }
            $symbolText.Text = $t
        } else { $symbolText.Text = '(the document default)' }
    } catch { Spur ('show preview: ' + $_.Exception.Message) }
}

$meldung = New-Object System.Windows.Forms.Label
$meldung.Location = New-Object System.Drawing.Point(356, 436)
$meldung.Size = New-Object System.Drawing.Size(636, 50)
$meldung.Anchor = 'Left,Right,Bottom'
$meldung.ForeColor = $FARBE_WARNUNG
$f.Controls.Add($meldung)

# ─── Button bar: arranges itself, cannot overlap ──────────────────────
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
        $meldung.ForeColor = if ($fehler.StartsWith('NOTE')) {
            [System.Drawing.Color]::DarkGoldenrod } else { $FARBE_WARNUNG }
        # A hint does not block - a network drive is allowed to be away.
        return $fehler.StartsWith('NOTE')
    }
    $meldung.Text = ''
    return $true
}

Leistenknopf 'Add' 105 {
    Spur ('Add pressed: name=[' + $fName.Text + '] target=[' + $fZiel.Text +
          '] icon=[' + $script:aktuellesSymbol + ']')
    if (-not (Pruefe-Eingabe)) { Spur ('  rejected: ' + $meldung.Text); return }
    [void]$eintraege.Add([PSCustomObject]@{
        Gruppe = $fGruppe.Text.Trim(); Name = $fName.Text.Trim()
        Ziel = $fZiel.Text.Trim(); Symbol = $script:aktuellesSymbol })
    Aktualisiere-Gruppen
    Fuelle-Liste ($eintraege.Count - 1)
    $fName.Clear(); $fZiel.Clear()
    $script:aktuellesSymbol = ''
    Zeige-Vorschau '' ''
}

Leistenknopf 'Apply' 105 {
    Spur ('Apply pressed: index=' + $script:aktuellerIndex +
          ' Name=[' + $fName.Text + '] icon=[' + $script:aktuellesSymbol + ']')
    # 🔴 Tim, 09-07: "DA cannot save a new entry, all fields filled in,
    #    still says 'select an entry in the list first'".
    #    Someone who fills in the fields and presses Apply wants to save -
    #    whether the row already exists or is new is not their concern.
    #    With no selection a new entry is now created, instead of showing
    #    a message that helps nobody.
    if ($script:aktuellerIndex -lt 0) {
        if (-not (Pruefe-Eingabe)) { Spur ('  rejected: ' + $meldung.Text); return }
        [void]$eintraege.Add([PSCustomObject]@{
            Gruppe = $fGruppe.Text.Trim(); Name = $fName.Text.Trim()
            Ziel = $fZiel.Text.Trim(); Symbol = $script:aktuellesSymbol })
        Aktualisiere-Gruppen
        Fuelle-Liste ($eintraege.Count - 1)
        $meldung.ForeColor = [System.Drawing.Color]::DarkGreen
        $meldung.Text = 'New entry created.'
        Spur '  nothing selected -> new entry created'
        return
    }
    if (-not (Pruefe-Eingabe)) { Spur ('  rejected: ' + $meldung.Text); return }
    $i = $script:aktuellerIndex
    $eintraege[$i].Gruppe = $fGruppe.Text.Trim()
    $eintraege[$i].Name = $fName.Text.Trim()
    $eintraege[$i].Ziel = $fZiel.Text.Trim()
    $eintraege[$i].Symbol = $script:aktuellesSymbol
    Aktualisiere-Gruppen
    Fuelle-Liste $i
}

Leistenknopf 'Delete' 88 {
    if ($script:aktuellerIndex -lt 0) { $meldung.Text = 'Select an entry first.'; return }
    $e = $eintraege[$script:aktuellerIndex]
    $frage = 'Remove the entry ' + [char]8222 + $e.Name + [char]8220 + '?'
    if ([System.Windows.Forms.MessageBox]::Show($frage, $script:TITEL, 'YesNo', 'Question') -eq 'Yes') {
        $i = $script:aktuellerIndex
        $eintraege.RemoveAt($i)
        $script:aktuellerIndex = -1
        Fuelle-Liste ([Math]::Min($i, $eintraege.Count - 1))
        $fName.Clear(); $fZiel.Clear()
    }
}

# ─── Group management (Tim, 09-07: create/rename/delete) ──────────────
# A new group is created by typing into the "Gruppe" field when adding.
# Renaming and deleting affect ALL entries of the group at once; up/down
# moves the whole group block (= tab order in the overlay). Nothing is
# persisted until "Speichern und schliessen".
function Aktuelle-Gruppe {
    if ($script:aktuellerIndex -ge 0 -and $script:aktuellerIndex -lt $eintraege.Count) {
        return $eintraege[$script:aktuellerIndex].Gruppe
    }
    return $fGruppe.Text.Trim()
}
function Keine-Gruppe {
    $meldung.ForeColor = $FARBE_WARNUNG
    $meldung.Text = 'Select a group first (click an entry, or type a group into the field).'
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
    $meldung.Text = 'Group ' + [char]8222 + $g + [char]8220 + ' moved. Use Save to keep it.'
}

Leistenknopf 'Rename group' 150 {
    $g = Aktuelle-Gruppe
    if (-not $g) { Keine-Gruppe; return }
    $neu = ([Microsoft.VisualBasic.Interaction]::InputBox(
        'Group ' + [char]8222 + $g + [char]8220 + ' rename to:', $script:TITEL, $g)).Trim()
    if (-not $neu -or $neu -eq $g) { return }
    $anz = 0; foreach ($e in $eintraege) { if ($e.Gruppe -eq $g) { $e.Gruppe = $neu; $anz++ } }
    Aktualisiere-Gruppen; $fGruppe.Text = $neu; Fuelle-Liste $script:aktuellerIndex
    $meldung.ForeColor = [System.Drawing.Color]::DarkGreen
    $meldung.Text = ('' + $anz + ' entry/entries to ') + [char]8222 + $neu + [char]8220 + ' renamed. Use Save to keep it.'
}

Leistenknopf 'Delete group' 130 {
    $g = Aktuelle-Gruppe
    if (-not $g) { Keine-Gruppe; return }
    $betroffen = @($eintraege | Where-Object { $_.Gruppe -eq $g })
    $frage = 'Group ' + [char]8222 + $g + [char]8220 + ' mit ' + $betroffen.Count + ' entry/entries?'
    if ([System.Windows.Forms.MessageBox]::Show($frage, $script:TITEL, 'YesNo', 'Warning') -eq 'Yes') {
        for ($i = $eintraege.Count - 1; $i -ge 0; $i--) {
            if ($eintraege[$i].Gruppe -eq $g) { $eintraege.RemoveAt($i) }
        }
        $script:aktuellerIndex = -1
        Aktualisiere-Gruppen; Fuelle-Liste; $fName.Clear(); $fZiel.Clear()
        $meldung.ForeColor = [System.Drawing.Color]::DarkGreen
        $meldung.Text = 'Group ' + [char]8222 + $g + [char]8220 + ' deleted. Use Save to keep it.'
    }
}

Leistenknopf 'Group ▲' 92 { Verschiebe-Gruppe -1 }
Leistenknopf 'Group ▼' 92 { Verschiebe-Gruppe 1 }

Leistenknopf 'Choose icon ...' 140 {
    # The gallery runs as its own process and returns its result through
    # a small file - it cannot share a variable.
    $galerieSkript = Join-Path $BASIS 'Symbolauswahl.ps1'
    $ablage = Join-Path $BASIS 'symbolauswahl.txt'
    if (-not (Test-Path $galerieSkript)) {
        $meldung.ForeColor = $FARBE_WARNUNG
        $meldung.Text = 'Symbolauswahl.ps1 is missing next to this script.'
        return
    }
    if (Test-Path $ablage) { Remove-Item $ablage -Force }
    # ⚠️ Do NOT disable the whole window. The gallery takes a few
    #    seconds to become visible, and a disabled window with no visible
    #    reason looks like a crashed program. Disabling the button bar is
    #    enough.
    $meldung.ForeColor = [System.Drawing.Color]::DimGray
    $meldung.Text = 'Opening the icon gallery, this takes a moment ...'
    $leiste.Enabled = $false
    $f.Cursor = [System.Windows.Forms.Cursors]::AppStarting
    $f.Refresh()
    try {
        $argumente = @('-NoProfile', '-ExecutionPolicy', 'Bypass',
                       '-File', ('"' + $galerieSkript + '"'))
        # Pass in the icon already configured so the gallery opens with it
        # selected instead of starting from scratch.
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
            Spur ('icon chosen: ' + $script:aktuellesSymbol)
            Zeige-Vorschau $fZiel.Text $script:aktuellesSymbol

            # 🔴 Write the icon into the selected entry IMMEDIATELY.
            #    It used to land only in a variable and was lost when
            #    someone went straight to Save instead of Apply - which is
            #    exactly what happened on 09-06, without any message.
            if ($script:aktuellerIndex -ge 0 -and $script:aktuellerIndex -lt $eintraege.Count) {
                $eintraege[$script:aktuellerIndex].Symbol = $script:aktuellesSymbol
                $merke = $script:aktuellerIndex
                Fuelle-Liste $merke
                $script:aktuellerIndex = $merke
                Spur ('  applied straight away to: ' + $eintraege[$merke].Name)
                $meldung.ForeColor = [System.Drawing.Color]::DarkGreen
                $meldung.Text = 'Icon applied to “' + $eintraege[$merke].Name +
                                '". Use Save to keep it.'
            } else {
                $meldung.ForeColor = [System.Drawing.Color]::DarkGoldenrod
                $meldung.Text = 'Icon chosen. It applies to the next entry you add.'
            }
        } else {
            Spur 'icon selection cancelled'
            $meldung.ForeColor = [System.Drawing.Color]::DimGray
            $meldung.Text = 'Icon selection cancelled, nothing changed.'
        }
    } catch {
        Spur ('after the gallery: ' + $_.Exception.Message)
        $meldung.ForeColor = $FARBE_WARNUNG
        $meldung.Text = 'The icon could not be applied: ' + $_.Exception.Message
    }
}

Leistenknopf 'Reset icon' 155 {
    $script:aktuellesSymbol = ''
    Zeige-Vorschau $fZiel.Text ''
    $meldung.ForeColor = [System.Drawing.Color]::DarkGreen
    $meldung.Text = 'Back to the default icon of the document.'
}

Leistenknopf 'Move up' 95 {
    $i = $script:aktuellerIndex
    if ($i -lt 1) { return }
    $e = $eintraege[$i]; $eintraege.RemoveAt($i); $eintraege.Insert($i - 1, $e)
    $script:aktuellerIndex = $i - 1
    Fuelle-Liste ($i - 1)
}

Leistenknopf 'Move down' 95 {
    $i = $script:aktuellerIndex
    if ($i -lt 0 -or $i -ge $eintraege.Count - 1) { return }
    $e = $eintraege[$i]; $eintraege.RemoveAt($i); $eintraege.Insert($i + 1, $e)
    $script:aktuellerIndex = $i + 1
    Fuelle-Liste ($i + 1)
}

Leistenknopf 'Open text file' 130 { Start-Process notepad.exe $KONFIG }

Leistenknopf 'Save and close' 180 {
    # Validate ALL rows before writing, not just the last one edited.
    $probleme = @()
    for ($i = 0; $i -lt $eintraege.Count; $i++) {
        $pr = Pruefe $eintraege[$i].Name $eintraege[$i].Ziel $eintraege $i
        if ($pr -and -not $pr.StartsWith('NOTE')) { $probleme += ($eintraege[$i].Name + ': ' + $pr) }
    }
    if ($probleme.Count) {
        [System.Windows.Forms.MessageBox]::Show(
            ("The list cannot be saved like this:`n`n" + ($probleme -join "`n")),
            $script:TITEL, 'OK', 'Warning') | Out-Null
        return
    }
    # ⚠️ Two open management windows overwrite each other on save -
    #    the last one to save wins, the other state is gone.
    $andere = @(Get-Process powershell -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -like '*Apprentice*' -and $_.Id -ne $PID })
    if ($andere.Count -gt 0) {
        $frage = 'There is still ' + $andere.Count + ' other management window open.' + "`n`n" +
                 'If it saves too, it will overwrite this state.' + "`n" +
                 'Save anyway?'
        if ([System.Windows.Forms.MessageBox]::Show($frage, $script:TITEL, 'YesNo', 'Warning') -ne 'Yes') {
            Spur 'save cancelled because of a second window'
            return
        }
    }
    # ⚠️ Anyone who edits the form and goes straight to Save would
    #    otherwise have typed in vain. So quietly commit the selected entry
    #    first - but only if the input is valid.
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
            Spur ('  pending change to entry ' + $i + ' applied before saving')
        }
    }
    $mitSymbol = @($eintraege | Where-Object { $_.Symbol }).Count
    Spur ('saving: ' + $eintraege.Count + ' entries, of which ' + $mitSymbol + ' have their own icon')
    Schreib-Eintraege $eintraege
    Spur 'saved'
    $f.Close()
}

Leistenknopf 'Cancel' 95 { $f.Close() }

# ─── Selection, file dialogs, validation on every keystroke ───────────
$knopfDatei.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Title = 'Which file should go into the quick access list?'
    $d.Filter = 'All files (*.*)|*.*'
    if ($d.ShowDialog() -eq 'OK') {
        $fZiel.Text = $d.FileName
        if (-not $fName.Text.Trim()) { $fName.Text = [IO.Path]::GetFileName($d.FileName) }
    }
})
$knopfOrdner.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Which folder should go into the quick access list?'
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

# ─── Drag-and-drop reordering ─────────────────────────────────────────
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
    # Adopt the new neighbour's group, otherwise the entry visually jumps
    # somewhere else on save.
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
Spur 'show window'
$f.Add_Shown({
    Spur ('appeared, size=' + $f.Size + ' location=' + $f.Location)
    $f.WindowState = 'Normal'
    $f.Activate()
})
# Who is closing the window? CloseReason names the cause.
$f.Add_FormClosing({
    Spur ('closing, reason=' + $_.CloseReason + ' DialogResult=' + $f.DialogResult)
    Spur ('  call stack: ' + ((Get-PSCallStack | Select-Object -First 4 |
        ForEach-Object { $_.Command + ':' + $_.ScriptLineNumber }) -join ' < '))
})
# Unhandled errors in events would otherwise end the loop silently.
[System.Windows.Forms.Application]::add_ThreadException({
    param($absender, $daten)
    Spur ('THREAD ERROR: ' + $daten.Exception.Message)
})
[AppDomain]::CurrentDomain.add_UnhandledException({
    param($absender, $daten)
    Spur ('UNHANDLED: ' + $daten.ExceptionObject)
})
# DA-20260913-163439041-83d7: colour first, then show -- after the layout
# is complete, so every control is in place.
QA-Dunkel $f

# Application::Run NEEDS the form as its argument.
[System.Windows.Forms.Application]::Run($f)
Spur 'closed'
