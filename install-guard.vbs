' install-guard.vbs - double-click this once to install the dsh-guard launcher.
' It runs install-guard.ps1 hidden, then shows the result in a message box.

Option Explicit

Dim fso, sh, base, ps, cmd, rc, msg

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

base = fso.GetParentFolderName(WScript.ScriptFullName)

If fso.FileExists("C:\Program Files\PowerShell\7\pwsh.exe") Then
  ps = """C:\Program Files\PowerShell\7\pwsh.exe"""
Else
  ps = """" & sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"""
End If

cmd = ps & " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & base & "\install-guard.ps1"""
rc = sh.Run(cmd, 0, True)

If fso.FileExists(base & "\install-result.txt") Then
  msg = fso.OpenTextFile(base & "\install-result.txt", 1).ReadAll()
Else
  msg = "No result file. Exit code: " & rc
End If

MsgBox msg, 64, "dsh-guard install result"
