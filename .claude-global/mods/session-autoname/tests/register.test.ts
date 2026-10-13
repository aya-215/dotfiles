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
    return {
      value:
        text === FAIL
          ? { isAnswered: false as const, reason: 'empty-reply' as const, usage: USAGE }
          : { isAnswered: true as const, text, usage: USAGE },
    }
  })
  on('ui.status', ($, e) => {
    statuses.push(e.text)
    return { value: undefined }
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
  expect(w.commands.items[0]).toEqual({ command: 'color', args: 'green' })
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
  await $.command.run({
    command: 'rename',
    args: '手動の名前',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 80 },
  })
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
