# Register-ClaudeGreeting.ps1
# Claude Codeのリセットサイクル管理のため、定期プロンプトをタスクスケジューラに登録する
# 実行方法: PowerShellを管理者として実行し、このスクリプトを実行する

# スリープ解除タイマーを有効化
Write-Host "スリープ解除タイマーを有効化中..."
powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1
powercfg /setactive SCHEME_CURRENT

$Settings = New-ScheduledTaskSettingsSet `
    -WakeToRun `
    -AllowStartIfOnBatteries `
    -StartWhenAvailable

# 朝7時のタスク
Write-Host "ClaudeGreeting-Morning を登録中..."
$Action7 = New-ScheduledTaskAction -Execute "wsl.exe" `
    -Argument "-e bash /home/aya/.dotfiles/scripts/claude-prompt.sh おはよう"
$Trigger7 = New-ScheduledTaskTrigger -Daily -At "07:00"
Register-ScheduledTask -TaskName "ClaudeGreeting-Morning" `
    -Action $Action7 -Trigger $Trigger7 -Settings $Settings -Force

# 昼12時のタスク
Write-Host "ClaudeGreeting-Noon を登録中..."
$Action12 = New-ScheduledTaskAction -Execute "wsl.exe" `
    -Argument "-e bash /home/aya/.dotfiles/scripts/claude-prompt.sh こんにちは"
$Trigger12 = New-ScheduledTaskTrigger -Daily -At "12:00"
Register-ScheduledTask -TaskName "ClaudeGreeting-Noon" `
    -Action $Action12 -Trigger $Trigger12 -Settings $Settings -Force

Write-Host "完了やで！タスクスケジューラで確認してな。"
