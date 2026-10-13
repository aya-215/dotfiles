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
