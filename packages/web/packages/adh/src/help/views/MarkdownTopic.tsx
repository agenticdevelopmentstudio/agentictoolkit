'use client'

import type { MouseEvent } from 'react'
import { isModifiedClick } from '@agenticdevelopertoolkit/ui/lib/navigation-guard'
// Package path (not '../HelpProvider') so useHelp resolves to the SINGLE HelpContext the provider
// created — a relative import would bundle a second HelpProvider/context into this window chunk and
// useHelp() would read the wrong (empty) context, silently no-op'ing the navigation below. Same
// preserved-import rationale as this package's header/recents and themes (see tsup.config.ts
// `external`). Note this is a SELF-reference: '@agentic-toolkit/adh/help' resolves back into this
// same package, and a self-reference is exactly the shape that silently forks state, because
// nothing about it reads as a cross-package boundary.
import { useHelp } from '@agentic-toolkit/adh/help'
import { MarkdownHtml } from '../../docs/MarkdownHtml'
import { HELP_CONTENT_HTML } from '../content.generated'
import { topicBySlug } from '../topics'

/**
 * Renders a markdown help topic in the modal's detail pane. `contentKey` indexes the generated
 * {@link HELP_CONTENT_HTML} map (PRE-RENDERED HTML built from `content/*.md` by
 * `tools/gen-help-content.py`), which {@link MarkdownHtml} injects as-is — no runtime markdown
 * processing, so the pane paints instantly with no "Rendering…" flash. The docs sites render the
 * exact same HTML server-side, so a topic looks identical in the modal and on its page.
 *
 * The shared content's cross-links are site-relative help paths (`/quickstart`, `/reference/errors`,
 * `/rest-api`, `/quickstart/oauth/overview`, …) — correct on the help site, but dead in the modal,
 * which is mounted on every site (none of which have those routes). So here we intercept clicks on
 * links whose path is a known help topic slug and navigate the modal's OWN topic tree instead,
 * keeping the reader in the modal rather than off-siting them into a 404. External links, anchors,
 * and links with no matching topic (or modified/new-tab clicks) are left to behave normally.
 */
export function MarkdownTopic({ contentKey }: { contentKey: string }) {
  const { open } = useHelp()
  const html = HELP_CONTENT_HTML[contentKey]

  function onDocLinkClick(e: MouseEvent<HTMLDivElement>) {
    // Already handled by something else, or a new-tab / download click the browser keeps.
    if (e.defaultPrevented || isModifiedClick(e)) return
    const anchor = (e.target as HTMLElement).closest('a')
    if (!anchor || anchor.target === '_blank') return
    const href = anchor.getAttribute('href') ?? ''
    // Only same-site absolute paths can be topics; skip external URLs and same-page anchors.
    if (!href.startsWith('/')) return
    const slug = href.replace(/^\//, '').replace(/[?#].*$/, '')
    const topic = topicBySlug(slug)
    if (!topic) return // no matching topic → let the link navigate normally
    e.preventDefault()
    open(topic.id)
  }

  return (
    <div className="adh-help-topic adh-help-topic--markdown" onClick={onDocLinkClick}>
      {html == null ? (
        <p className="adh-help-topic__missing">This topic has no content yet.</p>
      ) : (
        <MarkdownHtml html={html} />
      )}
    </div>
  )
}
