@echo off
setlocal

rem Uninstall-TeamsAddinFix.cmd
rem PowerShell-free removal of the preventive fix. Run from an ELEVATED prompt.
rem   Uninstall-TeamsAddinFix.cmd                         (default ProgramData)
rem   Uninstall-TeamsAddinFix.cmd "C:\YourExcludedFolder\TeamsAddinFix"

set "TASKNAME=TeamsAddinFix"
set "INSTALLDIR=%~1"
if "%INSTALLDIR%"=="" set "INSTALLDIR=%ProgramData%\TeamsAddinFix"

fsutil dirty query %SystemDrive% >nul 2>&1
if errorlevel 1 ( echo [X] Run this from an ELEVATED command prompt. & exit /b 1 )

echo [*] Removing scheduled task "%TASKNAME%"...
schtasks /delete /tn "%TASKNAME%" /f >nul 2>&1

if exist "%INSTALLDIR%" (
  echo [*] Removing "%INSTALLDIR%"...
  rmdir /s /q "%INSTALLDIR%"
)

echo [OK] Uninstalled. Per-user registrations already applied are left in place
echo      (removing them would re-break Outlook for those users).
exit /b 0
