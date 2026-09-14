' Startet QuickAccess ohne sichtbares Konsolenfenster.
' 0 = verstecktes Fenster, False = nicht auf das Ende warten.
Set shell = CreateObject("WScript.Shell")
skript = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\")) & "QuickAccess.ps1"
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & skript & """", 0, False
