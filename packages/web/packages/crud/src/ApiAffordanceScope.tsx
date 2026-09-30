'use client'

import type { ReactNode } from 'react'
import { RecordApiButton } from '@agentic-toolkit/api-explorer'
import {
  RecordAffordanceContext,
  useRecordAffordance,
  type RecordAffordanceProps,
} from '@agentic-toolkit/resource'

const renderRecordApi = (props: RecordAffordanceProps) => <RecordApiButton {...props} />

/**
 * Guarantees the header's API slot a live button below it: the host's affordance when a host
 * supplies one (the hub's workspace shell), else the api-explorer's own RecordApiButton.
 *
 * A pane that used to draw `<RecordApiButton>` itself worked on every site; once it hands its
 * endpoint to the header's `api` slot instead, that slot draws whatever the context renders —
 * and a satellite site or standalone feature site has no workspace shell to supply it, so the
 * button would go dead there. Here rather than in resource because resource cannot import the
 * api-explorer; crud is the lowest tier that depends on both.
 */
export function ApiAffordanceScope({ children }: { children: ReactNode }) {
  const host = useRecordAffordance()
  return (
    <RecordAffordanceContext.Provider value={host ?? renderRecordApi}>
      {children}
    </RecordAffordanceContext.Provider>
  )
}
