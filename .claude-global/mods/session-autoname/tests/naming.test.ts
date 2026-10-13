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
  resumeConversation,
} from '../hooks/naming'

const active = activate(INITIAL, 'red')

describe('pickColor', () => {
  test('保存された番号の色を選び、次の番号を返す', () => {
    expect(pickColor(2)).toEqual({ color: 'green', nextIndex: 3 })
  })
  test('最後の色の次は先頭に戻る', () => {
    expect(pickColor(7)).toEqual({ color: 'cyan', nextIndex: 0 })
    expect(pickColor(10)).toEqual({ color: 'green', nextIndex: 3 })
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
  test('出どころが分からない /rename でも止める', () => {
    expect(noteRename(active, undefined, 'session-autoname').isManual).toBe(true)
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

describe('resumeConversation', () => {
  const used = { ...active, answered: 7, prompts: ['p'], current: '前の名前', isManual: false }
  test('名前が付いた会話に戻ったら、数え直したうえで自動命名しない', () => {
    expect(resumeConversation(used, true)).toEqual({ ...active, answered: 0, prompts: [], current: '', isManual: true })
  })
  test('名前の無い会話に戻ったら、数え直して自動命名する', () => {
    expect(resumeConversation({ ...used, isManual: true }, false)).toEqual({
      ...active,
      answered: 0,
      prompts: [],
      current: '',
      isManual: false,
    })
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
