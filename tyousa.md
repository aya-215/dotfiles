# 調査結果

## 問題

WSL2 上で複数行ペースト時に文字が抜け落ちる・行が結合される

## 原因（特定済み）

**WSL2 PTY のパケット分割問題**

ペーストされたデータが WSL2 の PTY を通過する際に、複数のパケットに分割されて届く。

### 証拠: `read` コマンドでの確認

```bash
read line; echo "入力: $line"
# 5行ペースト後の結果:
  line1      ← read が受け取った
  line2      ← 別のタイミングで届いた（read 終了後）
入力: line1  ← read は line1 だけ処理
  line3      ← 残りがシェルに流出
  line4
  line5
```

**ペーストデータが複数チャンクに分割され、プログラムが最初のチャンクしか受け取れない。**

### なぜ zsh プロンプトでは問題ないのか

zsh（readline）は入力を非同期で継続的に読み取るため、分割されたパケットも正しく結合できる。
一方、`cat` や `read` は stdin を同期的に読むため、パケット境界で問題が発生。

### なぜ Claude CLI は WSL 直接だと問題ないのか

Claude CLI も readline 相当の入力処理を使用しているため、分割されたパケットを正しく処理できる。
ただし Neovim libvterm を経由すると、libvterm の入力転送方式により問題が発生。

## 切り分け結果

| 環境 | 結果 | 理由 |
|------|------|------|
| WezTerm → Windows PowerShell | ✅ | WSL2 PTY を経由しない |
| WezTerm → Windows Neovim ターミナル | ✅ | WSL2 PTY を経由しない |
| WSL シェル（zsh プロンプト） | ✅ | readline が分割を吸収 |
| WSL Neovim ターミナル（zsh プロンプト） | ✅ | readline が分割を吸収 |
| WSL シェル → `claude` | ✅ | readline 相当の処理で分割を吸収 |
| WSL シェル → `cat` | ❌ | raw stdin、分割の影響を受ける |
| WSL シェル → `read` | ❌ | 最初のチャンクのみ受け取り |
| Windows Terminal → WSL → `cat` | ❌ | 同上 |
| WSL Neovim ターミナル → `cat` | ❌ | 同上 |
| WSL Neovim ターミナル → `claude` | ❌ | libvterm 経由で分割の影響を受ける |

## 試した解決策（効果なし）

- Bracketed Paste の無効化 (`printf '\e[?2004l'`)

## 報告先

**Microsoft WSL** - https://github.com/microsoft/WSL/issues
- WSL2 PTY の入力パケット分割問題として

## 既存の関連 Issues

### Microsoft (WSL2 PTY)
- https://github.com/microsoft/terminal/issues/10833 - Multi-line paste with WSL omits and splices together lines
- https://github.com/microsoft/terminal/issues/9002 - Can't echo correctly when pasting multiple lines to WSL 2
- https://github.com/microsoft/terminal/issues/3502 - Formatting issues when pasting in WSL tab
- https://github.com/microsoft/WSL/issues/6510 - Can't echo correctly when pasting multiple lines to WSL 2

### Claude Code
- https://github.com/anthropics/claude-code/issues/3134 - Terminal Paste Corruption from Bracketed Paste Mode

### Neovim
- https://github.com/neovim/neovim/issues/9107 - pty: add options to control input buffering and echo

## ワークアラウンド

1. **WSL シェルから直接 claude を起動**: Neovim ターミナルを経由せずに使用
2. **ファイル経由で渡す**: ペーストしたい内容をファイルに保存し、`@file` で参照
3. **WSL1 を使用する**: WSL1 では問題が発生しないという報告あり
4. **Windows の Neovim を使用**: Windows ネイティブの Neovim では問題なし
