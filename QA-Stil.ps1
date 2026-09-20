# QA-Stil.ps1 -- one source for the look of every DA window.
#
# DA-20260913-163439041-83d7: the management window looked like a
# different program -- Windows grey against the dark overlay. Two copies
# of the same five colour values drift apart as soon as one is touched,
# so from here on the palette lives in this one place only.
#
# 🔴 What WinForms does not offer: MessageBox, OpenFileDialog,
#    FolderBrowserDialog and the VisualBasic InputBox are system dialogs
#    and stay light. That is not sloppiness, that is the limit.

# The palette needs System.Drawing. Whoever loads this file should not
# have to care about that.
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$global:FARBE_HG      = [System.Drawing.Color]::FromArgb(32, 32, 36)
$global:FARBE_HOVER   = [System.Drawing.Color]::FromArgb(58, 58, 66)
$global:FARBE_TEXT    = [System.Drawing.Color]::FromArgb(240, 240, 240)
$global:FARBE_GRUPPE  = [System.Drawing.Color]::FromArgb(150, 150, 160)
$global:FARBE_FEHLT   = [System.Drawing.Color]::FromArgb(130, 130, 130)
# Input fields sit slightly darker than the background so they still
# read as fields; red on a dark ground would be firebrick -- too dark.
$global:FARBE_FELD    = [System.Drawing.Color]::FromArgb(40, 40, 46)
$global:FARBE_RAND    = [System.Drawing.Color]::FromArgb(70, 70, 80)
$global:FARBE_WARNUNG = [System.Drawing.Color]::FromArgb(240, 150, 150)
$global:FARBE_KOPF    = [System.Drawing.Color]::FromArgb(52, 52, 60)
$global:QA_SCHRIFT    = New-Object System.Drawing.Font('Segoe UI', 9.5)


function QA-Dunkel {
    <#
      Colours a window and EVERYTHING inside it. Recursive, because
      WinForms does not pass the colour on to every child: a TextBox or
      ListView stays white until you touch it individually.
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
            # 🔴 A ListView's column header ignores BackColor --
            # it stays white until you draw it yourself.
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
                # Let the system keep drawing rows and sub-items: that is
                # the only way the list keeps selection, highlighting and
                # keyboard handling.
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
