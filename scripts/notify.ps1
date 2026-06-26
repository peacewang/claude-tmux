# Fire a Windows toast notification from WSL via PowerShell 5.1's built-in
# WinRT bindings (no BurntToast, no extra exe).
#
# This script is intentionally PURE ASCII: Chinese / emoji live in the UTF-8
# XML file passed via -XmlPath, read with -Encoding UTF8 so PowerShell 5.1
# decodes it correctly regardless of the system ANSI code page.
#
# Usage (from notify.sh):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File notify.ps1 -XmlPath <win-path>
#
# Exit code non-zero on failure so notify.sh can fall back to wsl-notify-send.
param([Parameter(Mandatory=$true)][string]$XmlPath)

$ErrorActionPreference = 'Stop'

try {
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

    $xmlText = Get-Content -Raw -Encoding UTF8 -LiteralPath $XmlPath
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($xmlText)
    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    # AppId controls the toast's display name / grouping in Action Center.
    # Unregistered AppIds still display (Windows falls back to a generic
    # icon); registering a Start Menu shortcut would refine the icon.
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('ClaudeTmux.Notifier')
    $notifier.Show($toast)
    Write-Output "NOTIFY_PS_OK"
    exit 0
} catch {
    Write-Output "NOTIFY_PS_ERR: $($_.Exception.Message)"
    exit 1
}
