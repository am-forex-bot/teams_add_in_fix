# Fix-TeamsMeetingAddin.ps1 (v7 - SILENT, USER CONTEXT, NO OUTLOOK CLOSE, PER-USER + MACHINE-WIDE)
# v7 changes vs v6:
#   - also scans machine-wide installs under Program Files / Program Files (x86)
#     (Microsoft\TeamsMeetingAdd-in), so an admin-time "all users" MSI install
#     (Install-TeamsAddinMsi.ps1) works for every user on the machine
#   - picks the newest version folder that actually CONTAINS the loader DLL,
#     instead of giving up when the newest folder is gutted
#   - accepts 2-4 part version folder names (e.g. 1.24.31301)
# v6 changes vs v5:
#   - regsvr32 now runs with /s: v5 popped a "DllInstall succeeded" dialog at the
#     user on every run, because /s was missing and Out-Null cannot hide a GUI box
#   - regsvr32 exit code is checked and logged on failure
#   - log moved from %LOCALAPPDATA%\Company to %LOCALAPPDATA%\TeamsAddinFix
$ErrorActionPreference = "Stop"

function Write-TinyLog([string]$msg) {
    try {
        $logDir = Join-Path $env:LOCALAPPDATA "TeamsAddinFix"
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $logFile = Join-Path $logDir "TeamsAddinFix.log"
        $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $logFile -Value "$ts  $msg" -Encoding UTF8

        $lines = Get-Content -Path $logFile -ErrorAction SilentlyContinue
        if ($lines.Count -gt 200) { $lines[-200..-1] | Set-Content -Path $logFile -Encoding UTF8 }
    } catch { }
}

function Get-BestAddinDll {
    param([string]$Platform)

    # Per-user installs (laid down by Teams itself) - both folder spellings
    # exist in the wild - plus machine-wide installs (Install-TeamsAddinMsi.ps1
    # or new Teams machine-wide deployments).
    $bases = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\TeamsMeetingAddin"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\TeamsMeetingAdd-in")
    )
    foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ($root) { $bases += (Join-Path $root "Microsoft\TeamsMeetingAdd-in") }
    }
    $bases = $bases | Where-Object { Test-Path $_ }
    if (-not $bases) { return $null }

    $candidates = @()
    foreach ($base in $bases) {
        $dirs = Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+(\.\d+){1,3}$' } |
            ForEach-Object {
                [PSCustomObject]@{
                    BasePath    = $base
                    VersionName = $_.Name
                    Version     = [version]$_.Name
                    DllPath     = Join-Path $_.FullName (Join-Path $Platform "Microsoft.Teams.AddinLoader.dll")
                }
            }
        if ($dirs) { $candidates += $dirs }
    }
    if (-not $candidates) { return $null }

    # Newest version folder that actually has the loader DLL wins; a gutted
    # newest folder falls through to the next-best copy instead of aborting.
    return ($candidates |
        Sort-Object Version -Descending |
        Where-Object { Test-Path $_.DllPath } |
        Select-Object -First 1)
}

$changed = $false

try {
    # Detect Office platform (Click-to-Run)
    $platform = $null
    $ctrKey = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
    try { $platform = (Get-ItemProperty -Path $ctrKey -ErrorAction Stop).Platform } catch { $platform = "x64" }
    if ($platform -notin @("x86","x64")) { $platform = "x64" }

    $best = Get-BestAddinDll -Platform $platform
    if (-not $best) {
        Write-TinyLog "ERROR: No add-in version folder containing $platform\Microsoft.Teams.AddinLoader.dll found (checked LOCALAPPDATA and Program Files)."
        exit 0
    }
    $addinDll = $best.DllPath

    $regsvr32 = if ($platform -eq "x64") {
        Join-Path $env:WINDIR "System32\regsvr32.exe"
    } else {
        Join-Path $env:WINDIR "SysWOW64\regsvr32.exe"
    }

    # Register per-user; /s keeps regsvr32 from showing its result dialog
    $proc = Start-Process -FilePath $regsvr32 -ArgumentList '/s', '/n', '/i:user', "`"$addinDll`"" -Wait -PassThru -WindowStyle Hidden
    if ($proc.ExitCode -eq 0) {
        $changed = $true
    } else {
        Write-TinyLog "WARN: regsvr32 exit code $($proc.ExitCode) registering $addinDll"
    }

    # Enforce LoadBehavior=3 for Teams-like add-in keys + ensure fallback exists
    $addinsRoot = "HKCU:\Software\Microsoft\Office\Outlook\Addins"
    if (-not (Test-Path $addinsRoot)) { New-Item -Path $addinsRoot -Force | Out-Null }

    $keys = Get-ChildItem $addinsRoot -ErrorAction SilentlyContinue
    $teamsKeys = $keys | Where-Object {
        $_.PSChildName -match 'teams' -or $_.PSChildName -match 'fastconnect' -or $_.PSChildName -match 'addinloader'
    }

    foreach ($k in $teamsKeys) {
        $current = $null
        try { $current = (Get-ItemProperty -Path $k.PSPath -ErrorAction Stop).LoadBehavior } catch {}
        if ($current -ne 3) {
            New-ItemProperty -Path $k.PSPath -Name "LoadBehavior" -PropertyType DWord -Value 3 -Force | Out-Null
            $changed = $true
        }
    }

    $fallbackKey = "HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect"
    if (-not (Test-Path $fallbackKey)) { New-Item -Path $fallbackKey -Force | Out-Null; $changed = $true }

    $fb = $null
    try { $fb = (Get-ItemProperty -Path $fallbackKey -ErrorAction Stop).LoadBehavior } catch {}
    if ($fb -ne 3) {
        New-ItemProperty -Path $fallbackKey -Name "LoadBehavior" -PropertyType DWord -Value 3 -Force | Out-Null
        $changed = $true
    }

    if ($changed) {
        Write-TinyLog "OK: Registered $($best.VersionName) from $($best.BasePath) ($platform), LoadBehavior enforced."
    }

} catch {
    Write-TinyLog ("ERROR: " + $_.Exception.Message)
}

exit 0
