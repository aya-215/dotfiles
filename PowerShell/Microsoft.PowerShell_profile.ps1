# ======================
# 超高速プロファイル
# ======================

# ======================
# Wezterm用OSC 7シーケンス（カレントディレクトリ通知）
# ======================
function prompt {
    # カレントディレクトリをWeztermに通知
    $loc = Get-Location
    $escapedPath = $loc.Path -replace '\\', '/'
    $OSC7 = "`e]7;file://localhost/$escapedPath`e\"
    Write-Host -NoNewline $OSC7

    # 通常のプロンプト表示
    return "PS $loc> "
}

# ======================
# mise（キャッシュ優先）
# ======================
$miseCache = "$env:TEMP\mise_activate_cache.ps1"
if (Test-Path $miseCache) {
    . $miseCache
}

# ======================
# エイリアス（即座に設定）
# ======================
Set-Alias -Name vim -Value nvim
Set-Alias -Name vi -Value nvim
Set-Alias -Name v -Value nvim
Set-Alias -Name c -Value claude
function cc { claude -c @args }
function cr { claude -r @args }

# 勤怠打刻
function ckin { python "D:\個人用\script\kintai\kintai_auto_checkin.py" }
function ckout { python "D:\個人用\script\kintai\kintai_auto_checkout.py" }

# ======================
# モジュール遅延読み込み
# ======================
$global:__PSFzfLoaded = $false
$global:__ZLocationLoaded = $false
$global:__kubectlCompletionLoaded = $false

# PSFzf初期化関数
function __InitPSFzf {
    if (-not $global:__PSFzfLoaded) {
        Import-Module PSFzf -ErrorAction SilentlyContinue
        if (Get-Module PSFzf) {
            Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
        }
        $global:__PSFzfLoaded = $true
    }
}

# ZLocation初期化関数
function __InitZLocation {
    if (-not $global:__ZLocationLoaded) {
        Import-Module ZLocation -ErrorAction SilentlyContinue
        $global:__ZLocationLoaded = $true
    }
}

# kubectl補完
function kubectl {
    if (-not $global:__kubectlCompletionLoaded) {
        $kubectlCompPath = "$PSScriptRoot\kubectl_completion.ps1"
        if (Test-Path $kubectlCompPath) {
            . $kubectlCompPath
            $global:__kubectlCompletionLoaded = $true
        }
    }
    & (Get-Command kubectl.exe -ErrorAction SilentlyContinue) @args
}

# ======================
# カスタム関数（遅延初期化付き）
# ======================

function zf {
    __InitZLocation
    $locations = Get-ZLocation 2>$null
    if ($locations) {
        $originalEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        try {
            $location = $locations.GetEnumerator() |
                        Sort-Object -Property Value -Descending |
                        Select-Object -ExpandProperty Name |
                        Out-String -Stream |
                        fzf --prompt="Z Location> " --height=40% --reverse --border --preview 'ls {}' --preview-window=right:50%
            if ($location) { Set-Location $location }
        }
        finally {
            [Console]::OutputEncoding = $originalEncoding
        }
    }
}
Set-Alias -Name zi -Value zf

function gb {
    __InitPSFzf
    $branch = git branch --all | ForEach-Object { $_.Trim('* ').Trim() } | fzf --prompt="Branch> "
    if ($branch) {
        $branch = $branch -replace 'remotes/origin/', ''
        git checkout $branch
    }
}

function fn {
    __InitPSFzf
    $file = fzf --prompt="File> " --preview 'type {}'
    if ($file) { nvim $file }
}

function fd {
    __InitPSFzf
    $dir = Get-ChildItem -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
           Select-Object -ExpandProperty FullName | fzf --prompt="Directory> "
    if ($dir) { Set-Location $dir }
}

function fe {
    __InitPSFzf
    $file = fzf --prompt="VS Code> " --preview 'type {}'
    if ($file) { code $file }
}

function ga {
    __InitPSFzf
    $files = git status -s | fzf -m --prompt="Git Add> " | ForEach-Object { ($_ -split '\s+', 2)[1] }
    if ($files) {
        $files | ForEach-Object { git add $_ }
        Write-Host "Added: $($files -join ', ')" -ForegroundColor Green
    }
}

function gl {
    __InitPSFzf
    git log --oneline --color=always |
    fzf --ansi --prompt="Commit> " --preview 'git show --color=always {1}' |
    ForEach-Object { ($_ -split ' ')[0] }
}

function gco {
    __InitPSFzf
    $commit = git log --oneline --color=always |
              fzf --ansi --prompt="Checkout Commit> " --preview 'git show --color=always {1}'
    if ($commit) {
        $hash = ($commit -split ' ')[0]
        git checkout $hash
    }
}

function gs {
    __InitPSFzf
    $stash = git stash list | fzf --prompt="Git Stash> " --preview 'git stash show -p {1}'
    if ($stash) {
        $index = ($stash -split ':')[0]
        git stash apply $index
    }
}

function pk {
    __InitPSFzf
    $process = Get-Process | Out-String -Stream | Select-Object -Skip 3 |
               fzf --prompt="Kill Process> " --header-lines=1
    if ($process) {
        $name = ($process -split '\s+')[1]
        Stop-Process -Name $name -Confirm
    }
}

function fenv {
    __InitPSFzf
    $env = Get-ChildItem env: | ForEach-Object { "$($_.Name)=$($_.Value)" } |
           fzf --prompt="Environment> "
    if ($env) { Write-Host $env }
}

function falias {
    __InitPSFzf
    Get-Alias | ForEach-Object { "$($_.Name) -> $($_.Definition)" } |
    fzf --prompt="Alias> "
}

# ======================
# キーバインド（遅延初期化付き）
# ======================

# Ctrl+D: ZLocation
Set-PSReadLineKeyHandler -Key Ctrl+d -ScriptBlock {
    __InitZLocation
    $zlocs = Get-ZLocation
    if ($zlocs) {
        $originalEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        try {
            $location = $zlocs.GetEnumerator() |
                        Sort-Object -Property Value -Descending |
                        Select-Object -ExpandProperty Name |
                        Out-String -Stream |
                        fzf --prompt="Z Location> "
            if ($location) {
                [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert("cd '$location'")
                [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
            }
        }
        finally {
            [Console]::OutputEncoding = $originalEncoding
        }
    }
}

# Ctrl+F: ファイル検索
Set-PSReadLineKeyHandler -Key Ctrl+f -ScriptBlock {
    __InitPSFzf
    $file = Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName |
            fzf --prompt="File> " --preview 'type {}'
    if ($file) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($file)
    }
}

# Ctrl+R: コマンド履歴検索（fzf）
Set-PSReadLineKeyHandler -Key Ctrl+r -ScriptBlock {
    __InitPSFzf
    $history = Get-Content (Get-PSReadlineOption).HistorySavePath -ErrorAction SilentlyContinue
    if ($history) {
        $originalEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        try {
            $command = $history |
                       Select-Object -Unique |
                       Sort-Object -Descending |
                       fzf --prompt="Command History> " --height=40% --reverse --border --tac --no-sort
            if ($command) {
                [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($command)
            }
        }
        finally {
            [Console]::OutputEncoding = $originalEncoding
        }
    }
}
