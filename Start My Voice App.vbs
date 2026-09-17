Option Explicit

Dim files, shell, root, scriptPath, powershellPath, command, result
Set files = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
root = files.GetParentFolderName(WScript.ScriptFullName)
scriptPath = files.BuildPath(root, "Start My Voice App.ps1")
powershellPath = shell.ExpandEnvironmentStrings("%WINDIR%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
command = """" & powershellPath & """ -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """"
result = shell.Run(command, 0, True)
If result <> 0 Then
    MsgBox "The local voice app did not start. Open 'Last Voice App Start.txt' in the app folder for the reason.", vbExclamation, "My Local Voice App"
End If
