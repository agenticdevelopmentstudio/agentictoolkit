# The library cookbook — how it is organized, and why

`cookbook/` holds one behavioral spec per component, window, service or model
this repo implements (387 specs at 2026-10-01). Each spec is addressed as
`agentictoolkit://cookbook/<group>/.../<name>` and lists the code that
implements it in its **Reference Implementations** table. `cookbook/cookbook.json`
is the manifest: it declares the concept groups and maps each code root
(`code.roots`) onto the group its specs belong in.

## The rules

1. **Grouped by concept, general to specific.** The top-level groups run from
   the most general to the most product-specific:

   | Group | Sub-groups |
   |-------|------------|
   | `foundation` | formats, git, networking, processes |
   | `data` | services, storage, sync |
   | `ui` | containers, controls, crud, layout, navigation, settings, theme, windows |
   | `system` | permissions, system-windows |
   | `ai` | agent-sessions, chat, mcp, models, plugins, providers |
   | `workspace` | documents, extensions, files, language, logs, notes, projects, terminal |
   | `status` | dashboard, service |
   | `adh` | hub, sites |

   A spec's place is decided by what it *is*, not by where its code lives.
2. **No loose specs at the root, and no platform directories.** The project is
   platform-agnostic, so there is no `macos/` or `web/` group: the AI chat
   window is `ai/chat/...`, whichever platform implements it.
3. **Normative text is platform-neutral.** Overview, Behavioral Requirements,
   Appearance, States, Accessibility, Edge Cases, Configuration and the test
   vectors describe behavior without naming a platform's types or frameworks.
   Platform specifics (AppKit/SwiftUI/React types, actor isolation, `Sendable`,
   nib/storyboard rules, exact API calls, private member names) live in
   **Platform Notes**, with Reference Implementations, Design Decisions,
   Compliance and Change History after them. External protocols a spec
   implements (VS Code API, LSP, AppleScript, SQL) are not platform terms
   and stay in the normative text.
4. **Titles are descriptive Title Case names** ("Disclosure Card View",
   "Project Tree"), not type names, and carry no platform role words.
   Requirement IDs that named a platform construct were renamed (for example
   `main-actor-isolation` → `main-thread-confinement`) or folded into
   Platform Notes.

## Tooling that enforces it

- `cookbook -p cookbook validate`: frontmatter, sections and URIs.
- `cookr arrangement --strict` (agenticcookbook `cookr` branch, commit
  `c65f3d5`): a spec is **aligned** when it sits anywhere inside the
  `recipes` group of a code root that its first platform's Reference
  Implementations rows fall under. It is **drifted** otherwise,
  **unplaced** with no rows, and **outside** when a row is under no root.
  Before that change, arrangement compared spec paths with the code's
  directory layout, which is what produced platform directories in the
  first place.
- `cookr coverage`: completeness grades per component.

## History

- The branch first moved the specs from the loose root `recipes/` into
  `cookbook/` and added Reference Implementations.
- It then regrouped them by concept and rewrote the normative text
  to be platform-neutral. Specs that were rewritten got a minor version bump;
  specs that were only moved got a patch bump. The rewrite ran one subagent
  at a time, in batches, to keep usage down.
- Both landed on main squashed as `52e0776b` (PR #53). The rebase merged main's
  `disclosure-card-view` 1.2.0 (title status symbol) into the neutral spec
  as 1.3.0.

## Known defects (from a `/code-review max` of the branch, 2026-09-29)

None of these are fixed yet. They are in priority order.

- **Prohibitions inverted.** The rewrite changed several "MUST NOT" rules
  to "Neither X … MUST", which forbids nothing. One is the rule against
  persisting a revealed secret (`adh/hub/security/authentication-client.md`).
  The others are in `security-client.md`, `organizations.md`,
  `status/service/monitor/issues.md` and
  `workspace/extensions/vscode-api.md`.
- **UI-thread confinement dropped in 23 specs** (`text-edit-view`,
  `settings-panel`, `tab-pane`, …) along with most of its vectors, while 17
  sibling specs keep `confines-to-ui-thread`. The intended fix is a neutral
  `confines-to-ui-thread` requirement everywhere, with the mechanism in
  Platform Notes.
- **The client-only rule is inconsistent across `status/dashboard/state/`.**
  Of 13 specs, 8 lost the MUST keyword and 4 lost the bullet.
- **Stub requirements.** Nine are just "- **id**: See Platform Notes." with
  no behavior and no vector (`badge`, `multi-choice-filter-button`,
  `key-command-capture-field`, `floating-chooser-panel`,
  `help-content-view`).
- **Swift constructs still normative** in about 12 specs the pass missed,
  such as `contribution-point`, `extension-registry`, `buckets`,
  `customers` and `invitations`.
- **Vector IDs and references.**
  - Some vector IDs were reused for different tests (`tab-pane-045`…`047`,
    `divider-view`).
  - Some prose cites deleted requirement IDs (`settings-panel.md`,
    `divider-view.md`, `extension-webview-presenting.md`,
    `vertical-stack-view.md`).
  - Shared IDs have diverging wordings: `requires-view-model-at-construction`
    and `confines-to-ui-thread`.
- **Format.**
  - 47 specs decorate Design Decision labels.
  - 11 specs add a fourth line to the decision triple.
  - 25 specs split the one-line `NEEDS REVIEW` marker across lines.
  - All of these break cookr's completeness rules.
- **Manifest and tools.**
  - The nested `FileBrowser` and `DocumentPane` roots lack their parent's
    ignore list, so 9 files report as missing.
  - `structure.name` is not allowed by cookr's `cookbook.schema.json`.
  - Nested roots are walked twice.
  - `tools/classify_recipes.py` keys results by basename and loses 15 specs.
- **Grouping.** `data/services/resource-data.md` and `query-cache.md`
  hard-code ADH keys. `workspace/notes/notes-model.md` depends on
  `adh/hub/content/markdown-store`.

Pre-existing gaps, not introduced by the regroup:

- 107 `NEEDS REVIEW` markers
- 124 missing compliance citations
- about 110 blank "Initial creation" history rows
