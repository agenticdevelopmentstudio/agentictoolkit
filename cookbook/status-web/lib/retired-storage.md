---
id: ae8d4137-e2fc-495f-9592-46ad4b1ac60f
title: Retired Storage
domain: agentictoolkit://cookbook/status-web/lib/retired-storage
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: One-time, never-throwing purge of localStorage keys the status board no longer
  reads
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status-web/hooks/use-live-snapshot
references: []
approved-by: ''
approved-date: ''
---

# Retired Storage

## Overview

`retired-storage.ts` exports one function, `purgeRetiredStorage()`, which deletes browser `localStorage` keys that the status board app no longer reads or writes. Its only entry today is `"adh-activity-v1"`, the activity feed that `use-live-snapshot.ts` used to persist and rehydrate before the board became server-derived. Removing the writer did not remove the data: every browser that loaded the old build still holds a dead blob of several hundred KB. That blob caused a phantom `hub-help-testing` problem that no server-side fix could clear.

Call it once, early, where the board mounts. It is safe during server-side rendering and when storage is unavailable, and it never throws. The package re-exports it from `src/index.ts` (`export * from "./lib/retired-storage"`).

## Behavioral Requirements

**Retired key list**

- **retired-key-list**: The module MUST keep a fixed, read-only list of retired key names (`RETIRED_KEYS`, declared `as const`) that contains exactly `"adh-activity-v1"`.
- **retired-key-semantics**: Each key in the retired list MUST be one that nothing in the app reads or writes, per the module's doc comment: "Each entry below is a RETIRED key: nothing in the app reads or writes it."
- **named-allow-list**: The purge MUST remove only the keys named in the retired list. It MUST NOT clear storage or remove any other key. The test "leaves keys the app still uses alone" checks that `adh-font-scale`, `adh-env-filter` and `adh-healthy-ttl` survive.

**Operation: `purgeRetiredStorage(): void`**

- **purge-signature**: `purgeRetiredStorage` MUST take no arguments and return `void`.
- **purge-removes-key**: When `window` exists and storage is usable, `purgeRetiredStorage` MUST call `window.localStorage.removeItem(key)` once for each key in the retired list, in list order.
- **purge-ssr-noop**: When `typeof window === "undefined"`, `purgeRetiredStorage` MUST return at once without touching storage and without throwing.
- **purge-never-throws**: `purgeRetiredStorage` MUST NOT throw. An exception from `removeItem`, or from reading `window.localStorage` (for example a `SecurityError` in Safari private browsing, a blocked third-party frame or a profile with `localStorage` disabled), MUST be caught for that key.
- **purge-failure-silent**: When removing a key throws, `purgeRetiredStorage` MUST leave the blob in place and move on to the next key without logging, retrying or reporting. The doc comment states the reason: "There is nothing to recover if it fails, and it must never be able to break the board's mount."
- **purge-per-key-isolation**: A failure on one key MUST NOT stop the purge from trying the rest of the retired list, because the `try`/`catch` wraps each key separately.
- **purge-idempotent**: Calling `purgeRetiredStorage` when no retired key is present MUST have no effect and MUST NOT throw. Calling it again after a successful purge MUST have the same effect as calling it once.

**Ordering, concurrency and side effects**

- **purge-synchronous**: `purgeRetiredStorage` MUST run synchronously and finish before it returns. It returns no promise and does not schedule later work.
- **purge-single-threaded**: The purge runs on the JavaScript main thread and cannot interleave with other calls. Calls that overlap in time (for example, several tabs) MUST be safe because each only removes keys, and removing a key that is already gone does nothing.
- **purge-side-effect-scope**: The only side effect of `purgeRetiredStorage` MUST be removing retired keys from `window.localStorage`. It MUST NOT touch `sessionStorage`, cookies, IndexedDB or the network, and it MUST NOT emit events or logs.
- **purge-persistence**: A key that is removed stays removed across reloads, since `localStorage` persists per origin. A key whose removal threw stays in storage until a later call succeeds. The module does not remember past runs, so it tries the purge on every call.

**Retirement lifecycle**

- **retirement-lifecycle**: A retired entry MAY be deleted from the list, and the module MAY be deleted once no retired keys remain, after a release has been out long enough that every live tab has run the purge. This comes from the module's doc comment.

## Appearance

Not applicable — this is a storage-cleanup function, not a visual component.

## States

Not applicable — this is a storage-cleanup function, not a visual component.

## Accessibility

Not applicable — this is a storage-cleanup function, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| retired-storage-001 | purge-removes-key, retired-key-list | Storage holds `adh-activity-v1` = `[{"id":"phantom"}]` as JSON; call `purgeRetiredStorage()` | `localStorage.getItem("adh-activity-v1")` returns `null` (test: "removes the retired activity blob") |
| retired-storage-002 | named-allow-list | Storage holds `adh-font-scale` = `"1.2"`, `adh-env-filter` = `["production"]` as JSON, `adh-healthy-ttl` = `"3600000"`; call `purgeRetiredStorage()` | All three keys keep their original values (test: "leaves keys the app still uses alone") |
| retired-storage-003 | purge-idempotent | Empty storage; call `purgeRetiredStorage()` | Does not throw; storage size stays 0 (test: "is a no-op when the key was never written") |
| retired-storage-004 | purge-never-throws, purge-failure-silent | `localStorage.removeItem` throws `DOMException("The operation is insecure.", "SecurityError")`; call `purgeRetiredStorage()` | Does not throw; `removeItem` was called with `"adh-activity-v1"` (test: "swallows a throwing localStorage") |
| retired-storage-005 | purge-ssr-noop | `window` is `undefined`; call `purgeRetiredStorage()` | Does not throw and touches no storage (test: "does nothing when there is no window (SSR)") |
| retired-storage-006 | purge-idempotent | Storage holds `adh-activity-v1`; call `purgeRetiredStorage()` twice | After both calls `getItem("adh-activity-v1")` is `null`, and the second call does not throw |
| retired-storage-007 | purge-never-throws | Reading the `window.localStorage` property throws `SecurityError`; call `purgeRetiredStorage()` | Does not throw, because the property read happens inside the per-key `try` |
| retired-storage-008 | purge-signature, purge-synchronous | Call `purgeRetiredStorage()` | Returns `undefined`, not a promise |

## Edge Cases

- **Null or empty input**: The function takes no input. An empty storage area MUST give a silent no-op (retired-storage-003).
- **Retired key absent**: `removeItem` on a missing key does nothing. The purge MUST complete without error.
- **Server-side rendering**: With no global `window`, the purge MUST return at once (retired-storage-005).
- **Storage disabled or denied**: When `removeItem`, or the `localStorage` property read, throws, the purge MUST catch the exception, leave the blob and return normally (retired-storage-004, retired-storage-007). The exception is not reported anywhere. The doc comment makes this a deliberate contract, so it is a fact, not a gap.
- **Several retired keys, one failing**: Each key has its own `try`/`catch`, so a throw on one key MUST NOT skip the others. The list has one entry today.
- **Large blob**: The retired value can be several hundred KB. Removing it MUST NOT read or parse the value. The purge only calls `removeItem`.
- **Concurrent tabs**: Several tabs of one origin MAY run the purge at the same time. Removing a key is idempotent, so the end state MUST be that the key is gone (or still present if storage is denied).
- **Boundary values**: Not applicable. There are no numeric or length inputs.
- **Offline or disconnected state**: Not applicable. The purge makes no network calls.
- **Timeouts and cancellation**: The purge has no timeout and cannot be cancelled. It is a short synchronous loop.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `RETIRED_KEYS` | `readonly ["adh-activity-v1"]` (module constant, not exported) | `["adh-activity-v1"]` | The keys to purge. Changing it means editing the source. The caller cannot supply it. |
| `window.localStorage` | Web Storage (environment) | The browser's per-origin storage | Injected by the environment. It may be missing (SSR) or throw on access (storage denied). |

## Deep Linking

Not applicable: `purgeRetiredStorage` is a storage-cleanup function with no route or URL.

## Localization

Not applicable: the module has no user-facing strings. The only string literal is the storage key `"adh-activity-v1"`.

## Accessibility Options

Not applicable: the module renders nothing, so display accessibility options do not apply.

## Feature Flags

Not applicable: the purge runs on every call with no flag guarding it.

## Analytics

Not applicable: the module emits no analytics events.

## Privacy

Not applicable: the module collects, stores and sends nothing. It only deletes the retired `adh-activity-v1` activity-feed blob from the browser's own `localStorage`, and that data never leaves the device.

## Logging

Not applicable: the module has no log calls. A storage failure is caught by an empty `catch` whose comment reads "Storage unavailable/denied — leave the blob and carry on."

## Platform Notes

- **SwiftUI**: Port the retired list as a `static let` array of keys. In `App.init` or an `.onAppear`/`.task` on the root view, call `UserDefaults.standard.removeObject(forKey:)` for each key. `removeObject` does not throw, so no `catch` is needed. There is no SSR case. Make the function `nonisolated` or `@MainActor`. `UserDefaults` is thread-safe either way.
- **Compose**: Use `SharedPreferences.edit { remove(key) }` or `DataStore<Preferences>.edit { it.remove(stringPreferencesKey(key)) }` from `Application.onCreate` or a startup `LaunchedEffect`. `DataStore.edit` is a suspend function that can throw `IOException`. Wrap each key in `runCatching` so the no-throw contract holds.
- **React/Web**: Source platform. `packages/web/packages/status-web/src/lib/retired-storage.ts` holds the function and the constant. It relies on `typeof window === "undefined"` for the SSR guard, and on a per-key `try`/`catch` because reading `window.localStorage` can throw a `SecurityError` DOMException. `retired-storage.test.ts` runs under jsdom and installs its own `localStorage`, because that jsdom build ships none. Call the function from a mount effect, not during render.
- **AppKit / UIKit**: The same `UserDefaults.standard.removeObject(forKey:)` loop, run from `applicationDidFinishLaunching` or `application(_:didFinishLaunchingWithOptions:)`. For apps with an App Group suite, remove keys from `UserDefaults(suiteName:)` too.
- **WinUI 3**: Use `Windows.Storage.ApplicationData.Current.LocalSettings.Values.Remove(key)` in packaged apps. Unpackaged apps store their settings in a file of their own (for example JSON through `System.Text.Json`), so delete the retired property from it. Call the purge from `App.OnLaunched` before the main `Window` is activated. `ApplicationData.Current` throws `InvalidOperationException` in an unpackaged process, so wrap each key's removal in `try { … } catch (Exception) { }` to keep the never-throw contract. `LocalSettings` access is synchronous, so no `Task`/`async` is needed. WebView2 content has its own `localStorage`. To purge that, call `CoreWebView2.ExecuteScriptAsync("localStorage.removeItem('adh-activity-v1')")` after `NavigationCompleted`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/retired-storage.ts` |

## Design Decisions

**Decision**: Purge a named allow-list of retired keys instead of clearing storage.
**Rationale**: The app still stores live preferences such as `adh-font-scale`, `adh-env-filter` and `adh-healthy-ttl`. A wipe would destroy them. The test "leaves keys the app still uses alone" pins this.
**Approved**: pending

**Decision**: Swallow every storage exception silently, per key.
**Rationale**: The doc comment says "There is nothing to recover if it fails, and it must never be able to break the board's mount." A leftover dead blob is harmless to the current build, which never reads it. A throw during mount would break the board.
**Approved**: pending

**Decision**: Keep the purge in client code instead of relying on a server fix.
**Rationale**: The phantom `hub-help-testing` problem lived only in one tab's `adh-activity-v1` key, so no server-side change could clear it. Only code running in that browser can delete the key.
**Approved**: pending

**Decision**: Run the purge on every call instead of recording that it has run.
**Rationale**: Removing a missing key costs nothing and is idempotent. A "done" marker would itself be another storage key to retire later.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |

**Separation of concerns.** The module does storage cleanup only. It has no React, rendering or network code, and the board decides when to call it.

**Unit test coverage.** `retired-storage.test.ts` covers removing the retired key, leaving live keys alone, the empty-storage no-op, a throwing `removeItem`, and the SSR guard.

**Explicit error handling.** Partial. The storage exception is caught by an empty `catch` and not surfaced, which the check forbids in general. The module's doc comment declares it deliberate: a failure leaves a harmless blob and must not break the mount. So the error is handled on purpose rather than lost by accident.

**Graceful degradation.** Missing `window` and denied storage both become silent no-ops instead of crashes.

**Idempotent operations.** Repeated calls, and calls from several tabs at once, converge on the same end state because deleting a missing key does nothing.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from source |
