import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import {
  EMPTY,
  addItem,
  bandParts,
  cancelEdit,
  editFocused,
  focusRow,
  inputValue,
  removeFocused,
  startEdit,
  submitInput,
  topFocused,
} from './memo'

export const PANE = 'memo'
const memo = atom({ plugin: 'session-memo', key: 'memo' } as const, EMPTY)

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'note',
      description: '作業メモを追加（引数なしでメモのパネルを開閉）',
      argumentHint: '[メモ]',
      immediate: true,
    })
    return next(e)
  })

  on('command.run', { command: 'note' }, async ($, e) => {
    const text = e.args.trim()
    if (text !== '') {
      let count = 0
      await update($, memo, s => {
        const added = addItem(s, text)
        count = added.items.length
        return added
      })
      return { text: `メモを追加（${count}件）` }
    }
    if ((await $.ui.panes()).some(p => p.id === PANE)) {
      await $.ui.close({ id: PANE })
      return { text: 'メモを閉じた' }
    }
    await update($, memo, cancelEdit)
    const { items } = await read($, memo)
    await $.ui.open({ id: PANE, title: 'Memo', focus: true, closeOnEscape: true, rows: Math.min(items.length + 3, 20) })
    return { text: 'メモを開いた' }
  })

  on('session.end', async ($, e, next) => {
    if (e.reason === 'clear' || e.reason === 'resume') await update($, memo, () => EMPTY)
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const parts = bandParts((await read($, memo)).items)
    if (e.props.hasSurvey || parts === null) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="row">
        <Box flexShrink={1}>
          <Text wrap="truncate">{parts.text}</Text>
        </Box>
        {parts.more !== '' && (
          <Box key="more" flexShrink={0}>
            <Text dimColor>{parts.more}</Text>
          </Box>
        )}
      </Box>
    )
  })

  on('ui.focus', { requestId: PANE }, async ($, e, next) => {
    await update($, memo, s => focusRow(s, e.element))
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    if (e.surface === 'mobile') return next(e)
    const state = await read($, memo)
    const { Box, Button, Input, Text } = $.ui.resolve(e)
    const { editing, focused } = state
    const focusInput = () => $.ui.focus({ requestId: PANE, key: 'input' }).catch(() => undefined)
    const focusRowAt = (i: number) => $.ui.focus({ requestId: PANE, key: `row:${i}` }).catch(() => undefined)
    return (
      <Box flexDirection="column">
        {state.items.length === 0 && <Text dimColor>メモはまだありません</Text>}
        {state.items.map((item, i) => (
          <Button
            key={`row:${i}`}
            plain
            onPress={async () => {
              await update($, memo, s => startEdit(s, i, item))
              await focusInput()
            }}
          >
            <Text bold={editing === i}>{`${i + 1}. ${item}`}</Text>
          </Button>
        ))}
        {state.items.length > 0 &&
          (focused === null ? (
            <Text dimColor>↑↓ で行を選ぶと e:編集 t:先頭へ x:削除</Text>
          ) : (
            <Box flexDirection="row" columnGap={1}>
              <Button
                key="act:e"
                plain
                dimColor
                hotkey="e"
                label="e:編集"
                onPress={async () => {
                  await update($, memo, editFocused)
                  await focusInput()
                }}
              />
              <Button
                key="act:t"
                plain
                dimColor
                hotkey="t"
                label="t:先頭へ"
                onPress={async () => {
                  await update($, memo, topFocused)
                  await focusRowAt(0)
                }}
              />
              <Button key="act:x" plain dimColor hotkey="x" label="x:削除" onPress={() => update($, memo, removeFocused)} />
            </Box>
          ))}
        <Box flexDirection="row">
          <Input
            key="input"
            label={editing === null ? 'memo>' : `${editing + 1}>`}
            value={inputValue(state)}
            submitLabel={editing === null ? '追加' : '書き換え'}
            autoFocus
            onSubmit={text => update($, memo, s => submitInput(s, text))}
          />
          {editing !== null && <Button key="cancel" label="取消" onPress={() => update($, memo, cancelEdit)} />}
        </Box>
      </Box>
    )
  })
}
