import type { MemoState } from '../types'

export const EMPTY: MemoState = { items: [], editing: null, focused: null }

function inRange(s: MemoState, index: number): boolean {
  return Number.isInteger(index) && index >= 0 && index < s.items.length
}

// ボタンは描いた時点の位置を持つので、押すまでに行がずれていたら別のメモに効かせない
function isAt(s: MemoState, index: number, item: string): boolean {
  return inRange(s, index) && s.items[index] === item
}

// 帯を1行に保つため、改行や連続した空白は1つの空白にまとめる
function normalize(text: string): string {
  return text.replace(/\s+/g, ' ').trim()
}

export function addItem(s: MemoState, text: string): MemoState {
  const item = normalize(text)
  return item === '' ? s : { ...s, items: [...s.items, item] }
}

export function startEdit(s: MemoState, index: number, item: string): MemoState {
  return isAt(s, index, item) ? { ...s, editing: index } : s
}

export function cancelEdit(s: MemoState): MemoState {
  return { ...s, editing: null }
}

export function submitInput(s: MemoState, text: string): MemoState {
  if (s.editing === null) return addItem(s, text)
  const item = normalize(text)
  if (item === '' || !inRange(s, s.editing)) return cancelEdit(s)
  return { ...s, items: s.items.map((old, i) => (i === s.editing ? item : old)), editing: null }
}

export function moveToTop(s: MemoState, index: number, item: string): MemoState {
  if (!isAt(s, index, item) || index === 0) return s
  const items = [s.items[index]!, ...s.items.filter((_, i) => i !== index)]
  let editing = s.editing
  if (editing === index) editing = 0
  else if (editing !== null && editing < index) editing += 1
  return { ...s, items, editing }
}

export function removeItem(s: MemoState, index: number, item: string): MemoState {
  if (!isAt(s, index, item)) return s
  const items = s.items.filter((_, i) => i !== index)
  let editing = s.editing
  if (editing === index) editing = null
  else if (editing !== null && editing > index) editing -= 1
  return { ...s, items, editing }
}

export function focusRow(s: MemoState, element: string | undefined): MemoState {
  if (element === 'input') return { ...s, focused: null }
  const index = Number(/^row:(\d+)$/.exec(element ?? '')?.[1])
  return inRange(s, index) ? { ...s, focused: index } : s
}

export function editFocused(s: MemoState): MemoState {
  return s.focused === null ? s : startEdit(s, s.focused, s.items[s.focused] ?? '')
}

export function topFocused(s: MemoState): MemoState {
  if (s.focused === null) return s
  const moved = moveToTop(s, s.focused, s.items[s.focused] ?? '')
  return moved === s ? s : { ...moved, focused: 0 }
}

export function removeFocused(s: MemoState): MemoState {
  if (s.focused === null) return s
  const removed = removeItem(s, s.focused, s.items[s.focused] ?? '')
  if (removed === s) return s
  const last = removed.items.length - 1
  return { ...removed, focused: last < 0 ? null : Math.min(s.focused, last) }
}

export function inputValue(s: MemoState): string {
  return s.editing === null ? '' : (s.items[s.editing] ?? '')
}

export function bandParts(items: readonly string[]): { text: string; more: string } | null {
  const first = items[0]
  if (first === undefined) return null
  return { text: `📝 ${first}`, more: items.length > 1 ? `（+${items.length - 1}）` : '' }
}
