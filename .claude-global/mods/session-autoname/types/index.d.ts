export type Color = 'red' | 'blue' | 'green' | 'yellow' | 'purple' | 'orange' | 'pink' | 'cyan'

export type Naming = {
  isActive: boolean
  color: Color | null
  answered: number
  prompts: string[]
  current: string
  isManual: boolean
}

declare module 'claude-code' {
  interface PluginState {
    'session-autoname': { naming: Naming }
  }
}
