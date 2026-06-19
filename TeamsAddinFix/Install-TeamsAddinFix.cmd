@echo off
setlocal

rem Install-TeamsAddinFix.cmd
rem PowerShell-FREE installer for the Teams Meeting Add-in preventive fix.
rem Run from an ELEVATED command prompt (right-click cmd > Run as administrator).
rem
rem Usage:
rem   Install-TeamsAddinFix.cmd
rem       installs to %ProgramData%\TeamsAddinFix, hidden launcher (no flash)
rem   Install-TeamsAddinFix.cmd "C:\YourExcludedFolder\TeamsAddinFix"
rem       installs to a custom / EDR-excluded folder (recommended under Aurora)
rem   Install-TeamsAddinFix.cmd "C:\YourExcludedFolder\TeamsAddinFix" visible
rem       use this if wscript is blocked: task runs cmd directly (brief flash)
rem
rem Needs Fix-TeamsMeetingAddin.cmd and RunHiddenTeamsAddInFix.vbs in the same
rem folder as this script.

set "TASKNAME=TeamsAddinFix"
set "SRC=%~dp0"
set "INSTALLDIR=%~1"
if "%INSTALLDIR%"=="" set "INSTALLDIR=%ProgramData%\TeamsAddinFix"
set "MODE=%~2"
if "%MODE%"=="" set "MODE=hidden"

rem --- require elevation (fsutil dirty query needs admin; no service dependency) ---
fsutil dirty query %SystemDrive% >nul 2>&1
if errorlevel 1 (
  echo [X] Run this from an ELEVATED command prompt ^(right-click cmd ^> Run as administrator^).
  exit /b 1
)

rem --- payload must be present next to this script ---
if not exist "%SRC%Fix-TeamsMeetingAddin.cmd"  ( echo [X] Missing Fix-TeamsMeetingAddin.cmd next to this script.  & exit /b 1 )
if not exist "%SRC%RunHiddenTeamsAddInFix.vbs" ( echo [X] Missing RunHiddenTeamsAddInFix.vbs next to this script. & exit /b 1 )

echo [*] Installing to "%INSTALLDIR%"
if not exist "%INSTALLDIR%" mkdir "%INSTALLDIR%"

rem --- copy payload (skip if running in place to avoid copy-onto-itself) ---
if /i not "%SRC:~0,-1%"=="%INSTALLDIR%" (
  copy /y "%SRC%Fix-TeamsMeetingAddin.cmd"  "%INSTALLDIR%\" >nul
  copy /y "%SRC%RunHiddenTeamsAddInFix.vbs" "%INSTALLDIR%\" >nul
)

rem --- lock down: SYSTEM + Administrators full, standard Users read/execute only ---
icacls "%INSTALLDIR%" /inheritance:r /grant "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" >nul
if errorlevel 1 echo [!] icacls returned %errorlevel% - check permissions on "%INSTALLDIR%".

echo [*] Creating scheduled task "%TASKNAME%" (runs at each user logon, in their own context)...
if /i "%MODE%"=="visible" goto :mkvisible

:mkhidden
schtasks /create /tn "%TASKNAME%" /sc onlogon /ru "Users" /rl limited /f /tr "wscript.exe //B //NoLogo \"%INSTALLDIR%\RunHiddenTeamsAddInFix.vbs\""
goto :aftercreate

:mkvisible
schtasks /create /tn "%TASKNAME%" /sc onlogon /ru "Users" /rl limited /f /tr "cmd.exe /c \"%INSTALLDIR%\Fix-TeamsMeetingAddin.cmd\""
goto :aftercreate

:aftercreate
if errorlevel 1 ( echo [X] Task creation failed. & exit /b 1 )

echo [*] Running the fix for the current user now...
schtasks /run /tn "%TASKNAME%" >nul 2>&1
if errorlevel 1 (
  echo [!] Could not trigger the task; running the fix directly instead.
  call "%INSTALLDIR%\Fix-TeamsMeetingAddin.cmd"
)

echo.
echo [OK] Done. Task "%TASKNAME%" installed (mode: %MODE%); current user fixed.
echo      Check the log at: %%LOCALAPPDATA%%\TeamsAddinFix\TeamsAddinFix.log
exit /b 0
