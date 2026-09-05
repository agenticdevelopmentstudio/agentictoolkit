import { defineConfig } from 'tsup'
import { preserveDirectivesPlugin } from 'esbuild-plugin-preserve-directives'

export default defineConfig({
  entry: {
    index: 'src/index.ts',
    server: 'src/server.ts',
    'header/index': 'src/header/index.ts',
    // Its own entry so the preserved import below has something to resolve to.
    'header/recents': 'src/header/recents.ts',
    // The menu-icon MAP, published as `./header/menu-icons`. Its own entry because the hub's
    // workspace rail reads its glyphs from here (FEATURE_META no longer hand-copies them), and
    // a data module should not drag the whole header barrel — SiteMenu, the popovers, the auth
    // chrome — in front of a module the workspace pages import for one lucide component.
    'header/menu-icons': 'src/header/menu-icons.ts',
    // The site menu's own topics, read as a grouping of the hub routes they point at — the
    // hub workspace rail's group rows. Its own entry for exactly menu-icons' reason above: the
    // hub's `workspace-features` data module reads it, and a data module should not drag
    // SiteMenu and the popovers in front of a page that wants a list of labels.
    'header/hub-rail-groups': 'src/header/hub-rail-groups.ts',
    // Same shape, same reason as recents above: module-level mutable state (`snapshot`,
    // `listeners`) that the settings panel writes and the site menu reads, so it must be
    // ONE copy. Its own entry + the preserved import below.
    'header/hub-preferences': 'src/header/hub-preferences.ts',
    // The pluggable header AUTH SOURCES (Task 6.2) — the `HeaderAuthState`/
    // `HeaderAuthSource` contract plus the anonymous and smart-SSO sources. Its own
    // entry, published as the `./header-auth` subpath, rather than a member of
    // `header/index`: this is the only module in the header directory that value-imports
    // `@agentic-toolkit/auth`, and folding it into the always-loaded header barrel would
    // put the auth package in front of every consumer of a nav link. Reaches
    // AdhHeader/AvatarMenu by TYPE only, so no relative-inlining hazard (see the file).
    'header/header-auth': 'src/header/header-auth.ts',
    'flags/index': 'src/flags/index.ts',
    'footer/index': 'src/footer/index.ts',
    // The page shell (AdhAppShell) plus the generic error family — the boundaries, the
    // themed fallback, the stale-deploy chunk recovery, the dev switches. Task 5.8. The
    // adh-specific half (which providers wrap the shell, the site-registry lookups
    // HomePlaceholder/SiteNotFound take as props here) merged into this same entry when
    // the app tier came across — see the vocabulary-tier block below.
    'layout/index': 'src/layout/index.ts',
    // The dev-only build identity, and its `browser`-condition twin. Two entries rather
    // than a re-export from `./server`, because `./server` is where the `node:fs` /
    // `node:child_process` imports live and AppShell — which the `layout` barrel above
    // contains — is what reaches them. A `'use client'` global-error.tsx imports that
    // barrel, so the consumer's bundler walked the edge into the builtins and the build
    // died. Splitting the pair out gives the subpath somewhere to hang its `browser`
    // condition, which is what actually keeps the builtins out of a client graph; see
    // live-build-identity-browser.ts for the full argument.
    'layout/live-build-identity': 'src/layout/live-build-identity.ts',
    'layout/live-build-identity-browser': 'src/layout/live-build-identity-browser.ts',
    // The fleet-wide profile page: the shared view, the not-found page with its union search,
    // the client fallback, and the viewer-upgrade hook. Its own entry because every site's
    // `/<slug>/profile` route imports it, and because the SERVER half below must not be
    // reachable from it.
    'profile/index': 'src/profile/index.ts',
    // `fetchPublicPrincipal`, published as `./profile-server`. A separate entry rather than a
    // member of the barrel above is the whole enforcement: this workspace does not install the
    // `server-only` package, so the subpath split is what keeps a server fetch out of a client
    // component's bundle. Named `profile/server` so it emits at dist/profile/server.js, which
    // is where the exports map's `./profile-server` points.
    'profile/server': 'src/profile/server.ts',
    'legal/index': 'src/legal/index.ts',
    'themes/index': 'src/themes/index.ts',
    // The two dev-only halves of theming, each its OWN entry so a production build can
    // leave them out — see the chunk-gate contract in adh-registry's src/deployment-env.ts. DbThemeApplier
    // is also the only 'use client' module in the themes graph, so hoisting it out is what
    // keeps `themes/index` (AdhThemeStyle + the switcher payload builder) server-only.
    'themes/DbThemeApplier': 'src/themes/DbThemeApplier.tsx',
    'themes/theme-preview': 'src/themes/theme-preview.ts',
    'debug/index': 'src/debug/index.ts',
    // The environment/debug CONSOLE — this package's own `debug/` (env-var inventory)
    // and `debug-console/` (the floating window) merged into one directory, because the
    // `./debug` subpath above was already taken. Its two host-owned surfaces (the env
    // override store, the theme taxonomy) arrive as props — see src/debug-env/seams.ts.
    'debug-env/index': 'src/debug-env/index.ts',
    // The site-theme EDITOR (theme-editor state + the injected THEME_AREAS taxonomy + the
    // Monaco CSS editor), reached only through the env-gated dynamic import in
    // debug-env/DebugConsole.tsx. Its own entry is one of the four legs of that gate — see
    // the chunk-gate contract in adh-registry's src/deployment-env.ts.
    'debug-env/SiteThemeConsole': 'src/debug-env/SiteThemeConsole.tsx',
    // The Help modal. `help/index` is the always-loaded barrel (HelpProvider context + useHelp +
    // topic data); the heavy window (the ~87K pre-rendered markdown corpus + shiki + the API
    // browser) is its OWN entry so HelpProvider's `next/dynamic(() =>
    // import('@agentic-toolkit/adh/help/HelpWindow'))` has a real subpath to resolve, and the
    // matching `external` keeps that specifier a dynamic import in the built help/index.js rather
    // than inlining the window and evaluating it eagerly on every page.
    //
    // A caveat used to live here, inherited from the pre-rename `@adh-shared/adh`: that barrel
    // re-exported the window RELATIVELY (`export { HelpWindow } from './HelpWindow'`), which
    // bypassed `external` and inlined a second copy of the corpus — dist/help/index.js was
    // 98,970 B. The barrel now re-exports it by package path, so the copy is gone: today's
    // dist/help/index.js is ~7 KB and both of its references to the window are specifiers, not
    // bodies. The static re-export that remains costs nothing to a tree-shaking consumer either
    // (`sideEffects` names only `**/*.css`, so an unused JS re-export is dropped), which is why
    // it can stay a public name. Do not restore a relative form here.
    'help/index': 'src/help/index.ts',
    'help/HelpWindow': 'src/help/HelpWindow.tsx',
    // The SSR help surface (server component) + its topic-tree helpers, for the help SITE.
    // `surface` stays a server module by keeping the interactive rail (help/HelpMasterDetail,
    // 'use client') as its OWN chunk it imports by package path — the same directive-isolation
    // trick as themes/DbThemeApplier. Kept un-inlined via the matching `external`.
    'help/surface': 'src/help/surface.ts',
    'help/HelpMasterDetail': 'src/help/HelpMasterDetail.tsx',
    // The ROUTE-keyed help store — one function over a JSON file, and nothing else in this
    // directory. Its own entry because every host mounting a portable feature package passes it
    // down as that package's `helpFor` seam, and a site that wants one blurb must not have to
    // load the help window's client graph to get it.
    'help/store': 'src/help/store.ts',
    // The shared /home shell (SiteHomeShell + WorkspacePicker). Its OWN entry so only a page
    // that imports `@agentic-toolkit/adh/home` pulls it — and with it this package's new
    // @agentic-toolkit/data dependency. That edge is legal (data depends on auth + ui only, so
    // no cycle) and it is confined to this entry: the header, which ships on every public page,
    // has no STATIC edge to data or to any workspace vocabulary. Its one reach across is the
    // notification bell (SiteHeader's `accountActions`), and it is a `next/dynamic` specifier
    // precisely so that stays true of what a public page loads — messaging, and the data it
    // pulls in behind it, arrive in their own chunk and only once someone is signed in.
    'home/index': 'src/home/index.ts',
    // The `[workspace]` gate's one exemption — the `'use client'` leaf that lets
    // `/<slug>/profile` render un-gated while everything else under `/<slug>` stays behind
    // the gate. Its own entry for the reason `site/site-id` has one: a SERVER layout on 40
    // sites mounts it, and any entry that inlined it would take its 'use client' banner on
    // the whole chunk (preserve-directives hoists it). Deliberately NOT a member of
    // `home/index`, even though that barrel is already 'use client': the barrel drags
    // SiteHomeShell and with it @agentic-toolkit/data, and the escape's whole job is to be
    // the piece the layout can reach without the gated app behind it.
    'home/PublicProfileEscape': 'src/home/PublicProfileEscape.tsx',
    // The ADH docs shell (server component: sidebar + article). No context/state, so it needs no
    // external self-entry like help — a plain entry the consumer resolves to dist/ in prod.
    'docs/index': 'src/docs/index.ts',
    // Pure Save-gates for the ecosystem settings dialogs admin and hub both render
    // (server bags, feature flags). No React — its own light entry so a dialog can
    // import the gate without pulling a UI barrel.
    'settings-dialogs/index': 'src/settings-dialogs/index.ts',
    // The Messaging compose form + log, shared by the admin tool (platform-wide) and the
    // per-product pane. 'use client', and its own entry so that directive stays off any
    // other subpath. The queries/mutation are INJECTED by the consumer and the wire shapes
    // are structural local minimums — the same arrangement, for the same reason, as
    // persona-chat below: it keeps this package free of @tanstack/react-query and
    // @agentic-toolkit/adh-api-types, which both of its two consumers already carry.
    'messaging/index': 'src/messaging/index.ts',
    // The shared persona-chat backend (SSE parser + status/retry state machine +
    // PersonaChatBackend class). Pure TS, no React. The auth-aware fetchers are
    // INJECTED by the consumer; the chat contract types are a traceable local copy
    // (src/persona-chat/chat-types.ts) rather than a cross-submodule dependency.
    'persona-chat/index': 'src/persona-chat/index.ts',
    // The VISITOR chat backend (anonymous, token-minting) — same shape, no auth.
    'visitor-chat/index': 'src/visitor-chat/index.ts',
    'telemetry/index': 'src/telemetry/index.ts',
    'telemetry/retry': 'src/telemetry/retry.ts',
    'telemetry/report-error': 'src/telemetry/report-error.ts',
    // The telemetry-wired AuthProvider + appearance sync (Task 6.1). Reaches the two
    // telemetry leaves above by package path (see wired-provider.tsx/AppearanceSync.tsx
    // import comments) so this new entry shares their module state rather than inlining
    // a private copy.
    'auth/index': 'src/auth/index.ts',
    // The User Settings surface (Task 7). `settings/index` is the always-loaded barrel
    // (SettingsOverlayProvider/useSettingsOverlay) every site's shell mounts; the ~3,000
    // LOC of panels (registry.tsx and everything it assembles, plus AppearancePanel) sit
    // ONLY behind the separate `settings/UserSettingsOverlay` entry, which `index` reaches
    // by a real `lazy()` import and by NOTHING else — a static re-export alongside it (which
    // this barrel used to carry) re-anchors the same chunk in the eager graph of every
    // consuming build and undoes the split; see settings/index.ts's own comment for the
    // measurement, and tools/check-settings-boundary.py for the guard.
    // ThemePickerRow is split out a second level further, same shape as the debug-env/
    // theme-editor trio below: its own entry so AppearancePanel's folded
    // NEXT_PUBLIC_DEPLOYMENT_ENV gate has a real chunk to gate out of production.
    'settings/index': 'src/settings/index.ts',
    'settings/UserSettingsOverlay': 'src/settings/UserSettingsOverlay.tsx',
    'settings/ThemePickerRow': 'src/settings/ThemePickerRow.tsx',
    // topics.ts is its own entry — NOT primarily for the usual reason a self-referencing
    // module gets one (avoiding two inlined copies of its top-level `new Set(...)`,
    // VALID_TOPICS): both modules that reach it internally, registry.tsx and
    // UserSettingsOverlay.tsx, live inside the SAME entry (`settings/UserSettingsOverlay`),
    // so esbuild would dedupe a relative `./topics` between them for free. The real reason
    // is external and load-bearing: `settings/index` (the barrel) is "use client" — it
    // re-exports SettingsOverlayProvider — and esbuild-plugin-preserve-directives hoists
    // that directive onto the WHOLE built chunk, so anything reachable ONLY through the
    // barrel becomes client-tainted in a production build even though it carries no
    // directive itself. SETTINGS_TOPICS/DEFAULT_SETTINGS_TOPIC/resolveSettingsTopic must
    // stay importable by a Server Component (hub's /settings route is exactly that shape),
    // so this entry — carrying nothing client-tainted — is their one and only route, and
    // `settings/index` does NOT re-export them (see settings/index.ts's own comment).
    // Every internal reach still writes the full package path rather than `./topics`, so
    // there is exactly one documented route to these exports, inside this package and out.
    'settings/topics': 'src/settings/topics.ts',

    // ── The adh VOCABULARY tier, merged in from the former `@adh/chrome` ─────────────
    // These directories were an adh-owned package under `frontend/src/app/chrome/`
    // until they moved here wholesale. A repo outside adh cannot reach into adh's app
    // tier, so "shared chrome that only adh can consume" was a contradiction; the whole
    // tier came across. The entry/`external` pairings below are chrome's own, carried
    // over verbatim — every one of them is load-bearing (see the `external` notes).

    // The concept TAXONOMY: `structure.json` + the locale content catalogs assembled at
    // module load into `conceptTree` plus six derived indexes (conceptById, conceptIds,
    // detailTopics, …). Heavy module-level state AND the site-config JSON is inlined
    // here (see `noExternal` below), so an entry that reached it relatively would carry
    // its own second copy of both. Every reaching module writes the package path.
    'concepts/index': 'src/concepts/index.ts',
    // The participation leaf on its own: the header's "Details" link needs to know
    // whether THIS site has a concept page, and pulling the whole taxonomy (plus its
    // JSON) into the always-loaded header entry to answer one boolean is the thing this
    // split exists to prevent.
    'concepts/participating': 'src/concepts/participating.ts',
    // bitbag in the footer — 'use client', `next/dynamic`-imported by FooterChat with
    // `ssr: false`. Its own entry so that dynamic specifier has a real subpath to
    // resolve and the avatar + gsap + chat CSS stay out of every site's first paint.
    'footer/FooterChatInner': 'src/footer/FooterChatInner.tsx',
    // The concept graph. `graph/index` is the SERVER half (ConceptGraph reads
    // next/headers, LandingGraph composes it); the animated diagram is 'use client' and
    // gets its own entry so preserve-directives can't hoist a 'use client' banner over
    // the server module — the same directive-isolation boundary as themes/DbThemeApplier.
    'graph/index': 'src/graph/index.ts',
    'graph/ConceptGraphClient': 'src/graph/ConceptGraphClient.tsx',
    // The `/details/<topic>` pages: a server page + metadata builder, with the
    // filterable, arrow-key-navigable rail split out as its own 'use client' entry for
    // the same directive reason as the graph above.
    'details/index': 'src/details/index.ts',
    'details/DetailsRail': 'src/details/DetailsRail.tsx',
    // adh's theme TAXONOMY (which named areas a site's theme paints) + the Monaco CSS
    // editor. Reached by package path from debug-console so the console and the theme
    // switcher agree on one taxonomy.
    'theme-editor/index': 'src/theme-editor/index.ts',
    // adh's Debug console: the toolkit's generic console (debug-env, above) wired to
    // adh's env store + theme taxonomy. Its own entry because the site menu
    // `next/dynamic`-imports it BY PACKAGE PATH — the menu is in the always-loaded
    // header entry, so a static import would drag the taxonomy and Monaco onto every page.
    'debug-console/index': 'src/debug-console/index.tsx',
    // The marketing-site shell: root html, landing, story sections, wordmark. Three of
    // its members are separate entries — LandingHeroGate and MarketingSiteHeader are
    // 'use client' leaves imported from server modules (directive boundary again), and
    // SiteWordmark is published standalone so a site can render the mark without
    // pulling the landing page in behind it.
    // The per-site declaration (`defineSite`) every family site's app/ tree reads. Its own
    // entry rather than a member of marketing/index, because robots.ts, sitemap.ts and the
    // details pages import a site's config too and none of them wants the landing deck
    // behind it.
    'site/index': 'src/site/index.ts',
    // The hub's workspace-path predicates. Split off `site/index` for the reason
    // concepts/participating is split off the taxonomy — the header asks both predicates on
    // every render, and the header is the entry that ships on every public page — and kept
    // un-inlined for the reason the matching `external` below spells out: the module holds
    // module-level state (the slug-less segment Set, and the memoized reserved list), and with
    // bundle:true/splitting:false every entry that reaches it RELATIVELY inlines its own copy.
    // Here the two copies would agree — this state is derived from module constants and never
    // written again, so it is duplicated work rather than forked state. The toolkit draws no
    // such distinction: verify-bundle-boundaries.py's Check B refuses a stateful module in two
    // entries outright, and its allowlist is not available to a toolkit package. Both halves
    // are load-bearing: this entry, AND the package path in every reaching module.
    'site/hubWorkspacePath': 'src/site/hubWorkspacePath.ts',
    // The site-id context. Its own entry for BOTH of this file's usual reasons at once. It is a
    // 'use client' leaf, and the `site/index` barrel it would otherwise sit in is a SERVER entry
    // (40 sites' sitemap.ts and site.config.ts import it), so inlining it there stamps the whole
    // barrel 'use client'. And it holds a module-scope React context, so — exactly as the flags
    // note below spells out — every entry that reached it relatively would inline its OWN context
    // object, and a provider mounted from one copy would be invisible to a `useSiteId` from
    // another. Both halves fail only in a production build.
    'site/site-id': 'src/site/site-id.tsx',
    // The family's landing DECK — the shape of every site's `/` and `/tour`, which used to
    // be emitted into each site as markup. Its own entry rather than a member of
    // marketing/index: that barrel is what a site's layout imports on every route, and the
    // deck plus its twenty-odd blocks belongs to two of them. It reaches NavChrome by
    // package path (`@agenticdevelopertoolkit/landing/client`) for the directive reason the
    // `external` list below spells out.
    'landing/index': 'src/landing/index.ts',
    'marketing/index': 'src/marketing/index.ts',
    'marketing/LandingHeroGate': 'src/marketing/LandingHeroGate.tsx',
    'marketing/SiteWordmark': 'src/marketing/SiteWordmark.tsx',
    'marketing/MarketingSiteHeader': 'src/marketing/MarketingSiteHeader.tsx',
  },
  outDir: 'dist',
  format: ['esm'],
  target: 'es2022',
  platform: 'browser',
  sourcemap: true,
  // Everything in dist EXCEPT the CSS. `build:css` writes dist/**/*.css a build step AFTER
  // tsup, so a plain `clean: true` leaves a window in which dist holds the JS and none of the
  // styles — and anything resolving this package's `./css/*` exports during it (a running dev
  // server, a site building in parallel) gets "no valid target file was found" and caches the
  // failure. Negating them costs nothing in staleness: copy-css.mjs prunes the orphans.
  clean: ['!**/*.css'],
  dts: false,
  bundle: true,
  splitting: false,
  outExtension: () => ({ js: '.js' }),
  external: [
    'react',
    'react-dom',
    'react/jsx-runtime',
    'next',
    'next/headers',
    'next/navigation',
    // Subpaths, like the two above: `next` is a peerDependency, and tsup does not
    // externalize a peer's SUBPATHS from the bare name. `next/dynamic` is
    // help/HelpProvider's lazy import of the help window; `next/link` is docs/DocsShell's
    // sidebar. Inlined, esbuild would try to bundle Next itself into this dist.
    'next/dynamic',
    'next/link',
    '@agenticdevelopertoolkit/themes',
    '@agenticdevelopertoolkit/themes/manifest',
    // The auth package's token store, refresh timer, and AuthContext all live at module
    // scope. Nothing under src/ imported it before Task 6.1's auth/index entry; inlined,
    // that entry would get its own private auth instance — a user logged in through the
    // site's own toolkit-auth import would read as signed out from AppearanceSync /
    // wired-provider, in production only (dev/vitest/tsc all resolve the `development`/src
    // condition and stay green). Preserved import ⇒ one copy, resolved by the consumer.
    // Subpath listed separately, same as `@agenticdevelopertoolkit/ui/*` below: tsup's `external`
    // matches specifiers, not packages, so the bare entry does nothing for
    // '@agentic-toolkit/auth/client'.
    '@agentic-toolkit/auth',
    '@agentic-toolkit/auth/client',
    // '/ui' and '/server' aren't reached by anything under src/ yet — pre-listed the same
    // way '@agentic-toolkit/adh/flags' is above, so the day a future entry in this package
    // imports one of them it's already covered and doesn't silently get its own inlined copy.
    '@agentic-toolkit/auth/ui',
    '@agentic-toolkit/auth/server',
    '@agenticdevelopertoolkit/ui',
    // Subpath form: tsup's `external` matches SPECIFIERS, not packages, so the bare
    // entry above does nothing for '@agenticdevelopertoolkit/ui/components/badge' and friends
    // (introduced by the header modules in Task 5.6).
    '@agenticdevelopertoolkit/ui/*',
    // recents.ts holds module-level mutable state (`snapshot`, and the `listeners`
    // Set). With bundle:true/splitting:false, every entry that reaches it by a
    // RELATIVE specifier inlines its own private copy of that state — a visit
    // recorded through one entry is then invisible to a `useRecents` subscriber that
    // came in through another, silently, with no type or build error and invisible in
    // dev (next dev / vitest / tsc all resolve the `development` condition to src/).
    // Inlining it would also hoist its 'use client' directive over the whole entry.
    // Preserved import ⇒ one copy, resolved by the consumer. BOTH halves are load
    // bearing: this entry, AND every reaching specifier written as the full package
    // path '@agentic-toolkit/adh/header/recents'. One surviving './recents' defeats
    // it. Enforced by <adh-tools>/sites/scripts/verify-bundle-boundaries.py.
    '@agentic-toolkit/adh/header/recents',
    // hub-preferences.ts is recents.ts's twin: module-level mutable state ('snapshot',
    // 'listeners') plus a 'use client' directive. Two entries reach it from opposite ends
    // — the settings panel WRITES the chord, the header READS it — which is the exact
    // shape that makes an inlined second copy invisible: each side would mutate its own
    // snapshot, so saving a new shortcut in Settings would leave the menu still listening
    // for the old one, with no type or build error and nothing wrong in dev (which
    // resolves the `development` condition to src/). One surviving relative
    // './hub-preferences' defeats it, exactly as one surviving './recents' would.
    '@agentic-toolkit/adh/header/hub-preferences',
    // The hub workspace-path leaf (entry above). Two entries reach it — the `site` barrel
    // re-exports both predicates, and the header calls them from useSiteMenu and
    // activeMenuGroups — so without this it is inlined twice. Preserved import ⇒ one copy,
    // resolved by the consumer. One surviving '../site/hubWorkspacePath' defeats it, exactly
    // as one surviving './recents' would above.
    '@agentic-toolkit/adh/site/hubWorkspacePath',
    // The site-id context leaf (entry above). Preserved import ⇒ ONE context object, resolved by
    // the consumer. One surviving '../site/site-id' relative import defeats it and forks the
    // context — see the flags note below for what a forked context looks like in production.
    '@agentic-toolkit/adh/site/site-id',
    // The flags module holds the React context (FeatureFlagsProvider / FeatureFlagsContext).
    // With splitting:false, every entry that inlines it gets its OWN context instance — a consumer
    // entry in THIS package (`footer/AdhFooter`, which landed here in Task 5.7, is the nearest
    // candidate) would stop sharing state with this package's own provider (index/layout), so
    // flag-gated surfaces would read permanently OFF in production builds while dev/vitest (which
    // resolve the `development`/src condition) stayed green. Preserved import ⇒ one copy, resolved
    // by the consumer. Inert today — nothing under src/ imports ./flags yet (the one in-package
    // candidate, HierarchicalDetailViewFlag, has its flag read commented out while HMDV is parked)
    // — but load-bearing the moment one does. The same stateful-module rule, with its own
    // rationale, governs the telemetry leaves and `themes/index` in the entries immediately below.
    '@agentic-toolkit/adh/flags',
    // The telemetry leaves hold module-level mutable state (`reporter` in report-error.ts,
    // `retriedInits` in retry.ts). With splitting:false, every entry that inlines a leaf gets its
    // OWN copy of that state — TelemetryProvider's setErrorReporter (in the `telemetry` entry)
    // would write one copy while a consumer reaching the leaf through a different entry reads
    // another, whose `reporter` stays null, silently no-oping every captureException/
    // reportUnexpectedError in production builds while dev/vitest (which resolve the
    // `development`/src condition) stayed green. Preserved import ⇒ one copy, resolved by the
    // consumer. Same trick as `@agentic-toolkit/adh/flags` above.
    // NOT hypothetical since Task 5.8: `layout/RouteError.tsx` and `layout/GlobalError.tsx` —
    // whose entire job is reporting the error they render a fallback for — reach this leaf from
    // the `layout` entry, and a null `reporter` would make them fail at exactly that while still
    // rendering a correct-looking fallback. Both write the full package path; a relative
    // '../telemetry/report-error' in either one silently defeats this entry.
    '@agentic-toolkit/adh/telemetry/report-error',
    '@agentic-toolkit/adh/telemetry/retry',
    // AdhThemeStyle.tsx (server) renders DbThemeApplier ('use client'). With
    // bundle:true/splitting:false, inlining a 'use client' leaf hoists its directive to
    // the top of the WHOLE entry file — server.ts's bundle would then open with 'use
    // client', so Turbopack refuses getAdhTheme's `next/headers` import in the same
    // file ("only available in Server Components"). Preserved import ⇒ its own chunk,
    // resolved by the consumer, keeping server.js a plain server module. Same trick as
    // the two directive boundaries the app tier already had, graph/ConceptGraphClient and
    // footer/FooterChatInner — both listed in the vocabulary-tier `external` block below,
    // carried over verbatim from that tier's own tsup config when it merged in.
    '@agentic-toolkit/adh/themes/DbThemeApplier',
    // The themes barrel, reached by PACKAGE PATH from the debug console (Task 5.2's
    // `debug-env/DebugConsole.tsx` calls `useThemeEditor`, and SiteThemeBranch.tsx takes
    // its `ThemeEditorApi` type). That specifier arrived here as a genuine cross-package
    // import and became a self-reference on the way in — exactly the shape that silently
    // forks state. `useThemeEditor` drives the SAME stored themes the `./themes` entry's
    // ThemeSwitcher/DbThemeApplier read, so an inlined second copy would give the console
    // its own themes-client module: a theme saved from the console would not be visible
    // to the applier that paints the page. Preserved import ⇒ one copy, resolved by the
    // consumer. BOTH halves required — this entry, AND the package-path specifier.
    '@agentic-toolkit/adh/themes',
    // ── Task 5.5: the help surface's three preserved imports, all SELF-references ────────
    // The light Help barrel holds the React HelpContext. With splitting:false, any entry
    // that reaches it RELATIVELY inlines its own context instance — MarkdownTopic's
    // `useHelp()` (inside the help/HelpWindow entry) would then read a DIFFERENT, empty
    // context than the provider in help/index created, so clicking a cross-link in a help
    // topic would silently no-op. Same class as ./flags and ./header/recents above.
    '@agentic-toolkit/adh/help',
    // The heavy window (pre-rendered help HTML + shiki + the API browser). External so
    // HelpProvider's `next/dynamic(() => import('@agentic-toolkit/adh/help/HelpWindow'))` survives
    // into dist/help/index.js as a dynamic import the consumer's bundler code-splits, instead of
    // esbuild resolving it to the local file and evaluating the window on every page.
    '@agentic-toolkit/adh/help/HelpWindow',
    // The SSR surface's interactive rail ('use client'), reached by package path from the
    // SERVER module help/HelpSurface. Inlined, preserve-directives would hoist its 'use
    // client' over the whole help/surface entry and the help site's server component would
    // stop being one. Same shape as themes/DbThemeApplier above.
    '@agentic-toolkit/adh/help/HelpMasterDetail',
    // help/HelpWindow borrows the debug console's draggable FloatingWindow shell. That was a
    // genuine cross-package import in @adh-shared/adh and became a SELF-reference on the way
    // in — the shape that silently forks state. FloatingWindow's module-level drag geometry
    // must be ONE copy shared with the console, so preserve it rather than let the help
    // entry inline a second.
    '@agentic-toolkit/adh/debug-env',
    // help/views/ApiTopic renders the api-explorer's ApiBrowser; adh-help.css also @imports
    // that package's stylesheet + `sources.css`. A real dependency, resolved by the consuming
    // site so there is one copy of the shiki highlighter singleton and one endpoint-metadata
    // module. tsup auto-externalizes bare `dependencies`, but not reliably their subpaths, so
    // list both forms as `@agenticdevelopertoolkit/ui` does.
    '@agentic-toolkit/api-explorer',
    '@agentic-toolkit/api-explorer/*',
    // Declared as a dependency for adh-help.css's `@import "@agenticdevelopertoolkit/markdown/styles"`
    // (bare specifiers in that stylesheet resolve from THIS package) and for
    // tools/gen-help-content.py's `processMarkdown` render step. No `src/` module imports it —
    // the help corpus is PRE-rendered — but list it so a future runtime import can never be
    // inlined by accident.
    '@agenticdevelopertoolkit/markdown',
    '@agenticdevelopertoolkit/markdown/*',
    // ── Task 6: the shared /home shell's data dependency + self-reference ───────────
    // The data layer holds module state: `dataConfig` (the API base URL every authed call
    // resolves against, set once by the host's configureData) and useResourceList's `caches`
    // Map. Inlined into this package's `home` entry, the shell would read an UNCONFIGURED
    // config — a second copy the site's configureData never touched — and its list cache would
    // be invisible to the feature's. Subpath form listed too: tsup's `external` matches
    // specifiers, not packages.
    '@agentic-toolkit/data',
    '@agentic-toolkit/data/*',
    // The `home` barrel, pre-listed the same way '@agentic-toolkit/auth/ui' is: nothing under
    // src/ imports it today, but the day an entry here does it is already a boundary rather
    // than a silently inlined second copy of the shell's state.
    '@agentic-toolkit/adh/home',
    // The `[workspace]` gate's escape leaf (entry above). Pre-listed for the same reason as the
    // barrel on the line above — nothing under src/ imports it today; the 40 site layouts do —
    // and it is a DIRECTIVE boundary the day one does, exactly like
    // '@agentic-toolkit/adh/graph/ConceptGraphClient' below. It is also what
    // verify-bundle-boundaries.py's Check C reads to hold this line, the entry above and the
    // `./home/PublicProfileEscape` exports subpath together.
    '@agentic-toolkit/adh/home/PublicProfileEscape',
    // ── Self-references from the merged adh vocabulary tier ─────────────────────────
    // Same rule as every entry above, and it applies to ALL of these without exception:
    // a package-path specifier that is NOT listed here is not a boundary — esbuild
    // resolves it and inlines the target, silently, with no build error, invisible in
    // dev/vitest/tsc (which take the `development` condition straight to src/) and wrong
    // only in production. Each line below pairs with an `entry:` above and with every
    // reaching module writing the full package path; all three halves are required.
    // `<adh-tools>/sites/scripts/verify-bundle-boundaries.py` gates the pairing.
    //
    // STATE: the taxonomy assembled at module load, plus the inlined site-config JSON.
    // Reached from graph, details, marketing — four entries that would otherwise each
    // carry their own tree and their own copy of the JSON.
    '@agentic-toolkit/adh/concepts',
    '@agentic-toolkit/adh/concepts/participating',
    // DIRECTIVE boundaries: a 'use client' leaf imported from a server module. Inlined,
    // preserve-directives hoists the leaf's banner over the whole entry and the server
    // module stops being one — the consuming site's build fails, or worse, doesn't.
    '@agentic-toolkit/adh/graph/ConceptGraphClient',
    '@agentic-toolkit/adh/details/DetailsRail',
    '@agentic-toolkit/adh/marketing/LandingHeroGate',
    '@agentic-toolkit/adh/marketing/MarketingSiteHeader',
    // LAZY boundaries: a `next/dynamic(() => import(...))` specifier. External keeps it
    // a real dynamic import in the emitted JS for the consumer's bundler to code-split;
    // inlined, esbuild resolves it to the local file and it is evaluated eagerly on
    // every page — exactly the cost the split was for.
    '@agentic-toolkit/adh/footer/FooterChatInner',
    '@agentic-toolkit/adh/debug-console',
    // STATE (again, not a LAZY boundary like the two lines just above — nothing here is
    // a next/dynamic specifier): SettingsOverlayContext, held at module scope by
    // settings-overlay.tsx. It is the light settings barrel itself (Task 8: AppShell.tsx
    // mounts one SettingsOverlayProvider for the whole shell, and SiteHeader.tsx's
    // useSettingsOverlay() reads it back). Both reach it by package path from OTHER
    // entries — layout/index and header/index respectively — making it a self-reference
    // of exactly the class '@agentic-toolkit/adh/flags' and '@agentic-toolkit/adh/help'
    // are above, and the same STATE reason `@agentic-toolkit/adh/concepts` is. With
    // bundle:true/splitting:false, a relative '../settings/settings-overlay' from either
    // entry would inline its own PRIVATE context object, so AppShell's provider would
    // write into one instance while SiteHeader's useSettingsOverlay() read from a
    // different, never-provided one — a forked context, always null, silently, with no
    // build error, and invisible in dev/vitest/tsc (which resolve the `development`
    // condition straight to src, where there is exactly one module either way).
    // Preserved import ⇒ one copy, resolved by the consumer. BOTH halves required: this
    // entry, and every reaching module writing the full package path
    // '@agentic-toolkit/adh/settings' rather than a relative one.
    '@agentic-toolkit/adh/settings',
    // The User Settings overlay body (Task 7). settings-overlay.tsx's SettingsOverlayProvider
    // `lazy()`-imports this by package path so the panel graph — registry.tsx and everything
    // it assembles — survives into dist/settings/index.js as a real dynamic import for the
    // consumer's bundler to code-split, instead of esbuild inlining it and evaluating every
    // panel eagerly on every page that mounts the provider (i.e. every site). Same trick as
    // `@agentic-toolkit/adh/help/HelpWindow` above — but NOT the same barrel shape, and the
    // difference is the whole point: help/index.ts ALSO re-exports HelpWindow statically, and
    // a static re-export in an always-loaded barrel is exactly what pulls the lazy chunk back
    // into a consumer's eager graph. settings/index.ts therefore names this entry once, in
    // the dynamic import and nowhere else, and check-settings-boundary.py fails the build if
    // that stops being true. hub's /settings route — the one host that renders the panels as
    // a page — imports this specifier itself instead.
    '@agentic-toolkit/adh/settings/UserSettingsOverlay',
    // ThemePickerRow, split a level further below UserSettingsOverlay. AppearancePanel's
    // NEXT_PUBLIC_DEPLOYMENT_ENV-folded gate `next/dynamic`-imports it by package path so
    // there is a real chunk boundary for that gate to fold OUT of a production build — the
    // same shape as the dev-only theme trio directly below, just one entry up the chain
    // (settings/UserSettingsOverlay itself is already behind the lazy() split above, so this
    // is the gate INSIDE that already-lazy panel, not a second top-level split).
    '@agentic-toolkit/adh/settings/ThemePickerRow',
    // topics.ts (entry above). Reached internally only from settings/UserSettingsOverlay
    // (UserSettingsOverlay.tsx + registry.tsx) — preserved as a package-path import there
    // anyway, not because a relative one would duplicate it (both modules share that one
    // entry, so esbuild would dedupe them for free), but so the internal route matches the
    // external one exactly: `@agentic-toolkit/adh/settings/topics` is also the ONLY route a
    // consumer outside this package may use to reach SETTINGS_TOPICS/DEFAULT_SETTINGS_TOPIC/
    // resolveSettingsTopic without going through the "use client"-tainted settings/index
    // barrel — see settings/topics.ts's and settings/index.ts's own header comments.
    '@agentic-toolkit/adh/settings/topics',
    // The dev-only theme trio, and these three are LOAD-BEARING in a way the rest of this
    // list is not: they are what keeps the site-theme editor (Monaco included) out of every
    // production bundle. With splitting:false a relative `import('./SiteThemeConsole')` is
    // not code-split at all — esbuild inlines the module into the importing bundle behind a
    // lazy-init wrapper, so the folded gate in debug-env/DebugConsole.tsx has nothing left to
    // gate. theme-preview is here for the tree-shaking half of the same rule: as a preserved
    // import, the header bundle can drop it once the folded gate leaves it unreferenced. See
    // the chunk-gate contract in adh-registry's src/deployment-env.ts, and productionBundleGates.test.ts,
    // which checks this line against the entry, the tsconfig path and the exports map.
    '@agentic-toolkit/adh/debug-env/SiteThemeConsole',
    '@agentic-toolkit/adh/themes/theme-preview',
    // BARRELS reached across entries. `header` is also reached from WITHIN its own entry
    // (SiteHeader/SiteMenu/useSiteMenu/devToolsEntries import their own barrel); that
    // emits a self-import in dist/header/index.js, which resolves back to the module
    // already being evaluated — ESM live bindings handle it, and it is what the app tier
    // shipped before the merge. `theme-editor` and `header` both carry module state the console must share.
    '@agentic-toolkit/adh/header',
    '@agentic-toolkit/adh/header-auth',
    '@agentic-toolkit/adh/footer',
    '@agentic-toolkit/adh/layout',
    '@agentic-toolkit/adh/legal',
    '@agentic-toolkit/adh/graph',
    '@agentic-toolkit/adh/theme-editor',
    '@agentic-toolkit/adh/auth',
    '@agentic-toolkit/adh/server',
    // AppShell reaches the build identity by THIS path, not through '@agentic-toolkit/adh/server'
    // any more. Externalising it is what keeps the specifier bare in dist/layout/index.js, so the
    // consumer's resolver — not esbuild — decides the target, and can therefore apply the `browser`
    // condition. Inlined, the real module's `node:fs`/`node:child_process` would land INSIDE the
    // layout barrel, which is strictly worse than the bug this replaced.
    '@agentic-toolkit/adh/live-build-identity',
    // The telemetry BARREL (not just the two leaves above): layout/AppShell imports
    // SiteTelemetryProvider from it, and the provider's `setErrorReporter` writes the
    // same module-level `reporter` the leaves read. Inlined, AppShell would install the
    // reporter on a private copy and every captureException elsewhere would no-op.
    '@agentic-toolkit/adh/telemetry',
    // ── The two remaining adh-owned packages, now siblings in this workspace ─────────
    // The 45-site REGISTRY (ids, urls, env detection, route table). One copy, resolved
    // by the consuming site: `detectEnv`'s result and the route table must agree across
    // every entry, and the site the host builds for is the host's fact, not ours.
    // Subpaths listed separately — tsup's `external` matches specifiers, not packages.
    '@agentic-toolkit/adh-registry',
    '@agentic-toolkit/adh-registry/*',
    // bitbag: the footer chat's avatar + dock, and the theme vocabulary its `theme` prop
    // takes (re-exported by bitbag from the persona toolkit — see footer/chat-theme-store).
    // Its CSS subpath rides with the lazy FooterChatInner chunk.
    '@agentic-toolkit/bitbag',
    '@agentic-toolkit/bitbag/css/bitbag-dock.css',
    // The framework-agnostic landing KIT the deck is built from. The subpath form is the
    // load-bearing half: `@agenticdevelopertoolkit/landing/client` is that package's `'use client'`
    // entry, and tsup's `external` matches specifiers rather than packages, so the bare
    // name above does nothing for it. Inlined, preserve-directives would hoist NavChrome's
    // banner over the whole `landing` entry and every screen of every site's landing copy
    // would ship as a Client Component — legal, silent, and three copies of the words.
    '@agenticdevelopertoolkit/landing',
    '@agenticdevelopertoolkit/landing/*',
    // Only `react-slot` is left of Radix: it backs components/ui/button's `asChild`.
    // The avatar and dropdown-menu primitives went with the components that used
    // them (both now come from @agenticdevelopertoolkit/ui, on Base UI).
    '@radix-ui/react-slot',
    'class-variance-authority',
    'clsx',
    'lucide-react',
    'tailwind-merge',
    // The landing hero's animation (marketing/LandingHeroGate) and the theme editor's
    // Monaco. Both are heavy third-party libraries the consuming site already resolves;
    // bundling them into this dist would ship a second copy per entry that touches them.
    //
    // External is NOT a production gate. This comment used to claim the editor's Monaco was
    // "tree-shaken out there", and it wasn't — Monaco shipped in a ~110 KB chunk on every
    // site until the editor got its own entry above. What keeps it out is the four-leg gate
    // in adh-registry's src/deployment-env.ts; external only decides who resolves the copy.
    'motion',
    'motion/react',
    '@monaco-editor/react',
    'monaco-editor',
  ],
  // The ONE dependency deliberately inlined. `concepts/structure.ts` and
  // `concepts/content.ts` import the authored taxonomy JSON from
  // `@agentic-toolkit/adh-site-config`; esbuild's json loader turns it into a module in
  // THIS bundle. Left external, the emitted JS would carry a bare `import ... from
  // '@agentic-toolkit/adh-site-config/structure.json'` — an import ATTRIBUTE-less JSON
  // import that Next/Turbopack resolves inconsistently across dev and prod. Inlining is
  // also why `concepts/index` must be a boundary: the JSON lands once, in that entry.
  noExternal: ['@agentic-toolkit/adh-site-config'],
  esbuildPlugins: [
    preserveDirectivesPlugin({
      directives: ['use client', 'use server'],
      include: /\.(js|ts|jsx|tsx)$/,
      exclude: /node_modules/,
    }),
  ],
})
