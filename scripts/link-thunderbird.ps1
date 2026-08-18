# Link dotfiles Thunderbird config into the TB profile.
# The profile directory name is a random ID, so it is resolved from installs.ini.
# Requires administrator privileges (for symlink creation).
#
# Messages are in English: PowerShell 5.1 misreads BOM-less UTF-8 as Shift-JIS
# and non-ASCII text breaks parsing.

$ErrorActionPreference = "Stop"
$source = (Resolve-Path (Join-Path $PSScriptRoot "..\config\thunderbird")).Path
$tbRoot = "$env:APPDATA\Thunderbird"

if (-not (Test-Path $tbRoot)) { throw "Thunderbird not found: $tbRoot" }

$profileRel = $null
foreach ($ini in @("installs.ini", "profiles.ini")) {
    $path = Join-Path $tbRoot $ini
    if (-not (Test-Path $path)) { continue }
    $line = Select-String -Path $path -Pattern '^Default=(.+)$' | Select-Object -First 1
    if ($line) { $profileRel = $line.Matches[0].Groups[1].Value.Trim(); break }
}
if (-not $profileRel) { throw "Could not determine the default profile" }

$profileDir = Join-Path $tbRoot ($profileRel -replace '/', '\')
if (-not (Test-Path $profileDir)) { throw "Profile does not exist: $profileDir" }
Write-Host "Profile: $profileDir"
Write-Host "Source : $source"

if (Get-Process thunderbird -ErrorAction SilentlyContinue) {
    Write-Host "NOTE: Thunderbird is running. A full restart is required to apply."
}

function Link-One($src, $dst, $label) {
    if (-not (Test-Path $src)) { return }
    if (Test-Path $dst) {
        if ((Get-Item $dst).LinkType -ne "SymbolicLink") {
            Copy-Item $dst "$dst.bak" -Force
            Write-Host "Backed up existing $label to $label.bak"
        }
        Remove-Item $dst -Force
    }
    New-Item -ItemType SymbolicLink -Path $dst -Target $src | Out-Null
    Write-Host "Linked: $label"
}

Link-One (Join-Path $source "user.js") (Join-Path $profileDir "user.js") "user.js"

# Link per file, not the whole chrome/ directory, to avoid clobbering
# other files Thunderbird may place there.
$chrome = Join-Path $profileDir "chrome"
if (-not (Test-Path $chrome)) { New-Item -ItemType Directory -Path $chrome -Force | Out-Null }

foreach ($f in @("userContent.css", "userChrome.css")) {
    Link-One (Join-Path $source "chrome\$f") (Join-Path $chrome $f) "chrome\$f"
}

Write-Host ""
Write-Host "Done. Fully quit and restart Thunderbird to apply."
