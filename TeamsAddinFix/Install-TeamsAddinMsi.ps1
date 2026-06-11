<#
.SYNOPSIS
    Installs the Teams Meeting Add-in MSI machine-wide, for ALL users.

.DESCRIPTION
    Run elevated, typically once while setting up a laptop:

        powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-TeamsAddinMsi.ps1 -MsiPath .\MicrosoftTeamsMeetingAddinInstaller.msi

    Why this script exists: running the MSI by hand as an admin - even with
    "install for all users" / ALLUSERS=1 - still drops the FILES into the
    installing admin's own profile (%LOCALAPPDATA%), which other users of the
    machine cannot read. The add-in then never loads for the laptop's actual
    user. ALLUSERS only controls registration, not where the payload lands.

    This script avoids that trap by reading the MSI's own ProductVersion and
    forcing TARGETDIR to a machine-wide, world-readable folder named after it:

        C:\Program Files (x86)\Microsoft\TeamsMeetingAdd-in\<version>\

    which is one of the locations Fix-TeamsMeetingAddin.ps1 (deployed by
    Deploy-TeamsAddinFix.ps1) scans: at every logon, each user gets registered
    against the newest usable copy on the machine - no per-user install needed.

    Best run on a fresh machine, before users have launched Teams.
#>
[CmdletBinding()]
param(
    [string]$MsiPath = (Join-Path $PSScriptRoot 'MicrosoftTeamsMeetingAddinInstaller.msi')
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'This script must be run elevated (as Administrator / System).'
    exit 1
}

if (-not (Test-Path $MsiPath)) {
    Write-Error "MSI not found: $MsiPath (pass -MsiPath or put the MSI next to this script)."
    exit 1
}
$MsiPath = (Resolve-Path $MsiPath).Path

# Read ProductVersion out of the MSI so the version folder matches the payload
try {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $db = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($MsiPath, 0))
    $view = $db.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $db, @("SELECT Value FROM Property WHERE Property = 'ProductVersion'"))
    $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)
    $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
    $version = $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, @(1))
    $view.GetType().InvokeMember('Close', 'InvokeMethod', $null, $view, $null)
} catch {
    Write-Error "Could not read ProductVersion from $MsiPath : $($_.Exception.Message)"
    exit 1
}
if (-not $version) {
    Write-Error "MSI has no ProductVersion property - is this the right installer?"
    exit 1
}

$pfBase = ${env:ProgramFiles(x86)}
if (-not $pfBase) { $pfBase = $env:ProgramFiles }
$targetDir = Join-Path $pfBase "Microsoft\TeamsMeetingAdd-in\$version"

Write-Host "Installing Teams Meeting Add-in $version machine-wide to:"
Write-Host "  $targetDir"
$msiArgs = @('/i', "`"$MsiPath`"", 'ALLUSERS=1', "TARGETDIR=`"$targetDir`"", '/qn', '/norestart')
$proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
    Write-Error "msiexec failed with exit code $($proc.ExitCode)."
    exit 1
}

# Sanity check: the loader DLL must be where the logon fix will look for it
$dll = Join-Path $targetDir 'x64\Microsoft.Teams.AddinLoader.dll'
$dll32 = Join-Path $targetDir 'x86\Microsoft.Teams.AddinLoader.dll'
if ((Test-Path $dll) -or (Test-Path $dll32)) {
    Write-Host "Install verified: loader DLL present under $targetDir"
} else {
    Write-Warning "msiexec reported success (exit $($proc.ExitCode)) but no loader DLL found under $targetDir - check the install."
    exit 1
}

Write-Host 'Done. Each user is registered automatically at their next logon by the TeamsAddinFix task.'
exit 0
