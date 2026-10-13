import { describe, expect, test } from 'claude-code/testing'

import {
  EMPTY,
  addItem,
  bandParts,
  cancelEdit,
  editFocused,
  focusRow,
  inputValue,
  moveToTop,
  removeFocused,
  removeItem,
  startEdit,
  topFocused,
  submitInput,
} from '../hooks/memo'

const three = { items: ['a', 'b', 'c'], editing: null, focused: null }

describe('addItem', () => {
  test('前後の空白を落として末尾に足す', () => {
    expect(addItem(EMPTY, '  買い物  ')).toEqual({ items: ['買い物'], editing: null, focused: null })
    expect(addItem(three, 'd').items).toEqual(['a', 'b', 'c', 'd'])
  })
  test('空白だけなら足さない', () => {
    expect(addItem(three, '   ')).toEqual(three)
  })
})

describe('startEdit / cancelEdit / inputValue', () => {
  test('編集を始めると入力欄にそのメモが入る', () => {
    const s = startEdit(three, 1, 'b')
    expect(s.editing).toBe(1)
    expect(inputValue(s)).toBe('b')
  })
  test('範囲外の位置では編集を始めない', () => {
    expect(startEdit(three, 3, 'x')).toEqual(three)
    expect(startEdit(three, -1, 'x')).toEqual(three)
  })
  test('取消で編集を抜け、入力欄は空', () => {
    const s = cancelEdit(startEdit(three, 1, 'b'))
    expect(s).toEqual(three)
    expect(inputValue(s)).toBe('')
  })
})

describe('submitInput', () => {
  test('編集中でなければ追加する', () => {
    expect(submitInput(three, 'd').items).toEqual(['a', 'b', 'c', 'd'])
  })
  test('編集中ならそのメモを書き換えて編集を抜ける', () => {
    expect(submitInput(startEdit(three, 1, 'b'), ' B ')).toEqual({ items: ['a', 'B', 'c'], editing: null, focused: null })
  })
  test('編集中に空白だけで Enter したら書き換えずに編集を抜ける', () => {
    expect(submitInput(startEdit(three, 1, 'b'), '  ')).toEqual(three)
  })
})

describe('moveToTop', () => {
  test('指定のメモを先頭に移す', () => {
    expect(moveToTop(three, 2, 'c').items).toEqual(['c', 'a', 'b'])
  })
  test('先頭や範囲外では何もしない', () => {
    expect(moveToTop(three, 0, 'a')).toEqual(three)
    expect(moveToTop(three, 5, 'x')).toEqual(three)
  })
  test('編集中のメモ自身を移したら、編集対象も先頭に付いていく', () => {
    const s = moveToTop(startEdit(three, 2, 'c'), 2, 'c')
    expect(s.editing).toBe(0)
    expect(inputValue(s)).toBe('c')
  })
  test('編集中のメモより後ろを移したら、編集対象は1つ後ろにずれて同じメモを指す', () => {
    const s = moveToTop(startEdit(three, 0, 'a'), 2, 'c')
    expect(inputValue(s)).toBe('a')
    expect(s.editing).toBe(1)
  })
  test('編集中のメモより前を移しても、編集対象は同じメモを指す', () => {
    const s = moveToTop(startEdit(three, 2, 'c'), 1, 'b')
    expect(inputValue(s)).toBe('c')
  })
})

describe('removeItem', () => {
  test('指定のメモを消す', () => {
    expect(removeItem(three, 1, 'b').items).toEqual(['a', 'c'])
  })
  test('範囲外では何もしない', () => {
    expect(removeItem(three, 3, 'x')).toEqual(three)
  })
  test('編集中のメモを消したら編集を抜ける', () => {
    expect(removeItem(startEdit(three, 1, 'b'), 1, 'b')).toEqual({ items: ['a', 'c'], editing: null, focused: null })
  })
  test('編集中のメモより前を消しても、編集対象は同じメモを指す', () => {
    const s = removeItem(startEdit(three, 2, 'c'), 0, 'a')
    expect(inputValue(s)).toBe('c')
  })
})

describe('古い描画のボタン（行がずれた後の押下）', () => {
  test('その位置のメモが押したときと違えば何もしない', () => {
    const once = removeItem(three, 0, 'a')
    expect(removeItem(once, 0, 'a')).toEqual(once)
    expect(moveToTop(three, 1, 'c')).toEqual(three)
    expect(startEdit(three, 1, 'c')).toEqual(three)
  })
})

describe('改行や連続した空白', () => {
  test('追加でも書き換えでも1つの空白にまとめる', () => {
    expect(addItem(EMPTY, 'a\n  b\tc').items).toEqual(['a b c'])
    expect(submitInput(startEdit(three, 0, 'a'), 'x\r\ny').items[0]).toBe('x y')
  })
})

describe('focusRow', () => {
  test('行に輪が来たらその行を選ぶ', () => {
    expect(focusRow(three, 'row:2').focused).toBe(2)
  })
  test('入力欄に輪が来たら選択を外す', () => {
    expect(focusRow({ ...three, focused: 1 }, 'input').focused).toBeNull()
  })
  test('それ以外や範囲外の行では選択を変えない', () => {
    expect(focusRow({ ...three, focused: 1 }, 'act:e').focused).toBe(1)
    expect(focusRow({ ...three, focused: 1 }, undefined).focused).toBe(1)
    expect(focusRow({ ...three, focused: 1 }, 'row:9').focused).toBe(1)
  })
})

describe('選んだ行への操作', () => {
  const picked = { ...three, focused: 1 }
  test('e で選んだ行を編集する', () => {
    const s = editFocused(picked)
    expect(s.editing).toBe(1)
    expect(inputValue(s)).toBe('b')
  })
  test('t で選んだ行を先頭へ移し、選択も先頭に付いていく', () => {
    const s = topFocused(picked)
    expect(s.items).toEqual(['b', 'a', 'c'])
    expect(s.focused).toBe(0)
  })
  test('x で選んだ行を消し、選択は同じ位置（末尾なら1つ上）に残る', () => {
    expect(removeFocused(picked)).toEqual({ items: ['a', 'c'], editing: null, focused: 1 })
    expect(removeFocused({ ...three, focused: 2 }).focused).toBe(1)
    expect(removeFocused({ items: ['a'], editing: null, focused: 0 })).toEqual({ items: [], editing: null, focused: null })
  })
  test('行を選んでいなければ何もしない', () => {
    expect(editFocused(three)).toEqual(three)
    expect(topFocused(three)).toEqual(three)
    expect(removeFocused(three)).toEqual(three)
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
