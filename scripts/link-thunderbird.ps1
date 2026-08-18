# Thunderbird のプロファイルへ dotfiles の設定をシンボリックリンクで繋ぐ。
# プロファイルディレクトリ名はランダムIDのため installs.ini から解決する。
# 管理者権限が必要（シンボリックリンク作成のため）。

$ErrorActionPreference = "Stop"
$source = Join-Path $PSScriptRoot "..\config\thunderbird" | Resolve-Path
$tbRoot = "$env:APPDATA\Thunderbird"

if (-not (Test-Path $tbRoot)) { throw "Thunderbirdが見つかりません: $tbRoot" }

$profileRel = $null
foreach ($ini in @("installs.ini", "profiles.ini")) {
    $path = Join-Path $tbRoot $ini
    if (-not (Test-Path $path)) { continue }
    $line = Select-String -Path $path -Pattern '^Default=(.+)$' | Select-Object -First 1
    if ($line) { $profileRel = $line.Matches[0].Groups[1].Value.Trim(); break }
}
if (-not $profileRel) { throw "プロファイルを特定できませんでした" }

$profile = Join-Path $tbRoot ($profileRel -replace '/', '\')
if (-not (Test-Path $profile)) { throw "プロファイルが存在しません: $profile" }
Write-Host "プロファイル: $profile"

if (Get-Process thunderbird -ErrorAction SilentlyContinue) {
    Write-Host "警告: Thunderbirdが起動中です。反映には完全終了と再起動が必要です。"
}

# user.js
$target = Join-Path $profile "user.js"
if (Test-Path $target) {
    if ((Get-Item $target).LinkType -ne "SymbolicLink") {
        Copy-Item $target "$target.bak" -Force
        Write-Host "既存の user.js を user.js.bak に退避しました"
    }
    Remove-Item $target -Force
}
New-Item -ItemType SymbolicLink -Path $target -Target (Join-Path $source "user.js") | Out-Null
Write-Host "リンク作成: user.js"

# chrome/ ディレクトリごとリンクすると Thunderbird 側の他ファイルを巻き込むため
# ファイル単位でリンクする
$chrome = Join-Path $profile "chrome"
if (-not (Test-Path $chrome)) { New-Item -ItemType Directory -Path $chrome -Force | Out-Null }

foreach ($f in @("userContent.css", "userChrome.css")) {
    $src = Join-Path $source "chrome\$f"
    if (-not (Test-Path $src)) { continue }
    $dst = Join-Path $chrome $f
    if (Test-Path $dst) {
        if ((Get-Item $dst).LinkType -ne "SymbolicLink") {
            Copy-Item $dst "$dst.bak" -Force
            Write-Host "既存の $f を $f.bak に退避しました"
        }
        Remove-Item $dst -Force
    }
    New-Item -ItemType SymbolicLink -Path $dst -Target $src | Out-Null
    Write-Host "リンク作成: chrome\$f"
}

Write-Host ""
Write-Host "完了。Thunderbirdを完全終了して再起動してください。"
