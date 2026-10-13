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
