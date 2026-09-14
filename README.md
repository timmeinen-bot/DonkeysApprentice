# Donkey's Apprentice

Kleines Werkzeug in der Taskleiste: zeigt beim Zeigen auf das Eselsymbol
eine Liste der wichtigsten Dateien, Ordner und Adressen. Ein Klick oeffnet
den Eintrag.

## Dateien

| Datei | Zweck |
|---|---|
| `QuickAccess.ps1` | Das Werkzeug selbst (Symbol in der Taskleiste, Ueberblendung) |
| `QuickAccess.vbs` | Starter ohne sichtbares Konsolenfenster |
| `QuickAccessAdmin.ps1` | Verwaltung: Eintraege anlegen, aendern, sortieren, loeschen |
| `QuickAccessAdmin.vbs` | Starter der Verwaltung (Fensterart **1**, nicht 0) |
| `Symbolauswahl.ps1` | Symbolgalerie: Auswahl aus den Windows-Standardsymbolen |
| `quickaccess.txt` | Die Liste selbst, im Klartext |
| `esel.ico` | Das Symbol in der Taskleiste |
| `LICENSE` | Die MIT-Lizenz -- gehoert in jedes Paket |
| `admin.log`, `quickaccess.log` | Spuren zum Nachsehen, wenn etwas nicht auftaucht |

## Beim ersten Start

Windows kennt das Programm noch nicht und warnt — das ist normal bei
allem, was nicht von einem grossen Anbieter kommt.

1. ZIP herunterladen, **Rechtsklick → Eigenschaften**, unten
   **„Zulassen"** ankreuzen, OK.
2. Erst danach entpacken.
3. `QuickAccess.vbs` doppelklicken.

Kommt trotzdem „Der Herausgeber konnte nicht überprüft werden":
**Weitere Informationen → Trotzdem ausführen**.

> **Schritt 1 gehört an das ARCHIV, nicht an die entpackten Dateien.**
> Wer erst entpackt und dann freigibt, muss es für jede Datei einzeln
> tun — die Markierung ist dann schon übertragen.

Die Ausführungsrichtlinie von PowerShell ist **kein** Hindernis:
`QuickAccess.vbs` startet mit `-ExecutionPolicy Bypass`, und das gilt nur
für diesen einen Aufruf und braucht keine Administratorrechte.

## Format von `quickaccess.txt`

```
[Gruppe]
Name = Ziel
Name = Ziel | Quelle,Nummer
```

* `[Gruppe]` erzeugt eine Ueberschrift in der Ueberblendung.
* `Ziel` darf eine Datei, ein Ordner oder eine Adresse sein (`http`, `https`, `mailto`).
* Hinter dem senkrechten Strich steht ein eigenes Symbol als `Quelle,Nummer`,
  zum Beispiel `C:\Windows\System32\imageres.dll,109`. Ohne diesen Teil nimmt
  das Werkzeug das Symbol des Dokuments.
* Der senkrechte Strich ist in Windows-Pfaden verboten und taugt deshalb als
  Trennzeichen.
* Die Datei ist **UTF-8 mit Kennung (BOM)**. Ohne Kennung liest PowerShell 5.1
  sie als ANSI und alle Umlaute sind kaputt.

## Symbolgalerie

Die Verwaltung oeffnet ueber `Symbol waehlen ...` die Galerie. Sie zeigt die
Symbole der ueblichen Windows-Bibliotheken als Kacheln:

| Sammlung | Datei | Anzahl |
|---|---|---:|
| Allgemein | `shell32.dll` | 335 |
| Modern | `imageres.dll` | 369 |
| Geraete und Ordner | `ddores.dll` | 151 |
| Netzwerk | `netshell.dll` | 165 |
| Systemsteuerung | `setupapi.dll` | 62 |
| Explorer | `explorer.exe` | 23 |

Doppelklick oder `Uebernehmen` gibt `Quelle,Nummer` zurueck. Ueber
`Andere Datei ...` laesst sich jede beliebige `.dll`, `.exe` oder `.ico` oeffnen.
Das bereits eingestellte Symbol wird beim Oeffnen markiert.

## Fallen, die hier schon zugeschlagen haben

* **`ExtractAssociatedIcon` kann keinen Index.** Es liefert immer nur das erste
  Symbol einer Datei. Fuer `shell32.dll,44` braucht es `ExtractIconEx`.
* **Zwei P/Invoke-Ueberladungen mit gleicher Argumentzahl kann PowerShell nicht
  auseinanderhalten** ("Es wurden mehrere nicht eindeutige Ueberladungen
  gefunden"). Loesung: zwei eigene Namen, beide ueber `EntryPoint` auf dieselbe
  Windows-Funktion gelegt (`HolSymbol` und `ZaehleSymbole`).
* **Jedes Symbolhandle muss mit `DestroyIcon` freigegeben werden.** Bei 369
  Symbolen je Bibliothek summiert sich das sonst.
* **Die Galerie darf nur bei `Uebernehmen` schreiben.** Die Vorauswahl markiert
  beim Oeffnen schon einen Eintrag; ohne Abfrage auf `DialogResult` haette auch
  ein Schliessen ueber das Kreuz das Symbol stillschweigend uebernommen.
* **Nicht mit `-WindowStyle Hidden` starten** - das versteckt auch das Fenster.
  Das Skript blendet nur die Konsole aus.
* **`Application::Run` braucht das Formular als Argument**, sonst endet die
  Schleife sofort.
* **`StartPosition = CenterScreen`** landete ausserhalb des sichtbaren Bereichs;
  feste Position ist verlaesslicher.
* **Keine festen Koordinaten fuer Knoepfe** - damit lagen drei uebereinander.
  Ein `FlowLayoutPanel` ordnet sie selbst.
* **`Start-Process -FilePath <Ordner>`** schlaegt fehl; Ordner brauchen
  `explorer.exe`.
* **`SetForegroundWindow` aus einem Fremdprozess wird von Windows abgewiesen**,
  `SendKeys` geht dann ins Leere. Fuer Proben `AppActivate` nehmen.
* **Aus einer Claude-Sitzung gestartet schliesst sich das Fenster wieder**,
  sobald der Werkzeugaufruf endet - der Prozess haengt in dessen Job. Sah aus
  wie ein Fehler im Skript, war aber die Prozesskette. Zur Kontrolle den
  Start in einem Aufruf machen und lange genug warten; `admin.log` haelt
  seitdem den Schliessgrund (`CloseReason`) fest.

## Lizenz

Donkey's Apprentice steht unter der **MIT-Lizenz** -- der volle Text liegt
in [`LICENSE`](LICENSE) im selben Ordner.

Das heisst: benutzen, aendern, weitergeben und auch verkaufen ist erlaubt.
Die einzige Bedingung ist, dass Lizenztext und Copyright-Zeile
(`Copyright (c) 2026 Eselchen Labs`) mitgegeben werden. Eine Gewaehr
uebernimmt niemand.

Die Lizenz ist wortgleich zu der von MarkUp -- zwei Werkzeuge desselben
Hauses sollen nicht verschieden lizenziert sein.

## Sicherungen

`QuickAccessAdmin.alt.ps1` und `QuickAccessAdmin.vor_galerie.ps1` sind
Staende von vorher, `quickaccess.alt.txt` eine aeltere Liste.

---

**Donkey's Apprentice** — Eselchen Labs, [MIT-Lizenz](LICENSE).

Stand: 13.09.2026
