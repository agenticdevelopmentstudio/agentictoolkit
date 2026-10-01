---
id: 6b796310-ff12-4d38-a1a9-1d3af3f1e87f
title: Media Query
domain: agentictoolkit://cookbook/status/dashboard/state/media-query
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: State that tracks whether a CSS media query matches, returning false during
  a server-rendering pass and first paint and updating on change.
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

# Media Query

## Overview

Media Query is client-only state that reports whether a CSS media query currently matches the viewport. Its contract: it returns false during a server-rendering pass and first paint (the server can't measure the viewport), then updates after its subscription is established and on every change. Callers use it to switch between layouts; in the status dashboard, the overview view evaluates `"(max-width: 760px)"` to pick the mobile layout and the wallboard status view evaluates `"(min-width: 761px)"` to pick the wide layout.

## Behavioral Requirements

- **signature**: Media Query MUST accept one input, a CSS media query string, and MUST return a single boolean value.
- **initial-value**: Media Query MUST return `false` on the first evaluation, before any subscription is established, regardless of whether the query would match.
- **ssr-value**: Media Query MUST return `false` during a server-rendering pass, where no viewport exists to measure.
- **client-only-directive**: Media Query has no server-only or universal-rendering variant; it requires a live client execution context.
- **mount-sync**: Once its subscription is established, Media Query MUST evaluate the query against the current viewport and MUST update its returned value to that match result.
- **change-subscription**: Once subscribed, Media Query MUST listen for change notifications for the query and MUST update its returned value to the match value carried by each notification.
- **unsubscribe-on-unmount**: When the caller stops using it, Media Query MUST remove the change listener it registered.
- **query-change-resubscribe**: When the query input changes, Media Query MUST remove the listener for the previous query, MUST evaluate the new query immediately, and MUST subscribe to change notifications for the new query.
- **stable-query-no-resubscribe**: While the query input is unchanged, Media Query MUST NOT re-evaluate or re-subscribe.
- **stale-value-on-query-change**: At the moment the query input changes, Media Query MUST still report the previous query's match result; the new query's result appears only once its subscription updates.
- **no-input-validation**: Media Query MUST pass the query to the environment's media-query facility unchanged; it performs no parsing or validation of its own.
- **no-environment-guard**: Media Query MUST call the environment's media-query facility directly with no check that it exists; in an environment without that facility, evaluation fails with an error.
- **modern-listener-api-only**: Media Query MUST register for change notifications using the environment's standard subscribe/unsubscribe pair; it has no fallback to a deprecated listener-registration mechanism.
- **no-side-effects**: Media Query MUST NOT perform network, file, storage, or logging side effects; its only side effect is the change-listener registration.
- **single-threaded-ordering**: All evaluation and listener callbacks MUST run on a single execution thread; updates are applied in the order the environment delivers change notifications.

## Appearance

Not applicable — this is state over a media-query subscription, not a visual component.

## States

Not applicable — this is state over a media-query subscription, not a visual component.

## Accessibility

Not applicable — this is state over a media-query subscription, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| media-query-001 | initial-value | Viewport matches `"(max-width: 760px)"`; inspect the value from the very first evaluation, before any subscription is established | `false` |
| media-query-002 | ssr-value | Render, in a server-rendering pass, something that evaluates `"(min-width: 761px)"` | Rendered output reflects `false` |
| media-query-003 | mount-sync | The media-query facility reports a match for the query; establish the subscription and let it settle | Returned value becomes `true` |
| media-query-004 | mount-sync | The media-query facility reports no match; establish the subscription and let it settle | Returned value stays `false` |
| media-query-005 | change-subscription | After subscribing with no match, deliver a change notification reporting a match | Returned value becomes `true`; a following notification reporting no match returns it to `false` |
| media-query-006 | unsubscribe-on-unmount | Subscribe, then stop using it | The environment's unsubscribe operation is called once, removing the same handler that was registered |
| media-query-007 | query-change-resubscribe | Re-evaluate with the query changed from `"(max-width: 760px)"` to `"(min-width: 761px)"` | Old listener removed, the media-query facility asked about the new query, new listener added, value set to the new query's match result |
| media-query-008 | stable-query-no-resubscribe | Re-evaluate with the same query string | The media-query facility is not asked again; the subscribe count is unchanged |
| media-query-009 | stale-value-on-query-change | Subscribed with query A (matches); the query input changes to query B (no match) | Immediately after the change it still returns `true`, then `false` once the subscription updates |
| media-query-010 | no-environment-guard | The media-query facility is absent; establish the subscription | Evaluation fails with an error; Media Query does not return a fallback |

## Edge Cases

- **Empty query string**: Passing `""` MUST pass `""` to the media-query facility unchanged; the returned value is whatever match result the environment reports for it (an empty media query is commonly treated as matching everything).
- **Malformed query**: A syntactically invalid query MUST be passed through unchanged; the environment commonly reports it as never matching, so Media Query returns `false` and no change notification is expected to fire.
- **Missing media-query facility**: In an environment without it, evaluation MUST fail with an error; callers or tests are responsible for supplying a stand-in.
- **Query changes every evaluation**: A caller that builds a new query string with different content each time MUST cause a teardown and resubscribe each time; a caller passing an identical string MUST NOT.
- **Stops being used before its subscription is established**: If the caller stops using it before that point, no subscription is created and no cleanup runs.
- **Change notification after the caller stops using it**: Because cleanup removes the listener, no update MUST occur from a notification that fires afterward.
- **Rapid consecutive change notifications**: Each notification MUST set the returned value to that notification's match result; the final value is the last delivered notification's value.
- **Concurrent uses**: Multiple callers evaluating the same query each MUST get an independent subscription and value; there is no shared cache.
- **Cancellation, timeout, network**: Not applicable — Media Query makes no asynchronous request and has nothing to cancel or time out beyond listener removal.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Query | string | none (required) | CSS media query to evaluate and track, for example `"(max-width: 760px)"`. |
| Initial / server-render value | boolean | `false` | Hardcoded; not caller-configurable. |
| Media-query facility | environment capability | the platform's built-in media-query facility | Read from the global environment, not injected; tests replace it with a stand-in. |

## Deep Linking

Not applicable: Media Query reads only a media query and registers no URL or route.

## Localization

Not applicable: Media Query contains no user-facing strings.

## Accessibility Options

Not applicable: Media Query responds to whatever query the caller passes and hardcodes no preference such as reduced motion or contrast; a caller could pass such a query, but Media Query itself has no option-specific behavior.

## Feature Flags

Not applicable: Media Query is not gated by any feature flag.

## Analytics

Not applicable: Media Query emits no analytics events.

## Privacy

Not applicable: Media Query reads a viewport match result in memory and stores or transmits nothing.

## Logging

Not applicable: Media Query makes no logging calls.

## Platform Notes

- **React/Web**: Source is `packages/web/packages/status-web/src/hooks/use-media-query.ts`, a `"use client"` hook `useMediaQuery(query: string)` using `useState(false)` plus a `useEffect` keyed on `[query]` that calls `window.matchMedia`, seeds state from `mq.matches`, and adds a `change` listener via `addEventListener("change", …)` that it removes (`removeEventListener`) in the effect cleanup. In an environment without `window.matchMedia` (jsdom, some test runners) the effect throws a `TypeError`; the status-web test `OverviewTab.dom.test.tsx` notes "jsdom has no matchMedia; useMediaQuery calls it directly with no defensive guard" and stubs the global. A `useSyncExternalStore` port with a server snapshot of `false` would remove the stale render on query change while keeping server-render output identical.
- **SwiftUI**: There is no CSS media query; the equivalent is reading environment values such as `@Environment(\.horizontalSizeClass)` or measuring with `GeometryReader` / `onGeometryChange`. These update automatically, so no manual subscribe and unsubscribe exists; there is no server-render phase, so the "false on first render" rule has no counterpart unless deliberately reproduced.
- **Compose**: Use `LocalConfiguration.current.screenWidthDp` or `currentWindowAdaptiveInfo().windowSizeClass` (Material 3 adaptive) inside composition; recomposition replaces the change listener. `BoxWithConstraints` covers container-relative queries.
- **AppKit / UIKit**: Override `traitCollectionDidChange` or use `registerForTraitChanges` (UIKit) and `viewDidLayout` / `NSWindow` resize notifications (AppKit) to re-evaluate a width predicate; remove observers on deinit to match the unmount cleanup.
- **WinUI 3**: Use `AdaptiveTrigger` with `MinWindowWidth` inside a `VisualStateManager.VisualStateGroups` block for pure XAML layout switching; for a boolean exposed to code, subscribe to `Window.SizeChanged` (or `FrameworkElement.SizeChanged` on the root) and set a property on a view model implementing `INotifyPropertyChanged`, unsubscribing in `Unloaded`. A predicate such as `width <= 760` replaces the CSS query string, so there is no string parsing and no malformed-query case. There is no server render, so the value is known at first layout; reproduce the `false` initial value only if parity with the web layout switch matters.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-media-query.ts` |

## Design Decisions

**Decision**: Return `false` until the subscription is established, rather than reading the media query immediately.

**Rationale**: The contract states the server "can't measure the viewport"; a fixed `false` keeps the server render and the first client render identical, which avoids a hydration mismatch. This rationale applies to the web platform, where a server-rendering pass and a client paint must agree; a platform with no such split has no counterpart requirement.

**Approved**: pending

---

**Decision**: Call the environment's media-query facility with no existence guard.

**Rationale**: Media Query targets environments where the facility always exists; test environments that lack it (jsdom) stub it, as `OverviewTab.dom.test.tsx` does, instead of Media Query carrying a fallback.

**Approved**: pending

---

**Decision**: Re-seed the value from the facility's match result on every query change.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
</content>
