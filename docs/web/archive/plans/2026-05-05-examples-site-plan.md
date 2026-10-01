> [!WARNING]
> **ARCHIVED — HISTORICAL RECORD, NOT CURRENT.** Captured 2026-10-01. This document reflects a
> past state or decision and may no longer describe how things work. Do not treat it as live
> documentation.

# Examples Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a static umbrella site at `/site/` that hosts toolkit examples (chat first), with hash-based example switching and a GitHub Actions workflow that deploys to GitHub Pages. Replaces the standalone `examples/chat/` Vite app.

**Architecture:** A new Vite + React + TypeScript app in `/site/` that depends on the toolkit via a self-`file:..` dep so it imports through the public exports map exactly like real consumers. Two-pane shell: thin left rail listing examples from a manifest, full-bleed right pane rendering the active example. URL hash mirrors active-example state. Each example is a directory under `site/src/examples/<id>/` exporting a default React component; site never reaches inside.

**Tech Stack:** Vite 6, React 19, TypeScript 5.8, GitHub Actions + `actions/deploy-pages`.

---

## File Structure

**New (in `site/`):**
- `site/package.json` — Vite app with `"@agentic-cookbook/agentic-web-toolkit": "file:.."`
- `site/tsconfig.json` — strict TS, JSX, ESM
- `site/vite.config.ts` — `base: '/agentic-web-toolkit/'`, React plugin
- `site/index.html` — Vite entry, Google Fonts (Inter, JetBrains Mono, Nunito)
- `site/run.sh` — moved from `examples/chat/run.sh`
- `site/src/main.tsx` — React mount
- `site/src/App.tsx` — two-pane shell + hash routing
- `site/src/examples/manifest.ts` — `[{ id, label, Component }]`
- `site/src/examples/chat/index.tsx` — folded chat example
- `site/.gitignore` — `node_modules/`, `dist/`

**New (top-level):**
- `.github/workflows/deploy-site.yml`

**Deleted:**
- `examples/chat/` (entire directory)

---

## Task 1: Scaffold the Vite app shell

**Files:**
- Create: `site/package.json`
- Create: `site/tsconfig.json`
- Create: `site/vite.config.ts`
- Create: `site/index.html`
- Create: `site/src/main.tsx`
- Create: `site/.gitignore`

- [ ] **Step 1.1: Create `site/package.json`**

```json
{
  "name": "agentic-web-toolkit-site",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc --noEmit && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "@agentic-cookbook/agentic-web-toolkit": "file:..",
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "devDependencies": {
    "@types/react": "^19.2.14",
    "@types/react-dom": "^19.2.3",
    "@vitejs/plugin-react": "^4.5.2",
    "typescript": "^5.8.3",
    "vite": "^6.4.2"
  }
}
```

- [ ] **Step 1.2: Create `site/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": false
  },
  "include": ["src"]
}
```

- [ ] **Step 1.3: Create `site/vite.config.ts`**

```ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  base: '/agentic-web-toolkit/',
  plugins: [react()],
})
```

- [ ] **Step 1.4: Create `site/index.html`**

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Agentic Web Toolkit — Examples</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500;700&family=Nunito:wght@400;600;700&display=swap" rel="stylesheet">
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.tsx"></script>
</body>
</html>
```

- [ ] **Step 1.5: Create `site/src/main.tsx`**

```tsx
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
```

- [ ] **Step 1.6: Create `site/.gitignore`**

```
node_modules/
dist/
```

- [ ] **Step 1.7: Commit scaffold**

```bash
git add site/package.json site/tsconfig.json site/vite.config.ts site/index.html site/src/main.tsx site/.gitignore
git commit -m "feat(site): scaffold Vite + React + TS examples site"
```

---

## Task 2: Site shell — two-pane layout with hash routing and manifest

**Files:**
- Create: `site/src/examples/manifest.ts`
- Create: `site/src/App.tsx`

- [ ] **Step 2.1: Create empty manifest**

`site/src/examples/manifest.ts`:

```ts
import type { ComponentType } from 'react'

export type ExampleEntry = {
  id: string
  label: string
  Component: ComponentType
}

export const examples: ExampleEntry[] = []
```

(Chat gets registered in Task 3.)

- [ ] **Step 2.2: Create `site/src/App.tsx`**

```tsx
import { useEffect, useState } from 'react'
import { examples } from './examples/manifest'

const RAIL_WIDTH = 180

function readHashId(): string | null {
  const h = window.location.hash.replace(/^#\/?/, '')
  return h || null
}

function writeHashId(id: string) {
  if (readHashId() !== id) window.location.hash = `#/${id}`
}

export default function App() {
  const initial = readHashId() ?? examples[0]?.id ?? ''
  const [activeId, setActiveId] = useState(initial)

  useEffect(() => {
    const onHashChange = () => {
      const next = readHashId()
      if (next) setActiveId(next)
    }
    window.addEventListener('hashchange', onHashChange)
    return () => window.removeEventListener('hashchange', onHashChange)
  }, [])

  useEffect(() => {
    if (activeId) writeHashId(activeId)
  }, [activeId])

  const active = examples.find((e) => e.id === activeId) ?? examples[0]

  return (
    <div style={{ minHeight: '100vh', display: 'flex', fontFamily: 'Inter, sans-serif', color: '#1a1a24', background: '#f4f4f8' }}>
      <nav
        style={{
          width: RAIL_WIDTH,
          flex: `0 0 ${RAIL_WIDTH}px`,
          padding: '1.25rem 0.75rem',
          borderRight: '1px solid rgba(0,0,0,0.1)',
          background: '#fff',
          display: 'flex',
          flexDirection: 'column',
          gap: '0.25rem',
        }}
      >
        <h1 style={{ fontSize: '0.85rem', fontWeight: 600, margin: '0 0 0.75rem', padding: '0 0.5rem', color: '#1a1a24' }}>
          Examples
        </h1>
        {examples.length === 0 && (
          <span style={{ padding: '0.5rem', fontSize: '0.8rem', color: 'rgba(0,0,0,0.55)' }}>
            No examples registered.
          </span>
        )}
        {examples.map((e) => {
          const selected = e.id === active?.id
          return (
            <button
              key={e.id}
              onClick={() => setActiveId(e.id)}
              style={{
                textAlign: 'left',
                padding: '0.45rem 0.6rem',
                borderRadius: 4,
                border: '1px solid transparent',
                background: selected ? 'rgba(0,0,0,0.06)' : 'transparent',
                fontFamily: 'inherit',
                fontSize: '0.85rem',
                color: 'inherit',
                cursor: 'pointer',
              }}
            >
              {e.label}
            </button>
          )
        })}
      </nav>

      <main style={{ flex: 1, position: 'relative', overflow: 'hidden' }}>
        {active ? <active.Component /> : null}
      </main>
    </div>
  )
}
```

- [ ] **Step 2.3: Verify scaffold builds with empty manifest**

```bash
cd site && npm install
npm run build
```

Expected: build succeeds, `site/dist/` produced. Site loads with empty rail message at `npm run dev`.

- [ ] **Step 2.4: Commit shell**

```bash
git add site/src/App.tsx site/src/examples/manifest.ts site/package-lock.json
git commit -m "feat(site): two-pane shell with hash routing and manifest"
```

---

## Task 3: Fold the chat example into `site/src/examples/chat/`

**Files:**
- Create: `site/src/examples/chat/index.tsx`
- Modify: `site/src/examples/manifest.ts`

The fold takes today's `examples/chat/src/App.tsx` and applies two surgical changes:
1. All `../../../packages/chat...` imports become bare `@agentic-cookbook/agentic-web-toolkit/chat...`.
2. Outer container is no longer viewport-sized. Its inner sidebar is `position: absolute` within a `position: relative` outer wrapper. The `.pc-mobile-overlay` override switches from `position: fixed`-implicit (its default CSS) to `position: absolute !important` so it stays inside the example region instead of spanning the viewport across the site's left rail.

- [ ] **Step 3.1: Create `site/src/examples/chat/index.tsx`**

```tsx
import { useState } from 'react'
import {
  InlineChatView,
  ThreePaneChatView,
  MobileChatView,
  MockBackend,
  useChatSession,
} from '@agentic-cookbook/agentic-web-toolkit/chat'
import '@agentic-cookbook/agentic-web-toolkit/chat/css/base.css'
import '@agentic-cookbook/agentic-web-toolkit/chat/css/modes/inline.css'
import '@agentic-cookbook/agentic-web-toolkit/chat/css/modes/three-pane.css'
import '@agentic-cookbook/agentic-web-toolkit/chat/css/modes/mobile.css'

import professionalCss from '@agentic-cookbook/agentic-web-toolkit/chat/themes/professional.css?inline'
import techyCss from '@agentic-cookbook/agentic-web-toolkit/chat/themes/techy.css?inline'
import whimsicalCss from '@agentic-cookbook/agentic-web-toolkit/chat/themes/whimsical.css?inline'
import agenticcookbookwebCss from '@agentic-cookbook/agentic-web-toolkit/chat/themes/agenticcookbookweb.css?inline'
import devTeamCss from '@agentic-cookbook/agentic-web-toolkit/chat/themes/dev-team.css?inline'
import mikefullertonCss from '@agentic-cookbook/agentic-web-toolkit/chat/themes/mikefullerton.css?inline'
import myprojectsCss from '@agentic-cookbook/agentic-web-toolkit/chat/themes/myprojects.css?inline'
import myprojectsoverviewCss from '@agentic-cookbook/agentic-web-toolkit/chat/themes/myprojectsoverview.css?inline'
import terminalCss from '@agentic-cookbook/agentic-web-toolkit/chat/themes/terminal.css?inline'
import terminalSplitCss from '@agentic-cookbook/agentic-web-toolkit/chat/themes/terminal-split.css?inline'

const themes = {
  professional: { label: 'Professional', css: professionalCss, persona: { name: 'Claire', avatar: 'C' }, welcome: "Hello! I'm Claire, your research assistant. How can I help you today?" },
  techy: { label: 'Techy', css: techyCss, persona: { name: 'NEXUS-7', avatar: '>' }, welcome: "Connection established. I'm NEXUS-7, your knowledge interface. Query away." },
  whimsical: { label: 'Whimsical', css: whimsicalCss, persona: { name: 'Sparkle', avatar: '✨' }, welcome: "Hey there, friend! I'm Sparkle, your friendly neighborhood fact-finder. What are you curious about today?" },
  agenticcookbookweb: { label: 'Agentic Cookbook', css: agenticcookbookwebCss, persona: { name: 'Sage', avatar: 'S' }, welcome: "Welcome to the Agentic Cookbook. Ask me about recipes, patterns, or examples." },
  'dev-team': { label: 'Dev Team', css: devTeamCss, persona: { name: 'Devy', avatar: 'D' }, welcome: "Hey, Devy here. What are we shipping today?" },
  mikefullerton: { label: 'Mike Fullerton', css: mikefullertonCss, persona: { name: 'MF', avatar: 'M' }, welcome: "Hi, this is the Mike Fullerton site assistant." },
  myprojects: { label: 'My Projects', css: myprojectsCss, persona: { name: 'Curator', avatar: 'P' }, welcome: "Browsing projects? Ask me about anything in the catalog." },
  myprojectsoverview: { label: 'Projects Overview', css: myprojectsoverviewCss, persona: { name: 'Overview', avatar: 'O' }, welcome: "Need the big picture across projects? I can help." },
  terminal: { label: 'Terminal', css: terminalCss, persona: { name: 'sh', avatar: '$' }, welcome: "$ ready" },
  'terminal-split': { label: 'Terminal (Split)', css: terminalSplitCss, persona: { name: 'sh', avatar: '$' }, welcome: "$ ready" },
} as const

type ThemeKey = keyof typeof themes
type Mode = 'inline' | 'three-pane' | 'mobile'
type Appearance = 'dark' | 'light'
type Sizing = 'fixed' | 'content'

const SIDEBAR_WIDTH = 240

const appearanceStyles: Record<Appearance, {
  pageBg: string
  patternColor: string
  sidebarBg: string
  text: string
  border: string
  borderActive: string
  buttonHoverBg: string
}> = {
  dark: {
    pageBg: '#1a1a24',
    patternColor: 'rgba(255,255,255,0.06)',
    sidebarBg: 'rgba(0,0,0,0.45)',
    text: '#fff',
    border: 'rgba(255,255,255,0.25)',
    borderActive: '#fff',
    buttonHoverBg: 'rgba(255,255,255,0.08)',
  },
  light: {
    pageBg: '#f4f4f8',
    patternColor: 'rgba(0,0,0,0.07)',
    sidebarBg: 'rgba(255,255,255,0.85)',
    text: '#1a1a24',
    border: 'rgba(0,0,0,0.2)',
    borderActive: '#1a1a24',
    buttonHoverBg: 'rgba(0,0,0,0.05)',
  },
}

const backend = new MockBackend()

export default function ChatExample() {
  const [theme, setTheme] = useState<ThemeKey>('professional')
  const [mode, setMode] = useState<Mode>('inline')
  const [appearance, setAppearance] = useState<Appearance>('dark')
  const [sizing, setSizing] = useState<Sizing>('fixed')

  const t = themes[theme]
  const a = appearanceStyles[appearance]

  const session = useChatSession({
    backend,
    persona: t.persona,
    user: { name: 'You', avatar: 'Y' },
    welcomeMessage: t.welcome,
  })

  const sectionHeaderStyle: React.CSSProperties = {
    fontFamily: 'Inter, sans-serif',
    fontSize: '0.7rem',
    textTransform: 'uppercase',
    letterSpacing: '0.08em',
    opacity: 0.55,
    margin: '0 0 0.5rem',
  }

  const optionRowStyle: React.CSSProperties = {
    display: 'flex',
    alignItems: 'center',
    gap: '0.5rem',
    fontFamily: 'Inter, sans-serif',
    fontSize: '0.85rem',
    padding: '4px 4px',
    cursor: 'pointer',
  }

  const sizingOverrides = sizing === 'content' ? `
    .pc-inline { width: auto !important; height: auto !important; max-height: none !important; }
    .pc-inline .persona-chat { width: max-content; max-width: 500px; height: auto; }
    .pc-inline .pc-transcript { justify-content: flex-start; flex: 0 1 auto; max-height: 60vh; }
    .pc-three-pane-frame .pc-chat-pane { flex: 0 1 auto; min-width: 240px; }
    .pc-three-pane-frame .pc-chat-pane .persona-chat { width: max-content; max-width: 360px; height: auto; }
  ` : ''

  return (
    <div style={{ position: 'absolute', inset: 0, background: a.pageBg, color: a.text, overflow: 'hidden' }}>
      <style>{t.css}</style>
      <style>{`
        .pc-mobile-overlay { position: absolute !important; left: ${SIDEBAR_WIDTH}px !important; top: 0; right: 0; bottom: 0; }
        ${sizingOverrides}
      `}</style>

      <nav
        style={{
          position: 'absolute',
          top: 0,
          left: 0,
          bottom: 0,
          width: SIDEBAR_WIDTH,
          padding: '1.25rem 1rem',
          display: 'flex',
          flexDirection: 'column',
          gap: '1.25rem',
          background: a.sidebarBg,
          backdropFilter: 'blur(8px)',
          color: a.text,
          overflowY: 'auto',
          zIndex: 200,
          borderRight: `1px solid ${a.border}`,
        }}
      >
        <section>
          <h3 style={sectionHeaderStyle}>Mode</h3>
          <label style={optionRowStyle}>
            <input
              type="checkbox"
              checked={mode === 'three-pane'}
              onChange={(e) => setMode(e.target.checked ? 'three-pane' : 'inline')}
            />
            three pane
          </label>
          <label style={optionRowStyle}>
            <input
              type="checkbox"
              checked={mode === 'mobile'}
              onChange={(e) => setMode(e.target.checked ? 'mobile' : 'inline')}
            />
            mobile overlay
          </label>
        </section>

        <section>
          <h3 style={sectionHeaderStyle}>Appearance</h3>
          <label style={optionRowStyle}>
            <input type="radio" name="appearance" checked={appearance === 'dark'} onChange={() => setAppearance('dark')} />
            dark
          </label>
          <label style={optionRowStyle}>
            <input type="radio" name="appearance" checked={appearance === 'light'} onChange={() => setAppearance('light')} />
            light
          </label>
        </section>

        <section>
          <h3 style={sectionHeaderStyle}>Sizing behavior</h3>
          <label style={optionRowStyle}>
            <input type="radio" name="sizing" checked={sizing === 'fixed'} onChange={() => setSizing('fixed')} />
            fixed
          </label>
          <label style={optionRowStyle}>
            <input type="radio" name="sizing" checked={sizing === 'content'} onChange={() => setSizing('content')} />
            content hugging
          </label>
        </section>

        <section style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem', minHeight: 0 }}>
          <h3 style={sectionHeaderStyle}>Theme</h3>
          {(Object.keys(themes) as ThemeKey[]).map((key) => {
            const active = key === theme
            return (
              <button
                key={key}
                onClick={() => setTheme(key)}
                style={{
                  padding: '8px 12px',
                  border: `${active ? '2px' : '1px'} solid ${active ? a.borderActive : a.border}`,
                  borderRadius: '4px',
                  background: active ? a.buttonHoverBg : 'transparent',
                  color: a.text,
                  cursor: 'pointer',
                  fontFamily: 'Inter, sans-serif',
                  fontSize: '0.85rem',
                  textAlign: 'left',
                }}
              >
                {themes[key].label}
              </button>
            )
          })}
        </section>
      </nav>

      <main
        style={{
          position: 'absolute',
          top: 0,
          left: SIDEBAR_WIDTH,
          right: 0,
          bottom: 0,
          backgroundImage: `radial-gradient(circle, ${a.patternColor} 1.5px, transparent 1.5px)`,
          backgroundSize: '24px 24px',
          overflow: 'hidden',
        }}
      >
        {mode === 'inline' && (
          <div className="pc-inline" style={{ left: '50%' }}>
            <InlineChatView session={session} />
          </div>
        )}

        {mode === 'three-pane' && <ThreePaneChatView session={session} />}

        {mode === 'mobile' && (
          <MobileChatView session={session} open onClose={() => setMode('inline')} />
        )}
      </main>
    </div>
  )
}
```

- [ ] **Step 3.2: Register chat in manifest**

Edit `site/src/examples/manifest.ts`:

```ts
import type { ComponentType } from 'react'
import ChatExample from './chat'

export type ExampleEntry = {
  id: string
  label: string
  Component: ComponentType
}

export const examples: ExampleEntry[] = [
  { id: 'chat', label: 'Chat', Component: ChatExample },
]
```

- [ ] **Step 3.3: Verify the build**

```bash
cd site && npm run build
```

Expected: TS passes, Vite produces `site/dist/`. The chat module imports through the public exports map (`@agentic-cookbook/agentic-web-toolkit/chat...`).

- [ ] **Step 3.4: Smoke test in browser**

```bash
cd site && npm run dev
```

Open `http://localhost:5173/agentic-web-toolkit/`. Verify:
- Left rail shows "Chat" entry, selected by default.
- Right pane shows the chat example with its inner sidebar (Mode / Appearance / Sizing / Theme).
- Picking each Theme swaps the active style block (no stacking).
- Mode swap (inline ↔ three-pane ↔ mobile) preserves transcript content.
- Mobile overlay sits inside the right pane, not over the site's left rail.
- URL updates to `#/chat` on selection; reloading at `#/chat` reopens the chat example.

- [ ] **Step 3.5: Commit chat example**

```bash
git add site/src/examples/chat/index.tsx site/src/examples/manifest.ts
git commit -m "feat(site): fold chat example into site/src/examples/chat/"
```

---

## Task 4: Move `run.sh`, delete `examples/chat/`

**Files:**
- Create: `site/run.sh` (with same body as old `examples/chat/run.sh`)
- Delete: `examples/chat/`

- [ ] **Step 4.1: Create `site/run.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
[ -d node_modules ] || npm install
exec npm run dev
```

- [ ] **Step 4.2: Make it executable**

```bash
chmod +x site/run.sh
```

- [ ] **Step 4.3: Delete the old chat example**

```bash
git rm -r examples/chat/
```

If `git rm` complains about untracked artifacts (`node_modules/`, `dist/`), follow up with:

```bash
rm -rf examples/chat
```

(These are session-induced orphans from the deletion; `rm -rf` is appropriate per project convention.)

If `examples/` is now empty, remove it:

```bash
[ -d examples ] && [ -z "$(ls -A examples)" ] && rmdir examples
```

- [ ] **Step 4.4: Verify `site/run.sh` works end-to-end**

```bash
./site/run.sh
```

Expected: dev server starts on port 5173. Ctrl-C to stop.

- [ ] **Step 4.5: Commit move + deletion**

```bash
git add site/run.sh
git commit -m "chore(site): move run.sh into /site, delete examples/chat"
```

---

## Task 5: GitHub Pages deploy workflow

**Files:**
- Create: `.github/workflows/deploy-site.yml`

- [ ] **Step 5.1: Create the workflow**

```yaml
name: Deploy site to GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install root deps
        run: npm install

      - name: Install site deps
        working-directory: site
        run: npm install

      - name: Build site
        working-directory: site
        run: npm run build

      - uses: actions/configure-pages@v5

      - uses: actions/upload-pages-artifact@v3
        with:
          path: site/dist

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

(Why `npm install` rather than `npm ci`: there's no committed `package-lock.json` at the toolkit root, and the `file:..` self-dep keeps the site's lockfile fragile across submodule moves.)

- [ ] **Step 5.2: Commit workflow**

```bash
git add .github/workflows/deploy-site.yml
git commit -m "ci(site): deploy /site to GitHub Pages on push to main"
```

---

## Task 6: Final verification

- [ ] **Step 6.1: Type-check + build**

```bash
cd site && npm run build
```

Expected: zero TS errors, `dist/` produced.

- [ ] **Step 6.2: Toolkit tests still pass**

```bash
cd .. && npm test
```

Expected: all toolkit Vitest tests pass.

- [ ] **Step 6.3: Verify clean tree**

```bash
git status
```

Expected: clean.

- [ ] **Step 6.4: Push branch**

```bash
git push -u origin worktree-examples-site
```

(Pages will only deploy after merge to `main`. You'll need to enable Pages in repo settings → Pages → Source = GitHub Actions one time. Mention this in the PR description.)

---

## Out of scope for this plan

- Adding examples beyond chat
- Repo-level reorganization
- Updating consumer apps in `~/Development` (toolkit's exports map is unchanged)
