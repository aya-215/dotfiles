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
