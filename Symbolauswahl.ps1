# =====================================================================
#  Symbolgalerie - aus den Windows-Standardsymbolen wählen
#
#  Tim, 04.09.2026: „lass mich aus den typischen windows symbolen wählen"
#
#  Zeigt die Symbole der üblichen Windows-Bibliotheken als Kacheln. Ein
#  Doppelklick übernimmt Quelle und Nummer.
#
#  🔴 ExtractAssociatedIcon KANN KEINEN INDEX und liefert immer nur das
#     erste Symbol einer Datei. Für eine Galerie braucht es ExtractIconEx,
#     das gezielt das n-te Symbol holt.
#  🔴 ZWEI ÜBERLADUNGEN MIT GLEICHER ARGUMENTZAHL KANN POWERSHELL NICHT
#     AUSEINANDERHALTEN: "Es wurden mehrere nicht eindeutige Überladungen
#     gefunden". Deshalb zwei eigene Namen, beide über EntryPoint auf
#     dieselbe Windows-Funktion gelegt.
#  ⚠️ Jedes Handle muss mit DestroyIcon freigegeben werden. Bei 300 Symbolen
#     je Bibliothek summiert sich das sonst zu einem echten Leck.
# =====================================================================
param([string]$Vorgabe = '')   # bereits eingestelltes Symbol als "quelle,index"
$ErrorActionPreference = 'Stop'

function Spur($text) {
    try {
        # Protokoll unter %LOCALAPPDATA%, nicht neben dem Skript
        # (DA-20260913-144004296-42e6).
        Add-Content -Path (Join-Path (Join-Path $env:LOCALAPPDATA 'QuickAccess') 'galerie.log') -Encoding UTF8 -Value (
            (Get-Date).ToString('HH:mm:ss.fff') + '  ' + $text)
    } catch { }
}
Spur ('Start, Vorgabe=[' + $Vorgabe + ']')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -Namespace QAG -Name Shell -MemberDefinition @'
[DllImport("shell32.dll", EntryPoint = "ExtractIconExW", CharSet = CharSet.Unicode)]
public static extern int HolSymbol(string datei, int index, out IntPtr gross, out IntPtr klein, int anzahl);
[DllImport("shell32.dll", EntryPoint = "ExtractIconExW", CharSet = CharSet.Unicode)]
public static extern int ZaehleSymbole(string datei, int index, IntPtr gross, IntPtr klein, int anzahl);
[DllImport("user32.dll")]
public static extern bool DestroyIcon(IntPtr handle);
'@

$SYS = Join-Path $env:SystemRoot 'System32'
# Die Bibliotheken, in denen die bekannten Windows-Symbole stecken.
$QUELLEN = [ordered]@{
    'Allgemein (shell32)'      = Join-Path $SYS 'shell32.dll'
    'Modern (imageres)'        = Join-Path $SYS 'imageres.dll'
    'Geräte und Ordner (ddores)' = Join-Path $SYS 'ddores.dll'
    'Systemsteuerung'          = Join-Path $SYS 'setupapi.dll'
    'Netzwerk'                 = Join-Path $SYS 'netshell.dll'
    'Explorer'                 = Join-Path $env:SystemRoot 'explorer.exe'
}

. "$PSScriptRoot\QA-Stil.ps1"   # DA-20260913-163439041-83d7: eine Stilquelle
$f = New-Object System.Windows.Forms.Form
$f.Text = 'Symbol auswählen'
$f.Size = New-Object System.Drawing.Size(880, 640)
$f.StartPosition = 'Manual'
$f.Location = New-Object System.Drawing.Point(220, 120)
$f.MinimumSize = New-Object System.Drawing.Size(600, 450)
$eigenes = Join-Path $PSScriptRoot 'esel.ico'
if ($eigenes -and (Test-Path $eigenes)) { $f.Icon = New-Object System.Drawing.Icon($eigenes) }

$oben = New-Object System.Windows.Forms.Panel
$oben.Dock = 'Top'
$oben.Height = 46
$f.Controls.Add($oben)

$l = New-Object System.Windows.Forms.Label
$l.Text = 'Sammlung'
$l.Location = New-Object System.Drawing.Point(12, 15)
$l.Size = New-Object System.Drawing.Size(70, 20)
$oben.Controls.Add($l)

$auswahlQuelle = New-Object System.Windows.Forms.ComboBox
$auswahlQuelle.DropDownStyle = 'DropDownList'
$auswahlQuelle.Location = New-Object System.Drawing.Point(84, 12)
$auswahlQuelle.Size = New-Object System.Drawing.Size(260, 24)
foreach ($name in $QUELLEN.Keys) {
    if (Test-Path $QUELLEN[$name]) { [void]$auswahlQuelle.Items.Add($name) }
}
$oben.Controls.Add($auswahlQuelle)

$eigeneDatei = New-Object System.Windows.Forms.Button
$eigeneDatei.Text = 'Andere Datei ...'
$eigeneDatei.Location = New-Object System.Drawing.Point(356, 11)
$eigeneDatei.Size = New-Object System.Drawing.Size(130, 26)
$oben.Controls.Add($eigeneDatei)

$hinweis = New-Object System.Windows.Forms.Label
$hinweis.Text = 'Doppelklick übernimmt das Symbol'
$hinweis.Location = New-Object System.Drawing.Point(500, 15)
$hinweis.Size = New-Object System.Drawing.Size(280, 20)
$hinweis.ForeColor = [System.Drawing.Color]::DimGray
$oben.Controls.Add($hinweis)

$unten = New-Object System.Windows.Forms.Panel
$unten.Dock = 'Bottom'
$unten.Height = 52
$f.Controls.Add($unten)

$gewaehlt = New-Object System.Windows.Forms.Label
$gewaehlt.Text = 'nichts gewählt'
$gewaehlt.Location = New-Object System.Drawing.Point(12, 16)
$gewaehlt.Size = New-Object System.Drawing.Size(560, 20)
$unten.Controls.Add($gewaehlt)

$knopfOk = New-Object System.Windows.Forms.Button
$knopfOk.Text = 'Übernehmen'
$knopfOk.Size = New-Object System.Drawing.Size(120, 30)
$knopfOk.Anchor = 'Right,Top'
$knopfOk.Enabled = $false
$unten.Controls.Add($knopfOk)

$knopfAbbruch = New-Object System.Windows.Forms.Button
$knopfAbbruch.Text = 'Abbrechen'
$knopfAbbruch.Size = New-Object System.Drawing.Size(100, 30)
$knopfAbbruch.Anchor = 'Right,Top'
$unten.Controls.Add($knopfAbbruch)

function Ordne-Knoepfe {
    $knopfOk.Location = New-Object System.Drawing.Point(($unten.Width - 240), 10)
    $knopfAbbruch.Location = New-Object System.Drawing.Point(($unten.Width - 112), 10)
}
Ordne-Knoepfe
$unten.Add_Resize({ Ordne-Knoepfe })

$galerie = New-Object System.Windows.Forms.ListView
$galerie.Dock = 'Fill'
$galerie.View = 'LargeIcon'
$galerie.MultiSelect = $false
$f.Controls.Add($galerie)
$galerie.BringToFront()

$bilder = New-Object System.Windows.Forms.ImageList
$bilder.ImageSize = New-Object System.Drawing.Size(32, 32)
$bilder.ColorDepth = 'Depth32Bit'
$galerie.LargeImageList = $bilder

$script:aktuelleQuelle = ''
$script:ergebnis = ''

function Lade-Galerie($pfad) {
    if (-not (Test-Path -LiteralPath $pfad)) { return }
    $f.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $galerie.BeginUpdate()
    $galerie.Items.Clear()
    $bilder.Images.Clear()
    # Erst zählen, wie viele Symbole drinstecken.
    $anzahl = [QAG.Shell]::ZaehleSymbole($pfad, -1, [IntPtr]::Zero, [IntPtr]::Zero, 0)
    # ⚠️ Deckel bei 400: manche Bibliotheken enthalten Hunderte, und jedes
    #    einzeln zu laden dauert sonst spürbar.
    if ($anzahl -gt 400) { $anzahl = 400 }
    for ($i = 0; $i -lt $anzahl; $i++) {
        $gross = [IntPtr]::Zero; $klein = [IntPtr]::Zero
        try {
            $n = [QAG.Shell]::HolSymbol($pfad, $i, [ref]$gross, [ref]$klein, 1)
            if ($n -gt 0 -and $gross -ne [IntPtr]::Zero) {
                $symbol = [System.Drawing.Icon]::FromHandle($gross)
                $bilder.Images.Add($symbol.ToBitmap())
                $eintrag = New-Object System.Windows.Forms.ListViewItem("$i")
                $eintrag.ImageIndex = $bilder.Images.Count - 1
                $eintrag.Tag = $i
                [void]$galerie.Items.Add($eintrag)
            }
        } catch { }
        finally {
            # Jedes Handle wieder freigeben - sonst leckt es bei Hunderten.
            if ($gross -ne [IntPtr]::Zero) { [void][QAG.Shell]::DestroyIcon($gross) }
            if ($klein -ne [IntPtr]::Zero) { [void][QAG.Shell]::DestroyIcon($klein) }
        }
    }
    $galerie.EndUpdate()
    $f.Cursor = [System.Windows.Forms.Cursors]::Default
    $script:aktuelleQuelle = $pfad
    $hinweis.Text = "$($galerie.Items.Count) Symbole - Doppelklick übernimmt"
    Spur ('geladen: ' + $galerie.Items.Count + ' Symbole aus ' + (Split-Path $pfad -Leaf))
}

$auswahlQuelle.Add_SelectedIndexChanged({
    $name = $auswahlQuelle.SelectedItem
    if ($name) { Lade-Galerie $QUELLEN[$name] }
})

$eigeneDatei.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Title = 'Aus welcher Datei sollen die Symbole kommen?'
    $d.Filter = 'Symbolquellen (*.dll;*.exe;*.ico)|*.dll;*.exe;*.ico|Alle Dateien (*.*)|*.*'
    $d.InitialDirectory = $SYS
    if ($d.ShowDialog() -eq 'OK') { Lade-Galerie $d.FileName }
})

function Merke-Auswahl {
    if ($galerie.SelectedItems.Count -eq 0) { Spur 'Merke-Auswahl: nichts markiert'; return }
    $index = $galerie.SelectedItems[0].Tag
    $script:ergebnis = $script:aktuelleQuelle + ',' + $index
    $gewaehlt.Text = 'Gewählt: ' + [IO.Path]::GetFileName($script:aktuelleQuelle) + ', Nummer ' + $index
    $knopfOk.Enabled = $true
    Spur ('gemerkt: ' + $script:ergebnis)
}
$galerie.Add_SelectedIndexChanged({ Merke-Auswahl })
$galerie.Add_DoubleClick({
    Merke-Auswahl
    if ($script:ergebnis) { $f.DialogResult = 'OK'; $f.Close() }
})
$knopfOk.Add_Click({ $f.DialogResult = 'OK'; $f.Close() })
$knopfAbbruch.Add_Click({ $script:ergebnis = ''; $f.DialogResult = 'Cancel'; $f.Close() })

# Eingabetaste übernimmt, Esc bricht ab.
$f.AcceptButton = $knopfOk
$f.CancelButton = $knopfAbbruch

function Erstauswahl {
# Bereits eingestelltes Symbol vorwaehlen, damit sichtbar ist, was gilt.
$vorgewaehlt = $false
if ($Vorgabe) {
    $teile = $Vorgabe -split ','
    $vQuelle = $teile[0].Trim('"').Trim()
    $vIndex = 0
    if ($teile.Count -gt 1) { [void][int]::TryParse($teile[1].Trim(), [ref]$vIndex) }
    if ($vQuelle -and -not (Test-Path -LiteralPath $vQuelle)) {
        $imSystem = Join-Path $SYS $vQuelle
        if (Test-Path -LiteralPath $imSystem) { $vQuelle = $imSystem }
    }
    if ($vQuelle -and (Test-Path -LiteralPath $vQuelle)) {
        # Steht die Quelle in der Aufklappliste? Sonst als eigene Datei laden.
        $treffer = ''
        foreach ($name in $QUELLEN.Keys) {
            if ($QUELLEN[$name] -eq $vQuelle) { $treffer = $name; break }
        }
        if ($treffer -and $auswahlQuelle.Items.Contains($treffer)) {
            $auswahlQuelle.SelectedItem = $treffer      # loest das Laden aus
        } else {
            Lade-Galerie $vQuelle
        }
        foreach ($eintrag in $galerie.Items) {
            if ([int]$eintrag.Tag -eq $vIndex) {
                $eintrag.Selected = $true
                $galerie.EnsureVisible($eintrag.Index)
                $vorgewaehlt = $true
                break
            }
        }
    }
}
if (-not $vorgewaehlt -and $auswahlQuelle.Items.Count -gt 0 -and $galerie.Items.Count -eq 0) {
    $auswahlQuelle.SelectedIndex = 0
}
}

# 🔴 ERST ZEIGEN, DANN LADEN. Vorher lief das Laden von 335 Symbolen
#    noch vor ShowDialog - das Fenster erschien mehrere Sekunden spaeter,
#    waehrend die Verwaltung schon gesperrt war. Von aussen sah das aus
#    wie ein haengendes Programm.
$f.Add_Shown({
    $f.Activate()
    # Ein frisch gestarteter Prozess landet sonst hinter dem Fenster, das
    # ihn gestartet hat. Kurz nach vorne holen, dann wieder freigeben.
    $f.TopMost = $true
    $f.TopMost = $false
    $hinweis.Text = 'lade Symbole ...'
    $f.Refresh()
    try { Erstauswahl; Spur 'Erstauswahl fertig' }
    catch { Spur ('Erstauswahl gescheitert: ' + $_.Exception.Message) }
    Spur ('Zustand: Eintraege=' + $galerie.Items.Count +
          ' markiert=' + $galerie.SelectedItems.Count +
          ' Uebernehmen-aktiv=' + $knopfOk.Enabled +
          ' Ergebnis=[' + $script:ergebnis + ']')
})
# DA-20260913-163439041-83d7: erst faerben, dann zeigen.
QA-Dunkel $f
[void]$f.ShowDialog()

# Das Ergebnis geht über eine Datei zurück - der Aufrufer ist ein eigener
# Prozess und kann keine Variable lesen.
#
# 🔴 NUR BEI „ÜBERNEHMEN" SCHREIBEN. Die Vorauswahl markiert beim Öffnen
#    schon einen Eintrag und füllt damit $ergebnis. Ohne die Abfrage auf
#    DialogResult hätte auch ein Schließen über das Kreuz das Symbol
#    stillschweigend übernommen.
$ablage = Join-Path $PSScriptRoot 'symbolauswahl.txt'
Spur ('Ende: DialogResult=' + $f.DialogResult + ' Ergebnis=[' + $script:ergebnis + ']')
if ($f.DialogResult -eq [System.Windows.Forms.DialogResult]::OK -and $script:ergebnis) {
    [IO.File]::WriteAllText($ablage, $script:ergebnis, (New-Object Text.UTF8Encoding $false))
} elseif (Test-Path $ablage) {
    Remove-Item $ablage -Force
}
