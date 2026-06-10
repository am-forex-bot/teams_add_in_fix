<#
.SYNOPSIS
    Deploys the Teams Meeting Add-in preventive fix to this machine.

.DESCRIPTION
    Copies the fix files to C:\ProgramData\TeamsAddinFix and registers a
    hidden scheduled task ("TeamsAddinFix") that runs the fix silently in
    each user's own context at every logon:

        - no admin rights / UAC prompt at runtime
        - no window shown to the user
        - Outlook is never closed or restarted

    Run this script ONCE per machine, elevated. Push it with your RMM,
    Intune (platform script, run as System, 64-bit), or a GPO computer
    startup script:

        powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Deploy-TeamsAddinFix.ps1

    Re-running is safe: files are overwritten and the task is replaced.
    Remove everything with Uninstall-TeamsAddinFix.ps1.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:ProgramData 'TeamsAddinFix'),
    [string]$TaskName   = 'TeamsAddinFix'
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'This script must be run elevated (as Administrator / System).'
    exit 1
}

try {
    $sourceDir = $PSScriptRoot
    $payload = @('Fix-TeamsMeetingAddin.ps1', 'RunHiddenTeamsAddInFix.vbs', 'FixTeamsAddin_Manual.bat')

    foreach ($f in $payload) {
        if (-not (Test-Path (Join-Path $sourceDir $f))) {
            throw "Missing '$f' next to this script. Deploy the whole TeamsAddinFix folder."
        }
    }

    Write-Host "Installing to $InstallDir ..."
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    foreach ($f in $payload) {
        Copy-Item -Path (Join-Path $sourceDir $f) -Destination (Join-Path $InstallDir $f) -Force
        Unblock-File -Path (Join-Path $InstallDir $f) -ErrorAction SilentlyContinue
    }

    # Standard users get read/execute only, so one user cannot plant code that
    # runs at another user's logon. SIDs keep this locale-independent.
    & icacls.exe $InstallDir /inheritance:r /grant '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "icacls exited with code $LASTEXITCODE - check ACLs on $InstallDir" }

    $vbsPath = Join-Path $InstallDir 'RunHiddenTeamsAddInFix.vbs'
    $ps1Path = Join-Path $InstallDir 'Fix-TeamsMeetingAddin.ps1'

    $usersGroup = ([Security.Principal.SecurityIdentifier]'S-1-5-32-545').Translate([Security.Principal.NTAccount]).Value

    $action = New-ScheduledTaskAction -Execute 'wscript.exe' `
        -Argument "//B //NoLogo `"$vbsPath`" powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ps1Path`""
    $trigger       = New-ScheduledTaskTrigger -AtLogOn
    $taskPrincipal = New-ScheduledTaskPrincipal -GroupId $usersGroup -RunLevel Limited
    $settings      = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -Hidden -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Principal $taskPrincipal -Settings $settings -Force `
        -Description 'Silently re-registers the Teams Meeting Add-in for Outlook at user logon (preventive fix).' | Out-Null
    Write-Host "Scheduled task '$TaskName' registered (runs at every user logon)."

    # Best effort: also fix whoever is logged on right now. If nobody is
    # logged on, the task simply runs at the next logon instead.
    try {
        Start-ScheduledTask -TaskName $TaskName
        Write-Host 'Triggered an immediate first run for the current user.'
    } catch {
        Write-Host 'Could not trigger an immediate run - fix will apply at next logon.'
    }

    Write-Host 'Deployment complete.'
    exit 0
}
catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    exit 1
}
