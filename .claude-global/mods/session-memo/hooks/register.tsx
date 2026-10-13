import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import { EMPTY, bandParts, cancelEdit, inputValue, moveToTop, removeItem, startEdit, submitInput } from './memo'

export const PANE = 'memo'
const memo = atom({ plugin: 'session-memo', key: 'memo' } as const, EMPTY)

export const register: Register = on => {
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const parts = bandParts((await read($, memo)).items)
    if (e.props.hasSurvey || parts === null) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="row">
        <Box flexShrink={1}>
          <Text wrap="truncate">{parts.text}</Text>
        </Box>
        {parts.more !== '' && <Text dimColor>{parts.more}</Text>}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    if (e.surface === 'mobile') return next(e)
    const state = await read($, memo)
    const { Box, Button, Input, Text } = $.ui.resolve(e)
    const editing = state.editing
    const focusInput = () => $.ui.focus({ requestId: PANE, key: 'input' }).catch(() => undefined)
    return (
      <Box flexDirection="column">
        {state.items.length === 0 && <Text dimColor>メモはまだありません</Text>}
        {state.items.map((item, i) => (
          <Box key={`row:${i}`} flexDirection="row">
            <Box flexGrow={1} flexShrink={1}>
              <Text wrap="truncate" bold={editing === i}>{`${i + 1}. ${item}`}</Text>
            </Box>
            {i > 0 && <Button key={`up:${i}`} label="↑" onPress={() => update($, memo, s => moveToTop(s, i))} />}
            <Button
              key={`edit:${i}`}
              label="e"
              onPress={async () => {
                await update($, memo, s => startEdit(s, i))
                await focusInput()
              }}
            />
            <Button key={`del:${i}`} label="x" onPress={() => update($, memo, s => removeItem(s, i))} />
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
