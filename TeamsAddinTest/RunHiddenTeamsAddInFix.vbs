' RunHiddenTeamsAddInFix.vbs - runs a command hidden (no window)
Dim shell, cmd, i
cmd = ""
For i = 0 To WScript.Arguments.Count - 1
  cmd = cmd & " " & WScript.Arguments(i)
Next
Set shell = CreateObject("WScript.Shell")
shell.Run Trim(cmd), 0, False
