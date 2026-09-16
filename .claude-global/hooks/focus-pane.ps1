# claude-pane://%27 を受けて WezTerm を前面化し、該当 pane へ移動する。
#
# BOM 付き UTF-8 で保存すること。PowerShell 5.1 は BOM が無いと CP932 として
# 読むため、非ASCIIを含むと構文が壊れる。
#
# WezTerm の前面化に wezterm cli を使わない理由:
#   default_domain が WSL ドメインのため CLI ソケットが Windows 側に露出せず、
#   Windows から実行しても gui-sock に接続できない(実測)。
#
# AppActivate ではなく Win32 API を直接叩く理由:
#   トーストのクリックから wscript→powershell と2段挟むとフォアグラウンド権限が
#   落ち、AppActivate が True を返しても実際には前面化しない(実測)。
#   AttachThreadInput で前面ウィンドウのスレッドに入力状態を接続し、
#   SetForegroundWindow の制限を回避する。

param([string]$Url)

$sig = @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr pid);
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
'@
$W = Add-Type -MemberDefinition $sig -Name Win -Namespace Fg -PassThru

# pane が閉じている・URL が壊れている場合でも、WezTerm を前面に出すところまでは
# 必ず行う。通知から「今いる場所」へ戻れることを最優先する。
$p = Get-Process wezterm-gui -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p) {
  $h = $p.MainWindowHandle
  if ($W::IsIconic($h)) { $W::ShowWindow($h, 9) | Out-Null }  # 9 = SW_RESTORE
  $fg = $W::GetForegroundWindow()
  $tFg = $W::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
  $tMe = $W::GetCurrentThreadId()
  $W::AttachThreadInput($tMe, $tFg, $true) | Out-Null
  $W::BringWindowToTop($h) | Out-Null
  $W::SetForegroundWindow($h) | Out-Null
  $W::AttachThreadInput($tMe, $tFg, $false) | Out-Null
}

$paneId = $Url -replace '^claude-pane:/*', '' -replace '/$', ''
if ($paneId -notmatch '^%\d+$') { exit 0 }

# tmux のソケットは WSLg の runtime-dir にあり、新規 wsl.exe には
# TMUX_TMPDIR が引き継がれないため明示指定する。
$sock = '/mnt/wslg/runtime-dir/tmux-1000/default'

# pane が存在しなければ何もしない(前面化のみで終わる)。
$cmd = "s=`$(tmux -S $sock display-message -p -t '$paneId' '#{session_name}:#{window_index}' 2>/dev/null) || exit 0; " +
       "tmux -S $sock switch-client -t `"`${s%:*}`" 2>/dev/null; " +
       "tmux -S $sock select-window -t `"`$s`" 2>/dev/null; " +
       "tmux -S $sock select-pane -t '$paneId' 2>/dev/null"
& "$env:SystemRoot\System32\wsl.exe" -d Ubuntu-22.04 -e bash -lc $cmd 2>$null
exit 0
