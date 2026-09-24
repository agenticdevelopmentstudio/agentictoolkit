'use client'

import type { ComponentType } from 'react'

// PRESERVED IMPORTS — the package paths, never '../header' / '../footer', even though
// both are now sibling directories in THIS package. Each barrel is its own tsup entry
// with a matching `external` because it holds module-level state (the header's
// `envOverride` listener Set; the footer's legal-modal open-once flags), so a relative
// specifier would inline a private copy and fork it. See verify-bundle-boundaries.py.
// The header's workspaces context is state of that kind, and the header preview below
// replaces it: a private copy would be a second context, which the switcher never reads.
//
// The names are adh's REGISTRY-BOUND chrome, not the registry-free primitives these two
// barrels also publish under confusingly close names: `SiteMenuSwitcher` (renamed from
// this source's `SiteSwitcher`, which would now bind the toolkit's own unrelated
// `SiteSwitcher`) and `SiteFooter` (renamed from `AdhFooter`, likewise). The previews
// below pass adh's props — `currentSiteId`, and the footer's `specimen` — so the
// primitives are not substitutes.
import {
  SiteHeader,
  SiteMenuSwitcher,
  WorkspacesMenuProvider,
  useWorkspacesMenu,
  type WorkspacesMenu,
} from '@agentic-toolkit/adh/header'
import type { HeaderAuthSource } from '@agentic-toolkit/adh/header-auth'
import { SiteFooter } from '@agentic-toolkit/adh/footer'
import { Button } from '@agenticdevelopertoolkit/ui/components/button'
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  CardFooter,
} from '@agenticdevelopertoolkit/ui/components/card'
import { Input } from '@agenticdevelopertoolkit/ui/components/input'

// The editor TAXONOMY: areas (level 2) → items (level 3). "Global" is the one
// comprehensive section for everything site-wide (the chrome, base styles, colors,
// components); Typography is the type scale; Marketing landing is page-specific; and
// Custom CSS is the free-form escape hatch for anything not curated here.
//
// Each item targets a real CSS selector (or `:root` variables) and may carry its own
// example (`Preview`) — so the editor prefills the level-3 CSS box with the CURRENT
// styling read LIVE from that example, and what you edit is what-you-see-is-what-you-get
// (the CSS styles the example AND the live page identically).

export interface ThemeItem {
  /** Stable key in the theme's `data` map, e.g. "global.header-title". */
  id: string
  /** Level-3 topic label. */
  label: string
  /** The CSS selector this item targets / scaffolds. */
  selector: string
  /** Regular CSS properties to read from the element matching `selector`. */
  props?: string[]
  /** `:root` custom properties to read (fonts, colors, the type scale, …). */
  vars?: string[]
  /** Fallback block when nothing can be read live (e.g. a pseudo-element / closed menu). */
  defaultCss?: string
  /** Override the area's example for this item (e.g. a header element shows the header). */
  Preview?: ComponentType
  hint?: string
}

export interface ThemeArea {
  id: string
  label: string
  items: ThemeItem[]
  /** Default example for the area's items (an item's own `Preview` wins). */
  Preview: ComponentType
}

// A canned auth source for the preview: the theme editor styles the SIGNED-IN header
// (avatar + menu are themable surfaces) without touching the real session. Since Task
// 6.2 the auth slice reaches SiteHeader only through a source hook, so the previous
// `user=` / `onLogout=` props are expressed as a source that returns them. Module scope
// is part of the HeaderAuthSource contract — SiteHeader invokes it as a hook on every
// render, so it must be one stable function, never redefined inline.
const usePreviewHeaderAuth: HeaderAuthSource = () => ({
  user: { name: 'Ada Lovelace', email: 'ada@example.com' },
  onLogout: () => {},
})

// The workspaces the preview's header offers, in place of the page's. On the hub the page's
// workspaces provider sits above the Debug console, and a signed-in header on such a host
// swaps its site menu for the workspace switcher (SiteMenuSwitcher) — so the preview, signed
// in by the canned source above, listed the REAL user's workspaces, and picking one switched
// the page behind the console to it and saved it as that user's preferred workspace.
//
// Canned rows in the real list's shape: the hub names a personal workspace after its owner,
// and there are two rows so that a current and a non-current one are both there to style.
// The inert `select` stands in for the host's switch, and it also keeps the menu off each
// row's `href`, which is where a menu without one goes. Module scope, so every render gets
// the one object and the menu does not rebuild its rows each time.
const PREVIEW_WORKSPACES: WorkspacesMenu = {
  workspaces: [
    { id: 'preview:ada', label: 'Ada Lovelace', href: '#', current: true },
    { id: 'preview:engine', label: 'Analytical Engine', href: '#' },
  ],
  loading: false,
  select: () => {},
}

function HeaderPreview() {
  // Unlike `SiteMenuPreview` below, this DOES render a path to the Debug console: `SiteHeader`
  // wires `useDebugOptions` into the avatar menu's last row, and the preview user above is
  // signed in, so clicking that "Debug Options" row here would open a second Debug console
  // on top of this one (R6-M9). Not a regression — the row sat in the bug-glyph dropdown
  // before it moved to the avatar menu, and the pre-rework `SiteMenu` before that, with no
  // suppression prop on this preview in any era. What actually keeps it out of production is
  // the same gate that keeps this whole editor out of production: `DEV_TOOLS_BUILD_ENABLED`
  // (`header/devToolsEntries.ts`) is `DEV_BUILD` directly, and the site-theme editor only ever
  // renders when that flag is set — "no path to the console" is `SiteMenuPreview`'s
  // guarantee, not this one's.
  const header = (
    <SiteHeader
      siteId="hub"
      navLinks={[
        { label: 'Docs', href: '#docs' },
        { label: 'Pricing', href: '#pricing' },
      ]}
      trailingNavLinks={[{ label: 'Blog', href: '#blog' }]}
      useAuthSource={usePreviewHeaderAuth}
      // Required, not optional: SiteHeader falls back to the settings overlay's
      // openSettings whenever `onSettings` is absent and a user is present, and the
      // canned source above makes a user present. Without this the PREVIEW's avatar
      // menu opens the real User Settings dialog over the theme editor — the live
      // account, from a swatch panel, for whoever is actually signed in. An inert
      // handler keeps the row (it is a themable surface, which is the point of the
      // preview) and keeps it from doing anything.
      onSettings={() => {}}
    />
  )
  // The canned workspaces (PREVIEW_WORKSPACES) replace the page's, and only where the page
  // has some: a host without them (every satellite) shows the site menu in that slot, so
  // its preview must too. What the editor styles here is what the page shows.
  const pageHasWorkspaces = useWorkspacesMenu() != null
  return pageHasWorkspaces ? (
    <WorkspacesMenuProvider value={PREVIEW_WORKSPACES}>{header}</WorkspacesMenuProvider>
  ) : (
    header
  )
}

function FooterPreview() {
  return (
    <div className="tep-preview">
      {/* Preview-only: hide the (recursive) theme switcher. The two-class selector
          outranks its single-class default — no !important. */}
      <style>{`.tep-preview .adh-theme-switcher { display: none; }`}</style>
      {/* A `specimen`, because the page's own footer is on the page too, and what there
          must be one of — the menus' ids, the dialogs, bitbag — this copy leaves to that
          one (SiteFooterProps.specimen). On the page's ids, both copyright buttons opened
          the page's menu, and it opened at this copy's caret, whichever was clicked.

          bitbag is NOT hidden the way the theme switcher is, and can't be: he portals
          himself to `document.body`, so he is not a descendant of `.tep-preview` and a
          scoped rule never matches him. Hiding him from here used to work and silently
          stopped when the portal landed — a second, full-size, live dock over the
          console previewing him. A specimen doesn't mount him at all. */}
      <SiteFooter
        specimen
        links={[
          { label: 'GitHub', href: '#' },
          { label: 'Status', href: '#' },
        ]}
      />
    </div>
  )
}

function SiteMenuPreview() {
  return (
    <div className="flex items-center gap-3 p-5">
      {/* No dev-only rows to suppress: this preview renders INSIDE the Debug console
          (the Site-theme editor), and a "Debug Options" row here would open a second
          console on top of this one — the same recursion the theme switcher is hidden
          for above. The menu used to need a `suppressDevTools` prop to avoid it; the
          row lives at the end of the avatar menu now, and THIS preview — `SiteMenuPreview`,
          which renders only `SiteMenuSwitcher` — has no path to it, so for this preview the
          recursion is impossible by construction rather than opted out of. That claim
          is scoped to this component: `HeaderPreview` above renders `SiteHeader`,
          whose avatar menu does carry the row, and has its own note explaining why. */}
      <SiteMenuSwitcher currentSiteId="hub" />
      <span className="font-mono text-xs text-apt-text-dim">← click to open the menu</span>
    </div>
  )
}

function GlobalPreview() {
  return (
    <div className="space-y-3 p-6">
      <h1 className="text-headline-large">The quick brown fox</h1>
      <p className="text-body-large">
        Body copy in the base font.{' '}
        <a href="#" className="text-apt-gold underline">
          an inline link
        </a>
        , some <mark>highlighted</mark> text, and a sentence you can select to preview
        the selection style.
      </p>
      <p className="font-mono text-sm text-apt-text-muted">Monospace — code &amp; labels.</p>
    </div>
  )
}

function MarketingPreview() {
  return (
    <div className="tep-marketing space-y-4 p-8 text-center">
      <h1 className="text-display-small">Build agentic software, faster.</h1>
      <p className="text-body-large text-apt-text-muted">
        A representative marketing hero (the real landing carries its own classes).
      </p>
      <Button>Get started</Button>
    </div>
  )
}

function ComponentsPreview() {
  return (
    <div className="space-y-4 p-6">
      <div className="flex flex-wrap gap-2">
        <Button>Primary</Button>
        <Button variant="outline">Outline</Button>
        <Button variant="ghost">Ghost</Button>
        <Button variant="destructive">Delete</Button>
      </div>
      <Input placeholder="An input field" />
      <Card className="max-w-sm">
        <CardHeader>
          <CardTitle>Card title</CardTitle>
          <CardDescription>A short description of the card.</CardDescription>
        </CardHeader>
        <CardContent>Card body content.</CardContent>
        <CardFooter>
          <Button size="sm">Action</Button>
        </CardFooter>
      </Card>
    </div>
  )
}

function TypePreview() {
  return (
    <div className="space-y-3 p-6">
      <p className="text-display-small">Display</p>
      <p className="text-headline-large">Headline</p>
      <p className="text-title-large">Title</p>
      <p className="text-body-large">Body text — the quick brown fox jumps over the lazy dog.</p>
      <p className="text-label-large">Label</p>
      <p className="text-code">const code = true</p>
    </div>
  )
}

function CustomPreview() {
  return (
    <div className="space-y-2 p-6 font-mono text-[0.8rem] text-apt-text-muted">
      <p className="text-apt-text">Free-form CSS — any selector, any property.</p>
      <p>
        It is concatenated into the live stylesheet and applies across the whole site, so
        you can target anything the curated sections don&apos;t cover.
      </p>
      <p className="pt-1 text-apt-text-dim">Examples:</p>
      <pre className="overflow-x-auto rounded bg-apt-bg p-2 text-apt-text-dim">{`:root { --type-headline-large-size: 2.5rem; }
.landing-page .adh-header__title { color: #fff; }
[data-slot="button"] { letter-spacing: 0.04em; }`}</pre>
    </div>
  )
}

// The size/line-height/weight trio for a type scale's steps — the props that define
// "how big" text is. Read live so the box shows the theme's current sizes.
const typeVars = (scale: string, steps: string[]): string[] =>
  steps.flatMap((s) => [
    `--type-${scale}-${s}-size`,
    `--type-${scale}-${s}-line-height`,
    `--type-${scale}-${s}-weight`,
  ])

export const THEME_AREAS: ThemeArea[] = [
  {
    id: 'global',
    label: 'Global',
    Preview: GlobalPreview,
    items: [
      // — Base & color —
      {
        id: 'global.base',
        label: 'Base text',
        selector: ':root',
        vars: ['--font-sans', '--font-serif', '--font-mono', '--color-surface', '--color-on-surface'],
        hint: 'Base fonts & background — cascade everywhere',
      },
      {
        id: 'global.brand-colors',
        label: 'Brand colors',
        selector: ':root',
        vars: [
          '--color-primary',
          '--color-primary-bright',
          '--color-on-primary',
          '--color-secondary',
          '--color-tertiary',
          '--color-error',
          '--color-success',
          '--color-warning',
        ],
      },
      {
        id: 'global.surfaces',
        label: 'Surfaces & text',
        selector: ':root',
        vars: [
          '--color-surface',
          '--color-surface-container',
          '--color-surface-container-high',
          '--color-on-surface',
          '--color-on-surface-variant',
          '--color-text-dim',
          '--color-outline',
        ],
      },
      { id: 'global.links', label: 'Links', selector: 'a', props: ['color', 'text-decoration-line'] },
      {
        id: 'global.selection',
        label: 'Selection / highlight',
        selector: '::selection',
        defaultCss: '::selection {\n  background: var(--color-accent-dim);\n  color: var(--color-accent);\n}\n',
      },
      // — Header —
      {
        id: 'global.header-bar',
        label: 'Header bar',
        selector: '.adh-header',
        props: ['background-color', 'border-bottom-color', 'box-shadow'],
        Preview: HeaderPreview,
      },
      {
        id: 'global.header-title',
        label: 'Header title',
        selector: '.adh-header__title',
        props: ['color', 'font-family', 'font-size', 'font-weight', 'font-style', 'letter-spacing'],
        Preview: HeaderPreview,
      },
      {
        id: 'global.header-nav',
        label: 'Header nav links',
        selector: '.adh-header__nav-link',
        props: ['color', 'font-family', 'font-size', 'letter-spacing', 'text-transform'],
        Preview: HeaderPreview,
      },
      {
        id: 'global.header-badges',
        label: 'Header badges',
        selector: '.adh-header__badge',
        props: ['color', 'background-color', 'border-color', 'border-radius', 'font-size'],
        Preview: HeaderPreview,
      },
      {
        id: 'global.auth-menu',
        label: 'Authenticated menu',
        selector: '.adh-avatar-menu-trigger',
        props: ['color', 'background-color', 'border-color', 'border-radius'],
        Preview: HeaderPreview,
      },
      // — Footer —
      {
        id: 'global.footer-bar',
        label: 'Footer bar',
        selector: '.adh-footer',
        props: ['background-color', 'border-top-color', 'color'],
        Preview: FooterPreview,
      },
      {
        id: 'global.footer-text',
        label: 'Footer text',
        selector: '.adh-footer__copyright',
        props: ['color', 'font-family', 'font-size', 'letter-spacing'],
        Preview: FooterPreview,
      },
      {
        id: 'global.footer-links',
        label: 'Footer links',
        selector: '.adh-footer__link',
        props: ['color', 'font-family', 'font-size'],
        Preview: FooterPreview,
      },
      {
        id: 'global.footer-brand',
        label: 'Footer brand',
        selector: '.adh-footer__brand-link',
        props: ['color', 'font-weight'],
        Preview: FooterPreview,
      },
      // — Site menu —
      {
        id: 'global.menu-trigger',
        label: 'Site-menu trigger',
        selector: '.adh-nav-popover__trigger',
        props: ['color', 'font-family', 'font-size'],
        Preview: SiteMenuPreview,
      },
      {
        id: 'global.menu-items',
        label: 'Site-menu items',
        selector: '.adh-dropdown-menu__item',
        defaultCss:
          '.adh-dropdown-menu__item {\n  color: var(--color-text-primary);\n  font-family: var(--font-mono);\n}\n',
        Preview: SiteMenuPreview,
      },
      // — Shared components —
      {
        id: 'global.buttons',
        label: 'Buttons',
        selector: '[data-slot="button"]',
        props: ['color', 'background-color', 'border-radius', 'font-weight', 'padding'],
        Preview: ComponentsPreview,
      },
      {
        id: 'global.cards',
        label: 'Cards',
        selector: '[data-slot="card"]',
        props: ['background-color', 'border-color', 'border-radius', 'color'],
        Preview: ComponentsPreview,
      },
      {
        id: 'global.inputs',
        label: 'Inputs',
        selector: '[data-slot="input"]',
        props: ['background-color', 'border-color', 'border-radius', 'color', 'height'],
        Preview: ComponentsPreview,
      },
    ],
  },
  {
    id: 'type',
    label: 'Typography',
    Preview: TypePreview,
    items: [
      { id: 'type.display', label: 'Display', selector: ':root', vars: typeVars('display', ['large', 'medium', 'small']) },
      { id: 'type.headline', label: 'Headline', selector: ':root', vars: typeVars('headline', ['large', 'medium', 'small']) },
      { id: 'type.title', label: 'Title', selector: ':root', vars: typeVars('title', ['large', 'medium', 'small']) },
      { id: 'type.body', label: 'Body', selector: ':root', vars: typeVars('body', ['large', 'medium', 'small']) },
      { id: 'type.label', label: 'Label', selector: ':root', vars: typeVars('label', ['large', 'medium', 'small']) },
      { id: 'type.code', label: 'Code', selector: ':root', vars: ['--type-code-size', '--type-code-line-height', '--type-code-weight'] },
    ],
  },
  {
    id: 'marketing',
    label: 'Marketing landing',
    Preview: MarketingPreview,
    items: [
      { id: 'marketing.hero', label: 'Hero heading', selector: '.tep-marketing h1', props: ['color', 'font-family', 'font-size', 'font-weight'] },
      { id: 'marketing.cta', label: 'Call to action', selector: '.tep-marketing [data-slot="button"]', props: ['color', 'background-color', 'border-radius'] },
    ],
  },
  {
    id: 'custom',
    label: 'Custom CSS',
    Preview: CustomPreview,
    items: [
      {
        id: 'custom.css',
        label: 'Custom CSS',
        selector: '',
        defaultCss:
          '/* Free-form CSS — any selector, any property. Applies across the whole site.\n' +
          '   Examples:\n' +
          '     :root { --type-headline-large-size: 2.5rem; }\n' +
          '     .landing-page .adh-header__title { color: #fff; }\n' +
          '*/\n',
      },
    ],
  },
]

/** Build the "current css" for an item — read LIVE so it reflects the selected theme.
 *  `:root` vars come from the document element; component props from the first element
 *  matching the selector, PREFERRING `scope` (the rendered example container) so the
 *  css shown matches the example. Falls back to `defaultCss` (or a bare rule) when
 *  nothing is readable — e.g. a pseudo-element or a closed menu. */
export function readItemCss(item: ThemeItem, scope?: ParentNode | null): string {
  const fallback = item.defaultCss ?? `${item.selector} {\n  \n}\n`
  if (typeof document === 'undefined') return fallback
  const fmt = (decls: string[]) =>
    decls.length ? `${item.selector} {\n${decls.map((d) => `  ${d}`).join('\n')}\n}\n` : fallback

  if (item.vars?.length) {
    const cs = getComputedStyle(document.documentElement)
    return fmt(
      item.vars
        .map((v) => [v, cs.getPropertyValue(v).trim()] as const)
        .filter(([, val]) => val)
        .map(([v, val]) => `${v}: ${val};`),
    )
  }
  if (item.props?.length) {
    let el: Element | null = null
    try {
      el = (scope ?? document).querySelector(item.selector) ?? document.querySelector(item.selector)
    } catch {
      el = null
    }
    if (el) {
      const cs = getComputedStyle(el)
      return fmt(
        item.props
          .map((p) => [p, cs.getPropertyValue(p).trim()] as const)
          .filter(([, val]) => val)
          .map(([p, val]) => `${p}: ${val};`),
      )
    }
  }
  return fallback
}
