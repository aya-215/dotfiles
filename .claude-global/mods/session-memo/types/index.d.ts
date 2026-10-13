export type MemoState = {
  items: string[]
  editing: number | null
  focused: number | null
}

declare module 'claude-code' {
  interface PluginState {
    'session-memo': { memo: MemoState }
  }
}
