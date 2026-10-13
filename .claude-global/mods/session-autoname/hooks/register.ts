import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import {
  COLOR_INDEX_KEY,
  INITIAL,
  activate,
  addPrompt,
  buildPrompt,
  buildRetryPrompt,
  buildSystem,
  clearConversation,
  countTurn,
  needsColor,
  judgeReply,
  noteRename,
  pickColor,
  resumeConversation,
} from './naming'
import type { Verdict } from './naming'

const naming = atom({ plugin: 'session-autoname', key: 'naming' } as const, INITIAL)
const STATUS_MS = 10000

function showStatus($: EngineInterface, text: string): void {
  $.ui.status(text)
  $.clock.after(STATUS_MS, () => $.ui.status(undefined))
}

async function runCommand($: EngineInterface, command: string, args: string): Promise<void> {
  try {
    await $.command.run({ command, args })
  } catch {
    showStatus($, `session-autoname: /${command} に失敗`)
  }
}

type Asked = Verdict | { kind: 'failed'; reason: string }

async function askName($: EngineInterface, prompt: string, current: string): Promise<Asked> {
  const reply = await $.model.complete({
    model: 'haiku',
    system: buildSystem(),
    prompt,
    maxTokens: 64,
    effort: 'low',
    timeoutMs: 30000,
  })
  return reply.isAnswered ? judgeReply(reply.text, current) : { kind: 'failed', reason: reply.reason }
}

async function nameSession($: EngineInterface, answer: string): Promise<void> {
  const before = await read($, naming)
  if (before.isManual) return
  const prompt = buildPrompt(before.prompts, answer, before.current)
  let asked = await askName($, prompt, before.current)
  if (asked.kind === 'invalid') asked = await askName($, buildRetryPrompt(prompt, asked.reason), before.current)
  if (asked.kind === 'failed' || asked.kind === 'invalid') {
    showStatus($, `session-autoname: 命名をスキップ (${asked.reason})`)
    return
  }
  if (asked.kind === 'keep') return
  // Haiku を待つ間に手で /rename された名前は上書きしない
  if ((await read($, naming)).isManual) return
  await update($, naming, s => ({ ...s, current: asked.name }))
  await runCommand($, 'rename', asked.name)
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
    // 戻った先の会話に名前があるかはまだ分からないので、上書きしない側に倒す
    if (e.reason === 'resume') await update($, naming, s => resumeConversation(s, true))
    return next(e)
  })

  on('classic.SessionStart', async ($, e, next) => {
    if (e.source === 'resume') {
      const hasTitle = (e.session_title ?? '').trim() !== ''
      await update($, naming, s => resumeConversation(s, hasTitle))
    }
    return next(e)
  })
}
