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

function world(on: On) {
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  on('ui.focus', () => ({}))
}

function openPane($: Engine, surface: Surface) {
  return $.ui.mount({ plugin: 'session-memo', surface, component: 'Pane', props: PANE_PROPS, requestId: 'memo' })
}

function openBand($: Engine, surface: Surface, hasSurvey = false) {
  return $.ui.mount({ plugin: 'session-memo', surface, component: 'AbovePrompt', props: bandProps(hasSurvey) })
}

function ring($: Engine, element: string) {
  return $.ui.focus({ component: 'Pane', requestId: 'memo', plugin: 'session-memo', element, origin: { kind: 'person' } })
}

async function rows(pane: Awaited<ReturnType<typeof openPane>>): Promise<string[]> {
  return (await pane.findAll({ type: 'Button', key: undefined })).filter(b => /^row:/.test(b.key ?? '')).map(b => b.text)
}

for (const surface of SURFACES) {
  test(`パネルの入力欄で追加すると並び、入力欄は空に戻る (${surface})`, async ($, on) => {
    world(on)
    const pane = await openPane($, surface)
    expect(await pane.find({ text: 'メモはまだありません' })).toBeDefined()
    await pane.input({ key: 'input', text: '認証まわりは触らんとく' })
    await pane.input({ key: 'input', text: 'あとでテスト追加' })
    expect(await rows(pane)).toEqual(['1. 認証まわりは触らんとく', '2. あとでテスト追加'])
    expect((await pane.find({ key: 'input' }))?.text).toBe('')
  })

  test(`行を押す（Enter・クリック）と編集に入り、[取消] なら元のまま (${surface})`, async ($, on) => {
    world(on)
    const pane = await openPane($, surface)
    await pane.input({ key: 'input', text: 'a' })
    await pane.input({ key: 'input', text: 'b' })
    await pane.press({ key: 'row:1' })
    expect((await pane.find({ key: 'input' }))?.text).toBe('b')
    await pane.input({ key: 'input', text: 'B' })
    expect(await rows(pane)).toEqual(['1. a', '2. B'])
    await pane.press({ key: 'row:0' })
    await pane.press({ key: 'cancel' })
    expect(await rows(pane)).toEqual(['1. a', '2. B'])
    expect((await pane.find({ key: 'input' }))?.text).toBe('')
  })

  test(`行を選ぶまで文字キーの操作は出さず、選ぶと e / t / x が出る (${surface})`, async ($, on) => {
    world(on)
    const pane = await openPane($, surface)
    for (const text of ['a', 'b', 'c']) await pane.input({ key: 'input', text })
    expect(await pane.find({ key: 'act:e' })).toBeUndefined()
    await ring($, 'row:1')
    expect((await pane.find({ key: 'act:e' }))?.props.hotkey).toBe('e')
    expect((await pane.find({ key: 'act:t' }))?.props.hotkey).toBe('t')
    expect((await pane.find({ key: 'act:x' }))?.props.hotkey).toBe('x')
    await ring($, 'input')
    expect(await pane.find({ key: 'act:e' })).toBeUndefined()
  })

  test(`選んだ行に e で編集、t で先頭へ、x で削除 (${surface})`, async ($, on) => {
    world(on)
    const pane = await openPane($, surface)
    for (const text of ['a', 'b', 'c']) await pane.input({ key: 'input', text })
    await ring($, 'row:2')
    await pane.press({ key: 'act:t' })
    expect(await rows(pane)).toEqual(['1. c', '2. a', '3. b'])
    await ring($, 'row:1')
    await pane.press({ key: 'act:x' })
    expect(await rows(pane)).toEqual(['1. c', '2. b'])
    await pane.press({ key: 'act:e' })
    expect((await pane.find({ key: 'input' }))?.text).toBe('b')
  })

  test(`帯は0件なら出さず、先頭と（+N）を出す (${surface})`, async ($, on) => {
    world(on)
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
    world(on)
    const pane = await openPane($, surface)
    await pane.input({ key: 'input', text: 'あ'.repeat(200) })
    await pane.input({ key: 'input', text: '二件目' })
    const band = await openBand($, surface)
    const head = await band.find({ type: 'Text', text: /^📝 / })
    expect(head?.props.wrap).toBe('truncate')
    expect(await band.find({ type: 'Text', text: '（+1）' })).toBeDefined()
    expect((await band.find({ key: 'more' }))?.props.flexShrink).toBe(0)
  })

  test(`アンケート中は帯を譲る (${surface})`, async ($, on) => {
    world(on)
    const pane = await openPane($, surface)
    await pane.input({ key: 'input', text: '買い物' })
    const band = await openBand($, surface, true)
    expect(await band.find({ text: 'engine' })).toBeDefined()
    expect(await band.find({ text: /📝/ })).toBeUndefined()
  })
}
