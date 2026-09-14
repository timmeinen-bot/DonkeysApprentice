' Startet die Verwaltung.
' WICHTIG: Fensterart 1 (normal), NICHT 0. Bei 0 versteckt Windows den
' gesamten Prozess samt Formular - man sieht dann gar nichts. Das
' Konsolenfenster blendet das PowerShell-Skript selbst aus.
Set shell = CreateObject("WScript.Shell")
skript = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\")) & "QuickAccessAdmin.ps1"
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & skript & """", 1, False
