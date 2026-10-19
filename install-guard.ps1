# install-guard.ps1 - one-time installer: point the DeepSeek Harness shortcuts at dsh-guard.
# Run by double-clicking install-guard.vbs (runs as the normal user, so it may write AppData).

$ErrorActionPreference = 'Stop'

$stage     = Split-Path -Parent $MyInvocation.MyCommand.Path
$guardVbs  = Join-Path $stage 'dsh-guard.vbs'
$exePath   = 'E:\DeepSeek Harness\DeepSeek Harness.exe'
$backupDir = Join-Path $stage 'backup'

New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$targets = @(
  @{
    Name = 'Start menu'
    Lnk  = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\DeepSeek Harness.lnk')
    Bak  = (Join-Path $backupDir 'DeepSeek Harness.menu.lnk')
  },
  @{
    Name = 'Startup'
    Lnk  = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\DeepSeek Harness.lnk')
    Bak  = (Join-Path $backupDir 'DeepSeek Harness.startup.lnk')
  }
)

$ws    = New-Object -ComObject WScript.Shell
$lines = New-Object System.Collections.Generic.List[string]
$ok    = $true

if (-not (Test-Path -LiteralPath $guardVbs)) {
  $lines.Add("ERROR: launcher missing: $guardVbs")
  $ok = $false
} else {
  foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t.Lnk)) {
      $lines.Add("SKIP  $($t.Name): not found ($($t.Lnk))")
      continue
    }
    try {
      if (-not (Test-Path -LiteralPath $t.Bak)) {
        Copy-Item -LiteralPath $t.Lnk -Destination $t.Bak -Force
      }
      $s = $ws.CreateShortcut($t.Lnk)
      $s.TargetPath       = "$env:SystemRoot\System32\wscript.exe"
      $s.Arguments        = '"' + $guardVbs + '"'
      $s.WorkingDirectory = $stage
      $s.IconLocation     = $exePath + ',0'
      $s.Description      = 'DeepSeek Harness (guard launcher)'
      $s.Save()
      $v = $ws.CreateShortcut($t.Lnk)
      $lines.Add("OK    $($t.Name) -> $($v.TargetPath) $($v.Arguments)")
    } catch {
      $ok = $false
      $lines.Add("FAIL  $($t.Name): $($_.Exception.Message)")
    }
  }
}

if (Test-Path -LiteralPath $exePath) {
  $lines.Add("exe ok: $exePath")
} else {
  $ok = $false
  $lines.Add("ERROR: exe missing: $exePath")
}
$lines.Add("guard vbs: $guardVbs")

# tidy up stray probe files left behind by diagnostics
foreach ($p in @((Join-Path $env:APPDATA '_dsh_guard_probe.txt'), 'E:\windows\_dsh_guard_probe.txt')) {
  if (Test-Path -LiteralPath $p) {
    try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop } catch {}
  }
}

# once the shortcuts themselves point at the guard, the startup .vbs would be a duplicate
if ($ok) {
  $startupVbs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\dsh-guard-launcher.vbs'
  if (Test-Path -LiteralPath $startupVbs) {
    try {
      Remove-Item -LiteralPath $startupVbs -Force -ErrorAction Stop
      $lines.Add('removed redundant startup .vbs (shortcuts handle launching now)')
    } catch {
      $lines.Add('note: startup .vbs kept (harmless duplicate)')
    }
  }
}

$text = ($lines -join "`r`n")
Set-Content -LiteralPath (Join-Path $stage 'install-result.txt') -Value $text -Encoding UTF8
Write-Output $text
if (-not $ok) { exit 1 }
