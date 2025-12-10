#Requires -RunAsAdministrator

<#
.SYNOPSIS
    WSL定期バックアップのタスクスケジューラ設定スクリプト（高機能版）

.DESCRIPTION
    Windowsタスクスケジューラに定期バックアップタスクを登録します。
    - 対話的な設定（時刻、頻度、通知など）
    - 失敗時の通知機能
    - 詳細なログ記録
    - タスクの管理機能（削除、状態確認）

.EXAMPLE
    .\Setup-BackupScheduler.ps1
#>

# カラー出力関数
function Write-ColorOutput {
    param(
        [string]$Message,
        [ValidateSet('Success', 'Error', 'Warning', 'Info')]
        [string]$Type = 'Info'
    )

    $colors = @{
        'Success' = 'Green'
        'Error'   = 'Red'
        'Warning' = 'Yellow'
        'Info'    = 'Cyan'
    }

    $prefix = @{
        'Success' = '[✓]'
        'Error'   = '[✗]'
        'Warning' = '[!]'
        'Info'    = '[i]'
    }

    Write-Host "$($prefix[$Type]) $Message" -ForegroundColor $colors[$Type]
}

# 管理者権限チェック
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# WSLディストリビューション確認
function Get-WSLDistribution {
    Write-ColorOutput "WSLディストリビューションを確認中..." -Type Info

    $wslList = wsl --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "WSLが見つかりません。WSL2がインストールされているか確認してください。" -Type Error
        return $null
    }

    # 空行とNULL文字を除外してクリーンアップ
    $distros = $wslList | Where-Object {
        $_ -and $_.Trim() -and $_ -match '\S' -and $_ -notmatch '^\s*$'
    } | ForEach-Object {
        $_.Trim() -replace '\x00',''
    } | Where-Object { $_ }

    if ($distros.Count -eq 0) {
        Write-ColorOutput "WSLディストリビューションが見つかりません。" -Type Error
        return $null
    }

    Write-ColorOutput "検出されたディストリビューション:" -Type Success
    for ($i = 0; $i -lt $distros.Count; $i++) {
        Write-Host "  [$($i + 1)] $($distros[$i])"
    }

    if ($distros.Count -eq 1) {
        Write-ColorOutput "自動選択: $($distros[0])" -Type Info
        return $distros[0]
    }

    do {
        $selection = Read-Host "`n使用するディストリビューション番号を入力してください (1-$($distros.Count))"
        $index = [int]$selection - 1
    } while ($index -lt 0 -or $index -ge $distros.Count)

    return $distros[$index]
}

# バックアップスクリプトの存在確認
function Test-BackupScript {
    param([string]$Distribution, [string]$Username)

    $scriptPath = "/home/$Username/.dotfiles/scripts/backup/backup-wsl-to-windows.sh"

    Write-ColorOutput "バックアップスクリプトを確認中: $scriptPath" -Type Info

    # WSLコマンドの実行と結果の確認を改善
    $checkCommand = "test -f '$scriptPath' && echo 'EXISTS' || echo 'NOT_FOUND'"
    $result = wsl -d $Distribution -u $Username -- bash -c $checkCommand 2>$null

    if ($result -ne 'EXISTS') {
        Write-ColorOutput "バックアップスクリプトが見つかりません: $scriptPath" -Type Error
        Write-ColorOutput "WSLディストリビューション名: $Distribution" -Type Info
        Write-ColorOutput "実際のパスを確認してください。" -Type Warning
        return $false
    }

    Write-ColorOutput "バックアップスクリプトを確認しました。" -Type Success
    return $true
}

# メイン処理
function Main {
    Write-Host @"

╔══════════════════════════════════════════════════════════╗
║   WSL バックアップ タスクスケジューラ セットアップ      ║
║                    (高機能版)                            ║
╚══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

    # 管理者権限チェック
    if (-not (Test-Administrator)) {
        Write-ColorOutput "このスクリプトは管理者権限で実行してください。" -Type Error
        Write-ColorOutput "PowerShellを右クリック → '管理者として実行' を選択してください。" -Type Warning
        Read-Host "`nEnterキーを押して終了..."
        exit 1
    }

    Write-ColorOutput "管理者権限を確認しました。" -Type Success

    # WSLディストリビューション選択
    $distribution = Get-WSLDistribution
    if (-not $distribution) {
        Read-Host "`nEnterキーを押して終了..."
        exit 1
    }

    # ユーザー名入力
    Write-Host ""
    $username = Read-Host "WSLのユーザー名を入力してください (デフォルト: aya)"
    if ([string]::IsNullOrWhiteSpace($username)) {
        $username = "aya"
    }

    # バックアップスクリプト確認
    if (-not (Test-BackupScript -Distribution $distribution -Username $username)) {
        Read-Host "`nEnterキーを押して終了..."
        exit 1
    }

    # スケジュール設定
    Write-Host ""
    Write-ColorOutput "=== スケジュール設定 ===" -Type Info
    Write-Host @"

バックアップの実行頻度を選択してください:
  [1] 毎日
  [2] 毎週（曜日指定）
  [3] カスタム（複数時刻指定）

"@

    do {
        $scheduleType = Read-Host "選択 (1-3)"
    } while ($scheduleType -notmatch '^[1-3]$')

    $triggers = @()

    switch ($scheduleType) {
        '1' {
            # 毎日
            Write-Host "`n実行時刻を選択してください:"
            Write-Host "  [1] 午前2時（推奨）"
            Write-Host "  [2] 午前0時"
            Write-Host "  [3] カスタム時刻"

            $timeChoice = Read-Host "選択 (1-3)"

            $time = switch ($timeChoice) {
                '1' { '2:00AM' }
                '2' { '12:00AM' }
                '3' {
                    $customTime = Read-Host "時刻を入力してください (例: 3:30AM, 23:00)"
                    $customTime
                }
                default { '2:00AM' }
            }

            $triggers += New-ScheduledTaskTrigger -Daily -At $time
            Write-ColorOutput "設定: 毎日 $time に実行" -Type Success
        }
        '2' {
            # 毎週
            Write-Host "`n曜日を選択してください (複数選択可, カンマ区切り):"
            Write-Host "  1: 月曜日, 2: 火曜日, 3: 水曜日, 4: 木曜日"
            Write-Host "  5: 金曜日, 6: 土曜日, 7: 日曜日"

            $dayInput = Read-Host "選択 (例: 1,3,5)"
            $days = $dayInput -split ',' | ForEach-Object { $_.Trim() }

            $dayNames = @{
                '1' = 'Monday'; '2' = 'Tuesday'; '3' = 'Wednesday'; '4' = 'Thursday'
                '5' = 'Friday'; '6' = 'Saturday'; '7' = 'Sunday'
            }

            $selectedDays = $days | ForEach-Object { $dayNames[$_] }

            $time = Read-Host "実行時刻を入力してください (例: 2:00AM)"
            if ([string]::IsNullOrWhiteSpace($time)) { $time = '2:00AM' }

            $triggers += New-ScheduledTaskTrigger -Weekly -DaysOfWeek $selectedDays -At $time
            Write-ColorOutput "設定: 毎週 $($selectedDays -join ', ') $time に実行" -Type Success
        }
        '3' {
            # カスタム（複数時刻）
            Write-Host "`n複数の実行時刻を設定します。"
            $timeCount = Read-Host "実行時刻の数を入力してください (1-5)"

            for ($i = 1; $i -le [int]$timeCount; $i++) {
                $time = Read-Host "実行時刻 $i を入力してください (例: 2:00AM)"
                $triggers += New-ScheduledTaskTrigger -Daily -At $time
            }

            Write-ColorOutput "設定: $timeCount 回/日 実行" -Type Success
        }
    }

    # 通知設定
    Write-Host ""
    Write-ColorOutput "=== 通知設定 ===" -Type Info
    $enableNotification = Read-Host "失敗時にトースト通知を表示しますか？ (Y/n)"
    $enableNotification = ($enableNotification -ne 'n')

    # タスク名とパス
    $taskName = "WSL-Daily-Backup"
    $taskPath = "\CustomBackups\"

    # 既存タスクの確認
    $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-ColorOutput "既存のタスクが見つかりました。" -Type Warning
        $overwrite = Read-Host "上書きしますか？ (Y/n)"
        if ($overwrite -eq 'n') {
            Write-ColorOutput "セットアップをキャンセルしました。" -Type Info
            Read-Host "`nEnterキーを押して終了..."
            exit 0
        }
        Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
        Write-ColorOutput "既存タスクを削除しました。" -Type Success
    }

    # アクション設定
    $scriptPath = "/home/$username/.dotfiles/scripts/backup/backup-wsl-to-windows.sh"
    $argument = "-d $distribution -u $username -- $scriptPath"

    if ($enableNotification) {
        # 通知付きラッパースクリプト
        $wrapperScript = @"
`$result = wsl.exe $argument
if (`$LASTEXITCODE -ne 0) {
    if (Get-Module -ListAvailable -Name BurntToast) {
        Import-Module BurntToast
        New-BurntToastNotification -Text 'WSL Backup Failed', 'Check logs at ~/.backup-logs/' -AppLogo 'C:\Windows\System32\imageres.dll' -Sound 'Alarm'
    }
    exit 1
}
"@
        $wrapperPath = "$env:TEMP\wsl-backup-wrapper.ps1"
        $wrapperScript | Out-File -FilePath $wrapperPath -Encoding UTF8 -Force

        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$wrapperPath`""
    } else {
        $action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument $argument
    }

    # 実行アカウント設定
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest

    # 設定
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1)

    # タスク登録
    Write-Host ""
    Write-ColorOutput "タスクスケジューラに登録中..." -Type Info

    try {
        Register-ScheduledTask `
            -TaskName $taskName `
            -TaskPath $taskPath `
            -Action $action `
            -Trigger $triggers `
            -Principal $principal `
            -Settings $settings `
            -Description "WSL /home/$username の定期バックアップ (自動生成)" `
            -ErrorAction Stop | Out-Null

        Write-ColorOutput "タスクの登録に成功しました！" -Type Success
    } catch {
        Write-ColorOutput "タスクの登録に失敗しました: $_" -Type Error
        Read-Host "`nEnterキーを押して終了..."
        exit 1
    }

    # 完了メッセージ
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║              セットアップが完了しました！                ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-ColorOutput "タスク名: $taskName" -Type Info
    Write-ColorOutput "タスクパス: $taskPath" -Type Info
    Write-ColorOutput "バックアップ先: D:\WSL\backup\home\$username\" -Type Info
    Write-Host ""
    Write-ColorOutput "=== 次のステップ ===" -Type Info
    Write-Host "  1. タスクスケジューラを開いて確認: taskschd.msc"
    Write-Host "  2. 今すぐテスト実行: Get-ScheduledTask -TaskName '$taskName' | Start-ScheduledTask"
    Write-Host "  3. 実行履歴確認: Get-ScheduledTask -TaskName '$taskName' | Get-ScheduledTaskInfo"
    Write-Host ""

    # 即座にテスト実行するか確認
    $runNow = Read-Host "今すぐテスト実行しますか？ (Y/n)"
    if ($runNow -ne 'n') {
        Write-ColorOutput "バックアップを実行中..." -Type Info
        Start-ScheduledTask -TaskName $taskName -TaskPath $taskPath
        Start-Sleep -Seconds 3

        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $taskPath
        Write-ColorOutput "最終実行結果: $($taskInfo.LastTaskResult)" -Type Info
        Write-ColorOutput "次回実行予定: $($taskInfo.NextRunTime)" -Type Info
    }

    Write-Host ""
    Read-Host "Enterキーを押して終了..."
}

# スクリプト実行
Main
