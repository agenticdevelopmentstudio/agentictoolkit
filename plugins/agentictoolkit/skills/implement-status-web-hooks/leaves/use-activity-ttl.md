<!-- leaf: implement-status-web-hooks/use-activity-ttl · source: status-web-hooks-use-activity-ttl.md -->

**Rules** (cite as `implement-status-web-hooks/use-activity-ttl#<slug>`):

- `initialization` MUST
- `supported-values` MUST
- `persistence-key` MUST
- `hydration` MUST
- `null-as-stored-value` MUST
- `invalid-value-rejection` MUST
- `parse-error-handling` MUST
- `persistence-error-handling` MUST
- `return-shape` MUST
- `setttl-signature` MUST — The function setTtl MUST accept an ActivityTtl argument (a number from ACTIVITY_TTL_OPTIONS_MIN or null), update …
- `ttlms-calculation` MUST — The hook MUST convert ttlMin to ttlMs by multiplying by 60,000 (ms/min), or return null if ttlMin is null.
- `ssr-hydration-match` MUST
- `winui-3` MUST — Equivalent to a ViewModel (INotifyPropertyChanged) with a private backing field that reads/writes to …

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DEFAULT_ACTIVITY_TTL_MS` | `number` | `3600000` (60 minutes) | Fallback age-out duration in milliseconds if no user choice is stored. |
| `ACTIVITY_TTL_OPTIONS_MIN` | `number[]` | `[1, 15, 30, 60]` | Array of valid age-out durations in minutes; also defines the set of permitted stored values. |
| Storage key | `string` | `"adh-healthy-ttl"` | Hardcoded localStorage key for persisting the user's choice. Key is unchanged from an earlier "Healthy" feature rename to preserve existing user settings. |

## Platform Notes

- **React/Web**: Source is a custom React hook (`useActivityTtl`) using `useState` for in-memory state, `useEffect` for one-shot hydration from `localStorage`, and `useCallback` to memoize `setTtl`. The `"use client"` directive indicates it is a client component in a Next.js App Router context.
- **SwiftUI**: Equivalent to a `@State` property or `@EnvironmentObject` that reads and writes to `UserDefaults` (macOS) or `NSUserDefaults` (iOS) with a hardcoded key. Hydration would occur during `onAppear`.
- **Compose**: Equivalent to a `ViewModel` with a `MutableState<Int?>` or a custom `Preference` data store that persists to `SharedPreferences`.
- **AppKit / UIKit**: Equivalent to a view controller property backed by `UserDefaults` with custom getters/setters for persistence and recovery.
- **WinUI 3**: Equivalent to a `ViewModel` (INotifyPropertyChanged) with a private backing field that reads/writes to `Windows.Storage.ApplicationData.Current.LocalSettings` or `IsolatedStorageSettings`. Loading from settings MUST validate against the allowed set (the setter, like `setTtl`, does not) and gracefully handle deserialization errors. Multi-user / profile-switching behavior differs: Windows Settings are per-user per-app; the equivalent of `localStorage.clear()` on logout is the app's responsibility.

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
