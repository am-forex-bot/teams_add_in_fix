<#
.SYNOPSIS
    Removes the Teams Meeting Add-in preventive fix from this machine.

.DESCRIPTION
    Deletes the "TeamsAddinFix" scheduled task and the files under
    C:\ProgramData\TeamsAddinFix. Run elevated.

    Per-user add-in registrations and LoadBehavior values written by past
    runs are left in place on purpose - they ARE the fix, and removing them
    would re-break Outlook for those users.
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

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed scheduled task '$TaskName'."
} else {
    Write-Host "Scheduled task '$TaskName' not found - nothing to remove."
}

if (Test-Path $InstallDir) {
    Remove-Item -Path $InstallDir -Recurse -Force
    Write-Host "Removed $InstallDir."
} else {
    Write-Host "$InstallDir not found - nothing to remove."
}

Write-Host 'Uninstall complete.'
exit 0
