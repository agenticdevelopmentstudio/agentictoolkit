'use client'

import { useEffect, useState } from 'react'
import { collectEnvVars, parseEnvEntries, type EnvVarEntry } from './env-vars'
import { EnvVarList } from './EnvVarList'

type Fetched = EnvVarEntry[] | 'unavailable' | null

const CLIENT_ENV: Record<string, string | undefined> = {
  NEXT_PUBLIC_DEPLOYMENT_ENV: process.env.NEXT_PUBLIC_DEPLOYMENT_ENV,
  NEXT_PUBLIC_AUTH_API_URL: process.env.NEXT_PUBLIC_AUTH_API_URL,
  NEXT_PUBLIC_POSTHOG_KEY: process.env.NEXT_PUBLIC_POSTHOG_KEY,
  NEXT_PUBLIC_POSTHOG_HOST: process.env.NEXT_PUBLIC_POSTHOG_HOST,
  NEXT_PUBLIC_GLITCHTIP_DSN: process.env.NEXT_PUBLIC_GLITCHTIP_DSN,
  NEXT_PUBLIC_TELEMETRY_DEBUG: process.env.NEXT_PUBLIC_TELEMETRY_DEBUG,
}

function fetchEntries(url: string): Promise<EnvVarEntry[]> {
  return fetch(url)
    .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
    // Read, never cast: whatever resolves here goes straight into a state setter below, and
    // a bare `[]` once put `Array.prototype.entries` there and crashed the page — see
    // parseEnvEntries. A body off the contract is shown as "unavailable" instead.
    .then(
      (body: unknown) =>
        parseEnvEntries(body) ?? Promise.reject(new Error('debug-env body is not { entries }')),
    )
}

export function EnvironmentPanel() {
  const [site, setSite] = useState<Fetched>(null)
  const [backend, setBackend] = useState<Fetched>(null)

  useEffect(() => {
    fetchEntries('/api/public/debug-env').then(setSite).catch(() => setSite('unavailable'))
    fetchEntries('/api/system/debug-env').then(setBackend).catch(() => setBackend('unavailable'))
  }, [])

  const client = collectEnvVars(Object.keys(CLIENT_ENV), (name) => CLIENT_ENV[name])
  const siteEntries = Array.isArray(site) && site.length > 0 ? site : client

  return (
    <div className="flex flex-col gap-4 overflow-auto p-4">
      <section>
        <h3 className="mb-2 font-mono text-xs tracking-[0.02em] text-apt-text-muted">Site (frontend)</h3>
        <EnvVarList entries={siteEntries} />
      </section>
      <section>
        <h3 className="mb-2 font-mono text-xs tracking-[0.02em] text-apt-text-muted">Backend</h3>
        {backend === null ? (
          <p className="font-mono text-xs text-apt-text-dim">Loading…</p>
        ) : backend === 'unavailable' ? (
          <p className="font-mono text-xs text-apt-text-dim">Backend env unavailable.</p>
        ) : (
          <EnvVarList entries={backend} />
        )}
      </section>
    </div>
  )
}
