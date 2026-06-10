# Fix-TeamsMeetingAddin.ps1 (v6 - SILENT, USER CONTEXT, NO OUTLOOK CLOSE, BOTH FOLDER NAMES)
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

function Get-LatestAddinFolder {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\TeamsMeetingAddin"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\TeamsMeetingAdd-in")
    ) | Where-Object { Test-Path $_ }

    if (-not $candidates) { return $null }

    $all = @()
    foreach ($base in $candidates) {
        $dirs = Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            ForEach-Object {
                [PSCustomObject]@{
                    BasePath    = $base
                    VersionName = $_.Name
                    Version     = [version]$_.Name
                    FullPath    = $_.FullName
                }
            }
        if ($dirs) { $all += $dirs }
    }

    if (-not $all) { return $null }
    return ($all | Sort-Object Version -Descending | Select-Object -First 1)
}

$changed = $false

try {
    $latestInfo = Get-LatestAddinFolder
    if (-not $latestInfo) {
        Write-TinyLog "ERROR: No TeamsMeetingAddin folder/version found (checked Addin and Add-in)."
        exit 0
    }

    # Detect Office platform (Click-to-Run)
    $platform = $null
    $ctrKey = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
    try { $platform = (Get-ItemProperty -Path $ctrKey -ErrorAction Stop).Platform } catch { $platform = "x64" }
    if ($platform -notin @("x86","x64")) { $platform = "x64" }

    $addinDll = Join-Path $latestInfo.FullPath (Join-Path $platform "Microsoft.Teams.AddinLoader.dll")
    if (-not (Test-Path $addinDll)) {
        Write-TinyLog "ERROR: Loader DLL missing at expected path ($platform) under $($latestInfo.FullPath)"
        exit 0
    }

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
        Write-TinyLog "OK: Reg+LB enforced (base=$($latestInfo.BasePath), ver=$($latestInfo.VersionName), platform=$platform)."
    }

} catch {
    Write-TinyLog ("ERROR: " + $_.Exception.Message)
}

exit 0
