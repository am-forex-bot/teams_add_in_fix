@echo off
setlocal EnableDelayedExpansion

rem Fix-TeamsMeetingAddin.cmd
rem PowerShell-free version of the Teams Meeting Add-in fix, for endpoints
rem where PowerShell is blocked by EDR (e.g. Aurora). Runs in the logged-in
rem user's context - NO admin required. Safe to run from an EDR-excluded
rem folder. Mirrors Fix-TeamsMeetingAddin.ps1 v7: re-register the loader DLL
rem per-user and force LoadBehavior=3.
rem
rem Note: version selection uses cmd's name sort (dir /o-n), not true version
rem sort, so it is reliable when version folders share the same segment widths
rem (e.g. 1.24.31301 vs 1.25.x). The PowerShell version sorts by true [version].

set "LOGDIR=%LOCALAPPDATA%\TeamsAddinFix"
set "LOGFILE=%LOGDIR%\TeamsAddinFix.log"
if not exist "%LOGDIR%" mkdir "%LOGDIR%" 2>nul

rem --- Office bitness from Click-to-Run (default x64) ---
set "PLAT=x64"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" /v Platform 2^>nul ^| find /i "REG_SZ"') do set "PLAT=%%A"
if /i not "%PLAT%"=="x86" if /i not "%PLAT%"=="x64" set "PLAT=x64"

rem --- newest version folder that actually contains the loader DLL ---
set "DLL="
set "VER="
for %%B in (
  "%LOCALAPPDATA%\Microsoft\TeamsMeetingAdd-in"
  "%LOCALAPPDATA%\Microsoft\TeamsMeetingAddin"
  "%ProgramFiles(x86)%\Microsoft\TeamsMeetingAdd-in"
  "%ProgramFiles%\Microsoft\TeamsMeetingAdd-in"
) do (
  if exist "%%~B\" (
    for /f "delims=" %%V in ('dir /b /ad /o-n "%%~B" 2^>nul') do (
      if not defined DLL if exist "%%~B\%%V\%PLAT%\Microsoft.Teams.AddinLoader.dll" (
        set "DLL=%%~B\%%V\%PLAT%\Microsoft.Teams.AddinLoader.dll"
        set "VER=%%V"
      )
    )
  )
)

if not defined DLL (
  call :log "ERROR: no %PLAT% loader DLL found under any known add-in path."
  exit /b 0
)

if /i "%PLAT%"=="x64" (set "RSVR=%WINDIR%\System32\regsvr32.exe") else (set "RSVR=%WINDIR%\SysWOW64\regsvr32.exe")
"%RSVR%" /s /n /i:user "%DLL%"

rem --- enforce LoadBehavior=3 on the fallback key + any teams-like keys ---
reg add "HKCU\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect" /v LoadBehavior /t REG_DWORD /d 3 /f >nul 2>&1

for /f "delims=" %%K in ('reg query "HKCU\Software\Microsoft\Office\Outlook\Addins" 2^>nul ^| findstr /i "HKEY_" ^| findstr /i "teams fastconnect addinloader"') do (
  reg add "%%K" /v LoadBehavior /t REG_DWORD /d 3 /f >nul 2>&1
)

call :log "OK: registered %VER% (%PLAT%) and enforced LoadBehavior=3."
exit /b 0

:log
>>"%LOGFILE%" echo %date% %time%  %~1
exit /b 0
