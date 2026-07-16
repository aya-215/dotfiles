# User CLAUDE.md

## 環境

- WSL + zsh
- エディタ: Neovim
- dotfiles: Nix/Home Manager で管理。tmux.conf, .claude.json 等の設定ファイルは生成物なので直接編集しないこと。設定変更は必ず dotfiles 内の Nix ソースファイルを確認・編集すること。
- GitHub CLI: 2つのアカウント（eBASE-Mori, aya-215）で認証済み。`gh` コマンドが認証エラーで失敗した場合は `gh auth switch` でアカウントを切り替えること。
- SSH: デフォルトキーは`~/.ssh/id_ed25519_ebase`（eBASE-Mori）。aya-215用は`github-aya215`エイリアス（`~/.ssh/id_ed25519_aya215`）を使用。dotfilesリポジトリのremoteは`git@github-aya215:aya-215/dotfiles.git`に設定すること。push失敗時は`git remote set-url origin git@github-aya215:aya-215/dotfiles.git`で修正すること。
- Git on /mnt/: `/mnt/` 配下のリポジトリで `index.lock` エラーが発生した場合は下記「index.lock 対処」に従うこと。
- Windows側で見たいファイル（Excel、画像、HTML等）を渡したい場合は `D:\temp_wsl`（WSLからは `/mnt/d/temp_wsl`）に置くこと。ここはWindows側で開くための受け渡し専用フォルダであり、永続保存場所ではない。

## index.lock 対処

`index.lock` エラーは、エディタ(Neovim等)のgit統合がバックグラウンドで `git status` 等を頻繁に実行し、ロックを断続的に掴むことが主因。競合相手は読み取り専用の `git status` であり書き換えるインデックスが無いため、削除のリスクは原則低い。以下の手順で対処すること。

1. **削除して即リトライ**: `rm -f /path/to/.git/index.lock && git ...`
2. **単発で通らなければリトライループ**: ロック再生成が頻繁な場合、「削除→実行→失敗なら `sleep 1`」を最大10回ループする。

※ 複合コマンドでは、本処理が成功した後に走る確認用 git 呼び出し（`git status` 等）もロックに当たるため、各 git 呼び出しの前に `rm -f .git/index.lock` を挟むこと。

## Git操作のツール選択

**必ず `git remote -v` でリモートURLを確認してからツールを選ぶこと。**

| リモートURL | 使うツール |
|---|---|
| `github.com` | `gh` コマンド（GitHub CLI） |
| 社内GitBucket URL | `mcp__gitbucket__*` ツール |

## コミュニケーションルール

不明点がある場合は、解消されるまで `AskUserQuestion` で再帰的に質問すること。

<!-- WORKAROUND(claude-code#74260): Fable本文消失バグ対策。upstream修正後はこのブロックごと削除 -->
### AskUserQuestion のターン分離（Fable実行時・全skill共通）

文脈説明を伴う `AskUserQuestion` は、説明テキストのみのメッセージを
「Now I'll end my turn, which will invoke the AskUserQuestion tool...」で締めて**実際にターンを終了**し、
Stopフック（fable-message-drop-fix）の自動継続を受けた**次のターンで単独呼び出し**すること。

**禁止**: 締め文を書いた後、同一ターン内で続けて AskUserQuestion を呼ぶこと。
「締め文を書くこと」はターン終了ではない。同一ターンで呼ぶと `thinking→text→thinking→tool_use` 形になり
説明テキストごと消失する（Stopフックも発火しない）。
詳細: agent-memory `claude-code/askuserquestion-text-drop-bug.md`
<!-- /WORKAROUND -->

## Memory 管理ルール

**メモリの実体は `agent-memory` スキル（`~/.claude/skills/agent-memory/memories/`、グローバル共有）に一元管理する。**
ハーネスが自動注入するネイティブの「Memory」機構（プロジェクト配下 `MEMORY.md` 等）は、
実体ではなく **agent-memory への入口** としてのみ使う。メモリの保存・検索・更新は必ず agent-memory 側で行う。

### ネイティブ MEMORY.md の役割（入口）

プロジェクトの `MEMORY.md` にメモリ本体を書かない。代わりに、常時効かせたい少数の重要ルールだけ
summary を転記し、末尾に必ず次の参照を置く:

> メモリの実体は agent-memory にある。関連作業の前に必ず
> `rg "^summary:" ~/.claude/skills/agent-memory/memories/ --no-ignore --hidden`
> で既存メモリを検索し、該当すれば本体を読むこと。

### 保存・検索の手順

- **保存/検索/更新はすべて `agent-memory` スキルを起動して行う**（frontmatter形式・カテゴリ構成はスキルに従う）。
  ネイティブ側の frontmatter 形式（name/description/metadata）では書かない。
- feedback 系メモリ（`memories/feedback/`）は `/retrospective` の学習機構が依存するため、
  カウント frontmatter（pain_count 等）を壊さない。移動・形式変更をしない。

### プロアクティブ使用

以下は指示がなくても agent-memory への保存を検討する：

- 調査に時間がかかった発見 / 非自明なバグ・回避策 / 難しい問題の解決策
- アーキテクチャ決定とその理由 / 中断する可能性のある進行中の作業

関連作業を開始するときは、上記の検索コマンドで既存メモリを必ず確認する。
