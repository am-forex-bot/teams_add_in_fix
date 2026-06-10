@echo off
rem Runs the Teams Meeting Add-in fix immediately for the current user, fully hidden.
rem Requires the fix to be deployed first (Deploy-TeamsAddinFix.ps1).
rem Also usable as a GPO user logon script if you prefer that over the scheduled task.
wscript.exe //B //NoLogo "%ProgramData%\TeamsAddinFix\RunHiddenTeamsAddInFix.vbs" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ProgramData%\TeamsAddinFix\Fix-TeamsMeetingAddin.ps1"
exit /b 0
