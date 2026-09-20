# Donkey's Apprentice

<img src="assets/eselchen-labs.png" align="right" width="110" alt="Eselchen Labs">


A small tray tool: hover over the donkey icon and it shows a list of your most
important files, folders and links. One click opens the entry.

## Files

| File | Purpose |
|---|---|
| `QuickAccess.ps1` | The tool itself (tray icon, overlay) |
| `QuickAccess.vbs` | Launcher without a visible console window |
| `QuickAccessAdmin.ps1` | Management: add, edit, reorder and delete entries |
| `QuickAccessAdmin.vbs` | Launcher for the management window (window style **1**, not 0) |
| `Symbolauswahl.ps1` | Icon gallery: pick from the standard Windows icons |
| `quickaccess.txt` | The list itself, in plain text |
| `esel.ico` | The tray icon |
| `LICENSE` | The MIT license -- belongs in every package |
| `admin.log`, `quickaccess.log` | Traces to look at when something does not show up |

## First start

Windows does not know this program yet and will warn you — that is normal for
anything that does not come from a large vendor.

1. Download the ZIP, **right-click → Properties**, tick **"Unblock"** at the
   bottom, OK.
2. Only then extract it.
3. Double-click `QuickAccess.vbs`.

If "The publisher could not be verified" still appears:
**More info → Run anyway**.

> **Step 1 applies to the ARCHIVE, not to the extracted files.**
> If you extract first and unblock afterwards, you have to do it for every
> single file — the mark has already been passed on by then.

PowerShell's execution policy is **not** an obstacle: `QuickAccess.vbs` starts
with `-ExecutionPolicy Bypass`, which applies to that one call only and needs
no administrator rights.

## Format of `quickaccess.txt`

```
[Group]
Name = Target
Name = Target | Source,Index
```

* `[Group]` creates a heading in the overlay.
* `Target` may be a file, a folder or a link (`http`, `https`, `mailto`).
* After the vertical bar comes a custom icon as `Source,Index`, for example
  `C:\Windows\System32\imageres.dll,109`. Without that part the tool uses the
  document's own icon.
* The vertical bar is forbidden in Windows paths, which is exactly why it works
  as a separator.
* The file is **UTF-8**. The management window writes it with a byte order
  mark (`UTF8Encoding $true`), and both scripts read it with an explicit
  `Get-Content -Encoding UTF8`. Measured on PowerShell 5.1.26100: with
  that parameter the file reads correctly **with or without** a BOM.
  Only a read *without* the parameter falls back to ANSI and mangles
  non-ASCII characters.

## Icon gallery

The management window opens the gallery via `Symbol wählen ...`. It shows the
icons of the usual Windows libraries as tiles:

| Collection | File | Count |
|---|---|---:|
| General | `shell32.dll` | 335 |
| Modern | `imageres.dll` | 369 |
| Devices and folders | `ddores.dll` | 151 |
| Network | `netshell.dll` | 165 |
| Control panel | `setupapi.dll` | 62 |
| Explorer | `explorer.exe` | 23 |

A double-click or `Übernehmen` returns `Source,Index`. Via `Andere Datei ...`
you can open any `.dll`, `.exe` or `.ico`. The icon currently configured is
preselected when the gallery opens.

## Traps that have already caught us here

* **`ExtractAssociatedIcon` cannot take an index.** It always returns only the
  first icon of a file. `shell32.dll,44` needs `ExtractIconEx`.
* **PowerShell cannot tell apart two P/Invoke overloads with the same argument
  count** ("Multiple ambiguous overloads found"). Solution: two distinct names,
  both mapped onto the same Windows function via `EntryPoint` (`HolSymbol` and
  `ZaehleSymbole`).
* **Every icon handle must be released with `DestroyIcon`.** At 369 icons per
  library that adds up quickly.
* **The gallery may only write on `Übernehmen`.** The preselection already
  highlights an entry when it opens; without checking `DialogResult`, closing
  the window with the X would have silently applied that icon.
* **Do not start with `-WindowStyle Hidden`** — that hides the window too. The
  script only hides the console.
* **`Application::Run` needs the form as its argument**, otherwise the loop
  ends immediately.
* **`StartPosition = CenterScreen`** ended up outside the visible area; a fixed
  position is more reliable.
* **No fixed coordinates for buttons** — that left three of them stacked on top
  of each other. A `FlowLayoutPanel` arranges them by itself.
* **`Start-Process -FilePath <folder>`** fails; folders need `explorer.exe`.
* **`SetForegroundWindow` from a foreign process is refused by Windows**, and
  `SendKeys` then goes nowhere. Use `AppActivate` for tests.
* **Started from a Claude session, the window closes again** as soon as the tool
  call ends — the process hangs in its job object. It looked like a bug in the
  script, but it was the process chain. To check, do the start in a single call
  and wait long enough; `admin.log` has recorded the close reason
  (`CloseReason`) ever since.

## License

Donkey's Apprentice is published under the **MIT license** — the full text is
in [`LICENSE`](LICENSE) in the same folder.

That means: using, modifying, redistributing and even selling it is allowed.
The only condition is that the license text and the copyright line
(`Copyright (c) 2026 Eselchen Labs`) travel with it. No warranty is given.

The license is word-for-word the same as MarkUp's — two tools from the same
house should not be licensed differently.

## Backups

`QuickAccessAdmin.alt.ps1` and `QuickAccessAdmin.vor_galerie.ps1` are earlier
states, `quickaccess.alt.txt` is an older list.

---

**Donkey's Apprentice** — Eselchen Labs, [MIT license](LICENSE).

Last updated: 2026-09-13
