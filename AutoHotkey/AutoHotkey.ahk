#Requires AutoHotkey v2.0

; キーマッピング（v2構文）
*vkBA:: {
    if (GetKeyState("Shift"))
        Send(";")
    else
        Send(":")
}

^g:: {
    Send("{Escape}")       ; Escape送信（先に実行）
    Sleep(100) 
    IME_SET(0)             ; IMEを明示的にOFFにする
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

~Ctrl:: {
    ; Ctrlが離されるまで待機（タイムアウト2秒）
    result := KeyWait("Ctrl", "T2")

    ; タイムアウトした（= 長押しされた）場合は何もしない
    ; KeyWaitはタイムアウト時に0を返す
    if (!result)
        return

    ; 2回押し判定（間隔を200msに短縮して誤検出を防ぐ）
    if (A_PriorHotkey = A_ThisHotkey and A_TimeSincePriorHotkey < 200) {
        if WinExist("ahk_exe wezterm-gui.exe") {
            if WinActive("ahk_exe wezterm-gui.exe") {
                ; 最小化前に前のウィンドウIDを取得
                WinMinimize
                ; 最小化後、次のウィンドウをアクティブにする
                Send "!{Esc}"  ; Alt+Escで次のウィンドウに切り替え
            } else {
                ; 先に最大化してから表示
                WinMaximize
                WinShow
                WinActivate
            }
        } else {
            Run "wezterm-gui.exe"
        }
    }
}