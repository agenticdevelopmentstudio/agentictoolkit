'use client'

import {
  Fragment,
  useCallback,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type KeyboardEvent,
  type MouseEvent,
  type ReactElement,
  type ReactNode,
} from 'react'
import { ChevronDown } from 'lucide-react'
import { type NavLinkIcon } from './NavLink'
import { cn, noAutofillProps } from '@agenticdevelopertoolkit/ui'
import {
  confirmNavigation,
  GUARDED_NAV_ATTR,
  isModifiedClick,
} from '@agenticdevelopertoolkit/ui/lib/navigation-guard'
import { useShortcut, chordFromEvent, sameChord } from '@agenticdevelopertoolkit/ui/hooks/useShortcut'
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubTrigger,
  DropdownMenuSubContent,
} from '@agenticdevelopertoolkit/ui/components/dropdown-menu'

// The menu rows are real <a href> links but navigate PROGRAMMATICALLY through
// chooseItem (to match the keyboard path / SSO rewriting), which consults the
// navigation-guard registry itself. This attribute tells an UnsavedChangesGuard's
// document click-interceptor to leave these anchors alone — otherwise a dirty page
// would prompt twice (once from the interceptor, once from chooseItem).
const GUARDED_NAV_PROPS = { [GUARDED_NAV_ATTR]: '' }

/** An icon component for a menu row.
 *
 *  Deliberately NOT lucide's `LucideIcon`. Every caller that fills this in lives in
 *  another package with its OWN lucide-react + @types/react copy (a consumer's icon
 *  map is normally in its own pnpm tree, not this one), and `LucideIcon` is a
 *  `ForwardRefExoticComponent` whose `ref` bottoms out in @types/react's nominal
 *  `UNDEFINED_VOID_ONLY` symbol — so a foreign lucide icon fails to assign with
 *  "Two different types with this name exist, but they are unrelated." Same problem
 *  and same remedy as {@link NavLinkIcon}, which this is an alias of: accept any
 *  className-bearing component. */
export type PopoverIcon = NavLinkIcon

/** One row. `href` makes the row a real link (middle-click / open-in-new-tab work).
 *  `onSelect` makes it an action rather than a destination — it runs INSTEAD of
 *  navigation (no `href` needed) and takes priority over the popover's `onChoose`, so a
 *  single popover can mix links with commands (Help, opening the help panel). A row with
 *  NEITHER has nothing to do when chosen: it is still a menuitem the arrow keys land on,
 *  and Enter or a click on it closed the menu and went nowhere — which is what the
 *  "Loading…" and "No workspaces yet" rows did. A line of text in the list is a
 *  {@link PopoverNotice}, never an item. `key` is a stable per-instance id; `current`
 *  flags the user's current location (aria-current); `description` is an optional
 *  tagline; `icon` is an optional leading glyph. */
export type PopoverItem = {
  key: string
  label: string
  description?: string
  href?: string
  current?: boolean
  /** Optional leading icon, rendered in a fixed-width slot before the label. */
  icon?: PopoverIcon
  onSelect?: () => void
}

/** A top-level entry: either a leaf row, or a topic that opens a flyout submenu.
 *  `section` groups entries for dividers — a divider falls between sections,
 *  never within one. `blurb` shows a leaf's description inline. `indent` renders
 *  the row as an always-visible inline sub-item (indented under the row above it);
 *  a topic's `icon` is its own leading glyph. */
export type PopoverEntry =
  | { kind: 'leaf'; section: number; item: PopoverItem; blurb?: boolean; indent?: boolean }
  | {
      kind: 'topic'
      section: number
      label: string
      items: PopoverItem[]
      icon?: PopoverIcon
      indent?: boolean
      /** Makes the topic's own trigger a destination as well as a disclosure: the
       *  row becomes a real `<a>` (middle-click / open-in-new-tab work), a plain
       *  click navigates, and Enter on the highlighted row navigates instead of
       *  opening. Hover and → still open the flyout either way. Omit for a pure
       *  grouping header. */
      href?: string
      /** Trailing tagline on the trigger row, right-aligned like a leaf's. */
      description?: string
      /** Flags the trigger as the user's current location (aria-current). */
      current?: boolean
    }

/** A line of text standing where rows would be — "Loading…", "No workspaces yet", "Couldn't
 *  load your workspaces". NOT a row: never highlighted, never reached by the arrow keys, never
 *  searched, never chosen, and not a menuitem to assistive tech. It is a polite status instead,
 *  so a notice whose text changes while the menu is open (loading → failed) is announced.
 *  `section` places it among the rows exactly like an entry (dividers and headings included);
 *  `key` is its identity, and keeping it across a text change is what keeps it ONE live region.
 *
 *  Its own type rather than a flag on {@link PopoverItem}, because an item is a thing you can
 *  choose — the empty and loading states were items once, and each was a menuitem that closed
 *  the menu and went nowhere. */
export type PopoverNotice = { kind: 'notice'; section: number; key: string; text: string }

/** Everything the list can hold: the rows, and the notices that stand in for rows that are
 *  not there. {@link PopoverEntry} stays rows-only, so code that walks a menu's ROWS
 *  (useSiteMenu, anything narrowing on `kind`) never has to account for a line of text. */
export type PopoverListEntry = PopoverEntry | PopoverNotice

/** Imperative handle handed to slot render-props so they can close the menu —
 *  optionally WITHOUT restoring focus to the trigger, when they're handing focus
 *  off to another surface (a dialog/popover) that owns Escape-to-dismiss. */
export type PopoverClose = (opts?: { restoreFocus?: boolean }) => void

/** An optional special command surfaced while searching (e.g. "help"). When
 *  `matches(query)` is true the list shows a single command row instead of search
 *  results; selecting it closes the menu (focus not restored) then runs `onSelect`. */
export type PopoverSearchCommand = {
  matches: (query: string) => boolean
  label: ReactNode
  shortcut?: ReactNode
  onSelect: () => void
}

export type NavigationPopoverProps = {
  /** The ordered top-level entries (resolved: hrefs + current flags applied), with any
   *  {@link PopoverNotice} placed among them where the rows it stands in for would be. */
  entries: PopoverListEntry[]
  /** Accessible label for the trigger button (e.g. "Storage — switch site"). */
  triggerLabel: string
  /** Replaces the trigger's default "{label} ⌄" content. */
  triggerContent?: ReactNode
  /** Short text shown inside the default trigger before the chevron. */
  triggerText?: string
  /** Optional icon rendered before the default trigger's text (ignored when
   *  `triggerContent` replaces the default). SiteMenu passes the brand mark. */
  triggerIcon?: ReactNode
  /** Extra class on the trigger button. */
  triggerClassName?: string
  /** Command-field placeholder + its accessible name. */
  placeholder?: string
  /** Empty-state line when a search matches nothing. */
  emptyLabel?: string
  /** Invoked to navigate to a chosen item. Defaults to a full-page assign to the
   *  item's href — subclasses override for SPA navigation. */
  onChoose?: (item: PopoverItem) => void
  /** Trailing control in the command row (e.g. a help "?" or settings gear).
   *  Receives `close` so it can dismiss the menu before handing focus off. */
  commandTrailing?: (api: { close: PopoverClose }) => ReactNode
  /** Optional special search command (see {@link PopoverSearchCommand}). */
  searchCommand?: PopoverSearchCommand
  /** Content pinned below the list, under a divider — a signature line rather than
   *  a row (SiteMenu puts the studio wordmark here). Outside `entries` on purpose:
   *  it is not keyboard-navigable, not searchable and never highlighted, so it can
   *  neither be reached by the arrow keys nor swallow an Enter meant for a
   *  destination. It sits outside the scrolling list too, so it stays visible on a
   *  menu long enough to scroll. */
  footer?: ReactNode
  /** A heading above a section's first entry, keyed by `section` — "Workspaces" over
   *  the workspace rows, say. Browse only: search results are one flat list with each
   *  row's area already spelled out, so a heading there would label nothing. Not a row:
   *  never highlighted, never reached by the arrow keys. */
  sectionLabels?: Partial<Record<number, string>>
  /** A chord that TOGGLES the menu, in `@agenticdevelopertoolkit/ui/hooks/useShortcut`
   *  spelling — `'mod+shift+k'`, say. Omit (or pass `''`) for no shortcut, which is
   *  what every popover that isn't the site menu wants: two popovers registering the
   *  same chord would race, and the registry's most-recent-wins tie-break would hand
   *  the win to whichever mounted last. Toggling rather than opening is deliberate —
   *  a chord the user can only press one way is a chord they have to reach for the
   *  mouse to undo. */
  openShortcut?: { keys: string; label: string }
}

/** Wrap every case-insensitive occurrence of `query` in `text` so the matched
 *  characters can be underlined (autocomplete). Returns the text unchanged when
 *  there's no query or no match. */
function highlightMatch(text: string, query: string): ReactNode {
  const needle = query.trim()
  if (!needle) return text
  const lower = text.toLowerCase()
  const ln = needle.toLowerCase()
  const out: ReactNode[] = []
  let i = 0
  let key = 0
  while (i < text.length) {
    const at = lower.indexOf(ln, i)
    if (at === -1) {
      out.push(text.slice(i))
      break
    }
    if (at > i) out.push(text.slice(i, at))
    out.push(
      <span key={key++} className="adh-nav-popover__hl">
        {text.slice(at, at + needle.length)}
      </span>,
    )
    i = at + needle.length
  }
  return out
}

/** The fixed-width leading icon slot for a row — muted, sized to the label line,
 *  never shrinking. Renders nothing when the row has no icon (the slot collapses,
 *  so iconless menus look exactly as before). */
function IconSlot({ icon: Icon }: { icon?: PopoverIcon }): ReactNode {
  if (!Icon) return null
  return <Icon className="adh-dropdown-menu__item-icon adh-nav-popover__icon" aria-hidden />
}

/** A navigable topic's TRIGGER, expressed as an ordinary row. Selecting it runs
 *  through the same `chooseItem` path as every other destination — so SPA
 *  navigation and SSO href rewriting apply identically — instead of a second,
 *  divergent navigation path that would drift from the leaves. */
function topicItem(entry: Extract<PopoverEntry, { kind: 'topic' }>): PopoverItem {
  return {
    key: `topic:${entry.label}`,
    label: entry.label,
    description: entry.description,
    href: entry.href,
    icon: entry.icon,
    current: entry.current,
  }
}

/** Should a row click be left alone rather than intercepted for in-app navigation?
 *  A modified or non-primary click is the browser's (new tab / download), and one
 *  that something earlier already handled (`defaultPrevented`) is not ours to turn
 *  into a navigation either. The modifier rule is the shared {@link isModifiedClick};
 *  `defaultPrevented` is this menu's own addition, so it is spelled here. */
function leaveClickAlone(event: MouseEvent): boolean {
  return event.defaultPrevented || isModifiedClick(event)
}

// The browse highlight as ONE value, so illegal combinations (a submenu item
// highlighted while its flyout is closed, a sub cursor with no entry, …) cannot
// be represented. `entry` indexes `entries`; `item` indexes a topic's `items`.
type NavState =
  | { kind: 'none' }
  | { kind: 'top'; entry: number; open: boolean }
  | { kind: 'sub'; entry: number; item: number }

/**
 * A header command menu: a trigger that opens a popover whose top level mixes
 * promoted leaf links and TOPICS — each a cascading submenu that pops out to the
 * side. Nothing is disclosed or selected until the user acts: hover a topic, or
 * press ↓ to start. Focus stays in the command field, which drives the highlight
 * in a two-level model: ↑/↓ move the highlight (walking the top-level entries,
 * or — once inside an open submenu — that submenu's items, then SPILLING into the
 * adjacent topic's submenu at the edges); → opens the highlighted topic and steps
 * into it; ← closes it again (→ reopens). Enter navigates the highlight (or opens
 * a closed topic). Typing switches to a flat autocomplete across EVERY item
 * (case-insensitive substring, matched chars underlined), each result shown as
 * "{area} → {item}".
 *
 * This is the reusable base behind the header's switchers: {@link SiteMenu} (the
 * family launcher), {@link WorkspaceMenu} (the signed-in hub's workspaces) and
 * {@link SiteSwitcher} (a plain caller-supplied site list). Subclasses supply the
 * resolved {@link PopoverEntry} structure, the trigger content, how to navigate a
 * chosen item, and any command-row trailing control / special search command.
 */
export function NavigationPopover({
  entries,
  triggerLabel,
  triggerContent,
  triggerText,
  triggerIcon,
  triggerClassName,
  placeholder = 'Search, or browse topics',
  emptyLabel = 'No matches',
  onChoose,
  commandTrailing,
  searchCommand,
  footer,
  sectionLabels,
  openShortcut,
}: NavigationPopoverProps): ReactElement {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  // Browse highlight — ONE discriminated-union cursor (see NavState): nothing,
  // a top-level row (with whether its topic flyout is disclosed), or an item
  // inside a topic's flyout. ↑/↓ move it (spilling across adjacent submenus at
  // the edges); → opens the highlighted topic and steps in; ← closes it.
  // `searchIndex` is the autocomplete cursor. All reset on open.
  const [nav, setNav] = useState<NavState>({ kind: 'none' })
  const [searchIndex, setSearchIndex] = useState(0)
  const inputRef = useRef<HTMLInputElement>(null)
  // Per-instance id namespace, so two popovers on one page don't collide on row ids /
  // aria-controls, and the scroll effect's getElementById targets THIS instance's rows.
  const uid = useId()
  // Only auto-scroll the highlight into view when it moved by keyboard/typing —
  // never on mouse hover, which would let scrollIntoView shift a new row under
  // a near-stationary cursor and chase the pointer (jitter loop).
  const navByKeyboard = useRef(false)
  // Set while handing focus off to another surface (dialog/popover) so the menu's
  // close doesn't yank focus back to its trigger (which would pull focus out of
  // the target and break its native Escape-to-dismiss).
  const suppressFocusRestore = useRef(false)

  // Close the menu. `restoreFocus: false` keeps the menu from returning focus to
  // the trigger, so a trailing control / command can move focus onto another surface.
  const close = useCallback<PopoverClose>((opts) => {
    if (opts?.restoreFocus === false) suppressFocusRestore.current = true
    setOpen(false)
  }, [])

  // The optional global chord (see `openShortcut`). Registered unconditionally with
  // `enabled` carrying the on/off, because mounting the hook conditionally is what
  // React forbids — and `enabled: false` also keeps a menu with no chord out of the
  // enumerated shortcut list, rather than advertising an empty binding.
  // `allowInInput` is on: the whole point of a site-switch chord is to reach it from
  // wherever you are, and the command field of the menu it opens is itself a text
  // field, so without this the chord could open the menu but never close it again.
  // An absent chord is spelled `''`, which parses to a key no keydown can report — so the
  // registration is inert twice over, by `enabled` and by the chord itself. The registry
  // preventDefaults a match before it runs the handler, so there is nothing to do here but
  // flip the state.
  useShortcut(
    {
      keys: openShortcut?.keys ?? '',
      label: openShortcut?.label ?? '',
      group: 'Navigation',
      allowInInput: true,
      enabled: Boolean(openShortcut?.keys),
    },
    () => setOpen((cur) => !cur),
  )

  // ...and the same chord again, from INSIDE the open menu. The popup stops keydown
  // from propagating past its own portal container, so the document-level registration
  // above never sees a press made while focus is in the menu — which, since the menu
  // takes focus when it opens, is every press meant to close it again. `allowInInput`
  // does not help: the event does not reach the registry at all. Capture phase, so a
  // chord built on a key the command field handles (Enter, an arrow) still gets here
  // before `handleInputKeyDown` stops it.
  const closeOnShortcut = useCallback(
    (event: KeyboardEvent<HTMLDivElement>): void => {
      const keys = openShortcut?.keys
      if (!keys) return
      const chord = chordFromEvent(event.nativeEvent)
      if (chord === null || !sameChord(chord, keys)) return
      event.preventDefault()
      setOpen(false)
    },
    [openShortcut?.keys],
  )

  // Navigate to a chosen item, then close. Default is a full-page assign (matches
  // cross-site switching); subclasses pass `onChoose` for SPA navigation.
  const chooseItem = useCallback(
    (item: PopoverItem) => {
      setOpen(false)
      if (item.onSelect) {
        // Action rows run instead of navigating — no href, no onChoose.
        item.onSelect()
        return
      }
      if (onChoose) {
        // The SPA path (e.g. useSiteMenu's navigate) consults confirmNavigation itself.
        onChoose(item)
        return
      }
      // Default full-page path: clear any active navigation guard first, since the
      // anchors carry GUARDED_NAV_PROPS so the document interceptor skips them.
      if (item.href && item.href !== '#') {
        const href = item.href
        void confirmNavigation().then((ok) => {
          if (ok) window.location.assign(href)
        })
      }
    },
    [onChoose],
  )

  // The autocomplete searches the entries themselves: every destination, labelled
  // with its topic group as the "area" (top-level leaves have no area).
  const searchTargets = useMemo(() => {
    const out: { item: PopoverItem; area: string | null }[] = []
    for (const e of entries) {
      if (e.kind === 'topic') {
        // A NAVIGABLE topic is a destination in its own right, so it has to be
        // findable like one — otherwise the rows that both group and go somewhere
        // (Hub, Personas, …) are the only destinations in the menu the filter box
        // cannot reach, and typing their own name lists their children instead of
        // them. No `area`: it IS a top-level row, not something under one. First,
        // so it precedes the children it names.
        if (e.href !== undefined) out.push({ item: topicItem(e), area: null })
        for (const item of e.items) out.push({ item, area: e.label })
      } else if (e.kind === 'leaf') {
        out.push({ item: e.item, area: null })
      }
      // A notice is not a destination, so it is never a search result: typing "load" into
      // a menu that is still loading must not offer "Loading…" as somewhere to go.
    }
    return out
  }, [entries])

  const searchResults = useMemo(() => {
    const needle = query.trim().toLowerCase()
    if (!needle) return []
    return searchTargets.filter(
      (t) =>
        t.item.label.toLowerCase().includes(needle) ||
        (t.item.description?.toLowerCase().includes(needle) ?? false),
    )
  }, [searchTargets, query])

  // Typing overlays a flat autocomplete; otherwise browse.
  const trimmed = query.trim()
  const searching = trimmed.length > 0
  const cmdActive = searching && (searchCommand?.matches(trimmed) ?? false)
  const searchActive =
    searchResults.length === 0 ? -1 : Math.min(searchIndex, searchResults.length - 1)

  // Run the special search command: close (releasing focus) then hand off.
  const selectCommand = useCallback(() => {
    if (!searchCommand) return
    close({ restoreFocus: false })
    searchCommand.onSelect()
  }, [close, searchCommand])

  // Pointer moved onto the menu's non-row CHROME — the command field, the footer,
  // the empty-state line, a notice. Those sit inside the popup but are not rows, so
  // `DropdownMenuContent`'s onMouseLeave never fires for them and a topic disclosed on
  // the way down stays disclosed, looking exactly as if the pointer were still on its
  // row. Clearing the cursor closes the flyout and drops the row highlight together.
  //
  // Deliberately NOT hung on the content or the list itself: a row's own onMouseMove
  // BUBBLES, so a parent handler would run after it and its `{ kind: 'none' }` would
  // win, killing hover disclosure entirely. Only the chrome elements carry it.
  //
  // Guarded on `navByKeyboard` for the same reason onMouseLeave leaves 'sub' alone: if
  // the cursor is merely resting on the chrome while someone arrows around, the browser
  // still emits a mousemove for an incidental jiggle, and stealing their highlight for
  // it would be worse than the bug this fixes.
  const leaveRows = useCallback(() => {
    if (navByKeyboard.current) return
    setNav((cur) => (cur.kind === 'none' ? cur : { kind: 'none' }))
  }, [])

  // Which topic's flyout is open — the controlled `open` for each DropdownMenuSub.
  const disclosed =
    nav.kind === 'sub' ? nav.entry : nav.kind === 'top' && nav.open ? nav.entry : null
  // Stable key of the highlighted row (for scroll-into-view + aria-activedescendant):
  // "cmd"/"s<i>" while searching, else "e<entry>" / "e<entry>s<item>". Row ids are
  // `${uid}-${key}` so they're unique per popover instance.
  const activeKey = searching
    ? cmdActive
      ? 'cmd'
      : searchActive >= 0
        ? `s${searchActive}`
        : null
    : nav.kind === 'sub'
      ? `e${nav.entry}s${nav.item}`
      : nav.kind === 'top'
        ? `e${nav.entry}`
        : null
  const activeId = activeKey ? `${uid}-${activeKey}` : undefined

  // Keep focus on the command field while the menu is open so it keeps owning
  // the keyboard. Runs on open (the engine's own open-focus would land on the
  // first item) and again whenever a flyout opens/steps (the engine moves focus
  // to the sub-trigger/content) — the rAF runs after that move so the input wins.
  useEffect(() => {
    if (!open) return
    const frame = requestAnimationFrame(() => {
      if (document.activeElement !== inputRef.current) inputRef.current?.focus()
    })
    return () => cancelAnimationFrame(frame)
  }, [open, nav, searching])

  // Keep the keyboard-highlighted row scrolled into view as it moves (a DOM side
  // effect, not state sync). Skipped for mouse-driven highlight changes. Targets
  // THIS instance's row by namespaced id via getElementById (submenu rows are
  // portaled outside the list, so a list-scoped query can't reach them; the uid
  // prefix keeps it from matching another popover's rows). `query` is a dep so a
  // filter that narrows results while searchActive stays the same still re-scrolls.
  useEffect(() => {
    if (!navByKeyboard.current || !activeKey) return
    document.getElementById(`${uid}-${activeKey}`)?.scrollIntoView({ block: 'nearest' })
  }, [uid, activeKey, query])

  // ↑/↓ move the highlight ONLY — they never open or close a submenu via the
  // top level. Inside an open submenu they walk that submenu's items; at an edge
  // they SPILL into the immediately adjacent sibling topic's submenu (skipping
  // leaf siblings) — ↓ off the bottom opens the next topic at its TOP item, ↑ off
  // the top opens the previous topic at its BOTTOM item; a non-topic sibling ⇒ no
  // change (no wrap). At the top level they walk the entries, wrapping, and
  // collapse any open submenu so the highlight never sits on an orphaned flyout.
  // A notice is stepped over: it is text, not a row, and a highlight resting on it
  // would be a row Enter could "choose".
  function moveSel(dir: 1 | -1): void {
    navByKeyboard.current = true
    if (nav.kind === 'sub') {
      const entry = entries[nav.entry]
      if (entry?.kind === 'topic') {
        const next = nav.item + dir
        if (next >= 0 && next < entry.items.length) {
          setNav({ kind: 'sub', entry: nav.entry, item: next }) // within this submenu
          return
        }
        // At an edge: spill into the adjacent sibling topic's submenu, entering
        // at the near end. A non-topic (or absent) sibling ⇒ stay put.
        const siblingIdx = nav.entry + dir
        const sibling = entries[siblingIdx]
        if (sibling?.kind === 'topic') {
          setNav({ kind: 'sub', entry: siblingIdx, item: dir > 0 ? 0 : sibling.items.length - 1 })
        }
        return
      }
    }
    // Top level: walk the entries (wrapping), highlight the row WITHOUT opening
    // its flyout (→ opens). Collapses any open flyout.
    const n = entries.length
    if (!n) return
    const cur = nav.kind === 'none' ? null : nav.entry
    let nextEntry = cur === null ? (dir > 0 ? 0 : n - 1) : (cur + dir + n) % n
    for (let hops = 0; hops < n && entries[nextEntry]?.kind === 'notice'; hops++) {
      nextEntry = (nextEntry + dir + n) % n
    }
    // Nothing but notices (a list with no rows at all): there is nothing to highlight.
    if (entries[nextEntry]?.kind === 'notice') return
    setNav({ kind: 'top', entry: nextEntry, open: false })
  }

  // → discloses the highlighted topic's submenu and steps INTO it (first item).
  // No-op on a leaf, with nothing selected, or when already inside a submenu — it
  // only ever opens, never moves the highlight up/down.
  function discloseRight(): void {
    if (nav.kind !== 'top') return
    if (entries[nav.entry]?.kind !== 'topic') return
    navByKeyboard.current = true
    setNav({ kind: 'sub', entry: nav.entry, item: 0 })
  }

  // ← closes the open submenu/flyout and returns the highlight to its topic
  // header (kept selected). No movement up/down. No-op when nothing is open.
  function collapseLeft(): void {
    navByKeyboard.current = true
    if (nav.kind === 'sub' || (nav.kind === 'top' && nav.open)) {
      setNav({ kind: 'top', entry: nav.entry, open: false })
    }
  }

  // Activate the highlight: a submenu item or a leaf navigates and closes the
  // menu; a highlighted (closed) topic opens its submenu instead; the special
  // search command runs its handler.
  function choose(): void {
    if (searching) {
      if (cmdActive) {
        selectCommand()
        return
      }
      const target = searchResults[searchActive]?.item
      if (!target) return // no match highlighted ⇒ Enter is a no-op, keep menu open
      chooseItem(target)
      return
    }
    if (nav.kind === 'none') return
    const entry = entries[nav.entry]
    // moveSel steps over a notice, so the highlight never rests on one; this keeps a
    // stale cursor (the list changed under it) from turning text into a choice.
    if (!entry || entry.kind === 'notice') return
    if (nav.kind === 'top') {
      if (entry.kind === 'topic') {
        // A NAVIGABLE topic is a destination that also groups: Enter goes there,
        // matching both the leaf row below and what clicking the row does. → still
        // opens the flyout (discloseRight is bound to ArrowRight), so disclosure
        // stays reachable from the keyboard. A pure grouping header has nowhere of
        // its own to go, so Enter opens it, as it always did.
        if (entry.href) {
          chooseItem(topicItem(entry))
          return
        }
        discloseRight()
        return
      }
      chooseItem(entry.item) // leaf
      return
    }
    // nav.kind === 'sub' — navigate the highlighted submenu item
    if (entry.kind === 'topic') {
      const item = entry.items[nav.item]
      if (item) chooseItem(item)
    }
  }

  // Each open starts fresh: empty filter, nothing disclosed, nothing selected.
  function handleOpenChange(next: boolean): void {
    setOpen(next)
    if (next) {
      setQuery('')
      setNav({ kind: 'none' })
      setSearchIndex(0)
    }
  }

  // The input owns every keystroke so it can drive the highlight while staying
  // focused (the submenus open beside it). stopPropagation keeps the menu's
  // built-in typeahead + roving focus from also acting. ↑/↓ move the highlight;
  // ←/→ close/open the highlighted topic's submenu (never moving the highlight).
  // With a query, ←/→ move the text caret instead. Escape bubbles so the menu
  // dismisses.
  function handleInputKeyDown(event: KeyboardEvent<HTMLInputElement>): void {
    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault()
        event.stopPropagation()
        navByKeyboard.current = true
        if (searching) setSearchIndex(Math.min(searchActive + 1, searchResults.length - 1))
        else moveSel(1)
        break
      case 'ArrowUp':
        event.preventDefault()
        event.stopPropagation()
        navByKeyboard.current = true
        if (searching) setSearchIndex(Math.max(searchActive - 1, 0))
        else moveSel(-1)
        break
      case 'ArrowRight':
        if (!searching) {
          event.preventDefault()
          event.stopPropagation()
          discloseRight()
        } else {
          event.stopPropagation()
        }
        break
      case 'ArrowLeft':
        if (!searching) {
          event.preventDefault()
          event.stopPropagation()
          collapseLeft()
        } else {
          event.stopPropagation()
        }
        break
      case 'Enter':
        event.preventDefault()
        event.stopPropagation()
        choose()
        break
      case 'Tab':
        // Keep focus in the command field — without this, Tab moves focus onto a
        // row, desyncing it from the highlight. Escape closes.
        event.preventDefault()
        event.stopPropagation()
        break
      case 'Escape':
        break
      default:
        // Printable keys (incl. Home/End, which edit the query text): keep them
        // in the input, away from the menu typeahead.
        event.stopPropagation()
    }
  }

  // A single destination row inside a topic's submenu flyout. The href makes it a
  // real link (middle-click / open-in-new-tab work); a plain left-click is routed
  // through chooseItem so SPA/SSO rewriting matches the keyboard path. (entryIndex,
  // j) ties it to the keyboard cursor; hovering selects it and keeps its submenu
  // open. Hover-select fires on mouseMOVE, not mouseENTER, so the synthetic enter
  // that fires when a keyboard-driven scroll slides a row under a STILL cursor
  // can't hijack the highlight — mousemove only fires when the pointer moves.
  function renderItem(item: PopoverItem, entryIndex: number, j: number): ReactNode {
    const isActive = nav.kind === 'sub' && nav.entry === entryIndex && nav.item === j
    return (
      <a
        key={`${item.key}-${entryIndex}-${j}`}
        id={`${uid}-e${entryIndex}s${j}`}
        data-nav={`e${entryIndex}s${j}`}
        role="menuitem"
        aria-current={item.current ? 'page' : undefined}
        href={item.href}
        {...GUARDED_NAV_PROPS}
        className={cn('adh-dropdown-menu__item', {
          'adh-nav-popover__item--active': isActive,
          'adh-nav-popover__item--current': item.current,
        })}
        // Selecting with the pointer must not pull focus out of the command
        // field (which drives the highlight); the click still navigates.
        onMouseDown={(event) => event.preventDefault()}
        onMouseMove={() => {
          navByKeyboard.current = false
          setNav({ kind: 'sub', entry: entryIndex, item: j })
        }}
        onClick={(event) => {
          if (leaveClickAlone(event)) return
          event.preventDefault()
          chooseItem(item)
        }}
      >
        <IconSlot icon={item.icon} />
        <span className="adh-nav-popover__link-name">{item.label}</span>
        {item.description && (
          <span className="adh-dropdown-menu__shortcut">{item.description}</span>
        )}
      </a>
    )
  }

  return (
    // Controlled so `close()` actually closes the menu — trailing controls and
    // the search command both close it programmatically before handing off.
    <DropdownMenu open={open} onOpenChange={handleOpenChange}>
      <DropdownMenuTrigger
        className={cn('adh-header__title adh-nav-popover__trigger', triggerClassName)}
        aria-label={triggerLabel}
      >
        {triggerContent ?? (
          <>
            {triggerIcon}
            <span>{triggerText ?? triggerLabel}</span>
            <ChevronDown className="adh-nav-popover__chevron" aria-hidden />
          </>
        )}
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align="start"
        className="adh-nav-popover__menu"
        onKeyDownCapture={closeOnShortcut}
        // Close a hover-opened topic flyout when the pointer genuinely leaves the
        // menu (not when it crosses into the portaled flyout — relatedTarget is
        // then still inside a [role="menu"]). Keyboard-driven 'sub' state is left
        // alone so arrowing isn't disturbed by an idle cursor leaving.
        onMouseLeave={(event) => {
          const to = event.relatedTarget
          if (to instanceof Element && to.closest('[role="menu"]')) return
          setNav((cur) =>
            cur.kind === 'top' && cur.open ? { kind: 'top', entry: cur.entry, open: false } : cur,
          )
        }}
        finalFocus={() => {
          // When handing focus off to another surface, don't let the menu
          // restore focus to the trigger — keep it free so the handoff can
          // move it. (`false` = leave focus where it is.)
          if (suppressFocusRestore.current) {
            suppressFocusRestore.current = false
            return false
          }
          return true
        }}
      >
        <div className="adh-nav-popover__search" onMouseMove={leaveRows}>
          <span className="adh-nav-popover__prompt" aria-hidden>
            &gt;
          </span>
          <input
            ref={inputRef}
            type="text"
            className="adh-nav-popover__search-input"
            placeholder={placeholder}
            aria-label={placeholder}
            role="combobox"
            aria-expanded
            aria-controls={`${uid}-list`}
            // Announce the keyboard-highlighted row to assistive tech (focus
            // stays in this input; the rows carry matching `${uid}-…` ids).
            aria-activedescendant={activeId}
            {...noAutofillProps}
            spellCheck={false}
            value={query}
            onChange={(event) => {
              navByKeyboard.current = true
              setQuery(event.target.value)
              setSearchIndex(0)
              // Entering/leaving search resets the browse cursor, so a topic
              // disclosed before typing doesn't spring back open on clear.
              setNav({ kind: 'none' })
            }}
            onKeyDown={handleInputKeyDown}
          />
          {commandTrailing?.({ close })}
        </div>
        <DropdownMenuSeparator />
        <div id={`${uid}-list`} className="adh-nav-popover__list">
          {/* Browse: topic submenus (disclosed on hover or keyboard) then the
              promoted leaf links. Nothing is open until the user acts. */}
          {!searching &&
            entries.map((entry, index) => {
              // A divider falls between sections, never within one or at the top.
              const prev = entries[index - 1]
              const divider = prev !== undefined && prev.section !== entry.section
              // A labelled section's heading sits above its FIRST entry, under the
              // divider — including at the very top, where there is no divider.
              const heading =
                prev === undefined || prev.section !== entry.section
                  ? sectionLabels?.[entry.section]
                  : undefined
              const sep = (
                <>
                  {divider && <div className="adh-dropdown-menu__separator" role="separator" />}
                  {heading && (
                    <DropdownMenuLabel className="adh-nav-popover__section-label">
                      {heading}
                    </DropdownMenuLabel>
                  )}
                </>
              )

              if (entry.kind === 'notice') {
                // Text where the rows would be, styled as the empty-search line it is a
                // sibling of. No id, no data-nav: nothing points the highlight at it.
                return (
                  <Fragment key={`notice-${entry.key}`}>
                    {sep}
                    <p
                      className="adh-nav-popover__empty"
                      role="status"
                      aria-live="polite"
                      onMouseMove={leaveRows}
                    >
                      {entry.text}
                    </p>
                  </Fragment>
                )
              }

              if (entry.kind === 'topic') {
                return (
                  <Fragment key={`topic-${index}`}>
                    {sep}
                    <DropdownMenuSub
                      open={index === disclosed}
                      onOpenChange={(next) => {
                        // Only act on OPEN. The engine's close (next===false)
                        // fires from focus-out too — and our focus-guard pulls
                        // focus back to the input the instant a flyout opens,
                        // which would otherwise close it immediately. Genuine
                        // pointer-exit close is handled by onMouseLeave above.
                        if (next) {
                          navByKeyboard.current = false
                          setNav({ kind: 'top', entry: index, open: true })
                        }
                      }}
                    >
                      <DropdownMenuSubTrigger
                        // A navigable topic renders as a real <a>, so the row is a
                        // link: middle-click and open-in-new-tab work on it exactly
                        // as on a leaf. This is Base UI, not Radix — there is no
                        // `asChild`; `render` clones the given element with the
                        // trigger's merged props, and the children below (plus the
                        // wrapper's chevron) become its children. Omitted for a
                        // grouping-only topic, which keeps the primitive's default
                        // element.
                        render={
                          entry.href !== undefined ? (
                            <a
                              href={entry.href}
                              aria-current={entry.current ? 'page' : undefined}
                              {...GUARDED_NAV_PROPS}
                              onClick={(event) => {
                                if (leaveClickAlone(event)) return
                                // Navigate instead of following the href, so this
                                // takes the same chooseItem path (SPA + SSO) as every
                                // other row. Nothing has to suppress the disclosure a
                                // click would otherwise trigger: the trigger opens on
                                // `useClick({ event: 'mousedown', ignoreMouse: true })`
                                // — ignoreMouse because it opens on HOVER — so a mouse
                                // click never reaches that handler at all.
                                event.preventDefault()
                                chooseItem(topicItem(entry))
                              }}
                            />
                          ) : undefined
                        }
                        // The row's own id — the target of the command input's
                        // aria-activedescendant when this row is highlighted, and of
                        // the scroll-into-view lookup. It belongs on the TRIGGER, the
                        // element that carries role="menuitem": pointed at the inner
                        // label span (a roleless <span>) instead, the highlight named
                        // nothing assistive tech could announce as a menu item.
                        // Setting it is safe here — Base UI threads an explicit id
                        // through `useBaseUiId`, so this one becomes the trigger id it
                        // registers, and the flyout still takes its accessible name
                        // from this row.
                        id={`${uid}-e${index}`}
                        data-nav={`e${index}`}
                        className={cn('adh-nav-popover__topic', {
                          'adh-nav-popover__item--active':
                            nav.kind === 'top' && nav.entry === index,
                          'adh-nav-popover__item--current': entry.current,
                          'adh-nav-popover__item--indent': entry.indent,
                        })}
                        // Keep focus in the command input (matches every other
                        // row) so a mousedown on a topic header can't hand the
                        // keyboard to the menu's own roving focus.
                        onMouseDown={(event) => event.preventDefault()}
                        onMouseMove={() => {
                          navByKeyboard.current = false
                          setNav({ kind: 'top', entry: index, open: true })
                        }}
                      >
                        {/* Identical for both kinds of topic — a grouping header is
                            still a row with an icon, a name and a tagline; only the
                            element it renders as differs. */}
                        <IconSlot icon={entry.icon} />
                        <span className="adh-nav-popover__link-name">{entry.label}</span>
                        {entry.description && (
                          <span className="adh-dropdown-menu__shortcut">{entry.description}</span>
                        )}
                      </DropdownMenuSubTrigger>
                      <DropdownMenuSubContent className="adh-nav-popover__submenu">
                        {entry.items.map((item, j) => renderItem(item, index, j))}
                      </DropdownMenuSubContent>
                    </DropdownMenuSub>
                  </Fragment>
                )
              }

              const isActive = nav.kind === 'top' && nav.entry === index
              return (
                <Fragment key={`leaf-${entry.item.key}`}>
                  {sep}
                  <a
                    id={`${uid}-e${index}`}
                    data-nav={`e${index}`}
                    role="menuitem"
                    aria-current={entry.item.current ? 'page' : undefined}
                    href={entry.item.href}
                    {...GUARDED_NAV_PROPS}
                    className={cn('adh-dropdown-menu__item', {
                      'adh-nav-popover__item--active': isActive,
                      'adh-nav-popover__item--current': entry.item.current,
                      'adh-nav-popover__item--indent': entry.indent,
                    })}
                    onMouseDown={(event) => event.preventDefault()}
                    onMouseMove={() => {
                      navByKeyboard.current = false
                      setNav({ kind: 'top', entry: index, open: false })
                    }}
                    onClick={(event) => {
                      if (leaveClickAlone(event)) return
                      event.preventDefault()
                      chooseItem(entry.item)
                    }}
                  >
                    <IconSlot icon={entry.item.icon} />
                    <span className="adh-nav-popover__link-name">{entry.item.label}</span>
                    {entry.blurb && entry.item.description && (
                      <span className="adh-dropdown-menu__shortcut">{entry.item.description}</span>
                    )}
                  </a>
                </Fragment>
              )
            })}

          {/* Special search command (e.g. "help"): a single row in place of the
              autocomplete results. */}
          {searching && cmdActive && searchCommand && (
            <button
              type="button"
              id={`${uid}-cmd`}
              role="menuitem"
              className="adh-dropdown-menu__item adh-nav-popover__item--active adh-nav-popover__help-row"
              onMouseDown={(event) => event.preventDefault()}
              onClick={selectCommand}
            >
              <span>{searchCommand.label}</span>
              {searchCommand.shortcut && (
                <span className="adh-dropdown-menu__shortcut">{searchCommand.shortcut}</span>
              )}
            </button>
          )}

          {/* Autocomplete: a flat list across every item, each shown as its area
              (topic) → the matching item, with the matched chars underlined. */}
          {searching &&
            !cmdActive &&
            searchResults.map((result, index) => {
              const { item, area } = result
              const isActive = index === searchActive
              return (
                <a
                  key={`${item.key}-${index}`}
                  id={`${uid}-s${index}`}
                  data-search={index}
                  role="menuitem"
                  aria-current={item.current ? 'page' : undefined}
                  href={item.href}
                  {...GUARDED_NAV_PROPS}
                  className={cn('adh-dropdown-menu__item adh-nav-popover__match', {
                    'adh-nav-popover__item--active': isActive,
                    'adh-nav-popover__item--current': item.current,
                  })}
                  // Match the browse rows: a pointer-select must not pull focus
                  // out of the command field (which drives the highlight); the
                  // click still navigates via onClick.
                  onMouseDown={(event) => event.preventDefault()}
                  onMouseMove={() => {
                    navByKeyboard.current = false
                    setSearchIndex(index)
                  }}
                  onClick={(event) => {
                    if (leaveClickAlone(event)) return
                    event.preventDefault()
                    chooseItem(item)
                  }}
                >
                  <IconSlot icon={item.icon} />
                  {area && (
                    <>
                      <span className="adh-nav-popover__area">{area}</span>
                      <span className="adh-nav-popover__arrow" aria-hidden>
                        →
                      </span>
                    </>
                  )}
                  <span className="adh-nav-popover__link-name">
                    {highlightMatch(item.label, query)}
                  </span>
                  {item.description && (
                    <span className="adh-dropdown-menu__shortcut">
                      {highlightMatch(item.description, query)}
                    </span>
                  )}
                </a>
              )
            })}
        </div>
        {searching && !cmdActive && searchResults.length === 0 && (
          <p
            className="adh-nav-popover__empty"
            role="status"
            aria-live="polite"
            onMouseMove={leaveRows}
          >
            {emptyLabel}
          </p>
        )}
        {footer && (
          <>
            <div
              className="adh-dropdown-menu__separator"
              role="separator"
              onMouseMove={leaveRows}
            />
            <div className="adh-nav-popover__footer" onMouseMove={leaveRows}>
              {footer}
            </div>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
