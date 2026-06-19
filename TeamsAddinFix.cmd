@echo off
setlocal EnableDelayedExpansion

rem ============================================================
rem  TeamsAddinFix.cmd
rem  Microsoft Teams Meeting Add-in for Outlook - fix + keep fixed.
rem  Re-registers the add-in for the signed-in user and forces it to
rem  load; on install it repeats this automatically at every logon, so
rem  it survives Teams / add-in version updates (it auto-detects the
rem  installed version). Pure cmd: schtasks + reg + regsvr32 + icacls.
rem  No PowerShell, no VBScript.
rem
rem  Run from an ADMIN command prompt:
rem     TeamsAddinFix.cmd install      set up on this machine (run once)
rem     TeamsAddinFix.cmd uninstall    remove it
rem     TeamsAddinFix.cmd              just apply the fix once, now
rem ============================================================

set "TASKNAME=TeamsAddinFix"
set "INSTALLDIR=%ProgramData%\TeamsAddinFix"

if /i "%~1"=="install"   goto :install
if /i "%~1"=="uninstall" goto :uninstall
goto :fix


:install
net session >nul 2>&1
if errorlevel 1 ( echo [X] Run this from an ADMIN command prompt ^(right-click cmd ^> Run as administrator^). & exit /b 1 )

echo [*] Installing to "%INSTALLDIR%" ...
if not exist "%INSTALLDIR%" mkdir "%INSTALLDIR%"

if /i not "%~f0"=="%INSTALLDIR%\TeamsAddinFix.cmd" copy /y "%~f0" "%INSTALLDIR%\TeamsAddinFix.cmd" >nul
if not exist "%INSTALLDIR%\TeamsAddinFix.cmd" ( echo [X] Could not place the script in "%INSTALLDIR%". & exit /b 1 )

rem lock down: SYSTEM + Administrators full, standard Users read/execute only
icacls "%INSTALLDIR%" /inheritance:r /grant "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" >nul 2>&1

echo [*] Creating logon task "%TASKNAME%" ...
schtasks /create /tn "%TASKNAME%" /sc onlogon /ru "Users" /rl limited /f /tr "cmd /c \"%INSTALLDIR%\TeamsAddinFix.cmd\"" >nul
if errorlevel 1 ( echo [X] Task creation failed. & exit /b 1 )

echo [*] Applying the fix to the current user now ...
call :fix

echo.
echo [OK] Done. The add-in is fixed now and will be re-checked at every logon
echo      (auto-detects the current version, so it survives Teams updates).
echo      Per-user log: %%LOCALAPPDATA%%\TeamsAddinFix\TeamsAddinFix.log
exit /b 0


:uninstall
net session >nul 2>&1
if errorlevel 1 ( echo [X] Run this from an ADMIN command prompt. & exit /b 1 )
echo [*] Removing task "%TASKNAME%" ...
schtasks /delete /tn "%TASKNAME%" /f >nul 2>&1
if exist "%INSTALLDIR%" rmdir /s /q "%INSTALLDIR%"
echo [OK] Removed. (Users it already fixed stay fixed.)
exit /b 0


:fix
set "LOGDIR=%LOCALAPPDATA%\TeamsAddinFix"
set "LOGFILE=%LOGDIR%\TeamsAddinFix.log"
if not exist "%LOGDIR%" mkdir "%LOGDIR%" 2>nul

rem Office bitness from Click-to-Run (default x64)
set "PLAT=x64"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" /v Platform 2^>nul ^| find /i "REG_SZ"') do set "PLAT=%%A"
if /i not "!PLAT!"=="x86" if /i not "!PLAT!"=="x64" set "PLAT=x64"

rem newest version folder that actually contains the loader DLL
set "DLL="
set "VER="
call :scan "%LOCALAPPDATA%\Microsoft\TeamsMeetingAdd-in"
call :scan "%LOCALAPPDATA%\Microsoft\TeamsMeetingAddin"
call :scan "%ProgramFiles(x86)%\Microsoft\TeamsMeetingAdd-in"
call :scan "%ProgramFiles%\Microsoft\TeamsMeetingAdd-in"

if not defined DLL (
  >>"%LOGFILE%" echo %date% %time%  ERROR: no !PLAT! loader DLL found under known add-in paths.
  goto :eof
)

if /i "!PLAT!"=="x64" ( set "RSVR=%WINDIR%\System32\regsvr32.exe" ) else ( set "RSVR=%WINDIR%\SysWOW64\regsvr32.exe" )
"!RSVR!" /s /n /i:user "!DLL!"

rem force LoadBehavior=3 on the fallback key + any teams-like add-in keys
reg add "HKCU\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect" /v LoadBehavior /t REG_DWORD /d 3 /f >nul 2>&1
for /f "delims=" %%K in ('reg query "HKCU\Software\Microsoft\Office\Outlook\Addins" 2^>nul ^| findstr /i "HKEY_" ^| findstr /i "teams fastconnect addinloader"') do (
  reg add "%%K" /v LoadBehavior /t REG_DWORD /d 3 /f >nul 2>&1
)

>>"%LOGFILE%" echo %date% %time%  OK: registered !VER! (!PLAT!), LoadBehavior=3.
goto :eof


:scan
rem %~1 = base folder; sets DLL/VER from newest versioned subfolder that has the loader DLL
if defined DLL goto :eof
set "BASE=%~1"
if not exist "!BASE!\" goto :eof
for /f "delims=" %%V in ('dir /b /ad /o-n "!BASE!" 2^>nul') do (
  if not defined DLL if exist "!BASE!\%%V\!PLAT!\Microsoft.Teams.AddinLoader.dll" (
    set "DLL=!BASE!\%%V\!PLAT!\Microsoft.Teams.AddinLoader.dll"
    set "VER=%%V"
  )
)
goto :eof
