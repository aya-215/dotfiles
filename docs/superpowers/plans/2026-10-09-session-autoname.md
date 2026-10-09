# セッション自動命名 mod Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 対話セッションの起動時に `/color` で色を付け、会話内容から Haiku で名前を作って `/rename` で付け続ける Claude Code の mod を作る。

**Architecture:** mod は function hooks の plugin（`.claude-global/mods/session-autoname/`）。判断はすべて `hooks/naming.ts` の純粋関数に置き、`hooks/register.ts` は hook の登録と `$`（engine）呼び出しだけの薄いつなぎにする。`/color` `/rename` と Haiku 呼び出しは hook の中で await せず `$.clock.after(0, ...)` で hook の外に出す。配布は `settings.json` の `env.CLAUDE_CODE_PLUGIN_DIRS`。

**Tech Stack:** TypeScript（Claude Code function hooks API, 本体 2.1.295 / EARLY ACCESS）、`claude plugin test` / `claude plugin validate`、`tsc`（`nix shell nixpkgs#typescript`）

**Spec:** `docs/superpowers/specs/2026-10-09-session-autoname-design.md`

## Global Constraints

- mod の場所: `/home/aya/.dotfiles/.claude-global/mods/session-autoname/`（以下 `$MOD`）
- plugin 名: `session-autoname`（`plugin.json` の `name` と `$.state` の `plugin` で同じ文字列）
- 色の候補は8色固定: `red, blue, green, yellow, purple, orange, pink, cyan`（`default` は使わない）
- 命名タイミング: 応答完了1回目と以後5ターンごと（1, 6, 11, …）
- 名前: 日本語15文字以内。モデルは `haiku`
- 命名の材料: `composer` から来た自分のプロンプト（新しい順に合計4,000文字まで）＋直近の応答の先頭1,000文字＋現在の名前
- 対象は `session.start` の `isInteractive: true` のセッションのメインスレッドだけ
- `$.command.run` と `$.model.complete` は hook の中で await しない（`$.clock.after(0, ...)` 経由）
- コードコメントは非自明な WHY だけ、1行で（`~/.claude/rules/code-comments.md`）
- コミットメッセージは `feat(claude):` 等のプレフィックス＋日本語。全タスクのコミット後に1回 `git push`
- `/home/aya/.dotfiles` は `/mnt/` 配下ではないが、`index.lock` エラーが出たら `rm -f /home/aya/.dotfiles/.git/index.lock` してから再実行する
- `.claude-global/settings.json` には既にユーザーの未コミット変更がある。**ファイル丸ごと `git add` しない**（Task 3 の手順で自分の1行だけを index に載せる）

## Review Focus

- `claude -p`（日報要約など）でも mod が読み込まれる → `isInteractive: false` のセッションでは Haiku を呼ばず、色も付けない（Task 1 `countTurn` / `needsColor` / `addPrompt` のテスト）
- サブエージェントのターンや中断したターン → 5ターン周期に数えず、命名の材料にもしない（Task 2 のテスト「サブエージェントと中断のターンは数えない」）
- タスク通知・plugin・スラッシュコマンドから来たプロンプト → 命名の材料に入れない（Task 1 `addPrompt` のテスト）
- Haiku の出力が崩れている（引用符付き・複数行・15文字超え・空白だけ）→ 1行目の中身だけを15文字に収めて使い、空なら名前を変えない（Task 1 `cleanName` / `nextName` のテスト）
- 4,000文字を超える長いプロンプトを1回で貼った → 落ちずに末尾4,000文字だけを材料にする（Task 1 `addPrompt` のテスト）

---

### Task 1: 雛形と命名ロジック（純粋関数）

**Files:**
- Create: `$MOD/.claude-plugin/plugin.json`
- Create: `$MOD/hooks/hooks.json`
- Create: `$MOD/hooks/register.ts`（この時点では何も登録しない）
- Create: `$MOD/hooks/naming.ts`
- Create: `$MOD/types/index.d.ts`
- Create: `$MOD/tsconfig.json`
- Create: `$MOD/.gitignore`
- Test: `$MOD/tests/naming.test.ts`

**Interfaces:**
- Consumes: なし
- Produces（`hooks/naming.ts`。Task 2 が使う）:
  - `COLORS: readonly Color[]`
  - `COLOR_INDEX_KEY = 'nextColorIndex'`
  - `INITIAL: Naming`
  - `pickColor(stored: unknown): { color: Color; nextIndex: number }`
  - `needsColor(state: Naming, isInteractive: boolean): boolean`
  - `activate(state: Naming, color: Color): Naming`
  - `addPrompt(state: Naming, text: string, originKind: string): Naming`
  - `countTurn(state: Naming, turn: TurnEnd): { state: Naming; isDue: boolean }`（`TurnEnd = { reason: string; agentId?: string }`）
  - `noteRename(state: Naming, origin: CommandOrigin, pluginName: string): Naming`（`CommandOrigin = { kind: string; name?: string }`）
  - `clearConversation(state: Naming): Naming`
  - `buildPrompt(prompts: readonly string[], answer: string, current: string): string`
  - `nextName(text: string, current: string): string | null`
- Produces（`types/index.d.ts`）: `Color`, `Naming`, `PluginState['session-autoname'] = { naming: Naming }`

- [ ] **Step 1: 雛形ファイルを作る**

`$MOD/.claude-plugin/plugin.json`:

```json
{
  "name": "session-autoname",
  "version": "0.1.0",
  "description": "対話セッションに色と、会話内容から作った名前を自動で付ける",
  "types": "./types/index.d.ts"
}
```

`$MOD/hooks/hooks.json`:

```json
{ "modules": ["./register.ts"] }
```

`$MOD/hooks/register.ts`（Task 2 で中身を書く）:

```ts
import type { Register } from 'claude-code'

export const register: Register = () => {}
```

`$MOD/types/index.d.ts`:

```ts
export type Color = 'red' | 'blue' | 'green' | 'yellow' | 'purple' | 'orange' | 'pink' | 'cyan'

export type Naming = {
  isActive: boolean
  color: Color | null
  answered: number
  prompts: string[]
  current: string
  isManual: boolean
}

declare module 'claude-code' {
  interface PluginState {
    'session-autoname': { naming: Naming }
  }
}
```

`$MOD/tsconfig.json`（型ファイル冒頭の推奨設定そのまま）:

```json
{
  "compilerOptions": {
    "target": "es2023", "lib": ["es2023"], "types": [],
    "module": "esnext", "moduleResolution": "bundler",
    "strict": true, "noUncheckedIndexedAccess": true,
    "noEmit": true, "skipLibCheck": true,
    "jsx": "react", "jsxFactory": "h", "jsxFragmentFactory": "Fragment"
  },
  "include": [".claude-plugin/types", "hooks", "types", "tests"]
}
```

`$MOD/.gitignore`（本体が読み込みのたびに書き出す型ファイルを除外）:

```
.claude-plugin/types/
```

- [ ] **Step 2: API の型ファイルを置く**

`tsc` 用に本体 2.1.295 の型宣言を `$MOD/.claude-plugin/types/claude-code/index.d.ts` に置く（gitignore 済み）。brainstorming 時に本体バイナリから展開したものがある:

```bash
mkdir -p /home/aya/.dotfiles/.claude-global/mods/session-autoname/.claude-plugin/types/claude-code
cp /tmp/claude-1000/-home-aya--dotfiles/aed5d3f2-2676-4c0a-84bd-429f57e61f2f/scratchpad/modref/frame5.md \
   /home/aya/.dotfiles/.claude-global/mods/session-autoname/.claude-plugin/types/claude-code/index.d.ts
head -1 /home/aya/.dotfiles/.claude-global/mods/session-autoname/.claude-plugin/types/claude-code/index.d.ts
```

Expected: `// Claude Code function hooks: the plugin API's TypeScript declarations.`

コピー元が無い場合（別セッションで実行するとき）は、本体バイナリから zstd フレームを展開して先頭行が一致するものを取り出す:

```bash
OUT=/home/aya/.dotfiles/.claude-global/mods/session-autoname/.claude-plugin/types/claude-code/index.d.ts
B=$(ls -d /home/aya/.local/share/claude/versions/* | sort -V | tail -1)
nix shell nixpkgs#zstd -c python3 -I - "$B" "$OUT" <<'EOF'
import re, subprocess, sys
b = open(sys.argv[1], 'rb').read()
for m in re.finditer(rb'\x28\xb5\x2f\xfd', b):
    try:
        out = subprocess.run(['zstd', '-dc', '--no-check'], input=b[m.start():m.start() + 400000],
                             capture_output=True, timeout=5).stdout
    except Exception:
        continue
    if out.startswith(b"// Claude Code function hooks: the plugin API's TypeScript declarations."):
        open(sys.argv[2], 'wb').write(out)
        print('written', len(out))
        break
EOF
```

- [ ] **Step 3: 失敗するテストを書く**

`$MOD/tests/naming.test.ts`:

```ts
import { describe, expect, test } from 'claude-code/testing'

import {
  COLORS,
  INITIAL,
  PROMPTS_MAX_CHARS,
  activate,
  addPrompt,
  buildPrompt,
  clearConversation,
  cleanName,
  countTurn,
  isNamingTurn,
  needsColor,
  nextName,
  noteRename,
  pickColor,
} from '../hooks/naming'

const active = activate(INITIAL, 'red')

describe('pickColor', () => {
  test('保存された番号の色を選び、次の番号を返す', () => {
    expect(pickColor(2)).toEqual({ color: 'yellow', nextIndex: 3 })
  })
  test('最後の色の次は先頭に戻る', () => {
    expect(pickColor(7)).toEqual({ color: 'cyan', nextIndex: 0 })
    expect(pickColor(10)).toEqual({ color: 'yellow', nextIndex: 3 })
  })
  test('未保存・不正な値は先頭から', () => {
    expect(pickColor(undefined)).toEqual({ color: 'red', nextIndex: 1 })
    expect(pickColor(-1)).toEqual({ color: 'red', nextIndex: 1 })
    expect(pickColor(1.5)).toEqual({ color: 'red', nextIndex: 1 })
    expect(pickColor('3')).toEqual({ color: 'red', nextIndex: 1 })
  })
  test('/color が受け付ける8色を default 抜きで持つ', () => {
    expect(COLORS).toEqual(['red', 'blue', 'green', 'yellow', 'purple', 'orange', 'pink', 'cyan'])
  })
})

describe('needsColor', () => {
  test('対話セッションでまだ色が無ければ付ける', () => {
    expect(needsColor(INITIAL, true)).toBe(true)
  })
  test('claude -p などの非対話セッションでは付けない', () => {
    expect(needsColor(INITIAL, false)).toBe(false)
  })
  test('hot reload で再発火しても付け直さない', () => {
    expect(needsColor(active, true)).toBe(false)
  })
})

describe('isNamingTurn', () => {
  test('1回目と以後5ターンごとだけ true', () => {
    const due = [0, 1, 2, 3, 4, 5, 6, 7, 10, 11].filter(isNamingTurn)
    expect(due).toEqual([1, 6, 11])
  })
})

describe('countTurn', () => {
  test('メインスレッドの応答を数え、1回目は命名する', () => {
    const r = countTurn(active, { reason: 'answer' })
    expect(r.state.answered).toBe(1)
    expect(r.isDue).toBe(true)
  })
  test('非対話セッションでは数えず命名もしない', () => {
    const r = countTurn(INITIAL, { reason: 'answer' })
    expect(r.state.answered).toBe(0)
    expect(r.isDue).toBe(false)
  })
  test('サブエージェントのターンは数えない', () => {
    const r = countTurn(active, { reason: 'answer', agentId: 'agent-1' })
    expect(r.state.answered).toBe(0)
    expect(r.isDue).toBe(false)
  })
  test('中断・エラーのターンは数えない', () => {
    expect(countTurn(active, { reason: 'aborted' }).state.answered).toBe(0)
    expect(countTurn(active, { reason: 'error' }).state.answered).toBe(0)
  })
  test('手で名前を付けた後は数えるが命名しない', () => {
    const r = countTurn({ ...active, isManual: true }, { reason: 'answer' })
    expect(r.state.answered).toBe(1)
    expect(r.isDue).toBe(false)
  })
})

describe('addPrompt', () => {
  test('composer から来たプロンプトを足す', () => {
    expect(addPrompt(active, ' バグを調べて ', 'composer').prompts).toEqual(['バグを調べて'])
  })
  test('タスク通知や plugin から来たものは足さない', () => {
    expect(addPrompt(active, '通知', 'task-notification').prompts).toEqual([])
    expect(addPrompt(active, '代理', 'plugin').prompts).toEqual([])
  })
  test('スラッシュコマンドと空白だけの入力は足さない', () => {
    expect(addPrompt(active, '/rename 手動', 'composer').prompts).toEqual([])
    expect(addPrompt(active, '   ', 'composer').prompts).toEqual([])
  })
  test('非対話セッションでは足さない', () => {
    expect(addPrompt(INITIAL, 'バグを調べて', 'composer').prompts).toEqual([])
  })
  test('新しい順に合計4,000文字までだけ残す', () => {
    const old = 'a'.repeat(3000)
    const recent = 'b'.repeat(2000)
    const state = addPrompt(addPrompt(active, old, 'composer'), recent, 'composer')
    expect(state.prompts).toEqual([recent])
  })
  test('1件で4,000文字を超えるプロンプトは末尾だけ残す', () => {
    const long = 'x'.repeat(PROMPTS_MAX_CHARS) + 'tail'
    const state = addPrompt(active, long, 'composer')
    expect(state.prompts).toHaveLength(1)
    expect(state.prompts[0]).toHaveLength(PROMPTS_MAX_CHARS)
    expect(state.prompts[0]).toEndWith('tail')
  })
})

describe('noteRename', () => {
  test('この mod 自身の /rename では止めない', () => {
    expect(noteRename(active, { kind: 'plugin', name: 'session-autoname' }, 'session-autoname').isManual).toBe(false)
  })
  test('手で打った /rename なら止める', () => {
    expect(noteRename(active, { kind: 'composer' }, 'session-autoname').isManual).toBe(true)
  })
  test('別の plugin の /rename でも止める', () => {
    expect(noteRename(active, { kind: 'plugin', name: 'other' }, 'session-autoname').isManual).toBe(true)
  })
})

describe('clearConversation', () => {
  test('会話に紐づく値だけ戻し、色と対象フラグは残す', () => {
    const used = { ...active, answered: 7, prompts: ['p'], current: '名前', isManual: true }
    expect(clearConversation(used)).toEqual({ ...active, answered: 0, prompts: [], current: '', isManual: false })
  })
})

describe('buildPrompt', () => {
  test('依頼と応答の冒頭1,000文字を含める', () => {
    const prompt = buildPrompt(['依頼A', '依頼B'], 'z'.repeat(1500), '')
    expect(prompt).toContain('- 依頼A\n- 依頼B')
    expect(prompt).toContain('z'.repeat(1000))
    expect(prompt).not.toContain('z'.repeat(1001))
    expect(prompt).not.toContain('現在の名前')
  })
  test('現在の名前があれば、合っていればそのまま返すよう頼む', () => {
    expect(buildPrompt([], '応答', '認証バグ調査')).toContain('現在の名前は「認証バグ調査」')
  })
})

describe('cleanName / nextName', () => {
  test('括弧や引用符を外す', () => {
    expect(cleanName('「認証バグ調査」')).toBe('認証バグ調査')
    expect(cleanName('"PRレビュー"')).toBe('PRレビュー')
  })
  test('1行目だけ使う', () => {
    expect(cleanName('PR#42レビュー\nこれは説明です')).toBe('PR#42レビュー')
  })
  test('15文字に切り詰める', () => {
    expect(cleanName('あいうえおかきくけこさしすせそたちつ')).toBe('あいうえおかきくけこさしすせそ')
  })
  test('空白だけなら空文字', () => {
    expect(cleanName('  \n  ')).toBe('')
  })
  test('空・現在と同じなら名前を変えない', () => {
    expect(nextName('', '旧名')).toBeNull()
    expect(nextName('「旧名」', '旧名')).toBeNull()
    expect(nextName('新名', '旧名')).toBe('新名')
  })
})
```

- [ ] **Step 4: テストが失敗することを確認する**

Run: `claude plugin test /home/aya/.dotfiles/.claude-global/mods/session-autoname`
Expected: FAIL（`../hooks/naming` が無いため読み込みエラー）

- [ ] **Step 5: 命名ロジックを実装する**

`$MOD/hooks/naming.ts`:

```ts
import type { Color, Naming } from '../types'

export const COLORS: readonly Color[] = ['red', 'blue', 'green', 'yellow', 'purple', 'orange', 'pink', 'cyan']
export const COLOR_INDEX_KEY = 'nextColorIndex'
export const RENAME_EVERY = 5
export const NAME_MAX_CHARS = 15
export const PROMPTS_MAX_CHARS = 4000
export const ANSWER_MAX_CHARS = 1000

export const INITIAL: Naming = {
  isActive: false,
  color: null,
  answered: 0,
  prompts: [],
  current: '',
  isManual: false,
}

export type TurnEnd = { reason: string; agentId?: string }
export type CommandOrigin = { kind: string; name?: string }

export function pickColor(stored: unknown): { color: Color; nextIndex: number } {
  const index = typeof stored === 'number' && Number.isInteger(stored) && stored >= 0 ? stored % COLORS.length : 0
  return { color: COLORS[index]!, nextIndex: (index + 1) % COLORS.length }
}

export function needsColor(state: Naming, isInteractive: boolean): boolean {
  return isInteractive && state.color === null
}

export function activate(state: Naming, color: Color): Naming {
  return { ...state, isActive: true, color }
}

export function isNamingTurn(answered: number): boolean {
  return answered >= 1 && (answered - 1) % RENAME_EVERY === 0
}

export function addPrompt(state: Naming, text: string, originKind: string): Naming {
  const trimmed = text.trim()
  if (!state.isActive || originKind !== 'composer' || trimmed === '' || trimmed.startsWith('/')) {
    return state
  }
  if (trimmed.length >= PROMPTS_MAX_CHARS) {
    return { ...state, prompts: [trimmed.slice(-PROMPTS_MAX_CHARS)] }
  }
  const prompts = [...state.prompts, trimmed]
  let total = 0
  let start = prompts.length
  while (start > 0 && total + prompts[start - 1]!.length <= PROMPTS_MAX_CHARS) {
    total += prompts[start - 1]!.length
    start -= 1
  }
  return { ...state, prompts: prompts.slice(start) }
}

export function countTurn(state: Naming, turn: TurnEnd): { state: Naming; isDue: boolean } {
  if (!state.isActive || turn.reason !== 'answer' || turn.agentId !== undefined) {
    return { state, isDue: false }
  }
  const answered = state.answered + 1
  return { state: { ...state, answered }, isDue: !state.isManual && isNamingTurn(answered) }
}

export function noteRename(state: Naming, origin: CommandOrigin, pluginName: string): Naming {
  if (origin.kind === 'plugin' && origin.name === pluginName) {
    return state
  }
  return { ...state, isManual: true }
}

export function clearConversation(state: Naming): Naming {
  return { ...state, answered: 0, prompts: [], current: '', isManual: false }
}

export function buildPrompt(prompts: readonly string[], answer: string, current: string): string {
  const lines = [
    'Claude Code のセッションに、作業内容を表す名前を付けてください。',
    `日本語で${NAME_MAX_CHARS}文字以内の名前を1つだけ出力し、説明や記号は付けないでください。`,
  ]
  if (current !== '') {
    lines.push(`現在の名前は「${current}」です。まだ作業内容に合っていれば、それをそのまま出力してください。`)
  }
  lines.push(
    '',
    '## ユーザーの依頼（古い順）',
    prompts.length === 0 ? '（なし）' : prompts.map(p => `- ${p}`).join('\n'),
    '',
    '## 直近の応答（冒頭）',
    answer.slice(0, ANSWER_MAX_CHARS),
  )
  return lines.join('\n')
}

export function cleanName(text: string): string {
  const firstLine = text.trim().split('\n')[0] ?? ''
  const unquoted = firstLine
    .trim()
    .replace(/^[「『"'`]+|[」』"'`]+$/g, '')
    .replace(/\s+/g, ' ')
    .trim()
  return Array.from(unquoted).slice(0, NAME_MAX_CHARS).join('')
}

export function nextName(text: string, current: string): string | null {
  const name = cleanName(text)
  return name === '' || name === current ? null : name
}
```

- [ ] **Step 6: テストが通ることを確認する**

Run: `claude plugin test /home/aya/.dotfiles/.claude-global/mods/session-autoname`
Expected: すべて PASS、終了コード 0

- [ ] **Step 7: 型と manifest を検査する**

Run:

```bash
nix shell nixpkgs#typescript -c tsc -p /home/aya/.dotfiles/.claude-global/mods/session-autoname
claude plugin validate /home/aya/.dotfiles/.claude-global/mods/session-autoname
```

Expected: `tsc` は出力なしで終了コード 0。`validate` はエラーなし（register はまだ何も hook しない）

- [ ] **Step 8: コミット**

```bash
rm -f /home/aya/.dotfiles/.git/index.lock
git -C /home/aya/.dotfiles add .claude-global/mods/session-autoname
git -C /home/aya/.dotfiles status --short .claude-global/mods/session-autoname
git -C /home/aya/.dotfiles commit -m "feat(claude): セッション自動命名modの雛形と命名ロジックを追加"
```

`status` に `.claude-plugin/types/` が出ていないこと（gitignore が効いていること）を確認してからコミットする。

---

### Task 2: hook の登録（register.ts）

**Files:**
- Modify: `$MOD/hooks/register.ts`（全体を置き換える）
- Test: `$MOD/tests/register.test.ts`

**Interfaces:**
- Consumes: Task 1 の `hooks/naming.ts` の関数・定数すべてと `types/index.d.ts` の `Naming`
- Produces: hook の登録（`session.start` / `prompt.submit` / `turn.complete` / `command.run`(rename) / `session.end`）。他タスクから呼ばれる関数は無い

テストキットの仕組み（型ファイル `claude-code/testing` より）:
- テストの `on` で登録した hook はすべての plugin の下に入り、engine の代役になる。下に何も無いイベントは例外になるため、使うイベントはすべて `world()` で受ける
- `mock.clock(on)` で `$.clock` がメモリ上の時計になり、`advance(ms)` で進めたときだけ `$.clock.after` のタイマーが発火する
- タイマー内の処理は非同期で続くため、結果は `recorder().until(n)` で「n 件目が届くまで」待つ。届かなければテストの制限時間（5秒）で失敗する
- 「起きないこと」を確かめるときは、後から必ず起きる処理を「区切り」として待ち、その時点の記録を見る（タイマーは登録順に発火する）

- [ ] **Step 1: 失敗するテストを書く**

`$MOD/tests/register.test.ts`:

```ts
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { expect, mock, test } from 'claude-code/testing'

type Recorder<T> = {
  items: T[]
  push: (item: T) => void
  until: (count: number) => Promise<void>
}

function recorder<T>(): Recorder<T> {
  const items: T[] = []
  let waiters: { count: number; resolve: () => void }[] = []
  return {
    items,
    push(item) {
      items.push(item)
      waiters = waiters.filter(w => {
        if (items.length < w.count) return true
        w.resolve()
        return false
      })
    },
    until(count) {
      if (items.length >= count) return Promise.resolve()
      return new Promise<void>(resolve => {
        waiters.push({ count, resolve })
      })
    },
  }
}

const USAGE = { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }
const FAIL = '<fail>'

function world(on: On, store: Record<string, unknown> = {}) {
  const commands = recorder<{ command: string; args: string }>()
  const models = recorder<string>()
  const statuses = recorder<string | undefined>()
  const replies: string[] = []

  on('command.run', ($, e) => {
    commands.push({ command: e.command, args: e.args })
    return {}
  })
  on('model.complete', ($, e) => {
    models.push(e.prompt)
    const text = replies.shift() ?? `名前${models.items.length}`
    return text === FAIL
      ? { isAnswered: false as const, reason: 'empty-reply' as const, usage: USAGE }
      : { isAnswered: true as const, text, usage: USAGE }
  })
  on('ui.status', ($, e) => {
    statuses.push(e.text)
  })
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('session.end', ($, e) => ({ sessionId: e.sessionId }))
  on('turn.complete', ($, e) => ({ text: e.answer }))
  on('prompt.submit', ($, e) => ({ text: e.text }))
  mock.store(on, store)
  const clock = mock.clock(on)

  return { commands, models, statuses, replies, clock }
}

function start($: Engine, isInteractive = true) {
  return $.session.start({ cwd: '/tmp/work', surface: isInteractive ? 'terminal' : null, isInteractive })
}

function turn($: Engine, answer: string, agentId?: string) {
  return $.turn.complete({
    reason: 'answer',
    answer,
    durationMs: 1,
    isAborted: false,
    turnId: answer,
    ...(agentId === undefined ? {} : { agentId }),
  })
}

test('起動時に色を順送りで選び、/color は hook が返った後に実行する', async ($, on) => {
  const w = world(on, { nextColorIndex: 2 })
  await start($)
  expect(w.commands.items).toEqual([])
  await w.clock.advance(1)
  await w.commands.until(1)
  expect(w.commands.items[0]).toEqual({ command: 'color', args: 'yellow' })
})

test('hot reload で session.start が再発火しても色を付け直さない', async ($, on) => {
  const w = world(on)
  await start($)
  await w.clock.advance(1)
  await w.commands.until(1)
  await start($)
  await turn($, 'answer-1')
  await w.clock.advance(1)
  await w.commands.until(2)
  expect(w.commands.items.map(c => c.command)).toEqual(['color', 'rename'])
})

test('命名は1回目と以後5ターンごとにだけ走り、自分の /rename では止まらない', async ($, on) => {
  const w = world(on)
  await start($)
  for (let n = 1; n <= 6; n++) {
    await turn($, `answer-${n}`)
    await w.clock.advance(1)
  }
  await w.models.until(2)
  expect(w.models.items[0]).toContain('answer-1')
  expect(w.models.items[1]).toContain('answer-6')
  expect(w.models.items[1]).toContain('現在の名前は「名前1」')
  await w.commands.until(3)
  expect(w.commands.items).toEqual([
    { command: 'color', args: 'red' },
    { command: 'rename', args: '名前1' },
    { command: 'rename', args: '名前2' },
  ])
})

test('サブエージェントと中断のターンは数えない', async ($, on) => {
  const w = world(on)
  await start($)
  await turn($, 'main-1')
  await w.clock.advance(1)
  for (let n = 2; n <= 5; n++) {
    await turn($, `sub-${n}`, 'agent-1')
    await $.turn.complete({ reason: 'aborted', answer: `aborted-${n}`, durationMs: 1, isAborted: true, turnId: `a${n}` })
    await turn($, `main-${n}`)
    await w.clock.advance(1)
  }
  await turn($, 'main-6')
  await w.clock.advance(1)
  await w.models.until(2)
  expect(w.models.items[1]).toContain('main-6')
})

test('手で /rename したら自動命名を止め、/clear で数え直す', async ($, on) => {
  const w = world(on)
  await start($)
  await turn($, 'answer-1')
  await w.clock.advance(1)
  await w.commands.until(2)
  await $.command.run({ command: 'rename', args: '手動の名前' })
  for (let n = 2; n <= 6; n++) {
    await turn($, `answer-${n}`)
    await w.clock.advance(1)
  }
  await $.session.end({ reason: 'clear', sessionId: 's-1', resume: { id: 's-1' } })
  await turn($, 'after-clear')
  await w.clock.advance(1)
  await w.models.until(2)
  expect(w.models.items[1]).toContain('after-clear')
  expect(w.models.items[1]).not.toContain('現在の名前')
})

test('Haiku が失敗したら名前を変えずに status に出す', async ($, on) => {
  const w = world(on)
  w.replies.push(FAIL)
  await start($)
  await w.clock.advance(1)
  await w.commands.until(1)
  await turn($, 'answer-1')
  await w.clock.advance(1)
  await w.statuses.until(1)
  expect(w.statuses.items[0]).toContain('命名をスキップ')
  expect(w.commands.items.map(c => c.command)).toEqual(['color'])
})
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `claude plugin test /home/aya/.dotfiles/.claude-global/mods/session-autoname`
Expected: `tests/naming.test.ts` は PASS、`tests/register.test.ts` は FAIL（register が何も hook しないため `/color` が記録されず、`until` 待ちが5秒で打ち切られる）

- [ ] **Step 3: register.ts を実装する**

`$MOD/hooks/register.ts`（全体を置き換え）:

```ts
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import {
  COLOR_INDEX_KEY,
  INITIAL,
  activate,
  addPrompt,
  buildPrompt,
  clearConversation,
  countTurn,
  needsColor,
  nextName,
  noteRename,
  pickColor,
} from './naming'

const naming = atom({ plugin: 'session-autoname', key: 'naming' } as const, INITIAL)

async function runCommand($: EngineInterface, command: string, args: string): Promise<void> {
  try {
    await $.command.run({ command, args })
  } catch {
    $.ui.status(`session-autoname: /${command} に失敗`)
  }
}

async function nameSession($: EngineInterface, answer: string): Promise<void> {
  const before = await read($, naming)
  if (before.isManual) return
  const reply = await $.model.complete({
    model: 'haiku',
    prompt: buildPrompt(before.prompts, answer, before.current),
    maxTokens: 64,
    effort: 'low',
    timeoutMs: 30000,
  })
  if (!reply.isAnswered) {
    $.ui.status(`session-autoname: 命名をスキップ (${reply.reason})`)
    return
  }
  $.ui.status(undefined)
  const name = nextName(reply.text, before.current)
  // Haiku を待つ間に手で /rename された名前は上書きしない
  const after = await read($, naming)
  if (name === null || after.isManual) return
  await update($, naming, s => ({ ...s, current: name }))
  await runCommand($, 'rename', name)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    if (!needsColor(await read($, naming), e.isInteractive)) return next(e)
    const { color, nextIndex } = pickColor(await $.store.get(COLOR_INDEX_KEY))
    await $.store.set(COLOR_INDEX_KEY, nextIndex)
    await update($, naming, s => activate(s, color))
    // session.start は最初のプロンプト前に待たれるため、ここで /color を await すると詰まる
    $.clock.after(0, () => void runCommand($, 'color', color))
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    await update($, naming, s => addPrompt(s, e.text, e.origin.kind))
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    let isDue = false
    await update($, naming, s => {
      const counted = countTurn(s, e)
      isDue = counted.isDue
      return counted.state
    })
    if (isDue) $.clock.after(0, () => void nameSession($, e.answer))
    return next(e)
  })

  on('command.run', { command: 'rename' }, async ($, e, next) => {
    await update($, naming, s => noteRename(s, e.origin, $.plugin.name))
    return next(e)
  })

  on('session.end', async ($, e, next) => {
    if (e.reason === 'clear') await update($, naming, clearConversation)
    return next(e)
  })
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `claude plugin test /home/aya/.dotfiles/.claude-global/mods/session-autoname`
Expected: `naming.test.ts` と `register.test.ts` がすべて PASS

テストが失敗し、失敗メッセージに「hook を skip した」理由が出ている場合は、その理由を読んで直す（テストキットは skip した hook とその理由を失敗に添える）。型や API の名前の食い違いは Step 5 の `tsc` でも出る。

- [ ] **Step 5: 型と manifest を検査する**

Run:

```bash
nix shell nixpkgs#typescript -c tsc -p /home/aya/.dotfiles/.claude-global/mods/session-autoname
claude plugin validate /home/aya/.dotfiles/.claude-global/mods/session-autoname
```

Expected: `tsc` は出力なしで終了コード 0。`validate` はエラーなしで、hook として `session.start` `prompt.submit` `turn.complete` `command.run` `session.end` を列挙する（`command.run` が `gating hook without .catch:` と表示されるのは仕様上の事実の表示であり、エラーではない）

- [ ] **Step 6: コミット**

```bash
rm -f /home/aya/.dotfiles/.git/index.lock
git -C /home/aya/.dotfiles add .claude-global/mods/session-autoname/hooks/register.ts .claude-global/mods/session-autoname/tests/register.test.ts
git -C /home/aya/.dotfiles commit -m "feat(claude): セッション自動命名modのhookを実装"
```

---

### Task 3: 配布設定と実機確認

**Files:**
- Modify: `/home/aya/.dotfiles/.claude-global/settings.json:2-6`（`env` に1行追加）

**Interfaces:**
- Consumes: Task 2 までの mod フォルダ
- Produces: 新しく起動する対話セッションすべてで mod が読み込まれる状態

- [ ] **Step 1: settings.json の env に1行足す**

`/home/aya/.dotfiles/.claude-global/settings.json` の `env` を次の形にする（作業ツリーにあるユーザーの他の変更には触れない）:

```json
  "env": {
    "CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR": "1",
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_AFK_TIMEOUT_MS": "604800000",
    "CLAUDE_CODE_PLUGIN_DIRS": "/home/aya/.dotfiles/.claude-global/mods/session-autoname"
  },
```

Run: `python3 -I -c "import json; print(json.load(open('/home/aya/.dotfiles/.claude-global/settings.json'))['env']['CLAUDE_CODE_PLUGIN_DIRS'])"`
Expected: `/home/aya/.dotfiles/.claude-global/mods/session-autoname`

- [ ] **Step 2: 自分の1行だけを index に載せてコミットする**

ユーザーの未コミット変更を巻き込まないよう、HEAD 版に同じ1行を足した内容を blob にして index に置く:

```bash
S=/tmp/claude-1000/-home-aya--dotfiles/aed5d3f2-2676-4c0a-84bd-429f57e61f2f/scratchpad/settings.staged.json
git -C /home/aya/.dotfiles show HEAD:.claude-global/settings.json > "$S"
python3 -I - "$S" <<'EOF'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = '    "CLAUDE_AFK_TIMEOUT_MS": "604800000"\n'
new = old.rstrip('\n') + ',\n    "CLAUDE_CODE_PLUGIN_DIRS": "/home/aya/.dotfiles/.claude-global/mods/session-autoname"\n'
assert s.count(old) == 1, 'HEAD の env が想定と違う'
open(p, 'w', encoding='utf-8').write(s.replace(old, new))
EOF
rm -f /home/aya/.dotfiles/.git/index.lock
BLOB=$(git -C /home/aya/.dotfiles hash-object -w "$S")
git -C /home/aya/.dotfiles update-index --cacheinfo 100644,"$BLOB",.claude-global/settings.json
git -C /home/aya/.dotfiles diff --cached -- .claude-global/settings.json
```

Expected: `diff --cached` が `CLAUDE_AFK_TIMEOUT_MS` 行のカンマ追加と `CLAUDE_CODE_PLUGIN_DIRS` 行の追加だけを示す。作業ツリーの `git diff -- .claude-global/settings.json` にはユーザーの元の変更が残っている。

```bash
rm -f /home/aya/.dotfiles/.git/index.lock
git -C /home/aya/.dotfiles commit -m "feat(claude): セッション自動命名modを全対話セッションで読み込む"
rm -f /home/aya/.dotfiles/.git/index.lock
git -C /home/aya/.dotfiles push
```

- [ ] **Step 3: 実機確認（ユーザーと一緒に行う）**

このセッションには mod は読み込まれない。ユーザーに新しい Claude Code を縦分割で2〜3個起動してもらい、次を確認する。

1. 起動直後、プロンプト欄の色がセッションごとに違う（red → blue → green の順）
2. 最初の応答のあと、会話内容に合った15文字以内の名前が付く。縦分割の幅で読める
3. 5ターン後の見直しで、話題が変わっていなければ名前が変わらない
4. 手で `/rename 手動テスト` と打つと、その後のターンで名前が上書きされない（`command.run` に `origin.kind === 'composer'` で届いていることの確認）
5. 引数なしの `/rename` を打ったときの動作。本体が自動で名前を付けるなら、その旨をユーザーに伝える
6. 失敗やエラーが出たときは `claude --debug` で起動し、`session-autoname:` で始まる行を確認する

確認結果を報告し、問題があれば spec に戻って直す。
