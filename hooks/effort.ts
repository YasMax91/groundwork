import type { Register } from 'claude-code'

/**
 * Groundwork plugin :: the effort a request runs at follows the task's level (wave 39).
 *
 * A session cannot change its own effort (the desktop app refuses set_session_effort on itself), and an agent
 * definition's `effort` is one value for every task. This mod sets it per request: the main conversation by
 * the level the checkpoint (`.claude/groundwork/task-state.md`) states for an open task, and groundwork's own
 * agents by their role and the same level. No task, a closed one, no `.groundwork.json`, or
 * `effort.by_level: false` — every request goes as the menu set it. On Opus 5.5, Sonnet 5.5, Haiku 5.5 and
 * Fable 5.1 a change of effort keeps the prompt cache; the model is never touched, a change of model would
 * re-read the whole conversation.
 */

export type Effort = 'low' | 'medium' | 'high' | 'xhigh' | 'max'
type Row = Record<number, Effort>
export type Tables = { main: Row; mapping: Row; checkers: Row }

// `max` is kept for L4: the model's documentation says it "may show diminishing returns and is prone to
// overthinking". Questions and chat (no open task) keep the menu's effort — "why does this test fail" is an
// investigation, not a small task.
export const DEFAULTS: Tables = {
  main: { 0: 'medium', 1: 'high', 2: 'high', 3: 'xhigh', 4: 'max' },
  mapping: { 0: 'medium', 1: 'medium', 2: 'medium', 3: 'high', 4: 'high' },
  checkers: { 0: 'high', 1: 'high', 2: 'high', 3: 'xhigh', 4: 'max' },
}

export const ROLES: Record<string, 'mapping' | 'checkers'> = {
  'groundwork:impact-mapper': 'mapping',
  'groundwork:grounded-researcher': 'mapping',
  'groundwork:conformance-reviewer': 'checkers',
  'groundwork:adversarial-verifier': 'checkers',
  'groundwork:blind-spot-mapper': 'checkers',
}

const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max']
const WORDS: Record<Effort, string> = {
  low: 'низкое', medium: 'среднее', high: 'высокое', xhigh: 'очень высокое', max: 'максимальное',
}
const WHY: Record<number, string> = {
  0: 'правка документов', 1: 'задача с кодом', 2: 'задача с кодом', 3: 'рискованная задача', 4: 'критичная задача',
}

/** The level an open task's checkpoint states; undefined for no task, a closed one, or no level. */
export function levelOf(checkpoint: string): number | undefined {
  const mode = /^-\s*Mode:\s*\**\s*([A-Za-z]+)/m.exec(checkpoint)?.[1]
  if (!mode || mode.toLowerCase() === 'done') return undefined
  const level = /^-\s*Level:\s*\**\s*L([0-4])\b/m.exec(checkpoint)?.[1]
  return level === undefined ? undefined : Number(level)
}

/** The tables `.groundwork.json` asks for — `effort.table.<row>.<L0..L4>` overrides — or undefined when off. */
export function tablesOf(config: unknown): Tables | undefined {
  const effort = ((config as { effort?: unknown } | null)?.effort ?? {}) as {
    by_level?: unknown
    table?: Partial<Record<keyof Tables, Record<string, unknown>>>
  }
  if (effort.by_level === false) return undefined
  const tables: Tables = { main: { ...DEFAULTS.main }, mapping: { ...DEFAULTS.mapping }, checkers: { ...DEFAULTS.checkers } }
  for (const row of ['main', 'mapping', 'checkers'] as const) {
    for (const [key, value] of Object.entries(effort.table?.[row] ?? {})) {
      const level = Number(String(key).replace(/^L/i, ''))
      if (Number.isInteger(level) && level >= 0 && level <= 4 && EFFORTS.includes(String(value))) {
        tables[row][level] = value as Effort
      }
    }
  }
  return tables
}

/**
 * The effort a request should carry, or undefined to send it as it is. `agentType` is undefined for the main
 * conversation; a request whose model takes no effort (`current` undefined) is never given one.
 */
export function decide(level: number | undefined, tables: Tables | undefined, agentType: string | undefined,
                       current: unknown): Effort | undefined {
  if (level === undefined || !tables || current === undefined) return undefined
  const row = agentType === undefined ? 'main' : ROLES[agentType]
  if (!row) return undefined
  const want = tables[row][level]
  return want && want !== current ? want : undefined
}

export function note(level: number, effort: Effort): string {
  return `усилие: ${WORDS[effort]} — ${WHY[level] ?? 'задача'}`
}

export const register: Register = on => {
  let cache: { at: number; level?: number; tables?: Tables } = { at: 0 }
  const types = new Map<string, string>()
  let pending: string | undefined     // what to say under this turn's answer
  let said: string | undefined        // the last line said: the same level and effort is not repeated

  on('turn.step', async function* ($, e, next) {
    if (Date.now() - cache.at >= 5000) {
      cache = { at: Date.now() }
      try {
        if (await $.fs.exists('.groundwork.json')) {
          cache.tables = tablesOf(JSON.parse(String(await $.fs.read('.groundwork.json'))))
          if (cache.tables && (await $.fs.exists('.claude/groundwork/task-state.md'))) {
            cache.level = levelOf(String(await $.fs.read('.claude/groundwork/task-state.md')))
          }
        }
      } catch {
        // unreadable or malformed: every request goes as the menu set it
      }
    }
    const state = cache
    let type: string | undefined
    if (e.agentId !== undefined) {
      type = types.get(e.agentId)
      if (type === undefined) {
        try {
          type = (await $.agent.list()).find(agent => agent.id === e.agentId)?.type ?? ''
        } catch {
          type = ''
        }
        types.set(e.agentId, type)
      }
    }
    const want = decide(state.level, state.tables, type, e.effort)
    if (!want) return yield* next(e)
    if (e.agentId === undefined && state.level !== undefined) {
      const line = note(state.level, want)
      if (line !== said) pending = line
    }
    return yield* next({ ...e, effort: want })
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (!pending || (e as { agentId?: string }).agentId !== undefined) return result
    said = pending
    pending = undefined
    return { ...result, text: result.text ? `${result.text}\n${said}` : said }
  })
}
