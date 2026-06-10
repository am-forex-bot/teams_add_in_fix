# Teams Meeting Add-in Fix

Fixes the recurring problem of the **Teams Meeting Add-in disappearing or being
disabled in Outlook** (no Teams meeting button when creating meetings).

## TL;DR — deploy the preventive fix

On each machine, run **once**, elevated (manually, or push via RMM / Intune /
GPO startup script):

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\TeamsAddinFix\Deploy-TeamsAddinFix.ps1
```

From then on the fix runs silently at **every user logon**, in the user's own
context. No UAC prompt, no window, Outlook is never closed. Users notice
nothing — the add-in just stops breaking.

## What's in this repo

| Path | What it is |
|---|---|
| `TeamsAddinFix/` | **The current, preventive fix** (productionized from `TeamsAddinTest.zip`) |
| `NEW TEAMS FIX MAYBE MAR2025.zip` | The old reactive fix (kept for history) |
| `TeamsAddinTest.zip` | Original draft of the preventive fix (kept for history) |

### Files in `TeamsAddinFix/`

| File | Purpose |
|---|---|
| `Deploy-TeamsAddinFix.ps1` | One-shot, per-machine install: copies files to `C:\ProgramData\TeamsAddinFix`, locks down ACLs, registers a hidden logon scheduled task, kicks off a first run |
| `Fix-TeamsMeetingAddin.ps1` | The actual fix (v6) — what runs at each logon |
| `RunHiddenTeamsAddInFix.vbs` | Wrapper that launches PowerShell with zero window flash |
| `FixTeamsAddin_Manual.bat` | Helpdesk convenience: double-click to run the fix immediately for the current user (also usable as a GPO user logon script) |
| `Uninstall-TeamsAddinFix.ps1` | Removes the task and files (handy while testing) |

## Old fix vs. new fix

| | Old (`NEW TEAMS FIX MAYBE MAR2025`) | New (`TeamsAddinFix/`) |
|---|---|---|
| When it runs | After the user reports it broken | Every logon, before it breaks |
| User impact | Outlook force-closed, UAC prompt to click | None — fully silent |
| Rights needed at runtime | Admin | None (user context) |
| Mechanism | Full MSI uninstall/reinstall via `Win32_Product` (slow, triggers MSI self-repair of other products) | Re-registers the add-in loader DLL per-user + enforces `LoadBehavior=3` |
| Version handling | Hardcoded `1.24.31301` and `C:\Temp\...` paths | Auto-detects newest installed version, both folder spellings, x86/x64 |

## How the fix works

At each logon, `Fix-TeamsMeetingAddin.ps1`:

1. Finds the newest installed add-in version under
   `%LOCALAPPDATA%\Microsoft\TeamsMeetingAddin` **or** `...\TeamsMeetingAdd-in`
   (both spellings exist in the wild).
2. Detects Office bitness (x86/x64) from the Click-to-Run registry config.
3. Silently re-registers `Microsoft.Teams.AddinLoader.dll` per-user
   (`regsvr32 /s /n /i:user`) — the same repair Microsoft documents for the
   add-in not appearing in Outlook.
4. Forces `LoadBehavior = 3` (load at startup) on the Teams add-in keys under
   `HKCU\Software\Microsoft\Office\Outlook\Addins`, so Outlook can't keep it
   "disabled" from a previous crash.
5. Logs only changes/errors to `%LOCALAPPDATA%\TeamsAddinFix\TeamsAddinFix.log`
   (auto-trimmed to 200 lines), and always exits 0 so logons are never blocked.

## What was broken in the original `TeamsAddinTest.zip` (and is now fixed)

1. **Filename mismatch** — both `.bat` files launched `System32\RunHidden.vbs`,
   but the shipped file was named `RunHiddenTeamsAddInFix.vbs`. With
   `wscript //B` suppressing errors, the logon run **silently did nothing**.
   This is almost certainly why testing went nowhere.
2. **It wasn't silent** — `regsvr32` was called without `/s`, so it popped a
   "DllInstall succeeded" dialog at the user on every run (`| Out-Null` cannot
   hide a GUI message box). Now `/s`, with the exit code checked and logged.
3. **Quote stripping** — the VBS rebuilt its arguments without re-quoting, so
   any path containing a space would break. Now re-quoted.
4. **No deployment story** — nothing actually wired it to run on devices.
   `Deploy-TeamsAddinFix.ps1` now installs it as a hidden scheduled task
   triggered at any user's logon, running as that user (group principal
   `BUILTIN\Users`, lowest privileges).
5. **Moved out of `System32`** — files now live in `C:\ProgramData\TeamsAddinFix`.
   Custom scripts in System32 risk 32/64-bit file-system redirection surprises
   (a 32-bit deployment agent writes to SysWOW64 instead), draw AV attention,
   and are awkward to clean up. ACLs are tightened so only admins/SYSTEM can
   modify the files; users can only read/execute.
6. Log folder renamed from `%LOCALAPPDATA%\Company` to
   `%LOCALAPPDATA%\TeamsAddinFix`.

## Verifying on a device

```bat
:: Task exists and last run succeeded (0x0)
schtasks /query /tn TeamsAddinFix /v /fo list

:: Fix activity for the logged-in user
type "%LOCALAPPDATA%\TeamsAddinFix\TeamsAddinFix.log"

:: Add-in set to load at startup (LoadBehavior = 3)
reg query "HKCU\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect" /v LoadBehavior
```

In Outlook: **File → Options → Add-ins** → "Microsoft Teams Meeting Add-in
for Microsoft Office" listed under *Active Application Add-ins*.

## Rolling back

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\TeamsAddinFix\Uninstall-TeamsAddinFix.ps1
```

Removes the task and files. Per-user registrations already applied are left in
place (removing them would re-break Outlook).

## Notes

- Roll out to a small pilot group first and check the log/task results before
  fleet-wide deployment.
- Some EDR products dislike `wscript.exe` launching PowerShell at logon. If
  yours flags it, change the task action in `Deploy-TeamsAddinFix.ps1` to run
  `powershell.exe -WindowStyle Hidden ...` directly — the only cost is a brief
  console flash at logon.
- If a machine's add-in install is genuinely corrupt (loader DLL missing — see
  "ERROR: Loader DLL missing" in the log), that machine still needs the old
  MSI reinstall once; the preventive fix keeps it healthy afterwards.
