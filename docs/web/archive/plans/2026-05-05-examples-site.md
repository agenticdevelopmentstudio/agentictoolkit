> [!WARNING]
> **ARCHIVED — HISTORICAL RECORD, NOT CURRENT.** Captured 2026-10-01. This document reflects a
> past state or decision and may no longer describe how things work. Do not treat it as live
> documentation.

# Examples Site

**Status:** approved design, pending implementation
**Date:** 2026-05-05

## Goal

A static umbrella site that hosts live examples of the toolkit, deployable to GitHub Pages. The first example is the existing chat demo; future examples drop in alongside it. Replaces the standalone `examples/chat/` Vite app.

## Layout

```
/site/
├── package.json          # Vite app; "@agentic-cookbook/agentic-web-toolkit": "file:.."
├── vite.config.ts        # base: '/agentic-web-toolkit/'
├── tsconfig.json
├── index.html            # Google Fonts (Inter, JetBrains Mono, Nunito) for theme CSS
├── run.sh                # moved from examples/chat/run.sh
└── src/
    ├── main.tsx
    ├── App.tsx           # Two vertical panes: example list (left rail) + active example (right)
    ├── styles.css        # Site chrome only
    └── examples/
        ├── manifest.ts   # `[{ id, label, Component }]` — single registration point
        └── chat/
            └── index.tsx # Folded from examples/chat/src/App.tsx, retargeted at public exports

/.github/workflows/deploy-site.yml  # Build + deploy to Pages on push to main
```

`examples/chat/` is deleted in the same change. The folded `site/src/examples/chat/index.tsx` is the canonical chat example going forward.

## Design

### Two-pane shell (`site/src/App.tsx`)

- Fixed thin left rail (~180px) listing examples from `manifest.ts`. Each entry is a button that updates active-example state and the URL hash.
- Right pane renders `<ActiveExample.Component />` full-bleed. The example owns everything inside the right pane — including its own internal controls/sidebar if it has them.
- Shell chrome uses the toolkit's theme tokens (`@agentic-cookbook/agentic-web-toolkit/theme/tokens.css`) — eats own dog food.

### Routing

Plain React `useState` for the active example id, mirrored to `window.location.hash` (`#/chat`, `#/<future>`). Reads hash on mount, writes hash on change, listens to `hashchange` for back/forward. No router library — keeps the site small and avoids the GH Pages 404.html SPA workaround.

Unknown / empty hash → first example in the manifest.

### Encapsulation contract

Each example is a directory under `site/src/examples/<id>/` exporting a default component that takes no props. The example renders into the site's right pane and is responsible for its own internal layout and controls. The site never reaches inside an example. Adding a new example: drop a directory, append one entry to `manifest.ts`.

### Folding the chat example

The current `examples/chat/src/App.tsx` (323 lines) ports as-is into `site/src/examples/chat/index.tsx` with two surgical changes:

1. **Imports retargeted at the public API.** Relative `../../../packages/chat` → bare `@agentic-cookbook/agentic-web-toolkit/chat`. The `?inline` CSS imports keep the qualifier; Vite resolves through the exports map first, then applies `?inline`.
2. **Outer container sized to the right pane, not the viewport.** Today's `position: fixed; left: 0; bottom: 0` sidebar would conflict with the site's left rail. Switch to a flex column inside the example's own region (`position: relative` container + `position: absolute` inner sidebar, or flex). The `pc-mobile-overlay` `left:` offset that currently equals the chat example's sidebar width still applies — but offsets only relative to the example's region, not the viewport.

No other behavior changes. Mode/Theme/Appearance/Sizing controls stay where they are.

### Self-`file:` dep

`/site/package.json`:

```json
"dependencies": {
  "@agentic-cookbook/agentic-web-toolkit": "file:..",
  "react": "^19.0.0",
  "react-dom": "^19.0.0"
}
```

This forces every site import through the same exports map real consumers use. If a public path breaks, the site fails to build — turning the site into a built-in regression check on the package's public surface.

### GH Pages

`.github/workflows/deploy-site.yml`:

- Trigger: push to `main`.
- Steps: checkout → setup node → `npm ci` at root → `npm ci` in `/site/` → `npm run build` in `/site/` → upload `site/dist/` as Pages artifact → `actions/deploy-pages`.
- Permissions: `pages: write`, `id-token: write`.
- Vite config sets `base: '/agentic-web-toolkit/'` so asset URLs resolve at the project-pages subpath. Final URL: `https://agentic-cookbook.github.io/agentic-web-toolkit/`.

Repo settings need Pages source = "GitHub Actions" (one-time manual step, called out in the PR description).

### `run.sh`

Moves verbatim from `examples/chat/run.sh` to `site/run.sh`. Same body — `cd "$(dirname "$0")"; npm install if needed; npm run dev`.

## Verification

- `cd site && ./run.sh` — site loads at `http://localhost:5173/agentic-web-toolkit/`, shows "Chat" in the left rail, chat example renders in the right pane with all existing controls (mode/theme/appearance/sizing) working.
- Deep link: open `http://localhost:5173/agentic-web-toolkit/#/chat` directly — same page.
- `cd site && npm run build` — produces `site/dist/` with no TS errors.
- After merge to `main`, the GH Actions workflow deploys; visit `https://agentic-cookbook.github.io/agentic-web-toolkit/` and confirm the same.

## Out of scope for this change

- Additional examples beyond chat. The manifest is set up for them; adding them is future work.
- Repository-level reorganization. `packages/chat/`, `src/`, etc. untouched.
- Updating consumer apps in `~/Development`. They depend on the toolkit's exports map, which is unchanged.
