# Claude設定 棚卸しと再構成案（2026-07-27）

**きっかけ**: 「Opus 5 が出て、過度なプロンプトや調査要求が逆効果になる」という話を受けての設定整備。
**当初スコープ**: (a)案 — 調査・現状分析・再構成案の提示まで。
**現在の状態**: ユーザー承認を得て **提案A・B・C すべて実施済み**（2026-07-27）。実施結果は §9 に記録。

---

## 1. 調査した一次情報

### 公式ドキュメント（一次情報・信頼度高）

| 出典 | 該当する主張 |
|---|---|
| [Prompting Claude Opus 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5) | 「検証を指示する記述があれば**削除せよ**」— `include a final verification step` / `use a subagent to verify` 等は Opus 5 では過剰検証を招き、削除すると品質を落とさずトークンを削減できる。`double-check your answer` / `re-verify before responding` も同様 |
| 同上 | `low`/`medium` effort が高品質・低コスト。**前モデルから引き継いだ effort 既定値は再スイープすべき** |
| 同上 | 前モデル向けに書いた**vision 回避策は再検証**（不要になっている可能性） |
| 同上 | レビューで「high-severity のみ報告」と書くと**字面どおり従って報告が減る** |
| [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) L776 | 「**Prefer general instructions over prescriptive steps.** "think thoroughly" のような一般的指示のほうが、人が手書きした step-by-step の手順より良い推論を生むことが多い。Claude の推論は人が規定する内容を上回ることが頻繁にある」 |
| 同上 L490 | Opus 4.5/4.6 以降はシステムプロンプトへの追従性が上がった。`CRITICAL: You MUST use this tool when...` のような**強調語は overtrigger を招く**ので `Use this tool when...` に落とす |
| skill `claude-api` (model-migration) | Fable 5 節：「前モデル向けのプロンプト・**スキルはしばしば過度に規定的（too prescriptive）で、出力品質を下げる**。古い step-by-step の足場を外して A/B せよ」 |
| [How Claude remembers your project](https://code.claude.com/docs/en/memory.md) | 「**target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence.**」＋「if two rules contradict each other, Claude may pick one arbitrarily」＋`paths:` frontmatter による条件ロード機構（詳細は §2） |

**→ ユーザーの前提は公式ドキュメントで裏付けられた。** ただし主張の中身は「長さ」より**「規定的すぎる指示」と「モデルが自前でやることの二重指示」**が本質。

### 個人記事・二次情報（信頼度は落とす）

| 出典 | 主張 | 検証結果 |
|---|---|---|
| [explainx.ai / Thariq(@trq212) の X スレッド要約](https://explainx.ai/blog/claude-5-context-engineering-thariq-doctor-july-2026) | Anthropic は Opus 5 / Fable 5 向けに **Claude Code のシステムプロンプトを 80%以上削除し、コーディング eval で測定可能な劣化なし**（2026-07-24、Opus 5 ローンチ日） | Anthropic 中の人（Claude Code スタッフ）発言として引用されている。ただし**出典は X スレッド1本**で公式ドキュメント未確認。記事自身が「Anthropic のコーディング eval の話であり、あなたの製品 eval の保証ではない」と留保 |
| 同上 | **"unhobbling"** — 昔は最悪ケースを防いだ制約が、今は指示の衝突とトークン浪費を生むので削除する。例：「適宜ドキュメントを残せ」と「コメントを追加するな」が同一リクエスト内で衝突 | 概念としては上記公式の「過度に規定的」と整合。記事著者の解釈 |
| 同上 | 残すもの：リポジトリ目的1段落／ハマりどころ／skillへのポインタ／絶対制約。切るもの：「綺麗なコードを書け」的な説教／検証手順書（skillへ）／矛盾するコメント禁止／Claudeが自分で発見できるフォルダ構成の再掲 | 記事著者の推奨。**具体的な行数・トークン上限は示していない** |
| 複数ブログ | 「CLAUDE.md は200行以内」「フロンティアモデルが確実に従うのは150〜200命令」「lost in the middle で精度30%以上低下」 | **検証できず。REFUTED寄り** — `agentlint.app` を実際に読むと、これらの数値の出典・実証データは無く著者の設計上の好みだった。**この数値を根拠に使わない** |

---

## 2. 現状インベントリ（常時ロードされる設定）

### ロード機構（実測で確認）

- `~/.claude/CLAUDE.md` → `~/.dotfiles/.claude-global/CLAUDE.md` への**手書きシンボリックリンク**
- `~/.claude/rules` → `~/.dotfiles/.claude-global/rules` への**手書きシンボリックリンク**
- **Nix/home-manager は関与していない**（`modules/*.nix` に claude 関連の記述なし。`git.nix` のみヒット＝無関係）
  → したがって編集対象は `.claude-global/` 配下の実ファイルで正しく、`home-manager switch` も不要
- `CLAUDE.md` に `@`-import は**無い**。`hooks/` にも `rules` 参照は**無い**
  → `rules/*.md` は**ハーネスが `~/.claude/rules/` を自動発見して読み込んでいる**（本セッションのシステムプロンプトに5ファイル全部が "user's private global instructions" として載っていることで確認）

#### `paths:` frontmatter による条件ロードが**存在する**（公式ドキュメントで確認）

当初「条件ロード機構は無い」と判断したが、これは**誤り**だった。[公式ドキュメント](https://code.claude.com/docs/en/memory.md) で確認：

> Rules without `paths` frontmatter are loaded at launch with the same priority as `.claude/CLAUDE.md`.
> Rules can be scoped to specific files using YAML frontmatter with the `paths` field. These conditional rules only apply when Claude is working with files matching the specified patterns. … Path-scoped rules trigger when Claude reads files matching the pattern, not on every tool use.

つまり:

| 書き方 | ロードタイミング |
|---|---|
| frontmatter 無し（**現状の5ファイル全部**） | **起動時に無条件ロード** |
| `paths:` frontmatter あり | **該当ファイルを読んだときだけロード** |

```markdown
---
paths:
  - "config/nvim/**/*"
---
# Neovim設定スタイルガイド
```

**ユーザーレベル（`~/.claude/rules/`）でも使える**（公式に「User-level rules … apply to every project」とあり、`paths:` の適用先を project-only に限る記述は無い）。
シンボリックリンク経由の到達も **v2.1.198 以降サポート**：「matching also works when Claude reaches a file through a symlinked path to the project directory」— `~/.config/nvim` → `config/nvim/` の構成でも効く見込み。

→ **提案Bの実現手段が変わる**（後述）。`rules/` から出す必要はなく、frontmatter を足すだけでよい。

### サイズ実測

`ant` CLI が未インストールのためトークン数は取れず、**バイト数**で計測（日本語主体なので概ね 1トークン≒1.5〜3バイト）。

| ファイル | bytes | 区分 |
|---|---:|---|
| `.claude-global/CLAUDE.md` | 5,384 | グローバル |
| `.claude-global/rules/learned-rules.md` | 2,475 | rules（retrospective昇格） |
| `.claude-global/rules/external-actions.md` | 1,298 | rules |
| `.claude-global/rules/neovim-style.md` | 659 | rules |
| `.claude-global/rules/git-workflow.md` | 408 | rules |
| `.claude-global/rules/shell-conventions.md` | 386 | rules |
| **小計（グローバル常時）** | **10,610** | |
| `.dotfiles/.claude/CLAUDE.md` | 4,661 | プロジェクト（dotfiles作業時のみ） |
| **合計（dotfiles作業時）** | **15,271** | |

加えて常時載っているもの（自分の管理対象ではないが予算の一部）:
- **skill 30個**の frontmatter（name + description 1行ずつ）
- superpowers プラグインの `using-superpowers` 全文（SessionStart hook が注入）
- MCP サーバ指示（context7 / eb-api-kenshu / serena の3つ）

---

## 3. 重複・冗長の指摘（file:line つき）

### 指摘1: `git-workflow.md` はプロジェクト CLAUDE.md とほぼ完全重複 — CONFIRMED

`rules/git-workflow.md:3-9`（コミットプレフィックス表）と `.claude/CLAUDE.md:89-94` が同一内容。
`rules/git-workflow.md:16` 「コミット後は必ずpush」も `.claude/CLAUDE.md:85-87` と重複。

dotfiles 作業中は**同じルールを2回読んでいる**。しかもグローバル版（`git-workflow.md:4-8`）は `feat:/fix:/refactor:/docs:/chore:` の5つに対し、プロジェクト版（`.claude/CLAUDE.md:91-94`）は `chore:` が無く `feat:/refactor:/docs:/fix:` の4つ — **微妙に食い違っている**（"unhobbling" が言う指示の衝突の実例）。

### 指摘2: `neovim-style.md` / `shell-conventions.md` はファイル種別スコープなのに常時ロード — CONFIRMED

`neovim-style.md:5-16` はディレクトリツリーの再掲。これは公式が言う「Claude が自分で発見できる構造の再掲」に該当し（`/doctor` の trim チェックも「directory layouts … を削る」と明記）、かつ**nvim を触らないセッションでも必ず載る**。`shell-conventions.md` も同様（ShellCheck 準拠・命名規約は、そもそも Opus 5 が既定でやること）。

**両ファイルとも frontmatter が無いため無条件ロードされている**。`paths:` を足すだけで該当ファイル編集時のみのロードに変わる（指摘2の解決策は提案B参照）。

### 指摘3: `learned-rules.md` の見出しと本文が二重管理気味 — PLAUSIBLE

`learned-rules.md:11-15`「前提は実データで検証してから判断する」は、本日の retrospective で **昇格済みなのに pain 3** だった項目。読ませても守られていない実証データがある（後述）。

### 指摘4: グローバル CLAUDE.md の「AskUserQuestion のターン分離」節が長い — 見送り推奨

`CLAUDE.md:36-46`（約 700 bytes）。長いが**ハーネスのバグ回避策**であり、削ると実害が出る（テキストが実際に消失する）。ソース中に `<!-- /WORKAROUND -->`（`CLAUDE.md:46`）と回避策マーカーが打たれている点も、意図的な措置であることの裏付け。「短いから安全／長いから危険」で判断してはいけない例。**維持。**

---

## 4. ルールを「なぜ存在するか」で4分類

公式ガイダンスは「短くせよ」ではなく「**モデルが自前でやること・規定的すぎる手順を削れ**」なので、削除候補は最後のバケツのみ。

| 分類 | 該当 | 判断 |
|---|---|---|
| **① ハーネスのバグ回避策** | `CLAUDE.md:36-46` AskUserQuestion ターン分離 | **維持**。実際にテキストが消えるので、"less is more" 論を理由に削ってはいけない |
| **② 安全ガード** | `rules/external-actions.md` 全体 | **維持**。かつ `settings.json` の `ask` permission と併用済み（`external-actions.md:27`）＝決定的ガードとの二段構えで正しい設計 |
| **③ 環境固有の事実** | `CLAUDE.md` の SSH鍵 / `gh auth switch` / index.lock対処 / `D:\temp_wsl` | **維持**。短く、推測不可能で、無いと実際に詰まる |
| **④ スタイル/重複/モデルが自前でやること** | `rules/git-workflow.md`、`rules/neovim-style.md`、`rules/shell-conventions.md` | **これが唯一の削除・移設候補** |

---

## 5. ローカルの実証データ（今日の retrospective より）

外部記事より**自分のデータのほうが強い証拠**なので先に出す。

**「常時ロードのルール本文」の行動変容効果は弱い、という実測:**
- `verify-assumptions-with-real-data` は **2026-07-02 に learned-rules.md へ昇格**（＝以後 全セッション常時ロード）
- にもかかわらず 2026-07-14〜27 の2週間で **pain 3件**
- うち2件はセッション要約自身が「学習ルールに反した」「グローバルルールを破った」と**自己記録**している
- → 「ルール文を常時読ませる」方式では止まっていない

**逆向きの証拠も同じデータセットにある（公平に併記）:**
- `separate-deterministic-from-nondeterministic`：reinforce 10 — **昇格済み（＝常時ロード）で機能している唯一の有効な反証**
- → **「ルールは全部無駄」ではない。効くルールと効かないルールがある**

※ SDD / TDD（success 各10）は反証に**使えない**。この2件は `learned-rules.md` へ昇格しておらず、superpowers スキルに裏打ちされた成功なので、「常時ロードのルール本文」の効果については何も語らない。

**示唆**: ルールの実効性は「載っているか」ではなく「決定的に強制されているか」で決まる。`external-actions.md` が `ask` permission と併用されているのが正しい形。

---

## 6. 再構成案

### 提案A: `git-workflow.md` の重複を解消 — 推奨度：高

**前提**: git 関連の記述は**3箇所**に分散している（2箇所ではない）:
1. `rules/git-workflow.md` — プレフィックス表・ブランチ戦略・push ルール
2. `.claude/CLAUDE.md:83-94` — プレフィックス表・push ルール（1と重複）
3. `.claude-global/CLAUDE.md`「Git操作のツール選択」節 — remote URL → `gh` / `mcp__gitbucket__*` の振り分け（**重複していない独自内容。維持**）

`git-workflow.md` の3ブロックそれぞれの行き先:

| `git-workflow.md` の内容 | 行き先 |
|---|---|
| プレフィックス表（`:4-8`） | **削除**。`.claude/CLAUDE.md:91-94` が正 |
| ブランチ戦略 `main`/`feat/*`/`fix/*`（`:11-14`） | **グローバル `CLAUDE.md` へ移す**。全プロジェクト共通の命名規約で、他に書かれていない — **落とさないこと** |
| push ルール（`:17-18`） | **グローバル `CLAUDE.md` へ2行で移す**。「force push は原則禁止」はプロジェクト側に無い独自内容 |

つまり実質は「プレフィックス表だけを削り、残り2ブロックをグローバル CLAUDE.md へ移設」。

**`chore:` の食い違いはユーザー判断**（監査側で決めない）: グローバルは5つ、プロジェクトは4つ（`chore:` なし）。直近コミット履歴は `fix:`/`docs:`/`feat:`/`refactor:` のみで **`chore:` の使用実績が無い**ため、プロジェクト側に `chore:` を足すのは既存の運用を変える行為になる。「どちらに寄せるか」は要確認 —「解消すべき」という点だけが監査の結論。

- 効果: 408 bytes 削減＋**指示の衝突を1つ解消**（こちらが本質）

### 提案B: `neovim-style.md` / `shell-conventions.md` に `paths:` frontmatter を足す — 推奨度：**高**（当初案より大幅に良化）

**ファイル移動も skill 化も不要**。frontmatter 4行を足すだけで条件ロードになる。内容は1文字も変えず、置き場所も変えない。

```markdown
---
paths:
  - "config/nvim/**/*"
  - "**/*.lua"
---
# Neovim設定スタイルガイド
（以下 現状のまま）
```

```markdown
---
paths:
  - "**/*.sh"
  - "**/*.bash"
  - "scripts/**/*"
---
# シェルスクリプト規約
（以下 現状のまま）
```

効果: 常時ロードから **1,045 bytes を外す**（該当ファイル編集時のみロード）。内容を失わないので「明示しておきたい」というニーズも満たす — 当初案（移設 or 削除）より明確に優れる。

**検証すべき点（UNVERIFIED）**: `~/.config/nvim` → `config/nvim/` のシンボリックリンク経由で編集した場合に発火するか。公式は v2.1.198 以降「symlinked path to the project directory」をサポートと明記しているが、この構成（プロジェクト外からプロジェクト内へ入るリンク）が該当するかは実測していない。
検証手順: frontmatter を足した後、nvim 設定を1ファイル編集して `/context` の **Memory files** に当該ルールが現れるか確認。または `InstructionsLoaded` hook でログを取る（公式が「useful for debugging path-specific rules or lazy-loaded files」と案内している方法）。
発火しない場合は `paths:` に `**/*.lua` のような拡張子パターンを併記すれば回避できる（上記案は既にそうしてある）。

### 提案C: `learned-rules.md` は現状維持、ただし昇格基準を見直す — 推奨度：高

- 現在3件（本日1件追加）。上限15件にはまだ余裕があり、**量の問題は無い**
- 問題は**質**: 「読んで守る」方式で守られないパターン（= `verify-assumptions-with-real-data`）を、ルール追加で対処し続けても効かない
- → retrospective スキルの手順7が既に「pain継続なら Hook等の機械的強制へ格上げを検討」と定めている。**その発動条件に今まさに当たっている**
- 提案: 次回以降の昇格判断で「これは決定的に強制できるか？」を先に問う。強制できるものは rules ではなく Hook / permission へ

### 提案D: 検証・自己チェックを促す文言の点検 — 結果：**対処不要（CONFIRMED clean）**

公式が明示的に「削除せよ」と言っている唯一の項目。実測した結果、**削除対象は無かった**。

- `CLAUDE.md` / `rules/`：`double-check` / `re-verify` / `必ず検証してから回答` 的な**汎用の自己検証指示は無し**
  （`learned-rules.md:13` の「実データで検証」は*何を根拠にするか*の話であり、*二度見しろ*ではないので該当しない）
- **skill 30個も実測してゼロ件**:
  ```
  grep -rln -iE "double.?check|再確認して|検証ステップ|verify.*subagent|subagent.*検証|必ず検証|re-verify" */SKILL.md
  → 0 件
  ```
- → **この観点では既に健全**。公式が最も強く警告している過剰検証の罠には、もともと踏み込んでいなかった

---

## 7. 何を変えないか、とその理由

明示しておく（"less is more" を機械適用すると壊れるもの）:

| 対象 | 変えない理由 |
|---|---|
| `CLAUDE.md` AskUserQuestion ターン分離節 | ハーネスの実バグ回避。削るとテキストが実際に消失する。長さは判断基準にならない |
| `rules/external-actions.md` | 安全ガード。かつ `ask` permission との二段構えという正しい設計 |
| `CLAUDE.md` 環境節（SSH鍵・index.lock・gh auth switch・temp_wsl） | 推測不可能な環境固有事実。短く、無いと実際に詰まる |
| `CLAUDE.md` Memory管理ルール | agent-memory への入口として機能しており、二重管理を防ぐ側の記述 |
| `learned-rules.md` の既存3ルール | 価値観系で常時効かせる意味がある。件数も上限内 |
| skill 30個 | 本監査のスコープ外。条件ロードなので常時コストは frontmatter のみ |

---

## 8. 削減見積まとめ

| 提案 | 常時ロードからの削減 | 本質的な効果 | 推奨度 |
|---|---:|---|---|
| A: git-workflow.md の重複解消（ブランチ戦略・pushは移設） | 408 | **指示の衝突1件を解消**（こちらが主目的） | 高 |
| B: neovim-style / shell-conventions に `paths:` を付与 | 1,045 | 内容を失わず条件ロード化。frontmatter 4行のみ | **高** |
| C: learned-rules 現状維持＋昇格基準見直し | 0 | 効かないルールの積み増しを止める | 高 |
| D: 検証指示の点検 | 0（該当なし） | 実測ゼロ件。既に健全で対処不要 | — |
| **合計** | **1,453 / 10,610（約14%）** | | |

**バイト削減は主目的ではない**。ただし公式ドキュメントが「CLAUDE.md は 200行以内を目標」「長いファイルはコンテキストを消費し**追従性を下げる**（reduce adherence）」と明記しているため、**量そのものにも公式の裏付けがある**（当初 REFUTED とした「150〜200命令」というブログの数値とは別物。公式は行数の目安を CLAUDE.md 単位で示している）。現状のグローバル CLAUDE.md は約110行で目安内。

効果が期待できる順:
1. **提案B** — コスト（frontmatter 4行）に対して効果が最大。内容を1文字も失わない
2. **提案A** — 指示の衝突の解消。公式も「if two rules contradict each other, Claude may pick one arbitrarily」と警告
3. **提案C** — 効かないルールを増やさない運用への転換

**総評: この設定群は既にかなり健全**。「Opus 5 で過度なプロンプトが逆効果」という前提は公式ドキュメントで裏付けられたが、公式が最も強く警告する「過剰検証を促す指示」は**実測ゼロ件**、「規定的すぎる step-by-step」も rules 内には無い。実際に見つかった問題は **(1) git ルールの二重定義＋`chore:` の食い違い、(2) 条件ロードにできるルールを無条件ロードしている（frontmatter 未使用）、(3) 昇格しても守られないルールが1件** の3点で、いずれも局所的。**大掛かりな再構成は不要**。

最大の発見は**設計の欠落ではなく機能の未使用** — `paths:` frontmatter という公式機能を使っていなかったこと。

---

## 9. 実施記録（2026-07-27）

ユーザー承認を得て提案A・B・Cを実施。

### 実測結果

| | BEFORE | AFTER | 差分 |
|---|---:|---:|---:|
| **無条件ロード**（CLAUDE.md + frontmatter無しrules） | 10,610 | **9,498** | **−1,112（−10.5%）** |
| 条件ロードへ移行（`paths:` 付き） | 0 | 1,164 | +1,164 |
| rules ファイル数 | 5 | 4 | −1 |

**見積との差異**: 予測1,453に対し実測1,112。グローバル `CLAUDE.md` がブランチ戦略・pushルールを吸収して 5,384→5,725（+341）に増えたため。移設した内容は消していないので**差分は情報の欠落ではない**。

### 実施内容

**提案A（git重複解消）**
- `.claude/CLAUDE.md`: `chore:` 追加＋順序をグローバルと統一（**ユーザー判断: `chore:` 追加**を採用。全履歴で46件の使用実績があり、当初「実績なし」と述べたのは直近5件のみを見た誤り → 訂正済み）
- `.claude-global/CLAUDE.md`: 「Git ワークフロー」節を新設し、ブランチ戦略＋pushルールを移設。プレフィックスは各プロジェクト CLAUDE.md に従う旨を明記
- `rules/git-workflow.md` を `git rm`（削除前に3ブロック全部の移設先を確認済み）

**提案B（条件ロード化）**
- `rules/neovim-style.md` に `paths: config/nvim/**/*`, `**/*.lua`
- `rules/shell-conventions.md` に `paths: **/*.sh`, `**/*.bash`, `scripts/**/*`
- 本文は1文字も変更なし。シンボリックリンク（`~/.claude/rules/`）経由で frontmatter が見えることを確認済み

**提案C（昇格基準の見直し）**
- `skills/retrospective/SKILL.md` 手順6に「**最初に問うこと: このルールは決定的に強制できるか？**」を追加。強制できるなら Hook/permission を第一候補にする
- 根拠として公式引用（"not enforced configuration" / PreToolUse hook）と `verify-assumptions-with-real-data` の pain 3 実証データ、`external-actions.md` の二段構え実例を記載
- 振り分け表に2行追加: 「機械判定できる → Hook優先」「ファイル種別に限定 → `paths:` frontmatter」
- 手順6の項3に `paths:` の説明と公式の adherence 引用を追記

### 検証状況

| 項目 | 状態 |
|---|---|
| frontmatter の構文（`---` で開閉、`paths:` リスト） | ✅ 確認済み |
| symlink 経由での frontmatter 可視性 | ✅ 確認済み |
| `external-actions.md` / `learned-rules.md` が無条件ロードのまま | ✅ 確認済み（意図どおり） |
| git-workflow.md の3ブロックの移設先 | ✅ 削除前に全数確認 |
| **`paths:` の実発火（symlink経由の nvim 編集）** | ⏳ **未検証** — 次に nvim 設定を編集するセッションで `/context` の Memory files を確認すること |

---

---

## 10. 未解決 / 次アクション候補

- **提案Bの実発火は未検証**。次に nvim 設定を触るときに `/context` の **Memory files** に `neovim-style.md` が出るか確認する。出ない場合は `paths:` に `**/*.lua` を入れてあるので拡張子側で拾われる想定
- `verify-assumptions-with-real-data` の Hook 化検討（retrospective 手順7の発動条件に該当。手順6の新しい判定基準の初適用対象になる）
- `pr-artifact-hygiene` の Hook 化検討（`.mcp.json` 混入検出は決定的に判定可能、success 4）
- `ant` CLI 未インストールのため本監査はバイト数ベース。トークン精度が必要なら `ant` 導入後に再計測
- **本監査は retrospective の昇格候補6件を裁定していない**（SDD/TDD/phased-layer-isolation/gh-api-patch/askuserquestion-turn-separation/pr-artifact-hygiene）。スコープ外として据え置き
- 未点検の公式機能: `/doctor`（v2.1.206+ で CLAUDE.md の trim 提案）、`claudeMdExcludes`、`--append-system-prompt`
