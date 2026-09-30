<!-- leaf: implement-window-management/window-manager--part-4 · source: window-management-window-manager.md -->

# WindowManager — continued (part 4)

## Platform Notes

- **SwiftUI**: No SwiftUI in the source. A SwiftUI macOS app gets frame persistence from `Window`/`WindowGroup` scene autosave and `defaultPosition`/`defaultSize`, and document recents from `DocumentGroup`; launch restore of utility windows still needs a coordinator like this one calling `openWindow(id:)` for IDs saved visible, with `@AppStorage` or `SceneStorage` in place of `WindowStateStorage`.
- **Compose**: Compose for Android has no multi-window desktop model; a Compose Desktop port starts from `rememberWindowState` and `WindowPosition`, persists with DataStore plus `kotlinx.serialization`, keeps the registry as a `Map<String, WeakReference<…>>` confined to `Dispatchers.Main`, and replaces the termination latch with an `ApplicationScope` exit hook. The namespace hash maps to `MessageDigest.getInstance("SHA-256")`.
- **React/Web**: Browsers own window placement; an Electron port starts from `BrowserWindow.getBounds`/`setBounds`, `app.on('before-quit')` for the termination latch, `app.addRecentDocument` for recents, `electron-store` or `localStorage` with `JSON.stringify` for storage, `webContents.capturePage()` for screenshots, and Node `crypto.createHash('sha256')` for the namespace.
- **AppKit / UIKit**: Source files: `WindowManager.swift` (Combine sink on `UserSettings.recentWindowsCount`, selector-based `NotificationCenter` observer for `willTerminateNotification`, `os.Logger`, `NSDocumentController` recents and reopen), `WindowRegistry.swift` (weak boxes over `SingleWindowController`), `WindowStateStorage.swift`, `SettingsStoreWindowStateStorage.swift` (`StorableSetting` keys through `SettingsStore`), `UserDefaultsWindowStateStorage.swift` (`JSONEncoder`/`JSONDecoder` over `UserDefaults.standard`, `dictionaryRepresentation()` scan), `WindowStateNamespace.swift` (`OSAllocatedUnfairLock`, CryptoKit `SHA256`), `WindowScreenshot.swift` (`dlsym` of `CGWindowListCreateImage`, `NSBitmapImageRep` PNG). UIKit has no free-floating windows; scene restoration (`stateRestorationActivity`, `UISceneSession.userInfo`) replaces frame and visibility persistence.
- **WinUI 3**: Start from `Microsoft.UI.Windowing.AppWindow` (`Position`, `Size`, `MoveAndResize`, `Show`/`Hide`, `IsVisible`, `Closing` event) with `DisplayArea` for screen bounds. Keep the manager and registry on the UI thread via `DispatcherQueue`; hold controllers in a `Dictionary<string, WeakReference<T>>` and expose `VisibleIds`/`HasVisibleWindow` through `INotifyPropertyChanged` if bound. Persist `PersistedWindowState` with `System.Text.Json` into `Windows.Storage.ApplicationData.Current.LocalSettings` (the 8 KB per-value limit favors one key per window, as the source already does) and store visibility as a native `bool` value so absence stays distinguishable via `ContainsKey`. Replace `willTerminateNotification` with `Application.Current` exit handling or `AppWindow.Closing` plus an app-level shutdown flag; replace the Combine settings sink with a `PropertyChanged` handler. Document recents map to `Windows.Storage.AccessCache.StorageApplicationPermissions.MostRecentlyUsedList` (with `MaximumItemsAllowed` in place of `NSRecentDocumentsLimit`) and jump lists (`Windows.UI.StartScreen.JumpList`). The namespace hash is `System.Security.Cryptography.SHA256.HashData`, guarded with `lock`. Own-window screenshots use `Windows.Graphics.Capture` with `GraphicsCaptureItem.TryCreateFromWindowId` or `RenderTargetBitmap` for XAML content, encoded with `BitmapEncoder.PngEncoderId`. Windows coordinates are top-left origin, unlike AppKit.

## Design Decisions

**Decision**: `WindowManager` is a thin coordinator over two sub-services (`frames`, `registry`) instead of one type that does everything.
**Rationale**: The type doc comment directs most callers to a sub-service (`frames.restoreFrame(...)`, `registry.controller(forID:)`); frame persistence and live lookup change independently.
**Approved**: pending

**Decision**: An omitted `screenManager` resolves to `ScreenManager.shared`, never a new instance.
**Rationale**: Per the initializer comment, a second `ScreenManager` on the same persistence key would clobber the real one's state and double-register the notification observer.
**Approved**: pending

**Decision**: Termination is latched with a one-way `isTerminating` flag read by `SingleWindowController.windowWillClose(_:)`.
**Rationale**: AppKit sends `windowWillClose:` to still-visible windows after `applicationWillTerminate`; persisting hidden there stopped windows left open from reopening (`WindowManagerTerminationTests`).
**Approved**: pending

**Decision**: Restore is driven by registered factories (`registerRestorable`) rather than hosts hand-constructing controllers.
**Rationale**: The doc comment says this ensures "a window can't silently miss restore"; the missing-factory error log exists to surface the remaining wiring gap loudly.
**Approved**: pending

**Decision**: The recent-documents cap is set by writing the `NSRecentDocumentsLimit` user default.
**Rationale**: `NSDocumentController.maximumRecentDocumentCount` is read-only; the default is the public knob and avoids subclassing `NSDocumentController`.
**Approved**: pending

**Decision**: When reopen is disabled the manager actively closes document windows AppKit restored.
**Rationale**: The comment calls this overriding AppKit's own state restoration; it closes through the window controller so the controller, not just the window, is torn down.
**Approved**: pending

**Decision**: The registry holds weak references and never prunes dead entries.
**Rationale**: A dropped controller "naturally disappears" from lookups; the number of window IDs is small and bounded, so dead boxes cost little.
**Approved**: pending

**Decision**: `WindowStateNamespace` is a process-wide lock-guarded static read at key-composition time, not an injected dependency.
**Rationale**: `WindowManager.shared` builds its storage on first access from anywhere, so an injected namespace would miss the storages that matter; the lock (not `@MainActor`) lets non-main-actor code compose the same keys.
**Approved**: pending

**Decision**: The namespace is an 8-hex-character SHA-256 prefix of the bundle path, empty by default.
**Rationale**: The bundle path is the identity that differs between two copies (bundle ID is shared, pid changes each launch); hashing keeps keys short and keeps directory names out of preferences; the empty default preserves every existing installation's layout.
**Approved**: pending

**Decision**: Both storage implementations use the same key formats and encodings (JSON state, native boolean visibility).
**Rationale**: Swapping `SettingsStoreWindowStateStorage` in over a UserDefaults-backed store reads existing state without migration, per its doc comment.
**Approved**: pending

**Decision**: `WindowScreenshot` resolves the deprecated `CGWindowListCreateImage` through `dlsym`.
**Rationale**: ScreenCaptureKit is async and requires Screen Recording permission even for own windows; the legacy symbol works without permission, and runtime resolution avoids the deprecation warning while degrading to `nil` if the symbol disappears.
**Approved**: pending

**Decision**: Non-document single windows are not recorded in recents yet.
**Rationale**: The source marks this intentional, pending `WindowRecentsTracker` in a follow-up slice.
**Approved**: pending
