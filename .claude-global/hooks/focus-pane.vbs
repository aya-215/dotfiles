' claude-pane:// のハンドラ。PowerShell を隠して起動するためのラッパー。
' powershell.exe を直接ハンドラにするとコンソールウィンドウが一瞬表示されるため、
' GUI サブシステムの wscript.exe から WindowStyle=0 で起動する。
Dim url, ps
url = ""
If WScript.Arguments.Count > 0 Then
  url = WScript.Arguments.Item(0)
End If
ps = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ _
   & "C:\Users\368\AppData\Local\ClaudeCodeToast\focus-pane.ps1"" """ & url & """"
CreateObject("WScript.Shell").Run ps, 0, False
