---
id: f97631a6-531f-45c9-98a9-c5a292a2e6ea
title: useActivityTtl
domain: agentictoolkit://cookbook/status-web/hooks/use-activity-ttl
type: ingredient
version: 1.0.1
status: review
language: en
created: 2026-09-24
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook that manages user-configured activity retention duration, persisted
  to localStorage.
platforms:
- web
tags: []
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# useActivityTtl

## Overview

A React hook that manages how long activity items remain in the activity list before automatic age-out. The user's choice (in minutes, or null for indefinite retention) is persisted to `localStorage` so it survives page reloads. The hook provides both the persisted value and a convenience millisecond form for filtering operations.

## Behavioral Requirements

- **initialization**: The hook MUST initialize to `DEFAULT_ACTIVITY_TTL_MS` (60 minutes) on first render, before hydration completes.
- **supported-values**: The selectable values are `ACTIVITY_TTL_OPTIONS_MIN` ([1, 15, 30, 60] minutes) plus `null` (indefinite retention). Only hydration enforces this set; `setTtl` stores and persists whatever number it is given, so callers MUST pass one of these values (the `ActivityTtl` type is `number | null`).
- **persistence-key**: The hook MUST persist the user's choice to `localStorage` under the key `"adh-healthy-ttl"` as a JSON-serialized value.
- **hydration**: The hook MUST hydrate the stored value from `localStorage` in a `useEffect` with an empty dependency array, executing only once after the initial render.
- **null-as-stored-value**: The hook MUST correctly deserialize `null` as a stored value (indefinite retention), not treat it as "no stored value".
- **invalid-value-rejection**: If the stored value is not `null` and not a number in `ACTIVITY_TTL_OPTIONS_MIN`, the hook MUST ignore it and retain the default.
- **parse-error-handling**: If `JSON.parse` throws, the hook MUST silently catch the exception and retain the current state.
- **persistence-error-handling**: If `localStorage.setItem` throws, the hook MUST silently catch the exception and leave the in-memory value intact.
- **return-shape**: The hook MUST return an object with exactly three properties: `ttlMin` (the stored value in minutes, or `null`), `ttlMs` (the value in milliseconds, or `null` if `ttlMin` is `null`), and `setTtl` (a function).
- **setTtl-signature**: The function `setTtl` MUST accept an `ActivityTtl` argument (a number from `ACTIVITY_TTL_OPTIONS_MIN` or `null`), update in-memory state immediately, and attempt to persist to `localStorage`.
- **ttlMs-calculation**: The hook MUST convert `ttlMin` to `ttlMs` by multiplying by 60,000 (ms/min), or return `null` if `ttlMin` is `null`.
- **ssr-hydration-match**: The hook MUST ensure the initial render (before `useEffect` runs) shows the default, preventing hydration mismatches between server and client.

## Appearance

Not applicable — this is a React hook, not a visual component.

## States

Not applicable — this is a React hook, not a visual component.

## Accessibility

Not applicable — this is a React hook, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input/Precondition | Action | Expected Output |
|----|---|---|---|---|
| activity-ttl-001 | initialization | First render, no localStorage | Render hook | Returns `{ ttlMin: 60, ttlMs: 3600000, setTtl: <function> }` |
| activity-ttl-002 | hydration | localStorage contains `"adh-healthy-ttl": 30` | Render hook and allow useEffect | After effect runs, `ttlMin` becomes `30` and `ttlMs` becomes `1800000` |
| activity-ttl-003 | null-as-stored-value | localStorage contains `"adh-healthy-ttl": null` | Render hook and allow useEffect | After effect runs, `ttlMin` is `null` and `ttlMs` is `null` |
| activity-ttl-004 | invalid-value-rejection | localStorage contains `"adh-healthy-ttl": 45` (not in valid options) | Render hook and allow useEffect | State remains at default (`ttlMin: 60`, `ttlMs: 3600000`) |
| activity-ttl-005 | parse-error-handling | localStorage contains `"adh-healthy-ttl": "{invalid json"` | Render hook and allow useEffect | Exception is caught, state remains default |
| activity-ttl-006 | setTtl-valid | Call `setTtl(15)` | Observe state change and localStorage write | `ttlMin` is `15`, `ttlMs` is `900000`, localStorage has `"adh-healthy-ttl": 15` |
| activity-ttl-007 | setTtl-null | Call `setTtl(null)` | Observe state change and localStorage write | `ttlMin` is `null`, `ttlMs` is `null`, localStorage has `"adh-healthy-ttl": null` |
| activity-ttl-008 | persistence-error-handling | `localStorage.setItem` throws (e.g., quota exceeded) | Call `setTtl(30)` | State updates to `ttlMin: 30, ttlMs: 1800000`, exception is caught, in-memory value persists |
| activity-ttl-009 | ssr-hydration-match | SSR render followed by browser hydration | Server-render and hydrate in browser with empty localStorage | Initial paint matches default (`ttlMin: 60`, `ttlMs: 3600000`), no hydration warning |

## Edge Cases

- **Empty localStorage key**: If `localStorage.getItem("adh-healthy-ttl")` returns `null`, the hook MUST keep the default and not attempt to parse `null`.
- **Malformed JSON in storage**: If stored value is valid JSON but not a recognized structure (e.g., `"adh-healthy-ttl": "string"` or `"adh-healthy-ttl": {}`), the hook MUST reject it and keep the default.
- **Out-of-range number**: If a number outside `ACTIVITY_TTL_OPTIONS_MIN` is stored (e.g., `50` or `120`), the hook MUST reject it and keep the default.
- **Type narrowing after JSON parse**: After `JSON.parse`, the value is `unknown`; the hook MUST check both type and membership in `VALID` before accepting.
- **localStorage unavailable**: If the browser environment lacks `localStorage` (e.g., private browsing, blocked), both read and write operations MUST catch and ignore exceptions.
- **Quota exceeded on write**: If `localStorage.setItem` throws due to quota, the state change MUST proceed in-memory and the hook MUST not propagate the error.
- **Rapid setTtl calls**: Multiple `setTtl` calls in quick succession MUST each attempt to persist; if some writes fail, others MAY succeed independently.
- **Hook unmount before hydration**: If the component unmounts before `useEffect` runs, no state update attempt MUST occur (React's cleanup handles this).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DEFAULT_ACTIVITY_TTL_MS` | `number` | `3600000` (60 minutes) | Fallback age-out duration in milliseconds if no user choice is stored. |
| `ACTIVITY_TTL_OPTIONS_MIN` | `number[]` | `[1, 15, 30, 60]` | Array of valid age-out durations in minutes; also defines the set of permitted stored values. |
| Storage key | `string` | `"adh-healthy-ttl"` | Hardcoded localStorage key for persisting the user's choice. Key is unchanged from an earlier "Healthy" feature rename to preserve existing user settings. |

## Deep Linking

Not applicable: this is a hook (no URL patterns).

## Localization

Not applicable: the hook contains no user-facing strings.

## Accessibility Options

Not applicable: the hook contains no accessible UI or state.

## Feature Flags

Not applicable: the hook is not gated by a feature flag.

## Analytics

Not applicable: the hook logs no analytics events.

## Privacy

Not applicable: the hook stores only a user's time-preference setting (a number or null) in browser localStorage; no sensitive personal data is collected, transmitted, or retained.

## Logging

Not applicable: the hook logs no debug or warning messages.

## Platform Notes

- **React/Web**: Source is a custom React hook (`useActivityTtl`) using `useState` for in-memory state, `useEffect` for one-shot hydration from `localStorage`, and `useCallback` to memoize `setTtl`. The `"use client"` directive indicates it is a client component in a Next.js App Router context.
- **SwiftUI**: Equivalent to a `@State` property or `@EnvironmentObject` that reads and writes to `UserDefaults` (macOS) or `NSUserDefaults` (iOS) with a hardcoded key. Hydration would occur during `onAppear`.
- **Compose**: Equivalent to a `ViewModel` with a `MutableState<Int?>` or a custom `Preference` data store that persists to `SharedPreferences`.
- **AppKit / UIKit**: Equivalent to a view controller property backed by `UserDefaults` with custom getters/setters for persistence and recovery.
- **WinUI 3**: Equivalent to a `ViewModel` (INotifyPropertyChanged) with a private backing field that reads/writes to `Windows.Storage.ApplicationData.Current.LocalSettings` or `IsolatedStorageSettings`. Loading from settings MUST validate against the allowed set (the setter, like `setTtl`, does not) and gracefully handle deserialization errors. Multi-user / profile-switching behavior differs: Windows Settings are per-user per-app; the equivalent of `localStorage.clear()` on logout is the app's responsibility.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-activity-ttl.ts` |

## Design Decisions

**Decision**: Hydration deferred to `useEffect` despite initialization to default.

**Rationale**: Ensures SSR/first paint matches the default (preventing hydration mismatch warnings) and treats `localStorage` as an external store updated after render, not as derived state.

**Approved**: pending

---

**Decision**: Silently ignoring `localStorage` errors instead of propagating or logging them.

**Rationale**: `localStorage` is not guaranteed to be available (private browsing, quota exceeded); the hook falls back to the in-memory state, which is sufficient for correctness. No user-facing error is necessary because the feature (age-out) remains functional with the default.

**Approved**: pending

---

**Decision**: Key `"adh-healthy-ttl"` deliberately unchanged from the earlier "Healthy" feature.

**Rationale**: Renaming would reset every existing reader's choice to the default, breaking user preference persistence.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |

The hook is a narrowly scoped, single-responsibility hook (activity TTL management). Errors from `localStorage` access and `JSON.parse` are caught and isolated via try-catch blocks, preventing cascade failures; the fallback (in-memory state with default) is always available. State changes are exposed through the `setTtl` callback only, ensuring controlled mutation.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
