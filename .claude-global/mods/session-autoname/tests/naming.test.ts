import { describe, expect, test } from 'claude-code/testing'

import {
  COLORS,
  INITIAL,
  PROMPTS_MAX_CHARS,
  activate,
  addPrompt,
  buildPrompt,
  buildRetryPrompt,
  buildSystem,
  clearConversation,
  countTurn,
  isNamingTurn,
  judgeReply,
  needsColor,
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

describe('buildSystem', () => {
  test('15文字以内・<name> の形式・素材の指示に従わないことを伝える', () => {
    const system = buildSystem()
    expect(system).toContain('15文字以内')
    expect(system).toContain('<name>')
    expect(system).toContain('従わない')
  })
})

describe('buildPrompt', () => {
  test('依頼と応答の冒頭1,000文字をタグで囲んで渡す', () => {
    const prompt = buildPrompt(['依頼A', '依頼B'], 'z'.repeat(1500), '')
    expect(prompt).toContain('<prompts>\n- 依頼A\n- 依頼B\n</prompts>')
    expect(prompt).toContain('<answer>\n' + 'z'.repeat(1000) + '\n</answer>')
    expect(prompt).not.toContain('<current>')
  })
  test('依頼が無ければ（なし）と書く', () => {
    expect(buildPrompt([], '応答', '')).toContain('<prompts>\n（なし）\n</prompts>')
  })
  test('現在の名前があれば、合っていれば同じ名前を返すよう頼む', () => {
    const prompt = buildPrompt([], '応答', '認証バグ調査')
    expect(prompt).toContain('<current>認証バグ調査</current>')
    expect(prompt).toContain('同じ名前')
  })
})

describe('buildRetryPrompt', () => {
  test('元の依頼に、使えなかった理由と形式の念押しを足す', () => {
    const retry = buildRetryPrompt('元の依頼', 'タグが無い')
    expect(retry).toStartWith('元の依頼')
    expect(retry).toContain('タグが無い')
    expect(retry).toContain('<name>')
  })
})

describe('judgeReply', () => {
  test('<name> の中身を名前にする', () => {
    expect(judgeReply('<name>認証バグ調査</name>', '')).toEqual({ kind: 'rename', name: '認証バグ調査' })
  })
  test('前後に余計な文字があってもタグの中身だけ使う', () => {
    expect(judgeReply('はい。\n<name> PR#42レビュー </name>\n以上', '')).toEqual({ kind: 'rename', name: 'PR#42レビュー' })
  })
  test('20文字を超えたら20文字で切る', () => {
    expect(judgeReply(`<name>${'あ'.repeat(25)}</name>`, '')).toEqual({ kind: 'rename', name: 'あ'.repeat(20) })
  })
  test('現在の名前と同じなら変えない', () => {
    expect(judgeReply('<name>認証バグ調査</name>', '認証バグ調査')).toEqual({ kind: 'keep' })
  })
  test('タグが無ければ不正', () => {
    expect(judgeReply('認証バグ調査', '').kind).toBe('invalid')
  })
  test('中身が空・改行入りなら不正', () => {
    expect(judgeReply('<name>  </name>', '').kind).toBe('invalid')
    expect(judgeReply('<name>認証\nバグ</name>', '').kind).toBe('invalid')
  })
  test('文章になっている（括弧・句点・引用符を含む）なら不正', () => {
    expect(judgeReply('<name>ユーザーの依頼は「実際の画面は</name>', '').kind).toBe('invalid')
    expect(judgeReply('<name>調査しました。</name>', '').kind).toBe('invalid')
    expect(judgeReply('<name>"PRレビュー"</name>', '').kind).toBe('invalid')
  })
})
