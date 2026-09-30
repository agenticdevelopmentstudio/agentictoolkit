<!-- leaf: implement-general-1/focused-topic-detail · source: focused-topic-detail.md -->

**Rules** (cite as `implement-general-1/focused-topic-detail#<slug>`):

- `shared-block-composition` MUST
- `first-topic-is-entity` MUST
- `no-action-bar` MUST
- `editable-identifier` MUST
- `validate-identifier-format` MUST
- `rename-unknown-rdid-404` MUST
- `identifier-availability-check` SHOULD
- `surface-identifier-collision` MUST
- `danger-zone-collapsed-neutral` MUST
- `two-step-delete` MUST
- `warning-copy-article-agreement` MUST
- `typed-confirm-exact` MUST
- `delete-navigates-to-all` MUST
- `selector-popup-switches-focus` MUST
- `new-action-in-popup` MUST
- `all-view-filter` MUST
- `all-view-toggle` MUST
- `explicit-all-precedence` MUST
- `persist-view-mode` MUST
- `resume-last-selected` MUST
- `clear-laststate-on-delete` MUST
- `resolve-after-list-load` MUST
- `shared-piece-location` MUST
- `surface-states` MUST
- `accessibility` MUST

# Focused Topic Detail (FTD) View

## Overview

This recipe defines the **general FTD contract** that governs *every* route built
on the Focused Topic Detail view. Concrete instantiations (Ecosystems, Teams,
Persona APIs) live in **## Instantiations**, below; when a general statement here
and an instantiation's own value seem to disagree, the general contract wins and
the instantiation is the one that's wrong.

A **Focused Topic Detail (FTD)** view manages a *collection of entities of one
kind* (ecosystems, teams, persona-services, …). At any moment the user is either:

- **Focused on one entity** — a left-hand **topic list** of that entity's sections, and a right-hand **detail panel** for the selected topic; or
- **Surveying all entities** — the **"All" view**, a browsable index of every entity in the collection.

The user moves between entities (and into "All") through a single **selector
popup** at the top-left of the view. The canonical implementation is the shared
`FocusedTopicDetail` block in `@agenticdevelopertoolkit/ui/blocks` (master/detail
layout) — all FTD routes compose it; none hand-roll the layout.

**Terminology / parameters.** Every FTD route binds these parameters (Ecosystems
values shown for reference — see **Instantiations**):

| Parameter | Meaning | Ecosystems value |
|---|---|---|
| `Entity` | Singular display name of the managed thing | **Ecosystem** |
| `Entities` | Plural | **Ecosystems** |
| `basePath` | Route root | `/ecosystems` |
| `rdid` | The **mutable** reverse-domain **identifier** that uniquely names an entity; shown as the **Identifier** field; maps to an immutable internal UUID via `registry.identifiers` | `identifier` (e.g. `{{org_package}}.myecosystem`) |
| `topics` | Ordered sections shown in the topic list | Ecosystem, Applications, Buckets, Users |
| `childEntities` | Dependent data a delete cascades through (used in delete copy) | applications, buckets, and users |

The identifier is the entity's **public, mutable** name; internally the row is
keyed by an immutable UUID, and `registry.identifiers` maps rdid → UUID so the
identifier can change without breaking UUID foreign keys.

Every `{id}` route segment — and the persisted `lastId` — is the **rdid**, never
the immutable UUID; the two exchange only through `registry.identifiers`.
Because the rdid is mutable, a deep link built from a pre-rename rdid no longer
matches any entity once the rename lands: the resolver treats an unrecognized
id exactly like a stale `lastId` (see **Edge Cases**) and falls back to the All
view rather than a 404.

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

- **shared-block-composition**: Every FTD route MUST compose the shared `FocusedTopicDetail` block (`@agenticdevelopertoolkit/ui/blocks`) and MUST NOT hand-roll the master/detail layout.
- **first-topic-is-entity**: The first topic MUST be the entity itself, labelled with the singular `Entity` name, editing the entity's own attributes plus the Danger section; there MUST be no divider above the first topic.
- **no-action-bar**: The FTD view MUST NOT render a full-width `New | Delete` action bar; New lives in the selector popup and Delete lives in the entity pane's Danger section.
- **editable-identifier**: The Identifier (rdid) MUST be editable for existing entities, renaming via `PATCH /registry/identifiers/{rdid}` with the **old** rdid in the path, leaving the internal UUID and all FK references unchanged.
- **validate-identifier-format**: The Identifier MUST validate the reverse-domain format `^[a-z0-9]+(?:\.[a-z0-9-]+)+$`, lowercased on input. The first segment excludes hyphens because it mirrors a top-level-domain label, which real TLDs never hyphenate; later segments mirror ordinary domain labels, which may. Because input is lowercased before validation, the stored rdid is always lowercase, so the case-sensitive match in **typed-confirm-exact** never has to reconcile case — both sides are already lowercase.
- **rename-unknown-rdid-404**: `PATCH /registry/identifiers/{rdid}` MUST return 404 when the rdid in the path is not currently registered to any entity.
- **identifier-availability-check**: The Identifier field SHOULD call `GET /registry/identifiers/{rdid}/exists` while the user edits it, to surface an inline availability hint ahead of the authoritative 409 in **surface-identifier-collision**.
- **surface-identifier-collision**: A server-side uniqueness collision (HTTP 409) MUST surface as an inline field error.
- **danger-zone-collapsed-neutral**: The Danger Zone MUST be a disclosure that is collapsed by default and styled neutrally while closed, taking the `apt-red` accent (red title + border) only once disclosed; the warning-triangle glyph MUST stay `apt-gold` in both states.
- **two-step-delete**: Deleting an entity MUST require two steps — a warning alert with `[ Cancel ][ Yes ]`, then (only on Yes) a type-to-confirm dialog.
- **warning-copy-article-agreement**: The step-1 warning copy MUST select "a" or "an" for `{Entity}` by the entity noun's leading sound, never a hardcoded article.
- **typed-confirm-exact**: The `Permanently Delete` button MUST stay disabled until the typed text exactly equals the rdid — case-sensitive, no leading/trailing/internal extra whitespace, no normalization.
- **delete-navigates-to-all**: On a successful delete, the view MUST clear the persisted last-selected entry and navigate to the All view; on error it MUST show inline error text and keep the dialog open.
- **selector-popup-switches-focus**: The selector popup MUST be the single entry point for switching focus; All and each entity MUST be radio items that navigate (`{basePath}/all` or `{basePath}/{id}/{topic}`).
- **new-action-in-popup**: The popup MUST place a non-radio `New {Entity}…` action at the bottom after a divider that opens the Create dialog (with its unsaved-changes guard), not a navigation.
- **all-view-filter**: The All view MUST provide a text filter immediately left of the card/list toggle, filtering client-side by name and identifier (case-insensitive substring), with an empty state "No {entities} match \"{query}\".".
- **all-view-toggle**: The All view MUST provide a two-option segmented toggle — cards (`LayoutGrid`) and list (`List`) — defaulting to cards, both linking each entity to `{basePath}/{id}/{firstTopic}`.
- **explicit-all-precedence**: `{basePath}/all` MUST always render the All view, even when a persisted `lastId` still matches a live entity.
- **persist-view-mode**: The chosen All view mode MUST persist under `{{app_prefix}}:ftd:{basePath}:viewMode` so it survives navigation and reload.
- **resume-last-selected**: On entering the bare base path, after the entity list loads the view MUST focus the last-selected entity under `{{app_prefix}}:ftd:{basePath}:lastId` when it still matches a live entity, otherwise show the All view.
- **clear-laststate-on-delete**: When an entity is deleted, the view MUST clear `…:lastId` if it pointed at that entity.
- **resolve-after-list-load**: Local-storage resolution MUST occur after the list has loaded (to avoid SSR hydration mismatch), showing the normal loading state until then.
- **shared-piece-location**: New shared pieces (the Danger Zone / delete-confirm `DeleteEntitySection` block, the All toolbar, the list-mode renderer) MUST go into `@agentic-toolkit/adh-ui/blocks`, never forked into a site.
- **surface-states**: Every new surface MUST handle loading, empty, and error states (All list loading, no entities yet, filter-no-match, delete error inline, identifier-collision inline).
- **accessibility**: Dialogs MUST be `role="dialog"` with focus trap + restore and labelled controls; the type-to-confirm input MUST have a `<label htmlFor>`; the All view's card/list toggle MUST carry `role="radiogroup"` and `aria-label="View as"`; full keyboard operability (Esc cancels dialogs) is required.

## Layout

```
┌──────────────────────────────────────────────────────────────────┐
│  [ Selector popup ▾ ]                                              │  ← top-left popup
├───────────────┬──────────────────────────────────────────────────┤
│  TOPIC LIST   │  DETAIL PANEL                                      │
│               │                                                    │
│  {Entity}     │   (content for the selected topic)                │
│  {Topic 2}    │                                                    │
│  {Topic 3}    │                                                    │
│  …            │                                                    │
└───────────────┴──────────────────────────────────────────────────┘
```

- **No action bar.** A full-width `New | divider | Delete` bar is never rendered above the grid; New lives in the selector popup, Delete lives in the entity pane's Danger section.
- In the **All** view the detail panel is replaced by the All index and the topic list is not shown (there is no focused entity).

The All view toolbar (upper-right):

```
┌──────────────────────────────────────────────────────────────────┐
│  All {Entities}                  [ filter… ]   [▦ cards] [☰ list] │  ← toolbar
├──────────────────────────────────────────────────────────────────┤
│   … cards grid  OR  list rows …                                   │
└──────────────────────────────────────────────────────────────────┘
```

The two-step delete (step 2, type-to-confirm):

```
You are about to permanently delete this {Entity}.

Enter "{rdid}" below
┌────────────────────────────────────────────┐
│                                            │   ← text entry
└────────────────────────────────────────────┘
                              [ Cancel ]  [ Permanently Delete ]   ← red, disabled
```

Color only via `apt-*` tokens (`apt-red` destructive, `apt-border`, `apt-text-muted`, …). No raw hex / arbitrary colors / `!important`.

