'use client'

import { useEffect, useState, type MouseEvent, type ReactNode } from 'react'
import { isModifiedClick } from '@agenticdevelopertoolkit/ui/lib/navigation-guard'
// PRESERVED IMPORT — the package path, never '../legal', even though it is a sibling
// directory here. `legal/index` is its own tsup entry with a matching `external`; a
// relative specifier would inline the whole legal tier (both prose bodies plus
// LegalPageShell) into the ALWAYS-loaded footer entry, and hoist its `'use client'`
// banner over everything else that entry inlines. See verify-bundle-boundaries.py.
import { LEGAL_EFFECTIVE_DATE, TermsBody, PrivacyBody } from '@agentic-toolkit/adh/legal'
import { AdhModalPopover } from './AdhModalPopover'

/** DOM ids of the footer's legal modals (opened by the footer's legal links, see openLegalModal). */
export const TERMS_DIALOG_ID = 'adh-terms-dialog'
export const PRIVACY_DIALOG_ID = 'adh-privacy-dialog'

/**
 * True once the popover with `id` has been opened at least once. The full legal
 * prose (TermsBody/PrivacyBody) is several KB; rendering it eagerly would embed
 * the entire Terms + Privacy text into the SSR HTML of EVERY page of every site
 * (the footer is on every page). Instead we mount it on first open — the
 * standalone /terms and /privacy pages remain the crawlable, no-JS source (the
 * legal link falls back to them when the Popover API is unavailable, see openLegalModal). */
function useOpenedOnce(id: string): boolean {
  const [opened, setOpened] = useState(false)
  useEffect(() => {
    if (opened) return
    const el = document.getElementById(id)
    if (!el) return
    const onToggle = (e: Event) => {
      if ((e as Event & { newState?: string }).newState === 'open') setOpened(true)
    }
    el.addEventListener('toggle', onToggle)
    return () => el.removeEventListener('toggle', onToggle)
  }, [id, opened])
  return opened
}

function LegalDoc({ children }: { children: ReactNode }) {
  return (
    <article className="adh-legal-doc">
      <p className="adh-legal-doc__meta">Effective {LEGAL_EFFECTIVE_DATE}</p>
      {children}
    </article>
  )
}

/** The footer "Terms of Service" modal (the same shared content as /terms). */
export function TermsModal() {
  const opened = useOpenedOnce(TERMS_DIALOG_ID)
  return (
    <AdhModalPopover id={TERMS_DIALOG_ID} title="Terms of Service" bodyClassName="adh-modal__body--legal">
      {opened && (
        <LegalDoc>
          <TermsBody />
        </LegalDoc>
      )}
    </AdhModalPopover>
  )
}

/** The footer "Privacy Policy" modal (the same shared content as /privacy). */
export function PrivacyModal() {
  const opened = useOpenedOnce(PRIVACY_DIALOG_ID)
  return (
    <AdhModalPopover id={PRIVACY_DIALOG_ID} title="Privacy Policy" bodyClassName="adh-modal__body--legal">
      {opened && (
        <LegalDoc>
          <PrivacyBody />
        </LegalDoc>
      )}
    </AdhModalPopover>
  )
}

/**
 * The click behaviour of a footer legal link, as a handler rather than a component:
 * when the browser supports the Popover API it opens the modal (preventing navigation);
 * otherwise it does nothing and the anchor's own href takes the user to the standalone
 * /terms or /privacy page — so the legal links are never dead.
 */
export function openLegalModal(dialogId: string) {
  return (e: MouseEvent<HTMLAnchorElement>) => {
    // Let modified or non-primary clicks (new tab, etc.) fall through to normal
    // navigation — the shared rule, which also carries the button check this copy
    // had lost — and leave a click something else already handled alone.
    if (e.defaultPrevented || isModifiedClick(e)) return
    const el = document.getElementById(dialogId)
    if (el && 'showPopover' in el) {
      e.preventDefault()
      ;(el as HTMLElement & { showPopover: () => void }).showPopover()
    }
  }
}
