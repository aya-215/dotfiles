Add-Type @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class WL {
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out R r);
  [StructLayout(LayoutKind.Sequential)] public struct R{public int L,T,Ri,B;}
  delegate bool EnumProc(IntPtr h, IntPtr p);
  public static List<string> Go(int target) {
    var res = new List<string>();
    EnumWindows((h,p) => {
      int pid; GetWindowThreadProcessId(h, out pid);
      if (pid != target || !IsWindowVisible(h)) return true;
      var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
      R r; GetWindowRect(h, out r);
      res.Add(h.ToInt64() + "|" + (r.Ri-r.L) + "x" + (r.B-r.T) + "|" + sb.ToString());
      return true;
    }, IntPtr.Zero);
    return res;
  }
}
"@
foreach ($p in Get-Process thunderbird -EA SilentlyContinue) {
  foreach ($w in [WL]::Go($p.Id)) { Write-Output "$($p.Id) $w" }
}
