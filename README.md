# agentictoolkit

A cross-platform toolkit for agentic development workflows. Consolidates
the Apple (`agentictoolkit`) and Web (`agentic-web-toolkit`) sources into
one repo so shared code lives in one place.

## Layout

Each platform folder under `packages/` is the **root of its native build
system** — its conventional manifest file lives there.

| Platform | Folder | Manifest | Status |
|---|---|---|---|
| Apple | `packages/apple/` | `project.yml` (XcodeGen) + `AgenticToolkit.xcworkspace` | active |
| Web | `packages/web/` | `package.json` + `pnpm-workspace.yaml` | active |
| Android | `packages/android/` | (TBD) | placeholder |
| Windows | `packages/windows/` | (TBD) | placeholder |

The Apple platform is a workspace of three XcodeGen-backed Xcode projects:
`AgenticToolkit` (four toolkit frameworks), `AgenticToolkitApp` (host app),
and `AIPlugins` (`AIPluginsShared.framework` plus five `.aiplugin` bundles).

The Web platform is a pnpm monorepo. Libraries live under
`packages/web/packages/`, a few of the load-bearing ones being:

- `@agentic-toolkit/adh` — family site chrome: header, footer, legal.
- `@agentic-toolkit/adh-ui` — the adh vocabulary the shared UI must not know
  about: rdid pickers and editors, invitation panes, the delete-entity
  danger zone.
- `@agentic-toolkit/auth` / `data` / `resource` / `crud` — the app platform.
- `@agentic-toolkit/api-explorer` — the API reference surface.
- `@agentic-toolkit/messaging` — DMs, notifications, presence.
- `@agentic-toolkit/persona` — the crossing consumers use to reach the
  persona vocabulary (`chat`, `themes`, `viewport`) without pulling a persona in.
- the packages under `packages/web/packages/features/` — one per product area
  (projects, teams, research, notebook, ecosystems, …), plus `bitbag`, the
  persona himself.

**The shared UI packages are not here any more.** `ui`, `themes`, `model`,
`controls`, `landing`, `markdown`, `search` and `editing` now live in the
public [agenticdevelopertoolkit](https://github.com/agenticdevelopmentstudio/agenticdevelopertoolkit)
toolkit and are named `@agenticdevelopertoolkit/*`. This repo reaches them
through its `external/agenticdevelopertoolkit` submodule, so a
`git clone --recursive` still has every one of them on disk — look under
`external/agenticdevelopertoolkit/packages/web/packages/<name>/`, and read
that repo's `README.md` for what each one contains.

The full table, with each package's dependencies, is in
[`packages/web/README.md`](packages/web/README.md).

The reference demo site sits at `websites/site/` and consumes the packages
via `file:` refs (it deliberately lives **outside** the pnpm workspace so
the consumer wiring matches what external apps will use).

## Build

One-shot bootstrap (Apple xcodegen + web pnpm install):

```bash
./install.sh
```

Per-platform commands:

```bash
# Apple
open packages/apple/AgenticToolkit.xcworkspace
# Full xcodebuild commands in .claude/CLAUDE.md

# Web
cd packages/web && pnpm test
cd packages/web && pnpm build      # populates dist/ for npm publish

# Demo site
cd websites/site && npm install && npm run dev
```

## Design

How this repo is laid out and how it's consumed:
[`docs/architecture/repo-pattern.md`](docs/architecture/repo-pattern.md).

Consumer setup walkthrough (git submodule path):
[`docs/project/consuming-as-submodule.md`](docs/project/consuming-as-submodule.md).

Web-platform docs (adoption, migration, Next.js consumer wiring):
[`docs/web/`](docs/web/).

Agent-oriented orientation: [`AGENTS.md`](AGENTS.md).
Repo conventions and build rules: [`.claude/CLAUDE.md`](.claude/CLAUDE.md).
