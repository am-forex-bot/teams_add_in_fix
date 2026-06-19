' RunHiddenTeamsAddInFix.vbs - runs a command completely hidden (no window).
'  - With arguments: runs the given program + args hidden, e.g.
'      wscript //B //NoLogo RunHiddenTeamsAddInFix.vbs <program> [args...]
'  - With NO arguments: runs the sibling Fix-TeamsMeetingAddin.cmd hidden
'    (used by the PowerShell-free scheduled task installed by Install-TeamsAddinFix.cmd)
Dim shell, fso, cmd, arg, i, scriptDir
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

If WScript.Arguments.Count = 0 Then
  scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
  cmd = "cmd.exe /c """ & scriptDir & "\Fix-TeamsMeetingAddin.cmd"""
Else
  cmd = ""
  For i = 0 To WScript.Arguments.Count - 1
    arg = WScript.Arguments(i)
    If InStr(arg, " ") > 0 Then arg = """" & arg & """"
    cmd = cmd & " " & arg
  Next
  cmd = Trim(cmd)
End If

shell.Run cmd, 0, False
