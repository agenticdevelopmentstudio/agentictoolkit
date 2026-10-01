# AGENTS.md

Orientation for agents (and humans) working in this repo.

## Purpose

A cross-platform toolkit for agentic development workflows. Each platform
folder under `packages/` is the **root of its native build system** — its
conventional manifest file lives there.

## Layout

| Platform | Folder | Manifest | Status |
|---|---|---|---|
| Apple | `packages/apple/` | `project.yml` (XcodeGen) + `AgenticToolkit.xcworkspace` | active |
| Web | `packages/web/` | `package.json` + `pnpm-workspace.yaml` | active |
| Android | `packages/android/` | (TBD) | placeholder |
| Windows | `packages/windows/` | (TBD) | placeholder |
| Demo site | `websites/site/` | `package.json` (Next.js) | active |

### Apple

Three XcodeGen-backed Xcode projects wired together by
`packages/apple/AgenticToolkit.xcworkspace`:

- `packages/apple/AgenticToolkit/` — four framework targets
  (`AgenticToolkitCore`, `AgenticToolkitCoreUI`, `AgenticToolkitCoreMacOS`,
  `AgenticToolkitMacOS`) and their test bundles.
- `packages/apple/AgenticToolkitApp/` — host app
  (`AgenticToolkitApp.app`).
- `packages/apple/AIPlugins/` — `AIPluginsShared.framework` plus five
  `.aiplugin` bundles (`ClaudeAPI`, `ClaudeLocal`, `Google`, `OpenAI`,
  `OpenAICompatible`).

### Web

`packages/web/` is the pnpm workspace root. Libraries live under
`packages/web/packages/` and ship as `@agentic-toolkit/*` packages
with prebuilt `dist/` output (no `transpilePackages` required for
Next.js consumers).

The shared UI vocabulary they build on lives in the
`external/agenticdevelopertoolkit` submodule and is named
`@agenticdevelopertoolkit/*` — `ui`, `themes`, `model`, `controls`, `landing`,
`markdown`, `search`, `editing`. It is a separate repo and a separate pnpm
workspace, reached from here by `link:`.

`websites/site/` is the in-repo demo consumer. It sits **outside** the
pnpm workspace and uses `file:` refs so its wiring matches what external apps
will use. Since the 2026-08 extraction **every one of those refs points into
the submodule** — its five dependencies are `chat`, `controls`, `model`,
`themes` and `ui`, all `@agenticdevelopertoolkit/*`, and it names no
`packages/web/packages/<name>` target at all. Nothing this workspace builds
reaches the demo site any more.

## Where to look first

- Repo conventions, build commands, ground rules →
  [`.claude/CLAUDE.md`](.claude/CLAUDE.md)
- Apple toolkit code review checklist → [`docs/project/toolkit-checklist.md`](docs/project/toolkit-checklist.md)
- Repo layout pattern (this design) → [`docs/architecture/repo-pattern.md`](docs/architecture/repo-pattern.md)
- Consumer flow (git submodule path) → [`docs/project/consuming-as-submodule.md`](docs/project/consuming-as-submodule.md)
- Web platform docs (adoption, migration, Next.js consumer) → [`docs/web/`](docs/web/)

## Build entry points

- One-shot bootstrap (Apple xcodegen + web pnpm install): `./install.sh`
- Apple workspace: `open packages/apple/AgenticToolkit.xcworkspace`
- Web tests: `cd packages/web && pnpm test`
- Web build: `cd packages/web && pnpm build`
- Demo site: `cd websites/site && npm run dev`

## Conventions you should know

- The repo root has **no language manifest** and no loose build configs.
  Tooling that needs one should `cd` into the relevant platform folder.
- `project.yml` is the source of truth for every Apple Xcode project.
  Hand-edits to `project.pbxproj` are lost on the next regeneration; run
  `xcodegen` (or `cc-xcgen`) after editing `project.yml`.
- Libraries may only depend on other targets within the same platform —
  never on ad-hoc paths outside their workspace.
- Web packages keep their `@agentic-toolkit/*` scope (preserved from
  the prior repo) so published consumers don't break. The eight shared UI
  packages that moved to `agenticdevelopertoolkit` in 2026-08 are now
  `@agenticdevelopertoolkit/*`; they changed repository, which is the only
  reason a rename was on the table.
