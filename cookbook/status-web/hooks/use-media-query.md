---
id: 6b796310-ff12-4d38-a1a9-1d3af3f1e87f
title: useMediaQuery
domain: agentictoolkit://cookbook/status-web/hooks/use-media-query
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook that tracks whether a CSS media query matches, returning false
  during SSR and first paint and updating on change.
platforms:
- typescript
- web
tags: []
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a React state hook over a media-query subscription, not a visual component.

## States

Not applicable — this is a React state hook over a media-query subscription, not a visual component.

## Accessibility

Not applicable — this is a React state hook over a media-query subscription, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| media-query-001 | initial-value | Viewport matches `"(max-width: 760px)"`; inspect the value returned from the very first render, before effects run | `false` |
| media-query-002 | ssr-value | Server-render a component calling `useMediaQuery("(min-width: 761px)")` | Rendered output reflects `false` |
| media-query-003 | mount-sync | Stubbed media-query API returns `matches: true` for the query; render and flush effects | Returned value becomes `true` |
| media-query-004 | mount-sync | Stubbed media-query API returns `matches: false`; render and flush effects | Returned value stays `false` |
| media-query-005 | change-subscription | After mount with `matches: false`, dispatch a change event with `matches: true` | Returned value becomes `true`; a following event with `matches: false` returns it to `false` |
| media-query-006 | unsubscribe-on-unmount | Mount, then unmount the calling component | `removeEventListener` is called once with `"change"` and the same handler passed to `addEventListener` |
| media-query-007 | query-change-resubscribe | Re-render with `query` changed from `"(max-width: 760px)"` to `"(min-width: 761px)"` | Old listener removed, media-query API called with the new query, new listener added, value set to the new query's `matches` |
| media-query-008 | stable-query-no-resubscribe | Re-render with the same `query` string | Media-query API is not called again; `addEventListener` call count unchanged |
| media-query-009 | stale-value-on-query-change | Mounted with query A (matches `true`); re-render with query B (matches `false`) | The render with B first returns `true`, then `false` after the effect runs |
| media-query-010 | no-environment-guard | Media-query API is absent (jsdom without a stub); render and flush effects | The effect throws a TypeError; the hook does not return a fallback |

## Edge Cases

- **Empty query string**: `useMediaQuery("")` MUST pass `""` to the platform API unchanged; the returned value is whatever `matches` the platform reports for it (browsers treat an empty media query as matching all).
- **Malformed query**: A syntactically invalid query MUST be passed through unchanged; the platform reports it as `not all`, so the hook returns `false` and no change event is expected to fire.
- **Missing media-query API**: In an environment without the API (jsdom, some test runners), the effect MUST throw; callers or tests are responsible for stubbing it.
- **Query changes every render**: A caller that builds a new query string on every render with different content MUST cause a teardown and resubscribe on every such render; a caller passing an identical string MUST NOT.
- **Unmount before effect runs**: If the component unmounts before its effect runs, no subscription is created and no cleanup runs.
- **Change event after unmount**: Because cleanup removes the listener, no state update MUST occur from change events that fire after unmount.
- **Rapid consecutive change events**: Each event MUST set state to that event's `matches`; the final returned value is the last delivered event's value.
- **Concurrent calls**: Multiple components calling the hook with the same query each MUST create an independent subscription and state; there is no shared cache.
- **Cancellation, timeout, network**: Not applicable — the hook makes no asynchronous request and has nothing to cancel or time out beyond listener removal.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `query` | `string` | none (required) | CSS media query to evaluate and track, for example `"(max-width: 760px)"`. |
| Initial / SSR value | `boolean` | `false` | Hardcoded; not caller-configurable. |
| Media-query API | platform global | browser `window.matchMedia` | Read from the global environment, not injected; tests replace it with a stub global. |

## Deep Linking

Not applicable: the hook reads only a media query and registers no URL or route.

## Localization

Not applicable: the hook contains no user-facing strings.

## Accessibility Options

Not applicable: the hook responds to whatever query the caller passes and hardcodes no preference such as reduced motion or contrast; a caller could pass such a query, but the hook itself has no option-specific behavior.

## Feature Flags

Not applicable: the hook is not gated by any feature flag.

## Analytics

Not applicable: the hook emits no analytics events.

## Privacy

Not applicable: the hook reads a viewport media-query result in memory and stores or transmits nothing.

## Logging

Not applicable: the hook makes no logging calls.

## Platform Notes

- **React/Web**: Source is `packages/web/packages/status-web/src/hooks/use-media-query.ts`, a `"use client"` hook using `useState(false)` plus a `useEffect` keyed on `[query]` that calls `window.matchMedia`, seeds state from `mq.matches`, and adds a `change` listener that it removes in the effect cleanup. A `useSyncExternalStore` port with a server snapshot of `false` would remove the stale render on query change while keeping SSR output identical.
- **SwiftUI**: There is no CSS media query; the equivalent is reading environment values such as `@Environment(\.horizontalSizeClass)` or measuring with `GeometryReader` / `onGeometryChange`. These update automatically, so no manual subscribe and unsubscribe exists; there is no SSR phase, so the "false on first render" rule has no counterpart unless deliberately reproduced.
- **Compose**: Use `LocalConfiguration.current.screenWidthDp` or `currentWindowAdaptiveInfo().windowSizeClass` (Material 3 adaptive) inside composition; recomposition replaces the change listener. `BoxWithConstraints` covers container-relative queries.
- **AppKit / UIKit**: Override `traitCollectionDidChange` or use `registerForTraitChanges` (UIKit) and `viewDidLayout` / `NSWindow` resize notifications (AppKit) to re-evaluate a width predicate; remove observers on deinit to match the unmount cleanup.
- **WinUI 3**: Use `AdaptiveTrigger` with `MinWindowWidth` inside a `VisualStateManager.VisualStateGroups` block for pure XAML layout switching; for a boolean exposed to code, subscribe to `Window.SizeChanged` (or `FrameworkElement.SizeChanged` on the root) and set a property on a view model implementing `INotifyPropertyChanged`, unsubscribing in `Unloaded`. A predicate such as `width <= 760` replaces the CSS query string, so there is no string parsing and no malformed-query case. There is no server render, so the value is known at first layout; reproduce the `false` initial value only if parity with the web layout switch matters.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-media-query.ts` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | performance |

The hook isolates viewport measurement from the components that consume it, returning only a boolean, so layout components hold no media-query plumbing. There is no dedicated test file for the hook: it is exercised only indirectly through `OverviewTab.dom.test.tsx`, which stubs the media-query API with a fixed `matches` value and no-op listener methods, so mount sync is covered but change delivery, cleanup and query-change resubscription are not asserted. The hook swallows no errors; a missing API surfaces as a thrown exception. Its work is a single synchronous query evaluation per mount or query change plus an event callback, which does not block the main thread.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
