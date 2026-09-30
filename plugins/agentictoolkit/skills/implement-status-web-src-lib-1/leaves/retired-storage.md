<!-- leaf: implement-status-web-src-lib-1/retired-storage · source: status-web-src-lib-retired-storage.md -->

**Rules** (cite as `implement-status-web-src-lib-1/retired-storage#<slug>`):

- `retired-key-list` MUST
- `retired-key-semantics` MUST
- `named-allow-list` MUST
- `purge-signature` MUST
- `purge-removes-key` MUST
- `purge-ssr-noop` MUST
- `purge-never-throws` MUST
- `purge-failure-silent` MUST
- `purge-per-key-isolation` MUST
- `purge-idempotent` MUST
- `purge-synchronous` MUST
- `purge-single-threaded` MUST
- `purge-side-effect-scope` MUST
- `retirement-lifecycle` MAY

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `RETIRED_KEYS` | `readonly ["adh-activity-v1"]` (module constant, not exported) | `["adh-activity-v1"]` | The keys to purge. Changing it means editing the source. The caller cannot supply it. |
| `window.localStorage` | Web Storage (environment) | The browser's per-origin storage | Injected by the environment. It may be missing (SSR) or throw on access (storage denied). |

## Platform Notes

- **SwiftUI**: Port the retired list as a `static let` array of keys. In `App.init` or an `.onAppear`/`.task` on the root view, call `UserDefaults.standard.removeObject(forKey:)` for each key. `removeObject` does not throw, so no `catch` is needed. There is no SSR case. Make the function `nonisolated` or `@MainActor`. `UserDefaults` is thread-safe either way.
- **Compose**: Use `SharedPreferences.edit { remove(key) }` or `DataStore<Preferences>.edit { it.remove(stringPreferencesKey(key)) }` from `Application.onCreate` or a startup `LaunchedEffect`. `DataStore.edit` is a suspend function that can throw `IOException`. Wrap each key in `runCatching` so the no-throw contract holds.
- **React/Web**: Source platform. `packages/web/packages/status-web/src/lib/retired-storage.ts` holds the function and the constant. It relies on `typeof window === "undefined"` for the SSR guard, and on a per-key `try`/`catch` because reading `window.localStorage` can throw a `SecurityError` DOMException. `retired-storage.test.ts` runs under jsdom and installs its own `localStorage`, because that jsdom build ships none. Call the function from a mount effect, not during render.
- **AppKit / UIKit**: The same `UserDefaults.standard.removeObject(forKey:)` loop, run from `applicationDidFinishLaunching` or `application(_:didFinishLaunchingWithOptions:)`. For apps with an App Group suite, remove keys from `UserDefaults(suiteName:)` too.
- **WinUI 3**: Use `Windows.Storage.ApplicationData.Current.LocalSettings.Values.Remove(key)` in packaged apps. Unpackaged apps store their settings in a file of their own (for example JSON through `System.Text.Json`), so delete the retired property from it. Call the purge from `App.OnLaunched` before the main `Window` is activated. `ApplicationData.Current` throws `InvalidOperationException` in an unpackaged process, so wrap each key's removal in `try { … } catch (Exception) { }` to keep the never-throw contract. `LocalSettings` access is synchronous, so no `Task`/`async` is needed. WebView2 content has its own `localStorage`. To purge that, call `CoreWebView2.ExecuteScriptAsync("localStorage.removeItem('adh-activity-v1')")` after `NavigationCompleted`.

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
