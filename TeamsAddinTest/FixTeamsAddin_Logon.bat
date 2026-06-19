@echo off
rem Logon script: runs the Teams add-in fix hidden, in the user's context.
rem No PowerShell - the worker is Fix-TeamsMeetingAddin.cmd.
wscript.exe //B //NoLogo "%SystemRoot%\System32\RunHiddenTeamsAddInFix.vbs" cmd.exe /c "%SystemRoot%\System32\Fix-TeamsMeetingAddin.cmd"
exit /b 0
