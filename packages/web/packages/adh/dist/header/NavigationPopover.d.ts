import { type ReactElement, type ReactNode } from 'react';
import { type NavLinkIcon } from './NavLink';
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
export type PopoverIcon = NavLinkIcon;
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
    key: string;
    label: string;
    description?: string;
    href?: string;
    current?: boolean;
    /** Optional leading icon, rendered in a fixed-width slot before the label. */
    icon?: PopoverIcon;
    onSelect?: () => void;
};
/** A top-level entry: either a leaf row, or a topic that opens a flyout submenu.
 *  `section` groups entries for dividers — a divider falls between sections,
 *  never within one. `blurb` shows a leaf's description inline. `indent` renders
 *  the row as an always-visible inline sub-item (indented under the row above it);
 *  a topic's `icon` is its own leading glyph. */
export type PopoverEntry = {
    kind: 'leaf';
    section: number;
    item: PopoverItem;
    blurb?: boolean;
    indent?: boolean;
} | {
    kind: 'topic';
    section: number;
    label: string;
    items: PopoverItem[];
    icon?: PopoverIcon;
    indent?: boolean;
    /** Makes the topic's own trigger a destination as well as a disclosure: the
     *  row becomes a real `<a>` (middle-click / open-in-new-tab work), a plain
     *  click navigates, and Enter on the highlighted row navigates instead of
     *  opening. Hover and → still open the flyout either way. Omit for a pure
     *  grouping header. */
    href?: string;
    /** Trailing tagline on the trigger row, right-aligned like a leaf's. */
    description?: string;
    /** Flags the trigger as the user's current location (aria-current). */
    current?: boolean;
};
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
export type PopoverNotice = {
    kind: 'notice';
    section: number;
    key: string;
    text: string;
};
/** Everything the list can hold: the rows, and the notices that stand in for rows that are
 *  not there. {@link PopoverEntry} stays rows-only, so code that walks a menu's ROWS
 *  (useSiteMenu, anything narrowing on `kind`) never has to account for a line of text. */
export type PopoverListEntry = PopoverEntry | PopoverNotice;
/** Imperative handle handed to slot render-props so they can close the menu —
 *  optionally WITHOUT restoring focus to the trigger, when they're handing focus
 *  off to another surface (a dialog/popover) that owns Escape-to-dismiss. */
export type PopoverClose = (opts?: {
    restoreFocus?: boolean;
}) => void;
/** An optional special command surfaced while searching (e.g. "help"). When
 *  `matches(query)` is true the list shows a single command row instead of search
 *  results; selecting it closes the menu (focus not restored) then runs `onSelect`. */
export type PopoverSearchCommand = {
    matches: (query: string) => boolean;
    label: ReactNode;
    shortcut?: ReactNode;
    onSelect: () => void;
};
export type NavigationPopoverProps = {
    /** The ordered top-level entries (resolved: hrefs + current flags applied), with any
     *  {@link PopoverNotice} placed among them where the rows it stands in for would be. */
    entries: PopoverListEntry[];
    /** Accessible label for the trigger button (e.g. "Storage — switch site"). */
    triggerLabel: string;
    /** Replaces the trigger's default "{label} ⌄" content. */
    triggerContent?: ReactNode;
    /** Short text shown inside the default trigger before the chevron. */
    triggerText?: string;
    /** Optional icon rendered before the default trigger's text (ignored when
     *  `triggerContent` replaces the default). SiteMenu passes the brand mark. */
    triggerIcon?: ReactNode;
    /** Extra class on the trigger button. */
    triggerClassName?: string;
    /** Command-field placeholder + its accessible name. */
    placeholder?: string;
    /** Empty-state line when a search matches nothing. */
    emptyLabel?: string;
    /** Invoked to navigate to a chosen item. Defaults to a full-page assign to the
     *  item's href — subclasses override for SPA navigation. */
    onChoose?: (item: PopoverItem) => void;
    /** Trailing control in the command row (e.g. a help "?" or settings gear).
     *  Receives `close` so it can dismiss the menu before handing focus off. */
    commandTrailing?: (api: {
        close: PopoverClose;
    }) => ReactNode;
    /** Optional special search command (see {@link PopoverSearchCommand}). */
    searchCommand?: PopoverSearchCommand;
    /** Content pinned below the list, under a divider — a signature line rather than
     *  a row (SiteMenu puts the studio wordmark here). Outside `entries` on purpose:
     *  it is not keyboard-navigable, not searchable and never highlighted, so it can
     *  neither be reached by the arrow keys nor swallow an Enter meant for a
     *  destination. It sits outside the scrolling list too, so it stays visible on a
     *  menu long enough to scroll. */
    footer?: ReactNode;
    /** A heading above a section's first entry, keyed by `section` — "Workspaces" over
     *  the workspace rows, say. Browse only: search results are one flat list with each
     *  row's area already spelled out, so a heading there would label nothing. Not a row:
     *  never highlighted, never reached by the arrow keys. */
    sectionLabels?: Partial<Record<number, string>>;
    /** A chord that TOGGLES the menu, in `@agenticdevelopertoolkit/ui/hooks/useShortcut`
     *  spelling — `'mod+shift+k'`, say. Omit (or pass `''`) for no shortcut, which is
     *  what every popover that isn't the site menu wants: two popovers registering the
     *  same chord would race, and the registry's most-recent-wins tie-break would hand
     *  the win to whichever mounted last. Toggling rather than opening is deliberate —
     *  a chord the user can only press one way is a chord they have to reach for the
     *  mouse to undo. */
    openShortcut?: {
        keys: string;
        label: string;
    };
};
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
export declare function NavigationPopover({ entries, triggerLabel, triggerContent, triggerText, triggerIcon, triggerClassName, placeholder, emptyLabel, onChoose, commandTrailing, searchCommand, footer, sectionLabels, openShortcut, }: NavigationPopoverProps): ReactElement;
//# sourceMappingURL=NavigationPopover.d.ts.map