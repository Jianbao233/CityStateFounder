# ===========================================================================
# check_alive.ps1 —— 【每次执行 Lua 脚本后都必须跑】
#
# 用户明确要求（2026-10-05）：
#   "我建议你每次执行脚本都检查游戏存活状态"
#
# 为什么必需：原生层的崩溃不会让 pcall 报错，也不会立刻反映到脚本输出上，
# 只能靠外部检查发现。此前我漏检了两次，用户先发现弹窗。
#
# 用法：  pwsh -File check_alive.ps1
# 返回：  退出码 0 = 游戏健康；1 = 有问题（弹窗 / 挂起 / 已退出）
# ===========================================================================

$ErrorActionPreference = 'SilentlyContinue'

$g    = 'F:\Steam\steamapps\common\Sid Meier''s Civilization VI'
$la   = Join-Path $env:LOCALAPPDATA "Firaxis Games\Sid Meier's Civilization VI\Logs"
$cl   = "$g\DLC\Expansion2\Logs\C6FW.log"
$ok   = $true

# --- ① 进程 ---
$pr = Get-Process -Name 'CivilizationVI*' -ErrorAction SilentlyContinue
if ($pr) {
    Write-Output "  进程      : OK ($($pr.ProcessName))"
} else {
    Write-Output "  进程      : [X] 已退出"
    $ok = $false
}

# --- ② Tuner 端口（进程活着但端口拒绝 = 挂起）---
$tuner = Test-NetConnection -ComputerName 127.0.0.1 -Port 4318 -InformationLevel Quiet -WarningAction SilentlyContinue
if ($tuner) {
    Write-Output "  Tuner 4318: OK"
} else {
    Write-Output "  Tuner 4318: [X] 拒绝连接（进程活着 = 已挂起）"
    if ($pr) { $ok = $false }
}

# --- ③ 错误弹窗（读全文，含滚动区）---
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class CSFCheck {
  [DllImport("user32.dll")] public static extern bool EnumWindows(P cb, IntPtr p);
  public delegate bool P(IntPtr h, IntPtr p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, P cb, IntPtr p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h, uint m, IntPtr w, StringBuilder l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public static List<string> Dump() { var o=new List<string>();
    EnumWindows((h,p)=>{ var t=new StringBuilder(512); GetWindowTextW(h,t,512);
      string s=t.ToString();
      if(IsWindowVisible(h) && (s.Contains("Exception")||s.Contains("Unhandled")||s.Contains("Error"))) {
        o.Add("WINDOW: " + s);
        EnumChildWindows(h,(c,p2)=>{ var ct=new StringBuilder(128); GetClassNameW(c,ct,128);
          var tt=new StringBuilder(8192); SendMessageW(c,0x000D,(IntPtr)8192,tt);
          string v=tt.ToString();
          if(v.Length>0 && ct.ToString().Contains("Edit")) {
            // 只取前 300 字，避免刷屏
            o.Add("  " + v.Substring(0, [Math]::Min(300, v.Length)).Replace("\r\n"," | "));
          }
          return true; }, IntPtr.Zero); }
      return true; }, IntPtr.Zero); return o; }
}
"@ -ReferencedAssemblies System.Windows.Forms | Out-Null

$w = [CSFCheck]::Dump()
if ($w.Count -eq 0) {
    Write-Output "  错误弹窗  : OK（无）"
} else {
    Write-Output "  错误弹窗  : [X] 有！"
    $w | ForEach-Object { Write-Output "    $_" }
    $ok = $false
}

# --- ④ 事件日志（最近 15 分钟）---
$ev = Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Error','Application Hang'; StartTime=(Get-Date).AddMinutes(-15)} -MaxEvents 3 -ErrorAction SilentlyContinue
if ($ev) {
    Write-Output "  事件日志  : [X] 最近有崩溃"
    $ev | ForEach-Object {
        $mod = if ($_.Message -match '出错模块名称：\s*([^，,]+)') { $Matches[1].Trim() } else { '?' }
        $addr = if ($_.Message -match '错误偏移：\s*(\S+)') { $Matches[1] } else { '?' }
        Write-Output "    $($_.TimeCreated.ToString('HH:mm:ss')) [$($_.ProviderName)] 模块=$mod 偏移=$addr"
    }
} else {
    Write-Output "  事件日志  : OK（最近 15 分钟无崩溃）"
}

# --- ⑤ C6FW 桥（若已装）---
if (Test-Path $cl) {
    $tail = Get-Content $cl -Tail 2 -ErrorAction SilentlyContinue
    if ($tail) { Write-Output "  C6FW 尾部 : $($tail[-1].Trim().Substring(0,[Math]::Min(90,$tail[-1].Trim().Length)))" }
}

Write-Output ""
if ($ok) { Write-Output "  ==> 游戏健康 [OK]" } else { Write-Output "  ==> 有问题 [X] —— 停止操作，先读弹窗" }
exit $(if ($ok) { 0 } else { 1 })
