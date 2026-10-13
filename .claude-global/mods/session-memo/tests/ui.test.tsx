import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { expect, test } from 'claude-code/testing'

const SURFACES = ['terminal', 'desktop'] as const
type Surface = (typeof SURFACES)[number]

const SCROLL = { offset: 0, bodyRows: 10 }
const PANE_PROPS = { title: 'Memo', isFocused: true, bodyColumns: 60, placement: 'inline' as const, scroll: SCROLL, view: {} }

function bandProps(hasSurvey = false) {
  return { hasSurvey, isWorking: false, maxRows: 10, bodyColumns: 60, scroll: SCROLL, view: {} }
}

function engineBand(on: On) {
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
}

function openPane($: Engine, surface: Surface) {
  return $.ui.mount({ plugin: 'session-memo', surface, component: 'Pane', props: PANE_PROPS, requestId: 'memo' })
}

function openBand($: Engine, surface: Surface, hasSurvey = false) {
  return $.ui.mount({ plugin: 'session-memo', surface, component: 'AbovePrompt', props: bandProps(hasSurvey) })
}

for (const surface of SURFACES) {
  test(`パネルの入力欄で追加すると並び、入力欄は空に戻る (${surface})`, async ($, on) => {
    engineBand(on)
    const pane = await openPane($, surface)
    expect(await pane.find({ text: 'メモはまだありません' })).toBeDefined()
    await pane.input({ key: 'input', text: '認証まわりは触らんとく' })
    await pane.input({ key: 'input', text: 'あとでテスト追加' })
    expect((await pane.find({ key: 'row:0' }))?.text).toContain('1. 認証まわりは触らんとく')
    expect((await pane.find({ key: 'row:1' }))?.text).toContain('2. あとでテスト追加')
    expect((await pane.find({ key: 'input' }))?.text).toBe('')
  })

  test(`[e] で書き換え、[取消] なら元のまま (${surface})`, async ($, on) => {
    engineBand(on)
    const pane = await openPane($, surface)
    await pane.input({ key: 'input', text: 'a' })
    await pane.input({ key: 'input', text: 'b' })
    await pane.press({ key: 'edit:1' })
    expect((await pane.find({ key: 'input' }))?.text).toBe('b')
    expect(await pane.find({ key: 'cancel' })).toBeDefined()
    await pane.input({ key: 'input', text: 'B' })
    expect((await pane.find({ key: 'row:1' }))?.text).toContain('2. B')
    expect(await pane.find({ key: 'cancel' })).toBeUndefined()
    await pane.press({ key: 'edit:0' })
    await pane.press({ key: 'cancel' })
    expect((await pane.find({ key: 'row:0' }))?.text).toContain('1. a')
    expect((await pane.find({ key: 'input' }))?.text).toBe('')
  })

  test(`[↑] で先頭へ、[x] で削除、先頭の行に [↑] は無い (${surface})`, async ($, on) => {
    engineBand(on)
    const pane = await openPane($, surface)
    for (const text of ['a', 'b', 'c']) await pane.input({ key: 'input', text })
    expect(await pane.find({ key: 'up:0' })).toBeUndefined()
    await pane.press({ key: 'up:2' })
    expect((await pane.find({ key: 'row:0' }))?.text).toContain('1. c')
    await pane.press({ key: 'del:1' })
    expect((await pane.findAll({ type: 'Text', text: /^\d+\. / })).map(t => t.text)).toEqual(['1. c', '2. b'])
  })

  test(`帯は0件なら出さず、先頭と（+N）を出す (${surface})`, async ($, on) => {
    engineBand(on)
    const empty = await openBand($, surface)
    expect(await empty.find({ text: 'engine' })).toBeDefined()
    const pane = await openPane($, surface)
    await pane.input({ key: 'input', text: '買い物' })
    const one = await openBand($, surface)
    expect(await one.find({ text: '📝 買い物' })).toBeDefined()
    expect(await one.find({ text: /（\+/ })).toBeUndefined()
    await pane.input({ key: 'input', text: '洗濯' })
    await pane.input({ key: 'input', text: '掃除' })
    const many = await openBand($, surface)
    expect(await many.find({ text: '📝 買い物' })).toBeDefined()
    expect(await many.find({ text: '（+2）' })).toBeDefined()
  })

  test(`長いメモでも（+N）は別要素で残る (${surface})`, async ($, on) => {
    engineBand(on)
    const pane = await openPane($, surface)
    await pane.input({ key: 'input', text: 'あ'.repeat(200) })
    await pane.input({ key: 'input', text: '二件目' })
    const band = await openBand($, surface)
    const head = await band.find({ type: 'Text', text: /^📝 / })
    expect(head?.props.wrap).toBe('truncate')
    expect(await band.find({ type: 'Text', text: '（+1）' })).toBeDefined()
  })

  test(`アンケート中は帯を譲る (${surface})`, async ($, on) => {
    engineBand(on)
    const pane = await openPane($, surface)
    await pane.input({ key: 'input', text: '買い物' })
    const band = await openBand($, surface, true)
    expect(await band.find({ text: 'engine' })).toBeDefined()
    expect(await band.find({ text: /📝/ })).toBeUndefined()
  })
}
