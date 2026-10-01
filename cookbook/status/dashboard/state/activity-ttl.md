---
id: f97631a6-531f-45c9-98a9-c5a292a2e6ea
title: Activity TTL
domain: agentictoolkit://cookbook/status/dashboard/state/activity-ttl
type: ingredient
version: 1.1.0
status: review
language: en
created: 2026-09-24
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Manages user-configured activity retention duration, persisted to durable
  browser storage.
platforms:
- web
tags: []
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Activity TTL

## Overview

This logic manages how long activity items remain in the activity list before automatic age-out. The user's choice (in minutes, or absent for indefinite retention) is persisted to durable browser storage so it survives page reloads. This logic provides both the persisted value and a convenience millisecond form for filtering operations.

## Behavioral Requirements

- **initialization**: This logic MUST initialize to a default of 60 minutes on first render, before hydration completes.
- **supported-values**: The selectable values are 1, 15, 30, or 60 minutes, plus no value at all (indefinite retention). Only hydration enforces this set; `setTtl` stores and persists whatever number it is given, so callers MUST pass one of these values.
- **persistence-key**: This logic MUST persist the user's choice to durable browser storage under the key `"adh-healthy-ttl"` as a JSON-serialized value.
- **hydration**: This logic MUST hydrate the stored value from durable browser storage once, after the initial render, and not again.
- **null-as-stored-value**: This logic MUST correctly deserialize a stored `null` (indefinite retention) as a real, present choice, not treat it as "no stored value".
- **invalid-value-rejection**: If the stored value is not `null` and not one of the selectable minute values, this logic MUST ignore it and retain the default.
- **parse-error-handling**: If parsing the stored JSON fails, this logic MUST silently catch the failure and retain the current state.
- **persistence-error-handling**: If writing to durable browser storage fails, this logic MUST silently catch the failure and leave the in-memory value intact.
- **return-shape**: This logic MUST return an object with exactly three fields: `ttlMin` (the stored value in minutes, or `null`), `ttlMs` (the value in milliseconds, or `null` if `ttlMin` is `null`), and `setTtl` (a callback).
- **setTtl-signature**: The `setTtl` callback MUST accept a number from the selectable set or `null`, update in-memory state immediately, and attempt to persist to durable browser storage.
- **ttlMs-calculation**: This logic MUST convert `ttlMin` to `ttlMs` by multiplying by 60,000 (milliseconds per minute), or return `null` if `ttlMin` is `null`.
- **ssr-hydration-match**: This logic MUST ensure the initial render (before hydration runs) shows the default, preventing mismatches between a server-rendered first paint and the client (see Platform Notes).

## Appearance

Not applicable — this logic manages state, not a visual component.

## States

Not applicable — this logic manages state, not a visual component.

## Accessibility

Not applicable — this logic manages state, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input/Precondition | Action | Expected Output |
|----|---|---|---|---|
| activity-ttl-001 | initialization | First render, no stored value | This logic runs for the first time | Returns `ttlMin: 60`, `ttlMs: 3600000`, and a `setTtl` callback |
| activity-ttl-002 | hydration | Durable storage holds `"adh-healthy-ttl": 30` | This logic runs and hydration completes | After hydration, `ttlMin` becomes `30` and `ttlMs` becomes `1800000` |
| activity-ttl-003 | null-as-stored-value | Durable storage holds `"adh-healthy-ttl": null` | This logic runs and hydration completes | After hydration, `ttlMin` is `null` and `ttlMs` is `null` |
| activity-ttl-004 | invalid-value-rejection | Durable storage holds `"adh-healthy-ttl": 45` (not in valid options) | This logic runs and hydration completes | State remains at default (`ttlMin: 60`, `ttlMs: 3600000`) |
| activity-ttl-005 | parse-error-handling | Durable storage holds `"adh-healthy-ttl": "{invalid json"` | This logic runs and hydration completes | The parse failure is caught, state remains default |
| activity-ttl-006 | setTtl-valid | The `setTtl` callback is called with `15` | Observe the state change and the storage write | `ttlMin` is `15`, `ttlMs` is `900000`, durable storage has `"adh-healthy-ttl": 15` |
| activity-ttl-007 | setTtl-null | The `setTtl` callback is called with no value | Observe the state change and the storage write | `ttlMin` is `null`, `ttlMs` is `null`, durable storage has `"adh-healthy-ttl": null` |
| activity-ttl-008 | persistence-error-handling | The durable-storage write fails (e.g., quota exceeded) | The `setTtl` callback is called with `30` | State updates to `ttlMin: 30, ttlMs: 1800000`, the failure is caught, in-memory value persists |
| activity-ttl-009 | ssr-hydration-match | A server-rendered first paint followed by browser hydration | The page is server-rendered and then hydrated in the browser with no stored value | Initial paint matches default (`ttlMin: 60`, `ttlMs: 3600000`), no mismatch warning |

## Edge Cases

- **Empty stored key**: If reading the stored value for `"adh-healthy-ttl"` returns nothing, this logic MUST keep the default and not attempt to parse it.
- **Malformed JSON in storage**: If the stored value is valid JSON but not a recognized structure (e.g., `"adh-healthy-ttl": "string"` or `"adh-healthy-ttl": {}`), this logic MUST reject it and keep the default.
- **Out-of-range number**: If a number outside the selectable set is stored (e.g., `50` or `120`), this logic MUST reject it and keep the default.
- **Type narrowing after parse**: After parsing, the value's type is not yet known; this logic MUST check both its type and its membership in the valid set before accepting it.
- **Durable storage unavailable**: If the runtime's durable storage is unavailable (e.g., private browsing, blocked), both read and write operations MUST catch and ignore the failure.
- **Quota exceeded on write**: If the durable-storage write fails due to quota, the state change MUST proceed in-memory and this logic MUST not propagate the error.
- **Rapid setTtl calls**: Multiple `setTtl` calls in quick succession MUST each attempt to persist; if some writes fail, others MAY succeed independently.
- **Teardown before hydration**: If the hook instance is torn down before hydration runs, no state update attempt MUST occur (the runtime's cleanup handles this).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Default TTL | number | `3600000` (60 minutes) | Fallback age-out duration in milliseconds if no user choice is stored. |
| Selectable TTL options (minutes) | list of numbers | `[1, 15, 30, 60]` | Valid age-out durations in minutes; also defines the set of permitted stored values. |
| Storage key | string | `"adh-healthy-ttl"` | Hardcoded durable-storage key for persisting the user's choice. Key is unchanged from an earlier "Healthy" feature rename to preserve existing user settings. |

## Deep Linking

Not applicable: this logic exposes no URL patterns.

## Localization

Not applicable: this logic contains no user-facing strings.

## Accessibility Options

Not applicable: this logic contains no accessible UI or state.

## Feature Flags

Not applicable: this logic is not gated by a feature flag.

## Analytics

Not applicable: this logic logs no analytics events.

## Privacy

Not applicable: this logic stores only a user's time-preference setting (a number or absent) in durable browser storage; no sensitive personal data is collected, transmitted, or retained.

## Logging

Not applicable: this logic logs no debug or warning messages.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
