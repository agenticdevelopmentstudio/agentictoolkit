<!-- leaf: implement-general-1/focused-topic-detail--part-2 · source: focused-topic-detail.md -->

# Focused Topic Detail (FTD) View — continued (part 2)

## Shared State

| State | Source | Consumer | Direction | Mechanism |
|---|---|---|---|---|
| selected entity id | Route (URL) | Topic list + detail panel | Down | URL param `{basePath}/{id}/{topic}` |
| last-selected id | localStorage `{{app_prefix}}:ftd:{basePath}:lastId` | Bare-path resolver | Both | Written on focus; cleared on delete of that id |
| view mode (`cards`/`list`) | localStorage `{{app_prefix}}:ftd:{basePath}:viewMode` | All view toggle | Both | Read on init (default `cards`); written on change |
| filter query | All view local state | Client-side entity filter | Down | Component state |
| entity list | Module-level cache (stale-while-revalidate) | Topic list, All view | Down | SWR-style cache |
| Danger Zone disclosure open | Entity pane local state | Disclosure styling + delete control | Down | Component state |

## Integration Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | editable-identifier, surface-identifier-collision | rename Identifier to a taken rdid | inline collision (409) error; UUID unchanged |
| T2 | editable-identifier | rename Identifier to a free rdid | `PATCH /registry/identifiers/{oldRdid}` called; route/`lastId` refresh to the new rdid |
| T3 | two-step-delete, typed-confirm-exact | Delete → Yes → type partial rdid | `Permanently Delete` disabled until exact, case-sensitive match |
| T4 | delete-navigates-to-all, clear-laststate-on-delete | confirm delete succeeds | API called; `lastId` cleared; navigates to All |
| T5 | new-action-in-popup | open popup → New {Entity}… | Create dialog opens (not a navigation) |
| T6 | all-view-filter | type a query in All filter | list narrows by name/identifier; no-match shows empty state |
| T7 | all-view-toggle, persist-view-mode | switch to list, reload | list mode persists via `…:viewMode` |
| T8 | resume-last-selected | enter bare base path with a live `lastId` | focuses that entity; stale/missing → All |
| T9 | delete-navigates-to-all | confirm delete → API call rejects | inline error text shown; dialog stays open; `lastId` unchanged |
| T10 | validate-identifier-format | type an uppercase or malformed identifier | value is lowercased; a malformed value blocks submit with an inline format error |
| T11 | danger-zone-collapsed-neutral | load the entity pane | Danger Zone renders collapsed, neutral border/title, `apt-gold` glyph; opening it applies the `apt-red` title/border |
| T12 | first-topic-is-entity | load any FTD route's topic list | first topic is the entity itself, labelled `Entity`, no divider above it |
| T13 | no-action-bar | load any FTD route | no full-width New/Delete action bar renders above the grid |
| T14 | selector-popup-switches-focus | choose a different entity (or All) in the selector popup | view navigates to `{basePath}/{id}/{topic}` (or `{basePath}/all`) for the chosen item |
| T15 | resolve-after-list-load | enter the bare base path before the entity list has loaded | normal loading state shows; `lastId` resolution runs only after the list resolves |
| T16 | surface-states | All view loading / no entities / filter-no-match / delete error / identifier collision | each condition shows its own state (spinner, empty copy, "No {entities} match…", inline delete error, inline collision error) |
| T17 | accessibility | open a delete dialog; inspect the All-view toggle | dialog has `role="dialog"` with focus trapped and restored on close; toggle carries `role="radiogroup"` and `aria-label="View as"` |
| T18 | rename-unknown-rdid-404 | `PATCH` with an old rdid that is no longer registered | 404 response surfaces as an inline error |
| T19 | identifier-availability-check | type a candidate identifier | inline availability hint reflects `GET …/exists` before submit |
| T20 | warning-copy-article-agreement | `Entity` starting with a vowel vs. a consonant | step-1 copy reads "an" vs. "a" correctly |
| T21 | explicit-all-precedence | navigate to `{basePath}/all` while a live `lastId` is set | All view renders regardless of the stored id |

## Platform Notes

- **React/Web** (source): Each FTD route composes the shared `FocusedTopicDetail` block (`@agenticdevelopertoolkit/ui/blocks`) for the master/detail layout and the `DeleteEntitySection` block (`@agentic-toolkit/adh-ui/blocks`) for the Danger Zone and two-step delete; the selector popup and All-view toolbar are the route's own composition around those two blocks. The Identifier field's rename flow calls `PATCH /registry/identifiers/{rdid}` (keyed by the *old* rdid) and `GET /registry/identifiers/{rdid}/exists`; the entity's own create/update endpoint never sends `identifier`, since it is server-managed and renamed only through the identifiers route.
- **SwiftUI**: A `NavigationSplitView` supplies the topic list as its sidebar and the detail panel as its detail column; the selector popup is a toolbar `Menu`/`Picker`; the Danger Zone is a `DisclosureGroup` gated behind a two-step `.alert` / `.confirmationDialog` pair; the All view toggles a `Grid`/`List` via a segmented `Picker(.segmented)`.
- **Compose**: A `ListDetailPaneScaffold` (or an adaptive two-pane `Row`) plays the split-view role; the selector popup is a `DropdownMenu`; the Danger Zone is an `ExpandableCard` gated behind a two-step `AlertDialog` pair; the All view toggles `LazyVerticalGrid`/`LazyColumn` via a segmented control.
- **AppKit / UIKit**: `NSSplitViewController` (AppKit) or a two-pane `UISplitViewController` (UIKit) plays the split-view role; the selector popup is an `NSPopUpButton` / `UIMenu`; the Danger Zone is a collapsible section gated behind a two-step `NSAlert` / `UIAlertController` pair.
- **WinUI 3**: A `NavigationView` (or a two-pane `SplitView`) plays the split-view role; the selector popup is a `DropDownButton` with a `MenuFlyout`; the Danger Zone is an `Expander` gated behind a two-step `ContentDialog` pair; the All view toggles a `GridView`/`ListView` via a segmented `ToggleSwitch`.

## Design Decisions

- **Decision**: Remove the full-width action bar (New | divider | red Delete) from the FTD composition; New lives in the selector popup and Delete lives in the entity pane's Danger section behind a two-step confirm.
  **Rationale**: A redundant, always-present destructive affordance violates least-astonishment; contextual placement plus a deliberate two-step confirm removes it without losing the action.
  **Approved**: pending

- **Decision**: The rdid is mutable via the `registry.identifiers` table, which maps the mutable rdid to an immutable UUID primary key; renaming updates the mapping only, never the UUID or its foreign-key references. The mapping table and its `PATCH /registry/identifiers/{rdid}` endpoint already exist and are in the OpenAPI spec and generated clients, so no backend route or codegen is added by this recipe.
  **Rationale**: Matches the platform-wide pattern of renaming organizations/namespaces via the identifiers route rather than an entity's own update endpoint, so FK relationships never need to be rewritten on rename; because the endpoint already exists, this recipe's remaining work is frontend wiring.
  **Approved**: pending

- **Decision**: Replace `window.confirm()` with a two-step delete built as one shared block, `DeleteEntitySection` (`@agentic-toolkit/adh-ui/blocks`), parameterized by `Entity`, `rdid`, and `childEntities`; the step-1 warning copy is templated ("{gerund} {a/an} {entity} deletes all the data associated with the {entity}, including {childEntities}. Do you wish to proceed?") with the article chosen by the entity noun's leading sound (**warning-copy-article-agreement**).
  **Rationale**: One authoritative implementation is shared by every FTD route (DRY) instead of each route re-deriving its own confirm copy and article agreement.
  **Approved**: pending

- **Decision**: Step-1 warning dialog buttons are labelled `Cancel` / `Yes`.
  **Rationale**: Cancel/Yes reads as a plain acknowledgement; the destructive verb is reserved for the type-to-confirm step's button, not repeated at step one.
  **Approved**: pending

- **Decision**: The All view's `cards`/`list` toggle persists its chosen mode.
  **Rationale**: A layout preference set once should survive navigation and reload rather than reset to the default on every visit.
  **Approved**: pending

## Instantiations

Concrete bindings for each route that composes this contract. The general
contract above always wins on conflict.

### Ecosystems

The first concrete FTD instantiation. Parameter bindings are given inline in
the Overview's Terminology table.

**Topic order** (top → bottom, no dividers): `Ecosystem` (the entity's own
pane), `Applications`, `Buckets`, `Users`. Route ids stay stable where only the
label changes, to avoid breaking deep links; renaming the `schemas` route
segment itself to `buckets` is a separate, reversible decision that would need
its own redirect.

**Layout, concretely:**
- Topic list: `Ecosystem, Applications, Buckets, Users`.
- All-view toolbar title: `All Ecosystems`.
- Delete dialog: "You are about to permanently delete this Ecosystem. Enter
  \"{{org_package}}.myecosystem\" below."
- `rdid` example: `{{org_package}}.myecosystem`.
- `childEntities` copy: "applications, buckets, and users".
- Persistence keys: `{{app_prefix}}:ftd:/ecosystems:lastId`,
  `{{app_prefix}}:ftd:/ecosystems:viewMode`.

**Frontend wiring** (identifier rename — the backend already supports it):
reuse `PATCH /registry/identifiers/{rdid}` and `GET …/{rdid}/exists`; no new
backend route, no codegen. An API client wraps the identifiers endpoints, and
the Identifier field's save renames via the *old* rdid, refreshing the
route/`lastId` to the new rdid on success. The ecosystem's own update endpoint
keeps ignoring `identifier` (it is server-managed).

**Hub file map:**
- `src/components/settings/topics.ts` — the ecosystem topic list: `Ecosystem` first (no divider above it), `Buckets` in place of `Schemas`.
- `src/components/settings/ecosystems/EcosystemDetail.tsx` — editable Identifier; Danger Zone.
- `@agentic-toolkit/adh-ui/blocks` — the shared `DeleteEntitySection` block, parameterized by `Entity`, `rdid`, `childEntities`.
- `src/components/home/resource/ResourcePopup.tsx` — the New action (trailing divider + non-radio `New {Entity}…`).
- `src/components/home/resource/ResourceLanding.tsx` — the All toolbar: filter, card/list toggle, list renderer.
- `src/components/home/resource/ResourceTab.tsx` — last-selected + view-mode persistence and bare-path resolution.

- **Decision**: Rename the Ecosystems "Schemas" topic to "Buckets".
  **Rationale**: Buckets are real ecosystem child data; "Schemas" no longer matches what the topic manages, and the delete-warning child-entities copy ("…applications, buckets, and users") already reflects this name.
  **Approved**: pending

### Teams / Persona APIs

Both compose the shared `ResourceTab` orchestrator. The entity's own pane
(`Team` / `Service`) is the first topic; `paneOwnedActions` keeps the action
bar out of the composition; New is the selector popup's trailing action;
Delete is the entity pane's `DeleteEntitySection` Danger Zone, with the
type-to-confirm value bound to the team's `identifier` or the service's
`name`. `Members/Permissions` and `Models` keep their existing route ids.
Each tab seeds its list from the same module-level (stale-while-revalidate)
cache as Ecosystems.
