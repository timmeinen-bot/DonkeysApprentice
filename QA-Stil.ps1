# QA-Stil.ps1 -- eine Quelle für das Aussehen aller DA-Fenster.
#
# DA-20260913-163439041-83d7: Die Verwaltung sah aus wie ein fremdes
# Programm -- Windows-Grau gegen das dunkle Overlay. Zwei Kopien
# derselben fuenf Farbwerte driften auseinander, sobald eine angefasst
# wird; deshalb steht die Palette ab hier NUR noch an dieser Stelle.
#
# 🔴 Was WinForms nicht hergibt: MessageBox, OpenFileDialog,
#    FolderBrowserDialog und die VisualBasic-InputBox sind Systemdialoge
#    und bleiben hell. Das ist keine Nachlaessigkeit, sondern die Grenze.

# Die Palette braucht System.Drawing. Wer diese Datei laedt,
# soll sich nicht darum kuemmern müssen.
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$global:FARBE_HG      = [System.Drawing.Color]::FromArgb(32, 32, 36)
$global:FARBE_HOVER   = [System.Drawing.Color]::FromArgb(58, 58, 66)
$global:FARBE_TEXT    = [System.Drawing.Color]::FromArgb(240, 240, 240)
$global:FARBE_GRUPPE  = [System.Drawing.Color]::FromArgb(150, 150, 160)
$global:FARBE_FEHLT   = [System.Drawing.Color]::FromArgb(130, 130, 130)
# Eingabefelder etwas tiefer als der Grund, damit sie als Felder lesbar
# bleiben; Rot auf dunklem Grund wäre Firebrick -- zu dunkel.
$global:FARBE_FELD    = [System.Drawing.Color]::FromArgb(40, 40, 46)
$global:FARBE_RAND    = [System.Drawing.Color]::FromArgb(70, 70, 80)
$global:FARBE_WARNUNG = [System.Drawing.Color]::FromArgb(240, 150, 150)
$global:FARBE_KOPF    = [System.Drawing.Color]::FromArgb(52, 52, 60)
$global:QA_SCHRIFT    = New-Object System.Drawing.Font('Segoe UI', 9.5)


function QA-Dunkel {
    <#
      Faerbt ein Fenster und ALLES darin. Rekursiv, weil WinForms die
      Farbe nicht an jedes Kind vererbt: eine TextBox oder ListView
      bleibt weiss, bis man sie einzeln anfasst.
    #>
    param($ctrl)
    if ($null -eq $ctrl) { return }

    $art = $ctrl.GetType().Name
    switch -Regex ($art) {
        '^(Form)$' {
            $ctrl.BackColor = $global:FARBE_HG
            $ctrl.ForeColor = $global:FARBE_TEXT
            $ctrl.Font = $global:QA_SCHRIFT
        }
        '^(Panel|FlowLayoutPanel|TableLayoutPanel|GroupBox|TabPage)$' {
            $ctrl.BackColor = $global:FARBE_HG
            $ctrl.ForeColor = $global:FARBE_TEXT
        }
        '^(Button)$' {
            $ctrl.BackColor = $global:FARBE_HOVER
            $ctrl.ForeColor = $global:FARBE_TEXT
            $ctrl.FlatStyle = 'Flat'
            $ctrl.FlatAppearance.BorderColor = $global:FARBE_RAND
        }
        '^(TextBox|ComboBox|NumericUpDown|ListBox)$' {
            $ctrl.BackColor = $global:FARBE_FELD
            $ctrl.ForeColor = $global:FARBE_TEXT
        }
        '^(ListView)$' {
            $ctrl.BackColor = $global:FARBE_FELD
            $ctrl.ForeColor = $global:FARBE_TEXT
            $ctrl.BorderStyle = 'FixedSingle'
            $ctrl.Font = $global:QA_SCHRIFT
            $ctrl.GridLines = $false
            $ctrl.FullRowSelect = $true
            # 🔴 Der Spaltenkopf einer ListView ignoriert BackColor --
            # er bleibt weiss, bis man ihn selbst zeichnet.
            if (-not $ctrl.OwnerDraw) {
                $ctrl.OwnerDraw = $true
                $ctrl.Add_DrawColumnHeader({
                    param($absender, $e)
                    $e.Graphics.FillRectangle(
                        (New-Object System.Drawing.SolidBrush $global:FARBE_KOPF), $e.Bounds)
                    $r = $e.Bounds
                    $r.X = $r.X + 6
                    $r.Width = $r.Width - 8
                    [System.Windows.Forms.TextRenderer]::DrawText(
                        $e.Graphics, $e.Header.Text, $global:QA_SCHRIFT, $r,
                        $global:FARBE_GRUPPE,
                        ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
                         [System.Windows.Forms.TextFormatFlags]::EndEllipsis))
                    $e.Graphics.DrawLine(
                        (New-Object System.Drawing.Pen $global:FARBE_RAND),
                        $e.Bounds.Right - 1, $e.Bounds.Top,
                        $e.Bounds.Right - 1, $e.Bounds.Bottom)
                })
                # Zeilen und Unterspalten weiter vom System zeichnen lassen:
                # nur so behaelt die Liste Auswahl, Markierung und Tastatur.
                $ctrl.Add_DrawItem({ param($absender, $e) $e.DrawDefault = $true })
                $ctrl.Add_DrawSubItem({ param($absender, $e) $e.DrawDefault = $true })
            }
        }
        '^(Label|LinkLabel|CheckBox|RadioButton)$' {
            $ctrl.BackColor = [System.Drawing.Color]::Transparent
            $ctrl.ForeColor = $global:FARBE_TEXT
        }
        '^(PictureBox)$' {
            $ctrl.BackColor = $global:FARBE_HG
        }
    }

    foreach ($kind in $ctrl.Controls) { QA-Dunkel $kind }
}
