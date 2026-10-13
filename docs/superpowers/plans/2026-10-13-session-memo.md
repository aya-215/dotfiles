# セッション作業メモ mod Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 会話ごとの作業メモを、プロンプト上の帯（先頭1件）と `/memo` で開くパネル（全件・追加・編集・先頭へ・削除）で扱う Claude Code の mod を作る。

**Architecture:** function hooks の plugin（`.claude-global/mods/session-memo/`）。メモの操作はすべて `hooks/memo.ts` の純粋関数にし、`hooks/register.tsx` は描画（`ui.render` の `AbovePrompt` と `Pane`）とコマンド・イベントのつなぎだけにする。状態は `$.state`（plugin `session-memo`, key `memo`）だけに持ち、`$.store` は使わない。

**Tech Stack:** TypeScript + JSX（Claude Code function hooks API, 本体 2.1.295 / EARLY ACCESS）、`claude plugin test` / `claude plugin validate`、`tsc`（`nix shell nixpkgs#typescript`）

**Spec:** `docs/superpowers/specs/2026-10-13-session-memo-design.md`

## Global Constraints

- mod の場所: `/home/aya/.dotfiles/.claude-global/mods/session-memo/`（以下 `$MOD`）
- plugin 名: `session-memo`（`plugin.json` の `name` と `$.state` の `plugin` で同じ文字列）。パネルの id は `memo`、コマンド名は `memo`
- 帯: `📝 <先頭のメモ>` と `（+N）`（N=先頭以外の件数、0なら付けない）。本文は `wrap="truncate"`、`（+N）` は別の `Text` で切らない。0件・`hasSurvey` 中は `next(e)`
- パネル: `$.ui.open({ id: 'memo', title: 'Memo', focus: true, closeOnEscape: true, rows })`。入力欄の key は `input`、行のボタンの key は `up:<i>` / `edit:<i>` / `del:<i>`、取消は `cancel`（i は0始まり）
- コマンド: `$.command.register({ name: 'memo', immediate: true, ... })`。返事は `メモを追加（N件）` / `メモを開いた` / `メモを閉じた`
- `session.end` の `reason` が `clear` か `resume` でメモを空にする
- 空白だけの入力は追加しない・書き換えない
- コードコメントは非自明な WHY だけ、1行で（`~/.claude/rules/code-comments.md`）
- コミットメッセージは `feat(claude):` 等＋日本語。全タスクのコミット後に1回 `git push`
- `index.lock` エラーは `rm -f /home/aya/.dotfiles/.git/index.lock` してから再実行
- `.claude-global/settings.json` にはユーザーの未コミット変更がある。**丸ごと `git add` しない**（Task 4 の手順で自分の変更だけを index に載せる）
- テストの書き方（自動命名 mod で確認済み）: `$` 呼び出しを受けるテストの hook（`ui.open` 等）は `{ value: ... }` で包んで返す。テストの `$.command.run` には `origin` と `presentation` も渡す

## Review Focus

- 幅を超える長いメモ → 帯は1行のまま本文だけ切れ、`（+N）` は見えたまま（Task 2 のテスト「長いメモでも（+N）は別要素で残る」）
- 空白だけの入力や、編集で中身を空にした Enter → メモが増えたり空のメモができたりしない（Task 1 `addItem` / `submitInput` のテスト）
- 編集中に別の行を `[↑]` や `[x]` → 編集対象が別のメモにずれない（Task 1 `moveToTop` / `removeItem` のテスト）
- Claude の作業中に `/memo ○○` → ターン終了を待たずにすぐ入る（Task 3 のテスト「immediate で登録する」）
- アンケートが帯を使っているとき → メモの帯を出さずに譲る（Task 2 のテスト「アンケート中は帯を譲る」）

---

### Task 1: 雛形とメモ操作（純粋関数）

**Files:**
- Create: `$MOD/.claude-plugin/plugin.json`
- Create: `$MOD/hooks/hooks.json`
- Create: `$MOD/hooks/register.tsx`（この時点では何も登録しない）
- Create: `$MOD/hooks/memo.ts`
- Create: `$MOD/types/index.d.ts`
- Create: `$MOD/tsconfig.json`
- Create: `$MOD/.gitignore`
- Test: `$MOD/tests/memo.test.ts`

**Interfaces:**
- Consumes: なし
- Produces（`hooks/memo.ts`。Task 2・3 が使う）:
  - `EMPTY: MemoState`
  - `addItem(s: MemoState, text: string): MemoState`
  - `startEdit(s: MemoState, index: number): MemoState`
  - `cancelEdit(s: MemoState): MemoState`
  - `submitInput(s: MemoState, text: string): MemoState`
  - `moveToTop(s: MemoState, index: number): MemoState`
  - `removeItem(s: MemoState, index: number): MemoState`
  - `inputValue(s: MemoState): string`
  - `bandParts(items: readonly string[]): { text: string; more: string } | null`
- Produces（`types/index.d.ts`）: `MemoState = { items: string[]; editing: number | null }`、`PluginState['session-memo'] = { memo: MemoState }`

- [ ] **Step 1: 雛形ファイルを作る**

`$MOD/.claude-plugin/plugin.json`:

```json
{
  "name": "session-memo",
  "version": "0.1.0",
  "description": "会話ごとの作業メモを帯とパネルで扱う",
  "types": "./types/index.d.ts"
}
```

`$MOD/hooks/hooks.json`:

```json
{ "modules": ["./register.tsx"] }
```

`$MOD/hooks/register.tsx`（Task 2 で中身を書く）:

```tsx
import type { Register } from 'claude-code'

export const register: Register = () => {}
```

`$MOD/types/index.d.ts`:

```ts
export type MemoState = {
  items: string[]
  editing: number | null
}

declare module 'claude-code' {
  interface PluginState {
    'session-memo': { memo: MemoState }
  }
}
```

`$MOD/tsconfig.json`:

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

`$MOD/.gitignore`:

```
.claude-plugin/types/
```

- [ ] **Step 2: API の型ファイルを置く**

自動命名 mod に置いた型ファイル（本体 2.1.295 のもの）をコピーする:

```bash
mkdir -p /home/aya/.dotfiles/.claude-global/mods/session-memo/.claude-plugin/types/claude-code
cp /home/aya/.dotfiles/.claude-global/mods/session-autoname/.claude-plugin/types/claude-code/index.d.ts \
   /home/aya/.dotfiles/.claude-global/mods/session-memo/.claude-plugin/types/claude-code/index.d.ts
head -1 /home/aya/.dotfiles/.claude-global/mods/session-memo/.claude-plugin/types/claude-code/index.d.ts
```

Expected: `// Claude Code function hooks: the plugin API's TypeScript declarations.`

コピー元が無いときは、agent-memory の `claude-code/mod-function-hooks-pitfalls.md` にある手順（本体バイナリの zstd フレームを展開）で取り出す。

- [ ] **Step 3: 失敗するテストを書く**

`$MOD/tests/memo.test.ts`:

```ts
import { describe, expect, test } from 'claude-code/testing'

import {
  EMPTY,
  addItem,
  bandParts,
  cancelEdit,
  inputValue,
  moveToTop,
  removeItem,
  startEdit,
  submitInput,
} from '../hooks/memo'

const three = { items: ['a', 'b', 'c'], editing: null }

describe('addItem', () => {
  test('前後の空白を落として末尾に足す', () => {
    expect(addItem(EMPTY, '  買い物  ')).toEqual({ items: ['買い物'], editing: null })
    expect(addItem(three, 'd').items).toEqual(['a', 'b', 'c', 'd'])
  })
  test('空白だけなら足さない', () => {
    expect(addItem(three, '   ')).toEqual(three)
  })
})

describe('startEdit / cancelEdit / inputValue', () => {
  test('編集を始めると入力欄にそのメモが入る', () => {
    const s = startEdit(three, 1)
    expect(s.editing).toBe(1)
    expect(inputValue(s)).toBe('b')
  })
  test('範囲外の位置では編集を始めない', () => {
    expect(startEdit(three, 3)).toEqual(three)
    expect(startEdit(three, -1)).toEqual(three)
  })
  test('取消で編集を抜け、入力欄は空', () => {
    const s = cancelEdit(startEdit(three, 1))
    expect(s).toEqual(three)
    expect(inputValue(s)).toBe('')
  })
})

describe('submitInput', () => {
  test('編集中でなければ追加する', () => {
    expect(submitInput(three, 'd').items).toEqual(['a', 'b', 'c', 'd'])
  })
  test('編集中ならそのメモを書き換えて編集を抜ける', () => {
    expect(submitInput(startEdit(three, 1), ' B ')).toEqual({ items: ['a', 'B', 'c'], editing: null })
  })
  test('編集中に空白だけで Enter したら書き換えずに編集を抜ける', () => {
    expect(submitInput(startEdit(three, 1), '  ')).toEqual(three)
  })
})

describe('moveToTop', () => {
  test('指定のメモを先頭に移す', () => {
    expect(moveToTop(three, 2).items).toEqual(['c', 'a', 'b'])
  })
  test('先頭や範囲外では何もしない', () => {
    expect(moveToTop(three, 0)).toEqual(three)
    expect(moveToTop(three, 5)).toEqual(three)
  })
  test('編集中のメモ自身を移したら、編集対象も先頭に付いていく', () => {
    const s = moveToTop(startEdit(three, 2), 2)
    expect(s.editing).toBe(0)
    expect(inputValue(s)).toBe('c')
  })
  test('編集中のメモより後ろを移したら、編集対象は1つ後ろにずれて同じメモを指す', () => {
    const s = moveToTop(startEdit(three, 0), 2)
    expect(inputValue(s)).toBe('a')
    expect(s.editing).toBe(1)
  })
  test('編集中のメモより前を移しても、編集対象は同じメモを指す', () => {
    const s = moveToTop(startEdit(three, 2), 1)
    expect(inputValue(s)).toBe('c')
  })
})

describe('removeItem', () => {
  test('指定のメモを消す', () => {
    expect(removeItem(three, 1).items).toEqual(['a', 'c'])
  })
  test('範囲外では何もしない', () => {
    expect(removeItem(three, 3)).toEqual(three)
  })
  test('編集中のメモを消したら編集を抜ける', () => {
    expect(removeItem(startEdit(three, 1), 1)).toEqual({ items: ['a', 'c'], editing: null })
  })
  test('編集中のメモより前を消しても、編集対象は同じメモを指す', () => {
    const s = removeItem(startEdit(three, 2), 0)
    expect(inputValue(s)).toBe('c')
  })
})

describe('bandParts', () => {
  test('0件なら帯を出さない', () => {
    expect(bandParts([])).toBeNull()
  })
  test('1件なら（+N）を付けない', () => {
    expect(bandParts(['買い物'])).toEqual({ text: '📝 買い物', more: '' })
  })
  test('複数件なら先頭と残りの件数', () => {
    expect(bandParts(['a', 'b', 'c'])).toEqual({ text: '📝 a', more: '（+2）' })
  })
})
```

- [ ] **Step 4: テストが失敗することを確認する**

Run: `claude plugin test /home/aya/.dotfiles/.claude-global/mods/session-memo`
Expected: FAIL（`cannot import "../hooks/memo"`）

- [ ] **Step 5: メモ操作を実装する**

`$MOD/hooks/memo.ts`:

```ts
import type { MemoState } from '../types'

export const EMPTY: MemoState = { items: [], editing: null }

function inRange(s: MemoState, index: number): boolean {
  return Number.isInteger(index) && index >= 0 && index < s.items.length
}

export function addItem(s: MemoState, text: string): MemoState {
  const item = text.trim()
  return item === '' ? s : { ...s, items: [...s.items, item] }
}

export function startEdit(s: MemoState, index: number): MemoState {
  return inRange(s, index) ? { ...s, editing: index } : s
}

export function cancelEdit(s: MemoState): MemoState {
  return { ...s, editing: null }
}

export function submitInput(s: MemoState, text: string): MemoState {
  if (s.editing === null) return addItem(s, text)
  const item = text.trim()
  if (item === '' || !inRange(s, s.editing)) return cancelEdit(s)
  return { items: s.items.map((old, i) => (i === s.editing ? item : old)), editing: null }
}

export function moveToTop(s: MemoState, index: number): MemoState {
  if (!inRange(s, index) || index === 0) return s
  const items = [s.items[index]!, ...s.items.filter((_, i) => i !== index)]
  let editing = s.editing
  if (editing === index) editing = 0
  else if (editing !== null && editing < index) editing += 1
  return { items, editing }
}

export function removeItem(s: MemoState, index: number): MemoState {
  if (!inRange(s, index)) return s
  const items = s.items.filter((_, i) => i !== index)
  let editing = s.editing
  if (editing === index) editing = null
  else if (editing !== null && editing > index) editing -= 1
  return { items, editing }
}

export function inputValue(s: MemoState): string {
  return s.editing === null ? '' : (s.items[s.editing] ?? '')
}

export function bandParts(items: readonly string[]): { text: string; more: string } | null {
  const first = items[0]
  if (first === undefined) return null
  return { text: `📝 ${first}`, more: items.length > 1 ? `（+${items.length - 1}）` : '' }
}
```

- [ ] **Step 6: テストが通ることを確認する**

Run: `claude plugin test /home/aya/.dotfiles/.claude-global/mods/session-memo`
Expected: すべて PASS、終了コード 0

- [ ] **Step 7: 型と manifest を検査する**

```bash
nix shell nixpkgs#typescript -c tsc -p /home/aya/.dotfiles/.claude-global/mods/session-memo
claude plugin validate /home/aya/.dotfiles/.claude-global/mods/session-memo
```

Expected: `tsc` は出力なしで終了コード 0。`validate` は `✔ Validation passed`（author 欄が無い警告のみ）

- [ ] **Step 8: コミット**

```bash
rm -f /home/aya/.dotfiles/.git/index.lock
git -C /home/aya/.dotfiles add .claude-global/mods/session-memo
git -C /home/aya/.dotfiles status --short .claude-global/mods/session-memo
git -C /home/aya/.dotfiles commit -m "feat(claude): セッション作業メモmodの雛形とメモ操作を追加"
```

`status` に `.claude-plugin/types/` が出ていないことを確認してからコミットする。

---

### Task 2: 帯とパネルの描画・操作

**Files:**
- Modify: `$MOD/hooks/register.tsx`（全体を置き換える）
- Test: `$MOD/tests/ui.test.tsx`

**Interfaces:**
- Consumes: Task 1 の `EMPTY`, `bandParts`, `cancelEdit`, `inputValue`, `moveToTop`, `removeItem`, `startEdit`, `submitInput` と `MemoState`
- Produces（Task 3 が使う。`register.tsx` 内）: `export const PANE = 'memo'`、モジュール内の `const memo = atom({ plugin: 'session-memo', key: 'memo' } as const, EMPTY)`

テストの仕組み:
- `$.ui.mount({ plugin, surface, component, props, requestId })` で描画し、返った `ui` の `find` / `press` / `input` で操作する。操作は state の書き込みと再描画が終わってから resolve する
- `find({ key })` の `text` は表示中の文字（`Input` なら値）
- 帯の hook が `next(e)` に回したときの下の描画は、テストの `on('ui.render', { component: 'AbovePrompt' })` が受ける（`engine` という Text を返して見分ける）
- 同じ test の中では state が続く。surface ごとに別の test にして、状態を持ち越さない

- [ ] **Step 1: 失敗するテストを書く**

`$MOD/tests/ui.test.tsx`:

```tsx
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { expect, test } from 'claude-code/testing'

const SURFACES = ['terminal', 'desktop'] as const
type Surface = (typeof SURFACES)[number]

const SCROLL = { offset: 0, bodyRows: 10 }
const PANE_PROPS = { title: 'Memo', isFocused: true, bodyColumns: 60, placement: 'inline' as const, scroll: SCROLL, view: {} }

function bandProps(hasSurvey = false) {
  return { hasSurvey, isWorking: false, maxRows: 10, bodyColumns: 60, scroll: SCROLL, view: {} }
}

function engineBand(on: On) {
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
}

function openPane($: Engine, surface: Surface) {
  return $.ui.mount({ plugin: 'session-memo', surface, component: 'Pane', props: PANE_PROPS, requestId: 'memo' })
}

function openBand($: Engine, surface: Surface, hasSurvey = false) {
  return $.ui.mount({ plugin: 'session-memo', surface, component: 'AbovePrompt', props: bandProps(hasSurvey) })
}

for (const surface of SURFACES) {
  test(`パネルの入力欄で追加すると並び、入力欄は空に戻る (${surface})`, async ($, on) => {
    engineBand(on)
    const pane = await openPane($, surface)
    expect(await pane.find({ text: 'メモはまだありません' })).toBeDefined()
    await pane.input({ key: 'input', text: '認証まわりは触らんとく' })
    await pane.input({ key: 'input', text: 'あとでテスト追加' })
    expect((await pane.find({ key: 'row:0' }))?.text).toContain('1. 認証まわりは触らんとく')
    expect((await pane.find({ key: 'row:1' }))?.text).toContain('2. あとでテスト追加')
    expect((await pane.find({ key: 'input' }))?.text).toBe('')
  })

  test(`[e] で書き換え、[取消] なら元のまま (${surface})`, async ($, on) => {
    engineBand(on)
    const pane = await openPane($, surface)
    await pane.input({ key: 'input', text: 'a' })
    await pane.input({ key: 'input', text: 'b' })
    await pane.press({ key: 'edit:1' })
    expect((await pane.find({ key: 'input' }))?.text).toBe('b')
    expect(await pane.find({ key: 'cancel' })).toBeDefined()
    await pane.input({ key: 'input', text: 'B' })
    expect((await pane.find({ key: 'row:1' }))?.text).toContain('2. B')
    expect(await pane.find({ key: 'cancel' })).toBeUndefined()
    await pane.press({ key: 'edit:0' })
    await pane.press({ key: 'cancel' })
    expect((await pane.find({ key: 'row:0' }))?.text).toContain('1. a')
    expect((await pane.find({ key: 'input' }))?.text).toBe('')
  })

  test(`[↑] で先頭へ、[x] で削除、先頭の行に [↑] は無い (${surface})`, async ($, on) => {
    engineBand(on)
    const pane = await openPane($, surface)
    for (const text of ['a', 'b', 'c']) await pane.input({ key: 'input', text })
    expect(await pane.find({ key: 'up:0' })).toBeUndefined()
    await pane.press({ key: 'up:2' })
    expect((await pane.find({ key: 'row:0' }))?.text).toContain('1. c')
    await pane.press({ key: 'del:1' })
    expect((await pane.findAll({ type: 'Text', text: /^\d+\. / })).map(t => t.text)).toEqual(['1. c', '2. b'])
  })

  test(`帯は0件なら出さず、先頭と（+N）を出す (${surface})`, async ($, on) => {
    engineBand(on)
    const empty = await openBand($, surface)
    expect(await empty.find({ text: 'engine' })).toBeDefined()
    const pane = await openPane($, surface)
    await pane.input({ key: 'input', text: '買い物' })
    const one = await openBand($, surface)
    expect(await one.find({ text: '📝 買い物' })).toBeDefined()
    expect(await one.find({ text: /（\+/ })).toBeUndefined()
    await pane.input({ key: 'input', text: '洗濯' })
    await pane.input({ key: 'input', text: '掃除' })
    const many = await openBand($, surface)
    expect(await many.find({ text: '📝 買い物' })).toBeDefined()
    expect(await many.find({ text: '（+2）' })).toBeDefined()
  })

  test(`長いメモでも（+N）は別要素で残る (${surface})`, async ($, on) => {
    engineBand(on)
    const pane = await openPane($, surface)
    await pane.input({ key: 'input', text: 'あ'.repeat(200) })
    await pane.input({ key: 'input', text: '二件目' })
    const band = await openBand($, surface)
    const head = await band.find({ type: 'Text', text: /^📝 / })
    expect(head?.props.wrap).toBe('truncate')
    expect(await band.find({ type: 'Text', text: '（+1）' })).toBeDefined()
  })

  test(`アンケート中は帯を譲る (${surface})`, async ($, on) => {
    engineBand(on)
    const pane = await openPane($, surface)
    await pane.input({ key: 'input', text: '買い物' })
    const band = await openBand($, surface, true)
    expect(await band.find({ text: 'engine' })).toBeDefined()
    expect(await band.find({ text: /📝/ })).toBeUndefined()
  })
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `claude plugin test /home/aya/.dotfiles/.claude-global/mods/session-memo`
Expected: `memo.test.ts` は PASS、`ui.test.tsx` は FAIL（register が何も描かないため。パネルの mount は下に何も無くて失敗し、帯は `engine` だけになる）

- [ ] **Step 3: 帯とパネルを実装する**

`$MOD/hooks/register.tsx`（全体を置き換え）:

```tsx
import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import { EMPTY, bandParts, cancelEdit, inputValue, moveToTop, removeItem, startEdit, submitInput } from './memo'

export const PANE = 'memo'
const memo = atom({ plugin: 'session-memo', key: 'memo' } as const, EMPTY)

export const register: Register = on => {
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const parts = bandParts((await read($, memo)).items)
    if (e.props.hasSurvey || parts === null) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="row">
        <Box flexShrink={1}>
          <Text wrap="truncate">{parts.text}</Text>
        </Box>
        {parts.more !== '' && <Text dimColor>{parts.more}</Text>}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    if (e.surface === 'mobile') return next(e)
    const state = await read($, memo)
    const { Box, Button, Input, Text } = $.ui.resolve(e)
    const editing = state.editing
    const focusInput = () => $.ui.focus({ requestId: PANE, key: 'input' }).catch(() => undefined)
    return (
      <Box flexDirection="column">
        {state.items.length === 0 && <Text dimColor>メモはまだありません</Text>}
        {state.items.map((item, i) => (
          <Box key={`row:${i}`} flexDirection="row">
            <Box flexGrow={1} flexShrink={1}>
              <Text wrap="truncate" bold={editing === i}>{`${i + 1}. ${item}`}</Text>
            </Box>
            {i > 0 && <Button key={`up:${i}`} label="↑" onPress={() => update($, memo, s => moveToTop(s, i))} />}
            <Button
              key={`edit:${i}`}
              label="e"
              onPress={async () => {
                await update($, memo, s => startEdit(s, i))
                await focusInput()
              }}
            />
            <Button key={`del:${i}`} label="x" onPress={() => update($, memo, s => removeItem(s, i))} />
          </Box>
        ))}
        <Box flexDirection="row">
          <Input
            key="input"
            label={editing === null ? 'memo>' : `${editing + 1}>`}
            value={inputValue(state)}
            submitLabel={editing === null ? '追加' : '書き換え'}
            autoFocus
            onSubmit={text => update($, memo, s => submitInput(s, text))}
          />
          {editing !== null && <Button key="cancel" label="取消" onPress={() => update($, memo, cancelEdit)} />}
        </Box>
      </Box>
    )
  })
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `claude plugin test /home/aya/.dotfiles/.claude-global/mods/session-memo`
Expected: `memo.test.ts` と `ui.test.tsx` がすべて PASS

失敗した場合は、失敗メッセージに添えられた engine の報告（hook の skip 理由、`ui.render (<Component>) refused: <理由>` のような木の検証エラー）を読んで直す。要素のプロップがその surface で許されないと木ごと拒否されるので、その場合は該当プロップを外す。

- [ ] **Step 5: 型と manifest を検査する**

```bash
nix shell nixpkgs#typescript -c tsc -p /home/aya/.dotfiles/.claude-global/mods/session-memo
claude plugin validate /home/aya/.dotfiles/.claude-global/mods/session-memo
```

Expected: `tsc` は出力なしで終了コード 0。`validate` は `✔ Validation passed`、hooks に `ui.render{component=AbovePrompt}` と `ui.render{component=Pane,requestId=memo}` が出る

- [ ] **Step 6: コミット**

```bash
rm -f /home/aya/.dotfiles/.git/index.lock
git -C /home/aya/.dotfiles add .claude-global/mods/session-memo/hooks/register.tsx .claude-global/mods/session-memo/tests/ui.test.tsx
git -C /home/aya/.dotfiles commit -m "feat(claude): セッション作業メモの帯とパネルを追加"
```

---

### Task 3: `/memo` コマンドと会話リセット

**Files:**
- Modify: `$MOD/hooks/register.tsx`（`register` の中に hook を3つ足す、import を足す）
- Test: `$MOD/tests/command.test.tsx`

**Interfaces:**
- Consumes: Task 1 の `EMPTY`, `addItem`, `cancelEdit`、Task 2 の `PANE` と `memo` atom
- Produces: なし（最終タスクの機能）

- [ ] **Step 1: 失敗するテストを書く**

`$MOD/tests/command.test.tsx`:

```tsx
import type { On, UiPane } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { expect, test } from 'claude-code/testing'

function world(on: On) {
  const registered: { name: string; immediate?: true }[] = []
  const opened: { id: string; focus?: true; closeOnEscape?: true }[] = []
  const closed: string[] = []
  let panes: UiPane[] = []

  on('command.register', ($, e) => {
    registered.push({ name: e.name, immediate: e.immediate })
    return { value: { command: e.name } }
  })
  on('ui.open', ($, e) => {
    opened.push({ id: e.id, focus: e.focus, closeOnEscape: e.closeOnEscape })
    panes = [{ id: e.id, title: e.title ?? '', isShown: true, isFocused: true, isPlaced: true }]
    return { value: { isPlaced: true as const } }
  })
  on('ui.close', ($, e) => {
    closed.push(e.id)
    panes = panes.filter(p => p.id !== e.id)
    return { value: undefined }
  })
  on('ui.panes', () => ({ value: panes }))
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('session.end', ($, e) => ({ sessionId: e.sessionId }))
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })

  return { registered, opened, closed }
}

function memo($: Engine, args: string) {
  return $.command.run({
    command: 'memo',
    args,
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 80 },
  })
}

const BAND = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 10,
  bodyColumns: 60,
  scroll: { offset: 0, bodyRows: 10 },
  view: {},
}

async function bandText($: Engine): Promise<string | undefined> {
  const band = await $.ui.mount({ plugin: 'session-memo', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  return (await band.find({ type: 'Text', text: /^📝 / }))?.text
}

test('起動時に /memo を immediate で登録する', async ($, on) => {
  const w = world(on)
  await $.session.start({ cwd: '/tmp/work', surface: 'terminal', isInteractive: true })
  expect(w.registered).toEqual([{ name: 'memo', immediate: true }])
})

test('/memo ○○ で追加し、件数を返す', async ($, on) => {
  world(on)
  expect((await memo($, '  買い物  ')).text).toBe('メモを追加（1件）')
  expect((await memo($, '洗濯')).text).toBe('メモを追加（2件）')
  expect(await bandText($)).toBe('📝 買い物')
})

test('引数なしの /memo でパネルを開閉する', async ($, on) => {
  const w = world(on)
  expect((await memo($, '')).text).toBe('メモを開いた')
  expect(w.opened).toEqual([{ id: 'memo', focus: true, closeOnEscape: true }])
  expect((await memo($, '   ')).text).toBe('メモを閉じた')
  expect(w.closed).toEqual(['memo'])
})

test('開き直したら編集モードではない', async ($, on) => {
  world(on)
  await memo($, 'a')
  const pane = await $.ui.mount({
    plugin: 'session-memo',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'memo',
    props: { title: 'Memo', isFocused: true, bodyColumns: 60, placement: 'inline', scroll: { offset: 0, bodyRows: 10 }, view: {} },
  })
  await pane.press({ key: 'edit:0' })
  expect(await pane.find({ key: 'cancel' })).toBeDefined()
  await memo($, '')
  expect(await pane.find({ key: 'cancel' })).toBeUndefined()
})

test('/clear と /resume でメモが消える', async ($, on) => {
  world(on)
  await memo($, 'a')
  await $.session.end({ reason: 'clear', sessionId: 's-1', resume: { id: 's-1' } })
  expect(await bandText($)).toBeUndefined()
  await memo($, 'b')
  await $.session.end({ reason: 'resume', sessionId: 's-1', resume: { id: 's-2' } })
  expect(await bandText($)).toBeUndefined()
})

test('それ以外の終了理由ではメモを残す', async ($, on) => {
  world(on)
  await memo($, 'a')
  await $.session.end({ reason: 'other', sessionId: 's-1', resume: { id: 's-1' } })
  expect(await bandText($)).toBe('📝 a')
})
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `claude plugin test /home/aya/.dotfiles/.claude-global/mods/session-memo`
Expected: `memo.test.ts` と `ui.test.tsx` は PASS、`command.test.tsx` は FAIL（`/memo` を答える hook が無く、`command.register` も呼ばれない）

- [ ] **Step 3: コマンドと会話リセットを実装する**

`$MOD/hooks/register.tsx` の import 行を次に置き換える:

```tsx
import { EMPTY, addItem, bandParts, cancelEdit, inputValue, moveToTop, removeItem, startEdit, submitInput } from './memo'
```

`register` の本体の先頭（`on('ui.render', { component: 'AbovePrompt' }` の前）に次を足す:

```tsx
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'memo',
      description: '作業メモを追加（引数なしでメモのパネルを開閉）',
      argumentHint: '[メモ]',
      immediate: true,
    })
    return next(e)
  })

  on('command.run', { command: 'memo' }, async ($, e) => {
    const text = e.args.trim()
    if (text !== '') {
      let count = 0
      await update($, memo, s => {
        const added = addItem(s, text)
        count = added.items.length
        return added
      })
      return { text: `メモを追加（${count}件）` }
    }
    if ((await $.ui.panes()).some(p => p.id === PANE)) {
      await $.ui.close({ id: PANE })
      return { text: 'メモを閉じた' }
    }
    await update($, memo, cancelEdit)
    const { items } = await read($, memo)
    await $.ui.open({ id: PANE, title: 'Memo', focus: true, closeOnEscape: true, rows: Math.min(items.length + 3, 20) })
    return { text: 'メモを開いた' }
  })

  on('session.end', async ($, e, next) => {
    if (e.reason === 'clear' || e.reason === 'resume') await update($, memo, () => EMPTY)
    return next(e)
  })
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `claude plugin test /home/aya/.dotfiles/.claude-global/mods/session-memo`
Expected: 3ファイルともすべて PASS

- [ ] **Step 5: 型と manifest を検査する**

```bash
nix shell nixpkgs#typescript -c tsc -p /home/aya/.dotfiles/.claude-global/mods/session-memo
claude plugin validate /home/aya/.dotfiles/.claude-global/mods/session-memo
```

Expected: `tsc` は出力なしで終了コード 0。`validate` は `✔ Validation passed`。`command.run{command=memo}` は「answers its own command」と表示される

- [ ] **Step 6: コミット**

```bash
rm -f /home/aya/.dotfiles/.git/index.lock
git -C /home/aya/.dotfiles add .claude-global/mods/session-memo/hooks/register.tsx .claude-global/mods/session-memo/tests/command.test.tsx
git -C /home/aya/.dotfiles commit -m "feat(claude): /memoコマンドと会話リセットでのメモ消去を追加"
```

---

### Task 4: 配布設定と実機確認

**Files:**
- Modify: `/home/aya/.dotfiles/.claude-global/settings.json`（`env.CLAUDE_CODE_PLUGIN_DIRS` の値に `:` 区切りで追加）

**Interfaces:**
- Consumes: Task 3 までの mod フォルダ
- Produces: 新しく起動する対話セッションで2つの mod が読み込まれる状態

- [ ] **Step 1: settings.json の値を書き換える**

`/home/aya/.dotfiles/.claude-global/settings.json` の該当行を次にする（作業ツリーにあるユーザーの他の変更には触れない）:

```json
    "CLAUDE_CODE_PLUGIN_DIRS": "/home/aya/.dotfiles/.claude-global/mods/session-autoname:/home/aya/.dotfiles/.claude-global/mods/session-memo"
```

Run: `python3 -I -c "import json; print(json.load(open('/home/aya/.dotfiles/.claude-global/settings.json'))['env']['CLAUDE_CODE_PLUGIN_DIRS'])"`
Expected: `/home/aya/.dotfiles/.claude-global/mods/session-autoname:/home/aya/.dotfiles/.claude-global/mods/session-memo`

- [ ] **Step 2: 自分の変更だけを index に載せてコミット・push する**

```bash
S=$(mktemp -d)/settings.staged.json
git -C /home/aya/.dotfiles show HEAD:.claude-global/settings.json > "$S"
python3 -I - "$S" <<'EOF'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = '"CLAUDE_CODE_PLUGIN_DIRS": "/home/aya/.dotfiles/.claude-global/mods/session-autoname"'
new = '"CLAUDE_CODE_PLUGIN_DIRS": "/home/aya/.dotfiles/.claude-global/mods/session-autoname:/home/aya/.dotfiles/.claude-global/mods/session-memo"'
assert s.count(old) == 1, 'HEAD の値が想定と違う'
open(p, 'w', encoding='utf-8').write(s.replace(old, new))
EOF
rm -f /home/aya/.dotfiles/.git/index.lock
BLOB=$(git -C /home/aya/.dotfiles hash-object -w "$S")
rm -f /home/aya/.dotfiles/.git/index.lock
git -C /home/aya/.dotfiles update-index --cacheinfo 100644,"$BLOB",.claude-global/settings.json
rm -f /home/aya/.dotfiles/.git/index.lock
git -C /home/aya/.dotfiles diff --cached -- .claude-global/settings.json
```

Expected: `diff --cached` が `CLAUDE_CODE_PLUGIN_DIRS` の1行の置き換えだけを示す。

```bash
rm -f /home/aya/.dotfiles/.git/index.lock
git -C /home/aya/.dotfiles commit -m "feat(claude): セッション作業メモmodを全対話セッションで読み込む"
rm -f /home/aya/.dotfiles/.git/index.lock
git -C /home/aya/.dotfiles push
```

- [ ] **Step 3: 実機確認（ユーザーと一緒に行う）**

ユーザーに新しい Claude Code を縦分割で起動してもらい、次を確認する。

1. `/memo 認証まわりは触らんとく` → プロンプトの上に `📝 認証まわりは触らんとく` が出る
2. Claude の作業中に `/memo あとでテスト追加` → すぐ入り、帯が `（+1）` になる
3. 引数なしの `/memo` → パネルが開き、キーボードがパネルに移る。Tab / 矢印で `[↑]` `[e]` `[x]` と入力欄を移れる
4. 入力欄で続けて追加・`[e]` で書き換え・`[取消]`・`[↑]`・`[x]` が動く。Esc でパネルが閉じる
5. 狭い幅（縦分割）でパネルがどこに・どの大きさで開くか、帯の長いメモが1行に収まるか
6. `/clear` でメモが消える
7. 自動命名 mod と同時に動いて、互いに邪魔しない

確認結果を報告し、問題があれば spec に戻って直す。
