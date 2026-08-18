$exe = "C:\Program Files\Mozilla Thunderbird\thunderbird.exe"
if (-not (Test-Path $exe)) { Write-Output "NOEXE"; exit 1 }
$procs = Get-Process thunderbird -EA SilentlyContinue
if ($procs) {
  foreach ($p in $procs) { if ($p.MainWindowHandle -ne 0) { $p.CloseMainWindow() | Out-Null } }
  for ($i=0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 250
    if (-not (Get-Process thunderbird -EA SilentlyContinue)) { break }
  }
  $left = Get-Process thunderbird -EA SilentlyContinue
  if ($left) {
    $left | Stop-Process -Force
    for ($i=0; $i -lt 20; $i++) {
      Start-Sleep -Milliseconds 250
      if (-not (Get-Process thunderbird -EA SilentlyContinue)) { break }
    }
  }
}
if (Get-Process thunderbird -EA SilentlyContinue) { Write-Output "STILLRUNNING"; exit 1 }
# Resolve the profile from installs.ini (the directory name is a random ID).
$tbRoot = "$env:APPDATA\Thunderbird"
$prof = $null
foreach ($ini in @("installs.ini", "profiles.ini")) {
  $path = Join-Path $tbRoot $ini
  if (-not (Test-Path $path)) { continue }
  $line = Select-String -Path $path -Pattern '^Default=(.+)$' | Select-Object -First 1
  if ($line) { $prof = Join-Path $tbRoot ($line.Matches[0].Groups[1].Value.Trim() -replace '/', '\'); break }
}
if (-not $prof) { $prof = $tbRoot }
foreach ($f in @("parent.lock","lock",".parentlock")) {
  $lp = Join-Path $prof $f
  if (Test-Path $lp) { Remove-Item $lp -Force -EA SilentlyContinue }
}
Start-Process -FilePath $exe | Out-Null
for ($i=0; $i -lt 80; $i++) {
  Start-Sleep -Milliseconds 500
  $p = Get-Process thunderbird -EA SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0}
  if ($p) { Write-Output "STARTED"; exit 0 }
}
Write-Output "TIMEOUT"
exit 1
