import { describe, expect, it } from 'vitest'
import { collectEnvVars, isSecretName, maskValue, parseEnvEntries } from '../debug-env/env-vars'

describe('isSecretName', () => {
  it('flags credential-ish names', () => {
    for (const n of [
      'JWT_SECRET',
      'GITHUB_CLIENT_SECRET',
      'NEXT_PUBLIC_POSTHOG_KEY',
      'NEXT_PUBLIC_GLITCHTIP_DSN',
      'PG_PASSWORD',
      'API_TOKEN',
      'PRIVATE_THING',
    ]) {
      expect(isSecretName(n)).toBe(true)
    }
  })

  it('leaves non-secret names alone', () => {
    for (const n of ['DEPLOYMENT_ENV', 'API_BACKEND_URL', 'DEBUG_MENU', 'AI_CHAT']) {
      expect(isSecretName(n)).toBe(false)
    }
  })
})

describe('maskValue', () => {
  it('keeps a short recognisable prefix and hides the rest', () => {
    expect(maskValue('phc_abcdef123456')).toBe('phc_••••••••')
    expect(maskValue('secret')).toBe('secr••••••••')
  })

  it('fully masks short values', () => {
    expect(maskValue('ab')).toBe('••••••••')
  })
})

describe('collectEnvVars', () => {
  const env: Record<string, string | undefined> = {
    DEPLOYMENT_ENV: 'local',
    API_BACKEND_URL: 'http://localhost:3000',
    NEXT_PUBLIC_POSTHOG_KEY: 'phc_supersecretkey',
    DEBUG_MENU: '', // set-but-empty → excluded
    AI_CHAT: undefined, // unset → excluded
  }
  const read = (n: string) => env[n]

  it('includes only SET (non-empty) vars, in the given order', () => {
    const entries = collectEnvVars(
      ['DEPLOYMENT_ENV', 'DEBUG_MENU', 'AI_CHAT', 'API_BACKEND_URL'],
      read,
    )
    expect(entries.map((e) => e.name)).toEqual(['DEPLOYMENT_ENV', 'API_BACKEND_URL'])
  })

  it('masks secret-named values and never exposes the raw secret', () => {
    const entry = collectEnvVars(['NEXT_PUBLIC_POSTHOG_KEY'], read)[0]!
    expect(entry.secret).toBe(true)
    expect(entry.value).toBe('phc_••••••••')
    expect(entry.value).not.toContain('supersecret')
  })

  it('shows non-secret values verbatim', () => {
    const entry = collectEnvVars(['API_BACKEND_URL'], read)[0]!
    expect(entry.secret).toBe(false)
    expect(entry.value).toBe('http://localhost:3000')
  })
})

describe('parseEnvEntries', () => {
  const row = { name: 'DEPLOYMENT_ENV', value: 'local', secret: false }

  it('returns the entries of a body on the { entries } contract', () => {
    expect(parseEnvEntries({ entries: [row] })).toEqual([row])
    expect(parseEnvEntries({ entries: [] })).toEqual([])
  })

  // The crash: a bare array's `entries` is the inherited Array.prototype.entries, a
  // function a state setter would run as an updater.
  it('refuses a bare array rather than returning its inherited entries method', () => {
    expect(parseEnvEntries([])).toBeNull()
    expect(parseEnvEntries([row])).toBeNull()
  })

  it('refuses bodies that are not an object carrying an entries array', () => {
    for (const body of [null, undefined, 'entries', 42, {}, { entries: 'x' }, { entries: {} }]) {
      expect(parseEnvEntries(body)).toBeNull()
    }
  })

  it('refuses a body with any row off the contract', () => {
    for (const bad of [
      null,
      'DEPLOYMENT_ENV',
      { name: 'DEPLOYMENT_ENV', value: { url: 'x' }, secret: false },
      { name: 'DEPLOYMENT_ENV', value: 'local' },
      { name: 7, value: 'local', secret: false },
    ]) {
      expect(parseEnvEntries({ entries: [row, bad] })).toBeNull()
    }
  })
})
