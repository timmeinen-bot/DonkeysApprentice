# =====================================================================
#  Icon gallery - pick from the standard Windows icons
#
#  Tim, 2026-09-04: "let me pick from the typical windows icons"
#
#  Shows the icons of the usual Windows libraries as tiles. A double-click
#  applies source and index.
#
#  🔴 ExtractAssociatedIcon CANNOT TAKE AN INDEX and always returns only
#     the first icon of a file. A gallery needs ExtractIconEx, which fetches
#     the n-th icon specifically.
#  🔴 POWERSHELL CANNOT TELL APART TWO OVERLOADS WITH THE SAME ARGUMENT
#     COUNT: "Multiple ambiguous overloads found". Hence two distinct names,
#     both mapped onto the same Windows function via EntryPoint.
#  ⚠️ Every handle must be released with DestroyIcon. At 300 icons per
#     library that otherwise adds up to a real leak.
# =====================================================================
param([string]$Vorgabe = '')   # bereits eingestelltes Symbol als "source,index"
$ErrorActionPreference = 'Stop'

function Spur($text) {
    try {
        # Log under %LOCALAPPDATA%, not next to the script
        # (DA-20260913-144004296-42e6).
        Add-Content -Path (Join-Path (Join-Path $env:LOCALAPPDATA 'QuickAccess') 'galerie.log') -Encoding UTF8 -Value (
            (Get-Date).ToString('HH:mm:ss.fff') + '  ' + $text)
    } catch { }
}
Spur ('start, default=[' + $Vorgabe + ']')

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
# The libraries that hold the well-known Windows icons.
$QUELLEN = [ordered]@{
    'General (shell32)'      = Join-Path $SYS 'shell32.dll'
    'Modern (imageres)'        = Join-Path $SYS 'imageres.dll'
    'Devices and folders (ddores)' = Join-Path $SYS 'ddores.dll'
    'Control Panel'          = Join-Path $SYS 'setupapi.dll'
    'Network'                 = Join-Path $SYS 'netshell.dll'
    'Explorer'                 = Join-Path $env:SystemRoot 'explorer.exe'
}

. "$PSScriptRoot\QA-Stil.ps1"   # DA-20260913-163439041-83d7: eine Stilquelle
$f = New-Object System.Windows.Forms.Form
$f.Text = 'Choose an icon'
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
$l.Text = 'Collection'
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
$eigeneDatei.Text = 'Other file ...'
$eigeneDatei.Location = New-Object System.Drawing.Point(356, 11)
$eigeneDatei.Size = New-Object System.Drawing.Size(130, 26)
$oben.Controls.Add($eigeneDatei)

$hinweis = New-Object System.Windows.Forms.Label
$hinweis.Text = 'Double-click applies the icon'
$hinweis.Location = New-Object System.Drawing.Point(500, 15)
$hinweis.Size = New-Object System.Drawing.Size(280, 20)
$hinweis.ForeColor = [System.Drawing.Color]::DimGray
$oben.Controls.Add($hinweis)

$unten = New-Object System.Windows.Forms.Panel
$unten.Dock = 'Bottom'
$unten.Height = 52
$f.Controls.Add($unten)

$gewaehlt = New-Object System.Windows.Forms.Label
$gewaehlt.Text = 'nothing chosen'
$gewaehlt.Location = New-Object System.Drawing.Point(12, 16)
$gewaehlt.Size = New-Object System.Drawing.Size(560, 20)
$unten.Controls.Add($gewaehlt)

$knopfOk = New-Object System.Windows.Forms.Button
$knopfOk.Text = 'Apply'
$knopfOk.Size = New-Object System.Drawing.Size(120, 30)
$knopfOk.Anchor = 'Right,Top'
$knopfOk.Enabled = $false
$unten.Controls.Add($knopfOk)

$knopfAbbruch = New-Object System.Windows.Forms.Button
$knopfAbbruch.Text = 'Cancel'
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
    # First count how many icons are in there.
    $anzahl = [QAG.Shell]::ZaehleSymbole($pfad, -1, [IntPtr]::Zero, [IntPtr]::Zero, 0)
    # ⚠️ Cap at 400: some libraries contain hundreds, and loading each
    #    one individually would otherwise take noticeably long.
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
            # Release every handle again - otherwise hundreds of them leak.
            if ($gross -ne [IntPtr]::Zero) { [void][QAG.Shell]::DestroyIcon($gross) }
            if ($klein -ne [IntPtr]::Zero) { [void][QAG.Shell]::DestroyIcon($klein) }
        }
    }
    $galerie.EndUpdate()
    $f.Cursor = [System.Windows.Forms.Cursors]::Default
    $script:aktuelleQuelle = $pfad
    $hinweis.Text = "$($galerie.Items.Count) icons - double-click to apply"
    Spur ('loaded: ' + $galerie.Items.Count + ' icons from ' + (Split-Path $pfad -Leaf))
}

$auswahlQuelle.Add_SelectedIndexChanged({
    $name = $auswahlQuelle.SelectedItem
    if ($name) { Lade-Galerie $QUELLEN[$name] }
})

$eigeneDatei.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Title = 'Which file should the icons come from?'
    $d.Filter = 'Icon sources (*.dll;*.exe;*.ico)|*.dll;*.exe;*.ico|All files (*.*)|*.*'
    $d.InitialDirectory = $SYS
    if ($d.ShowDialog() -eq 'OK') { Lade-Galerie $d.FileName }
})

function Merke-Auswahl {
    if ($galerie.SelectedItems.Count -eq 0) { Spur 'remember selection: nothing marked'; return }
    $index = $galerie.SelectedItems[0].Tag
    $script:ergebnis = $script:aktuelleQuelle + ',' + $index
    $gewaehlt.Text = 'chosen: ' + [IO.Path]::GetFileName($script:aktuelleQuelle) + ', number ' + $index
    $knopfOk.Enabled = $true
    Spur ('remembered: ' + $script:ergebnis)
}
$galerie.Add_SelectedIndexChanged({ Merke-Auswahl })
$galerie.Add_DoubleClick({
    Merke-Auswahl
    if ($script:ergebnis) { $f.DialogResult = 'OK'; $f.Close() }
})
$knopfOk.Add_Click({ $f.DialogResult = 'OK'; $f.Close() })
$knopfAbbruch.Add_Click({ $script:ergebnis = ''; $f.DialogResult = 'Cancel'; $f.Close() })

# Enter applies, Esc cancels.
$f.AcceptButton = $knopfOk
$f.CancelButton = $knopfAbbruch

function Erstauswahl {
# Preselect the icon already configured so it is visible what applies.
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
        # Is the source in the drop-down? Otherwise load it as a separate file.
        $treffer = ''
        foreach ($name in $QUELLEN.Keys) {
            if ($QUELLEN[$name] -eq $vQuelle) { $treffer = $name; break }
        }
        if ($treffer -and $auswahlQuelle.Items.Contains($treffer)) {
            $auswahlQuelle.SelectedItem = $treffer      # löst das Laden aus
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

# 🔴 SHOW FIRST, LOAD AFTERWARDS. Loading 335 icons used to happen
#    before ShowDialog - the window appeared several seconds later while
#    the management window was already blocked. From the outside that
#    looked like a hung program.
$f.Add_Shown({
    $f.Activate()
    # A freshly started process otherwise ends up behind the window that
    # launched it. Bring it to the front briefly, then release it again.
    $f.TopMost = $true
    $f.TopMost = $false
    $hinweis.Text = 'loading icons ...'
    $f.Refresh()
    try { Erstauswahl; Spur 'initial selection done' }
    catch { Spur ('initial selection failed: ' + $_.Exception.Message) }
    Spur ('state: entries=' + $galerie.Items.Count +
          ' marked=' + $galerie.SelectedItems.Count +
          ' apply-active=' + $knopfOk.Enabled +
          ' result=[' + $script:ergebnis + ']')
})
# DA-20260913-163439041-83d7: colour first, then show.
QA-Dunkel $f
[void]$f.ShowDialog()

# The result travels back through a file - the caller is a separate
# process and cannot read a variable.
#
# 🔴 ONLY WRITE ON "APPLY". The preselection already highlights an entry
#    when the window opens and thereby fills $ergebnis. Without the check on
#    DialogResult, closing the window with the X would have silently applied
#    that icon.
$ablage = Join-Path $PSScriptRoot 'symbolauswahl.txt'
Spur ('end: DialogResult=' + $f.DialogResult + ' result=[' + $script:ergebnis + ']')
if ($f.DialogResult -eq [System.Windows.Forms.DialogResult]::OK -and $script:ergebnis) {
    [IO.File]::WriteAllText($ablage, $script:ergebnis, (New-Object Text.UTF8Encoding $false))
} elseif (Test-Path $ablage) {
    Remove-Item $ablage -Force
}
