# dsh-guard.ps1 - launch guard for DeepSeek Harness (DSH)
#
# What it does on every launch:
#   1. If DSH is already running with a window -> exit (no-op).
#   2. Kill stale/crashed DSH processes that hold GPU caches / ports.
#   3. Clear GPU cache dirs (the usual cause of "Desktop renderer exited: crashed").
#   4. Delete accumulated dsh-auth-* cookies (the 431 "Web authentication failed" bomb).
#   5. Launch DSH. If no window appears -> clean harder and retry.
#   6. Last resort: switch dsh-undo-savepoint to SAFE MODE and try once more.
#
# Usage:  dsh-guard.ps1 [-DryRun] [-WindowTimeoutSec 90]
#   -DryRun : check and log what WOULD happen, touch nothing.

param(
  [switch]$DryRun,
  [int]$WindowTimeoutSec = 90
)

$ErrorActionPreference = 'Continue'

$exePath      = 'E:\DeepSeek Harness\DeepSeek Harness.exe'
$appDir       = 'E:\DeepSeek Harness'
$procName     = 'DeepSeek Harness'
$guardDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile      = Join-Path $guardDir 'guard.log'
$lockFile     = Join-Path $guardDir 'guard.lock'
$userData     = Join-Path $env:APPDATA '@deepseek-ai\dsh-desktop'
$nodeExe      = 'C:\Users\ireina\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'
$undoCli      = 'C:\Users\ireina\.dsh\profiles\desktop\node_modules\dsh-undo-savepoint\tools\dsh-undo.ps1'
$cookieCleaner = Join-Path $guardDir 'clean-auth-cookies.mjs'
$gpuCaches    = @('GPUCache','ShaderCache','GrShaderCache','DawnGraphiteCache','DawnWebGPUCache','GPUPersistentCache')

function Write-GuardLog([string]$msg) {
  $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  try { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 } catch {}
}

function Get-DshProcesses {
  @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
}

$script:WinApiLoaded = $false
function Initialize-WinApi {
  if ($script:WinApiLoaded) { return }
  try {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class DshGuardWin {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  public static int CountWindows(uint[] pids) {
    int n = 0;
    EnumWindows((h, l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      foreach (var p in pids) {
        if (p == pid) {
          var c = new StringBuilder(256); GetClassNameW(h, c, 256);
          if (c.ToString().StartsWith("Chrome_WidgetWin")) { n++; }
          break;
        }
      }
      return true;
    }, IntPtr.Zero);
    return n;
  }
}
'@ -ErrorAction Stop
    $script:WinApiLoaded = $true
  } catch {
    Write-GuardLog "winapi load failed: $($_.Exception.Message)"
  }
}

function Test-WindowReady {
  param($procs)
  foreach ($p in $procs) {
    try { if ($p.MainWindowHandle -ne 0) { return $true } } catch {}
  }
  Initialize-WinApi
  if ($script:WinApiLoaded) {
    $pids = [uint32[]]@($procs | ForEach-Object { $_.Id })
    try {
      if ([DshGuardWin]::CountWindows($pids) -gt 0) { return $true }
    } catch {}
  }
  return $false
}

function Get-RecentCrashLog([int]$withinSec = 180) {
  $logs = Join-Path $userData 'logs'
  if (-not (Test-Path $logs)) { return $null }
  $cut = (Get-Date).AddSeconds(-$withinSec)
  $f = Get-ChildItem -LiteralPath $logs -Filter 'crash-*.log' -ErrorAction SilentlyContinue |
       Where-Object { $_.LastWriteTime -gt $cut } |
       Sort-Object LastWriteTime -Descending |
       Select-Object -First 1
  return $f
}

function Stop-DshProcesses {
  $procs = Get-DshProcesses
  if ($procs.Count -eq 0) { return $true }
  foreach ($p in $procs) {
    try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
  }
  $deadline = (Get-Date).AddSeconds(15)
  while ((Get-Date) -lt $deadline) {
    if ((Get-DshProcesses).Count -eq 0) { return $true }
    Start-Sleep -Milliseconds 300
  }
  return ((Get-DshProcesses).Count -eq 0)
}

function Clear-GpuCaches {
  $removed = 0
  $failed  = @()
  foreach ($name in $gpuCaches) {
    $dir = Join-Path $userData $name
    if (-not (Test-Path $dir)) { continue }
    try {
      Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
      $removed++
    } catch {
      $failed += $name
    }
  }
  $failText = if ($failed.Count -gt 0) { $failed -join ',' } else { 'none' }
  Write-GuardLog ("gpu cache cleared: {0} dir(s), failed: {1}" -f $removed, $failText)
}

function Clear-CodeCache {
  $dir = Join-Path $userData 'Code Cache'
  if (Test-Path $dir) {
    try {
      Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
      Write-GuardLog 'code cache cleared'
    } catch {
      Write-GuardLog 'code cache clear failed (locked)'
    }
  }
}

function Clear-AuthCookies {
  if (-not (Test-Path $nodeExe)) { Write-GuardLog 'auth cookie cleanup skipped: bundled node not found'; return }
  if (-not (Test-Path $cookieCleaner)) { Write-GuardLog 'auth cookie cleanup skipped: cleaner script missing'; return }
  $out = & $nodeExe $cookieCleaner $userData 2>&1
  $text = ($out | Out-String).Trim()
  if ($text) { Write-GuardLog ("auth cookies: {0}" -f $text) }
}

function Start-Dsh {
  if (-not (Test-Path $exePath)) {
    Write-GuardLog "ERROR exe not found: $exePath"
    return $false
  }
  Start-Process -FilePath $exePath -WorkingDirectory $appDir -ErrorAction SilentlyContinue
  return $true
}

# Wait for a visible window. Returns: ok | dead | crashed | timeout
function Wait-DshWindow([int]$timeoutSec) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    $procs = Get-DshProcesses
    if ($procs.Count -eq 0) { return 'dead' }
    if (Test-WindowReady $procs) { return 'ok' }
    $crash = Get-RecentCrashLog 30
    if ($crash) { return 'crashed' }
    Start-Sleep -Milliseconds 1500
  }
  # Timeout: be conservative. If processes are still alive and no fresh crash log,
  # assume the window is hidden/rendering and do NOT kill a possibly healthy app.
  $procs = Get-DshProcesses
  if ($procs.Count -eq 0) { return 'dead' }
  if (Get-RecentCrashLog 180) { return 'crashed' }
  Write-GuardLog 'window handle not found within timeout, but process alive and no crash log -> assume OK'
  return 'ok'
}

# ---------- single instance ----------
$lockStream = $null
try {
  $lockStream = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
} catch {
  exit 0
}

Write-GuardLog ('=== guard start (dryRun={0}) ===' -f [bool]$DryRun)

# ---------- already running? ----------
$procs = Get-DshProcesses
if ($procs.Count -gt 0) {
  if (Test-WindowReady $procs) {
    Write-GuardLog 'DSH already running with window -> ask it to focus, then exit'
    if (-not $DryRun) { Start-Dsh | Out-Null }
    if ($lockStream) { $lockStream.Close() }
    exit 0
  }

  # Processes exist but no window: may be mid-start or a zombie.
  $oldest = $procs | Sort-Object StartTime | Select-Object -First 1
  $ageSec = if ($oldest -and $oldest.StartTime) { ((Get-Date) - $oldest.StartTime).TotalSeconds } else { 0 }
  if ($ageSec -lt 30) {
    Write-GuardLog ("DSH processes exist, started {0:N0}s ago -> waiting for window" -f $ageSec)
    $r = Wait-DshWindow 60
    if ($r -eq 'ok') {
      Write-GuardLog 'existing instance reached window -> guard exits'
      if ($lockStream) { $lockStream.Close() }
      exit 0
    }
    Write-GuardLog ("existing instance did not reach window ({0}) -> treating as stale" -f $r)
  }

  if ($DryRun) {
    Write-GuardLog '[dry] would kill stale DSH processes'
    if ($lockStream) { $lockStream.Close() }
    exit 0
  }

  Write-GuardLog 'killing stale DSH processes'
  if (-not (Stop-DshProcesses)) {
    Write-GuardLog 'ERROR could not kill all DSH processes, aborting'
    if ($lockStream) { $lockStream.Close() }
    exit 1
  }
}

if ($DryRun) {
  Write-GuardLog '[dry] would clear gpu caches, clear dsh-auth cookies, then launch DSH'
  if ($lockStream) { $lockStream.Close() }
  exit 0
}

# ---------- clean before launch ----------
Clear-GpuCaches
Clear-AuthCookies

# ---------- launch with retries ----------
$maxAttempts = 3
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
  Write-GuardLog ("launch attempt {0}/{1}" -f $attempt, $maxAttempts)
  if (-not (Start-Dsh)) {
    if ($lockStream) { $lockStream.Close() }
    exit 1
  }

  $result = Wait-DshWindow $WindowTimeoutSec
  if ($result -eq 'ok') {
    Write-GuardLog 'DSH started OK'
    if ($lockStream) { $lockStream.Close() }
    exit 0
  }

  Write-GuardLog ("attempt {0} failed: {1}" -f $attempt, $result)
  if (-not (Stop-DshProcesses)) {
    Write-GuardLog 'processes still alive after failed attempt; waiting 5s'
    Start-Sleep -Seconds 5
  }

  if ($attempt -eq 1) {
    Clear-GpuCaches
    Clear-AuthCookies
  } elseif ($attempt -eq 2) {
    Clear-GpuCaches
    Clear-CodeCache
    Clear-AuthCookies
  } else {
    # final attempt: escalate to safe mode (undo plugin disables all user plugins)
    Write-GuardLog 'escalating: entering dsh-undo SAFE MODE'
    try {
      $undoOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $undoCli safe-mode -Label on 2>&1
      $undoText = ($undoOut | Out-String).Trim()
      if ($undoText) { Write-GuardLog ("safe mode: {0}" -f $undoText) }
    } catch {
      Write-GuardLog 'safe mode CLI failed'
    }
  }
}

Write-GuardLog 'all launch attempts failed; giving up. See guard.log and dsh-desktop\logs'
if ($lockStream) { $lockStream.Close() }
exit 1
