#Requires AutoHotkey v2.0

; キーマッピング（v2構文）
*vkBA:: {
    if (GetKeyState("Shift"))
        Send(";")
    else
        Send(":")
}


; Ctrl+G で Escape + IME OFF
^g:: {
    Send("{Escape}")
    Sleep(100)
    IME_SET(0)
}

; ──────────────────────────────────────────────
; IMEを明示的にON/OFFする関数
;   isOn := 0  → IME OFF（英数）
;   isOn := 1  → IME ON（ひらがな）
; WinTitle := "A"  → アクティブウィンドウが対象
; ──────────────────────────────────────────────
IME_SET(isOn := 0, WinTitle := "A") {
    hwnd := WinGetID(WinTitle)
    if !hwnd
        return

    ; ImmGetDefaultIMEWnd で IMEウィンドウのハンドルを取得
    ctl := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
    if !ctl
        return

    WM_IME_CONTROL     := 0x283
    IMC_SETOPENSTATUS  := 0x006

    ; SendMessage( IMEウィンドウ, WM_IME_CONTROL, IMC_SETOPENSTATUS, isOn )
    ; isOn = 0 → IME OFF,  isOn = 1 → IME ON
    DllCall("SendMessage", "Ptr", ctl
                           , "UInt", WM_IME_CONTROL
                           , "Ptr",  IMC_SETOPENSTATUS
                           , "Ptr",  isOn)
}

; Ctrl + \ でWeztermをトグル
^\::ToggleWezterm()

ToggleWezterm() {
    if WinExist("ahk_exe wezterm-gui.exe") {
        if WinActive("ahk_exe wezterm-gui.exe") {
            WinMinimize
            Send "!{Esc}"
        } else {
            WinMaximize
            WinShow
            WinActivate
        }
    } else {
        Run "wezterm-gui.exe"
    }
}

; ──────────────────────────────────────────────
; WSL クリップボード画像ペースト (Alt+V)
; ──────────────────────────────────────────────
global gTempDir := "D:\wsl_clipboard_temp"
global gLastNotifyTime := 0

; 起動時にtempディレクトリ作成
if !DirExist(gTempDir)
    DirCreate(gTempDir)

; Alt+V でクリップボード画像をWSLパスでペースト
!v:: {
    global gTempDir

    ; クリップボードに画像があるか確認
    if !DllCall("IsClipboardFormatAvailable", "UInt", 2) {  ; CF_BITMAP
        ShowTip("クリップボードに画像がありません")
        return
    }

    ; ファイル名生成
    timestamp := FormatTime(, "yyyyMMdd_HHmmss")
    filename := "clip_" . timestamp . ".png"
    winPath := gTempDir . "\" . filename
    wslPath := "/mnt/d/wsl_clipboard_temp/" . filename

    ; 画像を保存（PowerShell使用）
    psCmd := 'Add-Type -AssemblyName System.Windows.Forms; '
           . '$img = [System.Windows.Forms.Clipboard]::GetImage(); '
           . 'if ($img) { $img.Save(\"' . winPath . '\") }'
    RunWait('powershell.exe -NoProfile -Command "' . psCmd . '"',, "Hide")

    ; WSLパスをペースト
    if FileExist(winPath) {
        A_Clipboard := wslPath
        Send("^v")
        ShowTip("画像パスをペーストしました")
    } else {
        ShowTip("画像の保存に失敗しました")
    }
}

; 通知表示（去抖処理付き）
ShowTip(msg) {
    global gLastNotifyTime
    now := A_TickCount
    if (now - gLastNotifyTime < 500)
        return
    gLastNotifyTime := now
    ToolTip(msg)
    SetTimer(() => ToolTip(), -2000)
}
