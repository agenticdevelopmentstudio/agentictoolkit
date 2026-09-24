---
id: 7f122a27-5b49-4f03-9439-1152249bc08f
title: "Focused Topic Detail (FTD) View"
domain: agentictoolkit://recipes/focused-topic-detail
type: recipe
version: 1.1.0
status: accepted
language: en
created: 2026-06-26
modified: 2026-06-26
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "The master/detail view contract governing every route that manages a collection of one entity kind: topic list, entity pane, selector popup, and All view."
platforms:
  - typescript
  - web
tags:
  - master-detail
  - view
  - layout
  - navigation
ingredients:
  - agenticdevelopertoolkit://recipes/resizable-split
  - agenticdevelopertoolkit://recipes/option-menu
  - agenticdevelopertoolkit://recipes/alert-and-dialog
  - agenticdevelopertoolkit://recipes/data-table
  - agenticdevelopertoolkit://recipes/disclosure
  - agenticdevelopertoolkit://recipes/topic-detail
depends-on: []
related: []
references: []
---

# Focused Topic Detail (FTD) View

## Overview

This recipe defines the **general FTD contract** that governs *every* route built
on the Focused Topic Detail view, and pins the **Ecosystems route** as the first
concrete instantiation. When the two diverge, the general contract wins;
ecosystem-specific values are called out as *instantiation*.

A **Focused Topic Detail (FTD)** view manages a *collection of entities of one
kind* (ecosystems, teams, persona-services, …). At any moment the user is either:

- **Focused on one entity** — a left-hand **topic list** of that entity's sections, and a right-hand **detail panel** for the selected topic; or
- **Surveying all entities** — the **"All" view**, a browsable index of every entity in the collection.

The user moves between entities (and into "All") through a single **selector
popup** at the top-left of the view. The canonical implementation is the shared
`focused-topic-detail` block in `@agenticdevelopertoolkit/ui/blocks` (master/detail layout) —
all FTD routes compose it; none hand-roll the layout.

**Terminology / parameters.** Every FTD route binds these parameters (Ecosystems
values shown for reference):

| Parameter | Meaning | Ecosystems value |
|---|---|---|
| `Entity` | Singular display name of the managed thing | **Ecosystem** |
| `Entities` | Plural | **Ecosystems** |
| `basePath` | Route root | `/ecosystems` |
| `rdid` | The **mutable** reverse-domain **identifier** that uniquely names an entity; shown as the **Identifier** field; maps to an immutable internal UUID via `registry.identifiers` | `identifier` (e.g. `com.agenticdeveloperhub.myecosystem`) |
| `topics` | Ordered sections shown in the topic list | Ecosystem, Applications, Buckets, Users |
| `childEntities` | Dependent data a delete cascades through (used in delete copy) | applications, buckets, and users |

The identifier is the entity's **public, mutable** name; internally the row is
keyed by an immutable UUID, and `registry.identifiers` maps rdid → UUID so the
identifier can change without breaking UUID foreign keys.

## Ingredients

| Name | Domain | Role | Required | Configuration |
|---|---|---|---|---|
| FocusedTopicDetail block | agenticdevelopertoolkit://recipes/topic-detail | The master/detail layout (topic list + detail panel) every route composes | yes | `topics`, `paneOwnedActions` |
| OptionMenu | agenticdevelopertoolkit://recipes/option-menu | The selector popup that switches focus and hosts the New action | yes | radio entities + All + trailing New item |
| AlertAndDialog | agenticdevelopertoolkit://recipes/alert-and-dialog | Step-1 warning alert + step-2 type-to-confirm delete dialog | yes | destructive; `Entity`/`rdid`/`childEntities` params |
| Disclosure | agenticdevelopertoolkit://recipes/disclosure | The collapsible Danger Zone in the entity pane | yes | collapsed default; apt-red accent only when open |
| DataTable | agenticdevelopertoolkit://recipes/data-table | The All view "list" render mode (one row per entity) | yes | name + identifier + key meta columns |
| ResizableSplit | agenticdevelopertoolkit://recipes/resizable-split | Optional split layout within a topic's detail panel | no | as needed per topic |

## Integration Requirements

- **compose-shared-block**: Every FTD route MUST compose the shared `focused-topic-detail` block and MUST NOT hand-roll the master/detail layout.
- **first-topic-is-entity**: The first topic MUST be the entity itself, labelled with the singular `Entity` name, editing the entity's own attributes plus the Danger section; there MUST be no divider above the first topic.
- **remove-action-bar**: The FTD view MUST NOT render the old full-width `New | Delete` action bar; New moves into the selector popup and Delete into the entity pane's Danger section.
- **editable-identifier**: The Identifier (rdid) MUST be editable for existing entities, renaming via `PATCH /registry/identifiers/{rdid}` with the **old** rdid in the path, leaving the internal UUID and all FK references unchanged.
- **validate-identifier-format**: The Identifier MUST validate the reverse-domain format `^[a-z0-9]+(?:\.[a-z0-9-]+)+$`, lowercased on input.
- **surface-identifier-collision**: A server-side uniqueness collision (HTTP 409) MUST surface as an inline field error.
- **danger-zone-collapsed-neutral**: The Danger Zone MUST be a disclosure that is collapsed by default and styled neutrally while closed, taking the `apt-red` accent (red title + border) only once disclosed; the warning-triangle glyph MUST stay `apt-gold` in both states.
- **two-step-delete**: Deleting an entity MUST require two steps — a warning alert with `[ Cancel ][ Yes ]`, then (only on Yes) a type-to-confirm dialog.
- **typed-confirm-exact**: The `Permanently Delete` button MUST stay disabled until the typed text exactly equals the rdid — case-sensitive, no leading/trailing/internal extra whitespace, no normalization.
- **delete-navigates-to-all**: On a successful delete, the view MUST clear the persisted last-selected entry and navigate to the All view; on error it MUST show inline error text and keep the dialog open.
- **selector-popup-switches-focus**: The selector popup MUST be the single entry point for switching focus; All and each entity MUST be radio items that navigate (`/{basePath}/all` or `/{basePath}/{id}/{topic}`).
- **new-action-in-popup**: The popup MUST place a non-radio `New {Entity}…` action at the bottom after a divider that opens the Create dialog (with its unsaved-changes guard), not a navigation.
- **all-view-filter**: The All view MUST provide a text filter immediately left of the card/list toggle, filtering client-side by name and identifier (case-insensitive substring), with an empty state "No {entities} match \"{query}\".".
- **all-view-toggle**: The All view MUST provide a two-option segmented toggle — cards (`LayoutGrid`) and list (`List`) — defaulting to cards, both linking each entity to `/{basePath}/{id}/{firstTopic}`.
- **persist-view-mode**: The chosen All view mode MUST persist under `adh:ftd:{basePath}:viewMode` so it survives navigation and reload.
- **resume-last-selected**: On entering the bare base path, after the entity list loads the view MUST focus the last-selected entity under `adh:ftd:{basePath}:lastId` when it still matches a live entity, otherwise show the All view.
- **clear-laststate-on-delete**: When an entity is deleted, the view MUST clear `…:lastId` if it pointed at that entity.
- **resolve-after-list-load**: Local-storage resolution MUST occur after the list has loaded (to avoid SSR hydration mismatch), showing the normal loading state until then.
- **keep-shared-pieces-in-the-toolkit**: New shared pieces (Danger zone / delete-confirm dialog, All toolbar, list-mode renderer) MUST go into `@agentic-toolkit`, never forked into a site.
- **handle-loading-empty-error**: Every new surface MUST handle loading, empty, and error states (All list loading, no entities yet, filter-no-match, delete error inline, identifier-collision inline).
- **be-accessible**: Dialogs MUST be `role="dialog"` with focus trap + restore and labelled controls; the type-to-confirm input MUST have a `<label htmlFor>`; the toolbar/toggle MUST carry ARIA roles; full keyboard operability (Esc cancels dialogs) is required.

## Layout

```
┌──────────────────────────────────────────────────────────────────┐
│  [ Selector popup ▾ ]                                              │  ← top-left popup
├───────────────┬──────────────────────────────────────────────────┤
│  TOPIC LIST   │  DETAIL PANEL                                      │
│               │                                                    │
│  Ecosystem    │   (content for the selected topic)                │
│  Applications │                                                    │
│  Buckets      │                                                    │
│  Users        │                                                    │
└───────────────┴──────────────────────────────────────────────────┘
```

- **No action bar.** The full-width `New | divider | Delete` bar (`ResourceActionBar`) that previously sat above the grid is removed; New → selector popup, Delete → the entity pane's Danger section.
- In the **All** view the detail panel is replaced by the All index and the topic list is not shown (there is no focused entity).

The All view toolbar (upper-right):

```
┌──────────────────────────────────────────────────────────────────┐
│  All Ecosystems                  [ filter… ]   [▦ cards] [☰ list] │  ← toolbar
├──────────────────────────────────────────────────────────────────┤
│   … cards grid  OR  list rows …                                   │
└──────────────────────────────────────────────────────────────────┘
```

The two-step delete (step 2, type-to-confirm):

```
You are about to permanently delete this Ecosystem.

Enter "com.agenticdeveloperhub.myecosystem" below
┌────────────────────────────────────────────┐
│                                            │   ← text entry
└────────────────────────────────────────────┘
                              [ Cancel ]  [ Permanently Delete ]   ← red, disabled
```

Color only via `apt-*` tokens (`apt-red` destructive, `apt-border`, `apt-text-muted`, …). No raw hex / arbitrary colors / `!important`.

## Shared State

| State | Source | Consumer | Direction | Mechanism |
|---|---|---|---|---|
| selected entity id | Route (URL) | Topic list + detail panel | Down | URL param `/{basePath}/{id}/{topic}` |
| last-selected id | localStorage `adh:ftd:{basePath}:lastId` | Bare-path resolver | Both | Written on focus; cleared on delete of that id |
| view mode (`cards`/`list`) | localStorage `adh:ftd:{basePath}:viewMode` | All view toggle | Both | Read on init (default `cards`); written on change |
| filter query | All view local state | Client-side entity filter | Down | Component state |
| entity list | Module-level cache (stale-while-revalidate) | Topic list, All view | Down | SWR-style cache |
| Danger Zone disclosure open | Entity pane local state | Disclosure styling + delete control | Down | Component state |

## Integration Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | editable-identifier, surface-identifier-collision | rename Identifier to a taken rdid | inline collision (409) error; UUID unchanged |
| T2 | editable-identifier | rename Identifier to a free rdid | `PATCH /registry/identifiers/{oldRdid}` called; route/`lastId` refresh to the new rdid |
| T3 | two-step-delete, typed-confirm-exact | Delete → Yes → type partial rdid | `Permanently Delete` disabled until exact, case-sensitive match |
| T4 | delete-navigates-to-all, clear-laststate-on-delete | confirm delete | API called; `lastId` cleared; navigates to All |
| T5 | new-action-in-popup | open popup → New {Entity}… | Create dialog opens (not a navigation) |
| T6 | all-view-filter | type a query in All filter | list narrows by name/identifier; no-match shows empty state |
| T7 | all-view-toggle, persist-view-mode | switch to list, reload | list mode persists via `…:viewMode` |
| T8 | resume-last-selected | enter bare base path with a live `lastId` | focuses that entity; stale/missing → All |

## Edge Cases

- A stale or deleted `lastId` (no longer a live entity) resolves to the All view.
- `/{basePath}/all` is the **explicit** All view and always shows All regardless of the stored id.
- Local storage is client-only; resolution happens after the list loads to avoid SSR hydration mismatch.
- `PATCH /registry/identifiers/{rdid}` returns 404 if the old rdid is unknown and 409 on collision; `GET /registry/identifiers/{rdid}/exists` supports inline availability checks.
- The type-to-confirm match is exact (`===` rdid), case-sensitive, with no whitespace normalization.
- The filter empty result shows "No {entities} match \"{query}\".".

## Platform Notes

**Identifier rename (frontend-only — backend already done):** Reuse the existing
`PATCH /registry/identifiers/{rdid}` (+ `GET …/{rdid}/exists`); no new backend
route, no codegen. Add a hub API client (e.g.
`websites/main/hub/src/api/identifiers.ts`) and wire the Identifier field save to
rename via the *old* rdid, refreshing the route/`lastId` to the new rdid on
success. The ecosystem PUT keeps ignoring `identifier` (id is server-managed).

**Frontend (hub):**

- `websites/main/hub/src/components/settings/topics.ts` — reorder/rename topics: move `settings` → top as **Ecosystem**, rename `schemas` → **Buckets**, drop the divider.
- `websites/main/hub/src/components/settings/ecosystems/EcosystemDetail.tsx` — editable Identifier; Danger section.
- `@agentic-toolkit/adh-ui/blocks` — new shared `danger-zone` / `delete-entity-dialog` block (parameterized by `Entity`, `rdid`, `childEntities`).
- `websites/main/hub/src/components/home/resource/ResourcePopup.tsx` — New action (trailing `DropdownMenuSeparator` + non-radio `New {Entity}…`).
- `websites/main/hub/src/components/home/resource/ResourceActionBar.tsx` — removed from the FTD composition.
- `websites/main/hub/src/components/home/resource/ResourceLanding.tsx` — All toolbar: filter + card/list toggle + list renderer.
- `websites/main/hub/src/components/home/resource/ResourceTab.tsx` — last-selected + view-mode persistence and bare-path resolution; drop the action bar.

**Other instantiations (Teams, Persona APIs):** Both already compose `ResourceTab`.
The entity pane moves to the first topic (`Team` / `Service`), `paneOwnedActions`
is set so the action bar is removed, New moves into the selector popup, and Delete
becomes the entity pane's `DeleteEntitySection` Danger zone (type-to-confirm value:
the team's `identifier`, the service's `name`). Members/Permissions and Models keep
their existing route ids. Each tab seeds its list from a module-level cache
(stale-while-revalidate) like Ecosystems.

## Design Decisions

- **Removed the action bar.** The full-width `ResourceActionBar` (New | divider | red Delete) is removed; its actions now live contextually — New in the selector popup, Delete in the entity's Danger section behind a deliberate two-step confirm — eliminating a redundant, always-present destructive affordance (least astonishment, simplicity).
- **rdid is mutable via `registry.identifiers`.** That backend table maps a mutable rdid → the immutable UUID primary key, so editing an identifier updates the mapping only; the UUID never changes and FK relationships are preserved. This matches the platform pattern (organizations/namespaces are renamed via the identifiers route, never via the entity's own PUT).
- **Two-step delete replaces `window.confirm()`.** Build it as a shared block (`delete-entity-dialog` / `danger-zone`) so every FTD route reuses one authoritative implementation (DRY), parameterized by `Entity`, `rdid`, and `childEntities`. The step-1 warning copy is templated: *"Deleting {a/an} {entity} deletes all the data associated with the {entity}, including {childEntities}. Do you wish to proceed?"*

**Resolved decisions (locked, 2026-06-21):**

- **A. Editable identifier ↔ backend → already supported.** The `registry.identifiers` table + `PATCH /registry/identifiers/{rdid}` rename endpoint already exist and are in the OpenAPI spec and generated clients, so there is no backend route to add and no codegen to regenerate; the rdid is already mutable platform-wide. Remaining work is the frontend wiring.
- **B. "Buckets" → rename the `Schemas` topic to `Buckets`.** Buckets are real ecosystem child data; the existing "Schemas" topic is renamed "Buckets". The delete-warning copy ("…applications, buckets, and users") is correct.
- **C. Step-1 button labels → Cancel / Yes.**
- **D. View-mode persistence → persist it.**

**Ecosystems instantiation — summary:**

| Aspect | Value |
|---|---|
| First topic label | **Ecosystem** (was "Settings"), moved to top, no divider above |
| Topic rename | **Schemas → Buckets** |
| Editable identifier | **Yes** — backend rdid editing via `registry.identifiers` |
| Danger childEntities | applications, buckets, and users |
| rdid example | `com.agenticdeveloperhub.myecosystem` |
| New action | **New Ecosystem…** at popup bottom, after a divider |
| All view | filter box + `LayoutGrid`/`List` toggle, cards default, **mode persisted** |
| Persistence keys | `adh:ftd:/ecosystems:lastId`, `adh:ftd:/ecosystems:viewMode` |

Ecosystems topic order (top → bottom, no dividers): `Ecosystem` (was "Settings",
renamed + moved to top), `Applications`, `Buckets` (was "Schemas"), `Users`.
Keep route ids stable where possible (label change only) to avoid breaking deep
links; if the `schemas` route segment is also renamed to `buckets`, treat it as a
separate, reversible decision and add a redirect.

## Compliance

| Check | Status | Category |
|---|---|---|
| Components reused from / promoted into `@agentic-toolkit` | required | adh-ui-guidelines |
| Tokens — `apt-*` only, no raw hex / `!important` | required | adh-ui-guidelines |
| Loading / empty / error states on every new surface | required | states |
| Accessibility — dialog roles, labelled type-to-confirm, card/list toggle `role="radiogroup"` + `aria-label="View as"`, keyboard | required | accessibility |
| Responsive at 375 / 768 / 1440 (All-view toolbar may wrap under the title at 375) | required | responsive |
| Playwright e2e for the primary flows | required | testing |
| Pre-commit gate — `check_ui.py`, typecheck, lint, `/code-review` before commit | required | process |

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.1.0 | 2026-09-23 | Mike Fullerton | Renamed every requirement to subject-only kebab-case, dropping the old prefix everywhere it is cited. |
| 1.0.0 | 2026-06-26 | Mike Fullerton | Initial conversion from legacy UI spec (carries forward the v0.2 locked decisions A–D). |
