$Handle = [IntPtr][int64]$args[0]
$Out = $args[1]
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public class W3 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT{public int L,T,R,B;}
}
"@
[W3]::BringWindowToTop($Handle) | Out-Null
[W3]::SetForegroundWindow($Handle) | Out-Null
Start-Sleep -Milliseconds 1500
$r = New-Object W3+RECT
[W3]::GetWindowRect($Handle,[ref]$r) | Out-Null
$w = $r.R-$r.L; $h = $r.B-$r.T
$bmp = New-Object System.Drawing.Bitmap $w,$h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L,$r.T,0,0,$bmp.Size)
$bmp.Save($Out,[System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "OK ${w}x${h}"
