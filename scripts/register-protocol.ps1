# One-shot: register the claudetmux:// URL protocol under HKCU (no admin needed).
#
# When Windows activates claudetmux://<session>, it runs the command below,
# which hands off to restore.sh inside WSL. %1 is replaced by the full URL
# (e.g. claudetmux://claude-abcd1234/).
#
# Usage (from install-wsl-notify.sh):
#   powershell.exe -File register-protocol.ps1 -RestoreScriptPath /abs/wsl/restore.sh
#
# Pure ASCII on purpose (PowerShell 5.1 reads no-BOM .ps1 as ANSI on zh-CN).
param([Parameter(Mandatory=$true)][string]$RestoreScriptPath)

$ErrorActionPreference = 'Stop'
$base = 'HKCU:\Software\Classes\claudetmux'

New-Item -Path $base -Force | Out-Null
Set-ItemProperty -Path $base -Name '(Default)'   -Value 'URL: Claude-tmux session restore'
Set-ItemProperty -Path $base -Name 'URL Protocol' -Value ''

$cmdKey = "$base\shell\open\command"
New-Item -Path $cmdKey -Force | Out-Null
# Direct wsl.exe: the ONLY launcher that toast-action protocol activation
# actually starts (hidden launchers like wscript/powershell aren't started by
# toast activation — confirmed empty vbs log). wsl.exe gets a brief console
# window; restore.sh fires display-popup in the background and exits in ~0.5s
# so that window only flashes, and activates the Windows Terminal window first.
$cmd = 'wsl.exe -e bash -lc "{0} %1"' -f $RestoreScriptPath
Set-ItemProperty -Path $cmdKey -Name '(Default)' -Value $cmd

Write-Output "PROTOCOL_REGISTERED"
Write-Output "  scheme  = claudetmux://"
Write-Output "  command = $cmd"
