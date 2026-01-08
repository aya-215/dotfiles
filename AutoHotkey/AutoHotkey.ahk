#Requires AutoHotkey v2.0

; キーマッピング（v2構文）
*vkBA:: {
    if (GetKeyState("Shift"))
        Send(";")
    else
        Send(":")
}


; Ctrl+セミコロン（物理位置 = 論理的にはコロン）
^;:: {
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
