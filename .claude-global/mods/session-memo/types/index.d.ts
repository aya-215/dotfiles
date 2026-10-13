export type MemoState = {
  items: string[]
  editing: number | null
}

declare module 'claude-code' {
  interface PluginState {
    'session-memo': { memo: MemoState }
  }
}
