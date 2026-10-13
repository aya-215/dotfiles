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
