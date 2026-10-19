' dsh-guard.vbs - hidden launcher for dsh-guard.ps1
' The .lnk shortcuts point here; it starts the guard with no visible console.
' All paths are derived from this script's own location (ASCII-only on purpose).

Option Explicit

Dim fso, sh, base, ps7, ps51, cmd

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")

base = fso.GetParentFolderName(WScript.ScriptFullName)
ps7 = "C:\Program Files\PowerShell\7\pwsh.exe"
ps51 = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"

If fso.FileExists(ps7) Then
  cmd = """" & ps7 & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & base & "\dsh-guard.ps1"""
Else
  cmd = """" & ps51 & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & base & "\dsh-guard.ps1"""
End If

' 0 = hidden window, False = don't wait
sh.Run cmd, 0, False
