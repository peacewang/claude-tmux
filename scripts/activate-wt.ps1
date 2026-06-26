# Bring the host terminal (Windows Terminal running tmux) to the foreground.
# Called by restore.sh so the tmux popup is visible even when the user was in
# another app when they clicked the toast.
#
# Must run AFTER wsl.exe (the protocol handler) has exited: while wsl.exe runs,
# the Windows Terminal process's MainWindowHandle non-deterministically points
# at a helper window titled with the wsl.exe path; once wsl.exe exits, it
# returns to the real "Ubuntu-22.04" terminal window. So restore.sh launches us
# in the background and we sleep briefly first.
#
# Pure ASCII on purpose (PowerShell 5.1 reads no-BOM .ps1 as ANSI on zh-CN).
$ErrorActionPreference = 'SilentlyContinue'

Add-Type -Namespace WTAct -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int n);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
'@

# Wait for wsl.exe (the protocol handler) to exit so MainWindowHandle recovers
# the real terminal window instead of the wsl.exe-path helper window.
Start-Sleep -Milliseconds 1500

# Host terminal = earliest-started terminal process with a visible window.
$wt = @(Get-Process WindowsTerminal -ErrorAction SilentlyContinue) +
     @(Get-Process powershell -ErrorAction SilentlyContinue) |
     Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
     Sort-Object StartTime |
     Select-Object -First 1

if ($wt) {
    # AttachThreadInput to bypass the foreground lock (caller is a hidden PS).
    $fg       = [WTAct.Win32]::GetForegroundWindow()
    $fgThread = [WTAct.Win32]::GetWindowThreadProcessId($fg, [ref]0)
    $myThread = [WTAct.Win32]::GetCurrentThreadId()
    [WTAct.Win32]::AttachThreadInput($myThread, $fgThread, $true) | Out-Null
    [WTAct.Win32]::ShowWindowAsync($wt.MainWindowHandle, 9) | Out-Null   # SW_RESTORE
    [void][WTAct.Win32]::SetForegroundWindow($wt.MainWindowHandle)
    [WTAct.Win32]::AttachThreadInput($myThread, $fgThread, $false) | Out-Null
}
