@echo off
rem Manual run: same as the logon script, runs the fix hidden for the current user.
wscript.exe //B //NoLogo "%SystemRoot%\System32\RunHiddenTeamsAddInFix.vbs" cmd.exe /c "%SystemRoot%\System32\Fix-TeamsMeetingAddin.cmd"
exit /b 0
