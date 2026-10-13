import type { On, UiPane } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { expect, test } from 'claude-code/testing'

function world(on: On) {
  const registered: { name: string; immediate?: true }[] = []
  const opened: { id: string; focus?: true; closeOnEscape?: true }[] = []
  const closed: string[] = []
  let panes: UiPane[] = []

  on('command.register', ($, e) => {
    registered.push({ name: e.name, immediate: e.immediate })
    return { value: { command: e.name } }
  })
  on('ui.open', ($, e) => {
    opened.push({ id: e.id, focus: e.focus, closeOnEscape: e.closeOnEscape })
    panes = [{ id: e.id, title: e.title ?? '', isShown: true, isFocused: true, isPlaced: true }]
    return { value: { isPlaced: true as const } }
  })
  on('ui.close', ($, e) => {
    closed.push(e.id)
    panes = panes.filter(p => p.id !== e.id)
    return { value: undefined }
  })
  on('ui.panes', () => ({ value: panes }))
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('session.end', ($, e) => ({ sessionId: e.sessionId }))
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })

  return { registered, opened, closed }
}

function memo($: Engine, args: string) {
  return $.command.run({
    command: 'note',
    args,
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 80 },
  })
}

const BAND = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 10,
  bodyColumns: 60,
  scroll: { offset: 0, bodyRows: 10 },
  view: {},
}

async function bandText($: Engine): Promise<string | undefined> {
  const band = await $.ui.mount({ plugin: 'session-memo', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  return (await band.find({ type: 'Text', text: /^📝 / }))?.text
}

test('起動時に /note を immediate で登録する', async ($, on) => {
  const w = world(on)
  await $.session.start({ cwd: '/tmp/work', surface: 'terminal', isInteractive: true })
  expect(w.registered).toEqual([{ name: 'note', immediate: true }])
})

test('/note ○○ で追加し、件数を返す', async ($, on) => {
  world(on)
  expect((await memo($, '  買い物  ')).text).toBe('メモを追加（1件）')
  expect((await memo($, '洗濯')).text).toBe('メモを追加（2件）')
  expect(await bandText($)).toBe('📝 買い物')
})

test('引数なしの /note でパネルを開閉する', async ($, on) => {
  const w = world(on)
  expect((await memo($, '')).text).toBe('メモを開いた')
  expect(w.opened).toEqual([{ id: 'memo', focus: true, closeOnEscape: true }])
  expect((await memo($, '   ')).text).toBe('メモを閉じた')
  expect(w.closed).toEqual(['memo'])
})

test('開き直したら編集モードではない', async ($, on) => {
  world(on)
  await memo($, 'a')
  const pane = await $.ui.mount({
    plugin: 'session-memo',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'memo',
    props: { title: 'Memo', isFocused: true, bodyColumns: 60, placement: 'inline', scroll: { offset: 0, bodyRows: 10 }, view: {} },
  })
  await pane.press({ key: 'row:0' })
  expect(await pane.find({ key: 'cancel' })).toBeDefined()
  await memo($, '')
  expect(await pane.find({ key: 'cancel' })).toBeUndefined()
})

test('/clear と /resume でメモが消える', async ($, on) => {
  world(on)
  await memo($, 'a')
  await $.session.end({ reason: 'clear', sessionId: 's-1', resume: { id: 's-1' } })
  expect(await bandText($)).toBeUndefined()
  await memo($, 'b')
  await $.session.end({ reason: 'resume', sessionId: 's-1', resume: { id: 's-2' } })
  expect(await bandText($)).toBeUndefined()
})

test('それ以外の終了理由ではメモを残す', async ($, on) => {
  world(on)
  await memo($, 'a')
  await $.session.end({ reason: 'other', sessionId: 's-1', resume: { id: 's-1' } })
  expect(await bandText($)).toBe('📝 a')
})
