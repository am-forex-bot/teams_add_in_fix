' RunHiddenTeamsAddInFix.vbs - runs the supplied command completely hidden (no window)
' Usage: wscript.exe //B //NoLogo RunHiddenTeamsAddInFix.vbs <program> [args...]
Dim shell, cmd, arg, i
cmd = ""
For i = 0 To WScript.Arguments.Count - 1
  arg = WScript.Arguments(i)
  If InStr(arg, " ") > 0 Then arg = """" & arg & """"
  cmd = cmd & " " & arg
Next
Set shell = CreateObject("WScript.Shell")
shell.Run Trim(cmd), 0, False
