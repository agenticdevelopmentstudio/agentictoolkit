---
id: f2d56415-ac36-4a27-bee5-b447c4186513
title: SiteMenu
domain: agentictoolkit://recipes/site-menu
type: recipe
version: 1.0.0
status: draft
language: en
created: '2026-07-05'
modified: '2026-07-05'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "The platform navigation menu: an icon+label+description list with inline sub-items, an auth-conditional top section, and a Recents flyout."
platforms:
- typescript
- web
tags:
- chrome
- navigation
- site-menu
- recents
- ui
ingredients:
- site-wordmark
depends-on: []
related:
- site-wordmark
- option-menu
- topic-detail
references:
- agenticdeveloperhub://docs/deep-linking-foundation
---

# SiteMenu

## Overview

`SiteMenu` is the platform's primary navigation menu — the popover disclosed from
the header wordmark. It renders a vertical list of rows, each `[icon] [label]
[description]`, organized into sections. It has one shared core layout used by
**both** the marketing (logged-out) and workspace (logged-in `/home`) surfaces;
only the **top section** differs by auth state.

It is chrome. The menu itself — `SiteMenu` and the `menu-icons` map — is ADH
vocabulary, and the registry-free machinery it composes (`NavigationPopover`, the
recents store) is generic; both halves now live in `@agentic-toolkit/adh/header`,
so the tier boundary this recipe once straddled is gone. It is built by composing that
`NavigationPopover` (surface, search, keyboard nav, flyout submenus) with a
declarative config (`MenuGroup[]`). This recipe defines the enhanced menu:
per-row **icons** from a single source of truth, a new **inline sub-item** row
kind, a **Hub** section that gathers the ecosystem's sites and tools, and an
auth-conditional **top section** that adds **Login/Sign up** when logged out and
**Home / Workspaces / Recents** when logged in. Recents records the last 10 places
the user actually landed on and deep-links back to each.

## Ingredients

| Name | Domain | Role | Required | Configuration |
|---|---|---|---|---|
| NavigationPopover | `@agentic-toolkit/adh/header` | Popover surface, search box, keyboard navigation, row rendering, flyout submenus | yes | Consumes `PopoverEntry[]` with icon + inline-subitem support |
| SiteWordmark | agentictoolkit://recipes/site-wordmark | The header trigger that opens the menu | yes | Unchanged |
| menu-icons map | `@agentic-toolkit/adh/header` `menu-icons.ts` (ADH vocabulary — it is keyed by `SiteId`) | Single source of truth for every row's icon — keyed by SiteId, in-hub route path, or chrome key | yes | `MENU_ICONS` record + `menuIcon(key)` resolver |
| lucide-react icons | (library) | The icon glyphs | yes | Only icons already used elsewhere on the platform are reused where one exists |
| `useWorkspaces` | `@/api/workspaces` (hub) | Supplies the Workspaces flyout entries | yes (logged-in) | react-query; `{ slug, name, type }[]` |
| Recents store | `@agentic-toolkit/adh/header/recents` — import that subpath, never `./recents`; it holds module-level state and a second inlined copy would silently fork the history | Persists + reads the last 10 visited places | yes (logged-in) | localStorage, `ftd-storage` pattern |

## Integration Requirements

- **shared-core-both-menus**: The marketing and workspace menus MUST render the
  identical core section structure (the Hub section and everything below it),
  differing ONLY in the auth-conditional top section.
- **row-icon-label-description**: Every row MUST render, in order, an icon, a label,
  and (when present) a description.
- **icon-single-source**: A row's icon MUST resolve from a single source of truth —
  the `menu-icons` map (`MENU_ICONS` / `menuIcon(key)`), keyed by SiteId for site
  rows, route path for in-hub route rows, and a chrome key for the non-site rows
  (Home, Recents, Workspaces, Login, Sign up) — and MUST NOT be hard-coded at a
  render site.
- **icon-reuse-existing**: Where the platform already associates an icon with a
  thing (e.g. Community→`Users`, Persona Registry→`UserCircle`, Dev Team→
  `UsersRound`, Narratives→`ScrollText`, Ecosystems→`Network`, Research→
  `FlaskConical`), that icon MUST be reused rather than a new one invented.
- **inline-subitem-kind**: The menu MUST support an inline sub-item row — a leaf row
  rendered indented under a parent row and ALWAYS visible (not a flyout).
- **hub-parent-links-and-parents**: The "Hub" row MUST be a clickable link to the
  hub apex AND the parent of its inline sub-items.
- **hub-subitems-inventory**: Hub's inline sub-items MUST be, in order, BitBag,
  Community, Persona Registry, Toolkit, Cookbook, Dev Team, MyAgenticTeams,
  Narratives, Help; plus News, Ecosystems, Personas, Organizations, Research.
- **reference-group-removed**: The former "Reference" topic group (docs/api/mcp)
  MUST NOT appear in either menu.
- **in-hub-rows-authed-only**: The in-hub destination rows (News, Ecosystems,
  Personas, Organizations, Research) MUST be hidden when the user is not
  authenticated.
- **top-section-logged-out**: When unauthenticated, the top section MUST show
  exactly two rows — Login and Sign up — above the Hub section.
- **top-section-logged-in**: When authenticated, the top section MUST show Home
  (with an inline sub-item Workspaces) and Recents, above the Hub section.
- **workspaces-flyout**: Selecting/hovering Workspaces MUST open a flyout submenu of
  the user's workspaces from `useWorkspaces`, each labelled per
  `workspaceListLabel` and navigating to that workspace's home.
- **recents-flyout**: Recents MUST open a flyout submenu of the recorded places,
  most-recent first, capped at 10.
- **recents-settle-only**: A place MUST be recorded only after the current selection
  **settles** (no further drill-down within the debounce window), so intermediate
  drill-through steps between a list and its leaf are NOT recorded.
- **recents-deep-link**: Each recent MUST link to the deep URL of the recorded view;
  a view that is not yet URL-addressable MUST record its best available URL (the
  feature route) and MUST NOT block recording.
- **recents-dedupe-cap**: Recording a place already present MUST move it to the
  front (not duplicate it); the list MUST be capped at 10, evicting the oldest.
- **recents-persist-local**: Recents MUST persist per-device in localStorage using
  the `ftd-storage` conventions — SSR-guarded (`typeof window`), try/catch
  swallowing, an `adh:` key prefix.
- **recents-empty-hidden**: When there are no recorded places, the Recents entry
  MUST be hidden (nothing to disclose).
- **current-marked**: The row matching the current location (a site, a workspace, a
  recent) MUST be marked `current`, matching existing `NavigationPopover` behavior.
- **keyboard-accessible**: The enhanced menu MUST retain `NavigationPopover`'s full
  keyboard model (open on trigger activation, arrow navigation, flyout entry/exit,
  Escape to close, focus return).

## Layout

```
LOGGED OUT (marketing)               LOGGED IN (/home + workspace)
──────────────────────               ─────────────────────────────
[LogIn]     Login                    [Home]     Home
[UserPlus]  Sign up                    [Boxes]  Workspaces        ▸ flyout
                                     [History]  Recents           ▸ flyout
── section divider ──                ── section divider ──
[Hub icon]  Hub                      [Hub icon]  Hub
  [Bot]      BitBag                    [Bot]       BitBag
  [Users]    Community                 [Users]     Community
  [UserCircle] Persona Registry        [UserCircle] Persona Registry
  [Wrench]   Toolkit                   [Wrench]    Toolkit
  [ChefHat]  Cookbook                  [ChefHat]   Cookbook
  [UsersRound] Dev Team                [UsersRound] Dev Team
  [Sparkles] MyAgenticTeams            [Sparkles]  MyAgenticTeams
  [ScrollText] Narratives              [ScrollText] Narratives
  [CircleHelp] Help                    [CircleHelp] Help
                                       [Newspaper]  News
                                       [Network]    Ecosystems
                                       [UserCircle] Personas
                                       [Building]   Organizations
                                       [FlaskConical] Research
```

- Indentation (2 spaces) = **inline sub-item**, always visible.
- `▸` = **flyout submenu** (the existing `topic` popover disclosure).
- Row visual language is unchanged from `NavigationPopover`: label
  `adh-nav-popover__link-name`, optional description below/beside; the icon sits in
  a fixed-width leading slot, `apt-text-muted`, sized to the label line.
- Icons are lucide-react; the exact glyph per row comes from the single source of
  truth (see Integration Requirements). Icons shown above are the proposed set;
  reused-where-existing, chosen-where-absent.
- Section divider between the top (auth) section and the Hub section reuses the
  existing section-break treatment (`MenuGroup.section` boundary).

## Shared State

| State | Source | Consumer | Direction | Mechanism |
|---|---|---|---|---|
| Auth (authenticated?) | `AdhHeader` `user` → `SiteSwitcher` `authenticated` | Which top section + whether in-hub rows show | one-way | prop |
| Active route / selection | `usePathname` + workspace chrome `mergedLevels` | `current` marking; Recents recorder input | read | context + hook |
| Workspaces | `useWorkspaces()` (hub) | Workspaces flyout entries | read | react-query |
| Recents list | Recents store (localStorage) | Recents flyout entries | read/write | module store; recorder writes, menu reads |
| Recorded place | Recents recorder (settle-debounced observer of `mergedLevels`) | Recents store | write | effect + timer |

## Integration Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | shared-core-both-menus, reference-group-removed | render marketing vs workspace menu | identical Hub section; no "Reference" group in either |
| T2 | top-section-logged-out | unauthenticated | Login + Sign up above Hub; no Home/Recents |
| T3 | top-section-logged-in, in-hub-rows-authed-only | authenticated | Home/Workspaces/Recents present; News/Ecosystems/Personas/Organizations/Research visible; hidden when logged out |
| T4 | inline-subitem-kind, hub-subitems-inventory | render Hub | sub-items rendered indented, in the specified order |
| T5 | row-icon-label-description, icon-reuse-existing | render any row | icon precedes label; Community shows `Users`, Narratives shows `ScrollText` |
| T6 | workspaces-flyout | open Workspaces with 3 workspaces | flyout lists all 3, labelled + navigating to each home |
| T7 | recents-flyout, recents-empty-hidden | 0 recents / 3 recents | entry hidden at 0; lists 3 most-recent-first otherwise |
| T8 | recents-settle-only | drill list→detail→leaf within the settle window, stop at leaf | only the leaf is recorded |
| T9 | recents-dedupe-cap | record 11 distinct, then re-record #1 | 10 kept, oldest evicted; #1 moves to front |
| T10 | recents-deep-link | click a recent | navigates to that view's deep URL |
| T11 | recents-persist-local | record, reload | recents survive reload (same device) |
| T12 | keyboard-accessible | open, arrow, flyout, Escape | selection moves, flyout opens/closes, focus returns to trigger |

## Edge Cases

- **Not-yet-addressable view.** A recorded place whose view is not URL-addressable
  records the feature route; its recent reopens the feature page (label still tells
  the user what it was). As deep-linking lands, the same place records a precise URL.
- **Workspaces still loading / empty.** Workspaces flyout shows the shared `Spinner`
  while loading and the shared `EmptyState` when the user has none.
- **Recents referencing a deleted entity.** Clicking navigates to the deep URL; the
  feature renders its own not-found/empty state (recents is not authoritative and is
  not pruned server-side).
- **localStorage unavailable** (private mode / quota) — reads return `[]`, writes are
  swallowed; the menu still renders (Recents simply stays empty/hidden).
- **Logged-out device with stale recents in storage.** Recents is a logged-in-only
  section; the recorder only runs and the flyout only shows when authenticated.
- **Very long labels / descriptions** truncate with the existing row ellipsis; the
  icon slot never shrinks.

## Platform Notes

- Files: menu config `websites/shared/adh/src/header/MarketingSiteMenu.tsx` +
  `WorkspaceSiteMenu.tsx` (both compose the shared `hubCoreGroups.ts`); types +
  rendering `SiteMenu.tsx` (auth top section + compose) + `NavigationPopover.tsx`
  (icon slot + inline sub-item indent); icon SSoT
  `websites/shared/adh/src/header/menu-icons.ts`; Recents store + hook
  `websites/shared/adh/src/header/recents.ts`; Workspaces context
  `websites/shared/adh/src/header/workspaces-menu.tsx` (hub filler +
  `hub-workspaces-menu-provider.tsx`); recorder
  `websites/main/hub/src/components/workspace/recents-recorder.tsx`.
- The recorder observes `WorkspaceChromeProvider.mergedLevels`
  (`frontend/src/sites/hub/src/components/workspace/workspace-chrome.tsx`) — the one
  place holding the full current selection path (with labels) for both nav models.
- Demo: `frontend/src/local/ui-showcase/app/page.tsx` — a `site-menu` topic rendering
  both auth states with seeded workspaces + recents.
- Responsive: verify via Playwright at 375 / 768 / 1440; keyboard + pointer.
- Tailwind sources: no new package boundary; icons are lucide (already a dependency
  of `@agentic-toolkit/adh` and externalized by it, so the host supplies the one copy).

## Design Decisions

- **One shared core, two configs.** The menu is already `SiteMenu` →
  `NavigationPopover` driven by two `MenuGroup[]` arrays; "duplicate the layout"
  means extracting the shared Hub core so both configs reuse it and only the top
  section diverges. Avoids the copy-paste drift the two configs risk today.
- **Icons live in one `menu-icons` map.** A single co-located map
  (`header/menu-icons.ts`) keyed by SiteId / route path / chrome key is the one
  authoritative icon per entry — none inline in JSX. Chosen over hanging an `icon`
  field on `SiteDef`: the registry is consumed by ~40 sites, so an added field is a
  higher-blast public-shape change for no current non-menu consumer (YAGNI); the
  map is a small-reversible-decision that can be promoted to `SiteDef` later if a
  card/launcher ever needs the same glyphs. It still satisfies the single-source
  requirement — every row, site or chrome, resolves through `menuIcon(key)`.
- **Inline sub-items are a new row kind, not the existing flyout.** The existing
  `topic` group discloses a side flyout; inline sub-items are always-visible
  indented leaves. They are distinct kinds so Hub can nest visibly while Workspaces
  and Recents still use flyouts.
- **Settle-based Recents, not per-view instrumentation.** Recording after the
  selection stack settles (~1.5s) coalesces drill-through into the final
  destination with one observer and no per-page hooks — see
  `docs/ui/deep-linking-foundation.md`. Records "the eventual destination, not each
  click."
- **localStorage, not a backend.** Recents is inherently ephemeral and per-device;
  the `ftd-storage` pattern already exists for exactly this. No table, no migration
  (YAGNI); a cross-device sync can be added later behind the same store API.

## Compliance

| Check | Status | Category |
|---|---|---|
| No raw hex / arbitrary colors (`check_ui.py`) | required | ui-tokens |
| Reuses `@agentic-toolkit/adh` chrome; no bespoke menu | required | ui-consistency |
| Keyboard + ARIA (menu roles, focus return) | required | accessibility |
| Recents stores no PII beyond local place labels/URLs on-device | n/a | privacy |

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.0 | 2026-07-05 | Mike Fullerton | Initial spec: icons SSoT, inline sub-items, Hub gathering, auth top section, Recents. |
