<!-- leaf: implement-status-web-hooks/use-media-query · source: status-web-hooks-use-media-query.md -->

**Rules** (cite as `implement-status-web-hooks/use-media-query#<slug>`):

- `signature` MUST
- `initial-value` MUST
- `ssr-value` MUST
- `client-only-directive` MUST
- `mount-sync` MUST
- `change-subscription` MUST
- `unsubscribe-on-unmount` MUST
- `query-change-resubscribe` MUST
- `stable-query-no-resubscribe` MUST
- `stale-value-on-query-change` MUST
- `no-input-validation` MUST
- `no-environment-guard` MUST
- `modern-listener-api-only` MUST
- `no-side-effects` MUST
- `single-threaded-ordering` MUST

# useMediaQuery

## Overview

`useMediaQuery(query)` is a client-only React hook in the status-web package (`src/hooks/use-media-query.ts`) that reports whether a CSS media query currently matches the viewport. Its doc comment states the contract: it "Returns false during SSR / first paint (server can't measure the viewport), then updates after mount and on change." Callers use it to switch between layouts; in status-web, `OverviewTab` calls `useMediaQuery("(max-width: 760px)")` to pick the mobile layout and `WallboardStatus` calls `useMediaQuery("(min-width: 761px)")` to pick the wide layout.

## Behavioral Requirements

- **signature**: The hook MUST accept one argument, `query: string` (a CSS media query string), and MUST return a single `boolean`.
- **initial-value**: The hook MUST return `false` on the first render, before any effect runs, regardless of whether the query would match.
- **ssr-value**: The hook MUST return `false` during server-side rendering, where no viewport exists to measure.
- **client-only-directive**: The module MUST be marked as client code (the `"use client"` directive) so it runs only in the browser under a React Server Components framework.
- **mount-sync**: After mount, the hook MUST evaluate `query` against the current viewport and MUST update its returned value to that match result.
- **change-subscription**: After mount, the hook MUST subscribe to change notifications for `query` and MUST update its returned value to the `matches` value carried by each change event.
- **unsubscribe-on-unmount**: When the calling component unmounts, the hook MUST remove the change listener it registered.
- **query-change-resubscribe**: When `query` changes between renders, the hook MUST remove the listener for the previous query, MUST evaluate the new query immediately, and MUST subscribe to change notifications for the new query.
- **stable-query-no-resubscribe**: While `query` is unchanged between renders, the hook MUST NOT re-evaluate or re-subscribe.
- **stale-value-on-query-change**: On the render in which `query` changes, the hook returns the previous query's match result; the new query's result MUST appear only after the effect runs.
- **no-input-validation**: The hook MUST pass `query` to the platform media-query API unchanged; it performs no parsing or validation of its own.
- **no-environment-guard**: The hook MUST call the platform media-query API directly with no check that the API exists; in an environment without it the effect throws (the status-web test `OverviewTab.dom.test.tsx` notes "jsdom has no matchMedia; useMediaQuery calls it directly with no defensive guard" and stubs it).
- **modern-listener-api-only**: The hook MUST register with the standard `addEventListener("change", …)` / `removeEventListener("change", …)` pair; it has no fallback to the deprecated `addListener` / `removeListener` methods.
- **no-side-effects**: The hook MUST NOT perform network, file, storage, or logging side effects; its only side effect is the change-listener registration.
- **single-threaded-ordering**: All evaluation and listener callbacks MUST run on the browser main thread; state updates are applied in the order the platform delivers change events.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `query` | `string` | none (required) | CSS media query to evaluate and track, for example `"(max-width: 760px)"`. |
| Initial / SSR value | `boolean` | `false` | Hardcoded; not caller-configurable. |
| Media-query API | platform global | browser `window.matchMedia` | Read from the global environment, not injected; tests replace it with a stub global. |

## Platform Notes

- **React/Web**: Source is `packages/web/packages/status-web/src/hooks/use-media-query.ts`, a `"use client"` hook using `useState(false)` plus a `useEffect` keyed on `[query]` that calls `window.matchMedia`, seeds state from `mq.matches`, and adds a `change` listener that it removes in the effect cleanup. A `useSyncExternalStore` port with a server snapshot of `false` would remove the stale render on query change while keeping SSR output identical.
- **SwiftUI**: There is no CSS media query; the equivalent is reading environment values such as `@Environment(\.horizontalSizeClass)` or measuring with `GeometryReader` / `onGeometryChange`. These update automatically, so no manual subscribe and unsubscribe exists; there is no SSR phase, so the "false on first render" rule has no counterpart unless deliberately reproduced.
- **Compose**: Use `LocalConfiguration.current.screenWidthDp` or `currentWindowAdaptiveInfo().windowSizeClass` (Material 3 adaptive) inside composition; recomposition replaces the change listener. `BoxWithConstraints` covers container-relative queries.
- **AppKit / UIKit**: Override `traitCollectionDidChange` or use `registerForTraitChanges` (UIKit) and `viewDidLayout` / `NSWindow` resize notifications (AppKit) to re-evaluate a width predicate; remove observers on deinit to match the unmount cleanup.
- **WinUI 3**: Use `AdaptiveTrigger` with `MinWindowWidth` inside a `VisualStateManager.VisualStateGroups` block for pure XAML layout switching; for a boolean exposed to code, subscribe to `Window.SizeChanged` (or `FrameworkElement.SizeChanged` on the root) and set a property on a view model implementing `INotifyPropertyChanged`, unsubscribing in `Unloaded`. A predicate such as `width <= 760` replaces the CSS query string, so there is no string parsing and no malformed-query case. There is no server render, so the value is known at first layout; reproduce the `false` initial value only if parity with the web layout switch matters.

## Design Decisions

**Decision**: Return `false` until the component mounts, rather than reading the media query during render.

**Rationale**: The doc comment states the server "can't measure the viewport"; a fixed `false` keeps the server render and the first client render identical, which avoids a hydration mismatch.

**Approved**: pending

---

**Decision**: Call `window.matchMedia` with no existence guard.

**Rationale**: The hook targets browsers where the API always exists; test environments that lack it (jsdom) stub it, as `OverviewTab.dom.test.tsx` does, instead of the hook carrying a fallback.

**Approved**: pending

---

**Decision**: Re-seed state from `mq.matches` inside the effect on every query change.

**Rationale**: A change listener fires only on transitions, so without the immediate read the value would stay at the previous query's result until the viewport next crossed the new query's boundary.

**Approved**: pending
