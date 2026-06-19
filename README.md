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
| `Fix-TeamsMeetingAddin.ps1` | The actual fix (v7) — what runs at each logon |
| `RunHiddenTeamsAddInFix.vbs` | Wrapper that launches PowerShell with zero window flash |
| `FixTeamsAddin_Manual.bat` | Helpdesk convenience: double-click to run the fix immediately for the current user (also usable as a GPO user logon script) |
| `Install-TeamsAddinMsi.ps1` | Laptop provisioning: installs the add-in MSI machine-wide into Program Files so it works for **every** user (see "Setting up a new laptop" below) |
| `Uninstall-TeamsAddinFix.ps1` | Removes the task and files (handy while testing) |
| `Fix-TeamsMeetingAddin.cmd` | **PowerShell-free** version of the fix, for endpoints where PowerShell is blocked by EDR |
| `Install-TeamsAddinFix.cmd` | **PowerShell-free** installer (cmd + `schtasks` + `icacls`) — the no-PowerShell equivalent of `Deploy-TeamsAddinFix.ps1` |
| `Uninstall-TeamsAddinFix.cmd` | PowerShell-free removal |

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

1. Detects Office bitness (x86/x64) from the Click-to-Run registry config.
2. Scans every place the add-in can live — per-user
   (`%LOCALAPPDATA%\Microsoft\TeamsMeetingAddin` and `...\TeamsMeetingAdd-in`,
   both spellings exist in the wild) **and** machine-wide
   (`%ProgramFiles(x86)%\Microsoft\TeamsMeetingAdd-in` and `%ProgramFiles%\...`)
   — and picks the **newest version folder that actually contains the loader
   DLL**, so a gutted newest folder falls through to the next-best copy
   instead of aborting.
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

## Setting up a new laptop (and the admin-install trap)

Historically, installing the add-in MSI while logged in as the setup admin —
even with "install for all users" / `ALLUSERS=1` — dropped the **files** into
the *admin's own profile* (`C:\Users\<admin>\AppData\Local\...`). `ALLUSERS`
only controls where the registration goes, not where the payload lands. Other
users can't read another profile, so the add-in never loaded for the laptop's
actual user. That trap is why the old reactive fix had to pass the username
around and reinstall into that specific user's profile.

The supported flow now, as the setup admin (no user logon needed first):

```bat
:: 1. Install the add-in machine-wide (forces TARGETDIR into Program Files,
::    named after the MSI's own product version, readable by everyone)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\TeamsAddinFix\Install-TeamsAddinMsi.ps1 -MsiPath .\MicrosoftTeamsMeetingAddinInstaller.msi

:: 2. Deploy the preventive fix (hidden logon task)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\TeamsAddinFix\Deploy-TeamsAddinFix.ps1
```

Then hand the laptop over. At the user's first logon the task registers the
add-in for *them* against the machine-wide copy — no per-user install, no
restart ritual, nothing for the user to click. Every later logon re-asserts
it, and when Teams starts laying down newer per-user versions through its own
updates, the fix automatically follows the newest usable copy wherever it is.

(The MSI lives in `NEW TEAMS FIX MAYBE MAR2025.zip` in this repo; extract it
next to the script or point `-MsiPath` at it.)

## PowerShell-free deployment (EDR-locked endpoints, e.g. Aurora)

If PowerShell is blocked on your endpoints, use the `.cmd` toolchain instead —
it does the same job with only `cmd`, `schtasks`, `reg`, `regsvr32` and
`icacls` (all native Windows binaries), and never invokes PowerShell.

Put these three files in one folder (ideally your EDR-excluded folder):

- `Install-TeamsAddinFix.cmd`
- `Fix-TeamsMeetingAddin.cmd`
- `RunHiddenTeamsAddInFix.vbs`

Then, from an **elevated** command prompt:

```bat
:: install to your EDR-excluded folder so the logon task runs from an allowed path
Install-TeamsAddinFix.cmd "C:\YourExcludedFolder\TeamsAddinFix"
```

This copies the files in, tightens the ACLs, registers a hidden `schtasks`
logon task that runs in each user's own context, and fixes the current user
immediately. Remove it with `Uninstall-TeamsAddinFix.cmd "C:\YourExcludedFolder\TeamsAddinFix"`.

If `wscript` is also blocked (so the hidden launcher never fires and the log
stays empty after logon), re-run with `visible` as the second argument —
the task then runs `cmd` directly, at the cost of a brief console flash at
logon:

```bat
Install-TeamsAddinFix.cmd "C:\YourExcludedFolder\TeamsAddinFix" visible
```

Note: the scheduled task uses the `BUILTIN\Users` group principal at limited
run level, so it runs for every user at their logon with no stored password
and no admin rights at runtime — same security model as the PowerShell version.

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
- If a machine has **no** usable copy of the add-in anywhere (log shows
  "ERROR: No add-in version folder containing ... found"), run
  `Install-TeamsAddinMsi.ps1` on it once; the preventive fix keeps it healthy
  from then on.
