import ApplicationServices
import CoreLocation
import CoreServices
import Foundation
import Security
import UserNotifications

/// Production `PermissionChecking` over the real macOS permission APIs.
///
/// The Apple Events probe is injected so the status mapping is testable; the
/// Accessibility and Notification checks are thin pass-throughs to the system
/// and are exercised only at runtime.
public struct SystemPermissionChecker: PermissionChecking {
    private let automationProbe: any AutomationProbing

    // A single long-lived coordinator: `CLLocationManager` reports
    // authorization on the instance, and a freshly allocated one can answer
    // `.notDetermined` before it has talked to the daemon. Both the
    // coordinator type and this static reference to it are `@MainActor`,
    // because CoreLocation delivers delegate callbacks on the run loop of the
    // thread that created the manager — creating it and receiving callbacks
    // on the main actor is what makes that well-defined under strict
    // concurrency. That isolation also removes the need for a
    // `nonisolated(unsafe)` opt-out: the manager itself is never touched off
    // the main actor, so there is nothing left to be unsafe about.
    @MainActor private static let locationCoordinator = LocationAuthorizationCoordinator()

    public init(automationProbe: any AutomationProbing = SystemAutomationProbe()) {
        self.automationProbe = automationProbe
    }

    public func status(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .accessibility:
            // Deliberately re-calls the OS primitive rather than delegating to
            // CoreMacOS's `SystemAccessibilityPermission`: this target is daemon-safe
            // and must not depend on CoreMacOS (which pulls in AppKit). `AXIsProcessTrusted`
            // is an OS-defined primitive, not knowledge we own, so the two thin
            // wrappers can't meaningfully diverge.
            return AXIsProcessTrusted() ? .granted : .denied
        case .notifications:
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return Self.notificationStatus(settings.authorizationStatus)
        case .automation(let bundleID):
            let status = await automationStatus(forBundleID: bundleID, promptIfNeeded: false)
            return Self.automationStatus(status)
        case .location:
            let status = await Self.locationCoordinator.currentStatus
            return Self.locationStatus(status)
        case .keychain(let service):
            // Deliberately does not touch the keychain. See
            // `KeychainPermissionLedger` for why there is nothing to ask, and
            // `PermissionsPanelView` for why asking would be harmful: it
            // refreshes every row on every app activation, so a status check
            // that could raise the ACL dialog would raise it over and over.
            return KeychainPermissionLedger.status(service: service)
        }
    }

    @discardableResult
    public func request(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .accessibility:
            // String-literal key rather than the SDK's global `kAXTrustedCheckOptionPrompt`
            // var, which is not concurrency-safe to reference.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
        case .notifications:
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            return await status(permission)
        case .automation(let bundleID):
            let status = await automationStatus(forBundleID: bundleID, promptIfNeeded: true)
            return Self.automationStatus(status)
        case .location:
            // `requestAlwaysAuthorization` is the background-capable grant —
            // olylod observes location while the user is not in the app. It is
            // also fire-and-forget: the decision arrives later through the
            // delegate, which `locationCoordinator` awaits so this returns the
            // user's actual answer rather than the pre-prompt status.
            let status = await Self.locationCoordinator.requestAlways()
            return Self.locationStatus(status)
        case .keychain(let service):
            // The request *is* the read: macOS grants access to a keychain
            // item by putting up its own dialog the first time a process
            // reads it, and there is no separate API to ask. Which is also
            // what makes the alert name this app — the dialog names the
            // process that called `SecItemCopyMatching`, so this has to
            // happen in-process and never in a helper.
            let status = await Self.keychainReadStatus(service: service)
            KeychainPermissionLedger.record(status, service: service)
            return status
        }
    }

    /// Reads the item on a GCD queue, for the same reason the Apple Events
    /// probe does: a first read blocks until the user dismisses the ACL
    /// dialog, and a cooperative thread is not one you may block for that
    /// long.
    private static func keychainReadStatus(service: String) async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    // Both keychains: the item may be local to this Mac or
                    // synchronised through iCloud, and the permission is the
                    // same either way.
                    kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                    // The data, not just the attributes — reading attributes
                    // does not touch the ACL, so a metadata-only query would
                    // report success without having asked for anything.
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ]
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                continuation.resume(returning: keychainStatus(status))
            }
        }
    }

    /// Maps an `OSStatus` from a keychain read to a tri-state.
    ///
    /// `errSecItemNotFound` is `undetermined`, not a denial: there is no item,
    /// so there is nothing to have been refused access to. Saying "denied"
    /// there would send the user looking for a permission to grant that does
    /// not exist yet.
    static func keychainStatus(_ status: OSStatus) -> PermissionStatus {
        switch status {
        case errSecSuccess:
            return .granted
        case errSecItemNotFound:
            return .undetermined
        default:
            // errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed,
            // errSecMissingEntitlement — every one of them means this app did
            // not get the bytes.
            return .denied
        }
    }

    /// Runs the synchronous, potentially long-blocking Apple Events probe on a GCD
    /// global queue rather than the calling context. With `promptIfNeeded: true`,
    /// `AEDeterminePermissionToAutomateTarget` blocks until the user dismisses the
    /// consent dialog; Apple's header warns against calling it on a thread you
    /// can't block arbitrarily. A cooperative (Swift concurrency) thread is exactly
    /// such a thread, so we hop to GCD — which spawns more threads as needed —
    /// instead of starving the cooperative pool.
    private func automationStatus(forBundleID bundleID: String, promptIfNeeded: Bool) async -> OSStatus {
        let probe = automationProbe
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    returning: probe.permissionStatus(forBundleID: bundleID, promptIfNeeded: promptIfNeeded)
                )
            }
        }
    }

    /// Maps an `AEDeterminePermissionToAutomateTarget` status to a tri-state.
    /// `noErr` is granted; `errAEEventNotPermitted` (-1743) is a real denial;
    /// everything else — consent-required (-1744), target-not-running (-600), … —
    /// is `undetermined` (we can't prove granted *or* denied), so the UI doesn't
    /// mislabel a granted permission whose target app simply isn't running.
    static func automationStatus(_ status: OSStatus) -> PermissionStatus {
        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .undetermined
        }
    }

    /// Maps a `UNAuthorizationStatus` to a tri-state. `notDetermined` (never
    /// requested) is `undetermined`, not a denial.
    static func notificationStatus(_ status: UNAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            return .undetermined
        @unknown default:
            return .undetermined
        }
    }

    /// Maps a `CLAuthorizationStatus` to a tri-state. Only `.authorizedAlways`
    /// counts as granted — a when-in-use grant is not enough for a daemon that
    /// observes location while the app is not running, so it must read as
    /// not-granted rather than as a lie.
    static func locationStatus(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorizedAlways: return .granted
        // "While Using the App" is not a grant we can use: olylod reads location
        // while the user is in no app at all. Reported as `.denied` rather than
        // `.undetermined` so PermissionPresenter's Settings-pane fallback fires and
        // the user has a route to upgrade it to Always — `requestAlwaysAuthorization()`
        // will not re-prompt once any decision exists.
        case .authorizedWhenInUse: return .denied
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }
}

/// Owns the `CLLocationManager` and bridges its delegate-based authorization
/// flow into async/await. Isolated to `@MainActor` because CoreLocation
/// delivers delegate callbacks on the run loop of the thread that created the
/// manager — creating the manager and receiving its callbacks on the main
/// actor is what makes both sides of that contract well-defined under strict
/// concurrency.
@MainActor
private final class LocationAuthorizationCoordinator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    var currentStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// Requests Always authorization. If the status is already settled
    /// (anything but `.notDetermined`), fires the request for its
    /// no-op/Settings-hint effect and returns the current status
    /// synchronously — only a genuinely undetermined first ask needs to wait.
    /// `requestAlwaysAuthorization()` itself is fire-and-forget; the user's
    /// decision arrives later through `locationManagerDidChangeAuthorization`,
    /// which resumes the waiters this sets up. Concurrent callers (a settings
    /// UI and the daemon's trigger-arming path can both ask while the status
    /// is still undetermined) share one system prompt and one timeout rather
    /// than each triggering its own: `requestAlwaysAuthorization()` is a
    /// no-op after the first call, and CoreLocation delivers exactly one
    /// decision to all of them. A 120-second timeout guards against a prompt
    /// the user closes without deciding, or one that never appears (Location
    /// Services off globally, missing usage-description), so no caller's
    /// `await` can hang forever.
    func requestAlways() async -> CLAuthorizationStatus {
        let before = manager.authorizationStatus
        manager.requestAlwaysAuthorization()
        guard before == .notDetermined else {
            return manager.authorizationStatus
        }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)

            // Re-read rather than trust `before`: the delegate can fire between
            // `requestAlwaysAuthorization()` above and this closure, and a
            // decision that landed in that window would otherwise wait out the
            // full timeout for a status that is already settled.
            let settled = manager.authorizationStatus
            guard settled == .notDetermined else {
                resumeAll(with: settled)
                return
            }

            // The first waiter owns the timeout; later waiters join it rather
            // than starting a second one that would outlive the first.
            guard timeoutTask == nil else { return }
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(120))
                guard let self, !Task.isCancelled else { return }
                self.resumeAll(with: self.manager.authorizationStatus)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        Task { @MainActor [weak self] in
            self?.resumeAll(with: status)
        }
    }

    /// Resumes every waiter exactly once. The read-and-clear of `waiters` is a
    /// single uninterruptible main-actor step with no `await` between the two
    /// halves, so a second delegate callback or the timeout cannot observe a
    /// non-empty list after this has taken it — either would trap
    /// `CheckedContinuation` by resuming twice.
    private func resumeAll(with status: CLAuthorizationStatus) {
        guard !waiters.isEmpty else { return }
        let pending = waiters
        waiters = []
        timeoutTask?.cancel()
        timeoutTask = nil
        for continuation in pending {
            continuation.resume(returning: status)
        }
    }
}

/// Remembers whether this app has ever successfully read a given keychain
/// item, because macOS offers no way to ask.
///
/// The two candidate oracles contradict each other on the same item: a read
/// with `SecKeychainSetUserInteractionAllowed(false)` returns
/// `errSecAuthFailed`, while a `kSecUseAuthenticationUISkip` query against
/// that same item, from the same process, returns the bytes without
/// prompting. So neither answers "would this prompt?", and a status built on
/// either would be a guess presented as a fact.
///
/// What *is* knowable is what already happened — the app read the item, or it
/// was refused, or it has never tried — and that is what this records. A
/// permission whose grant is remembered rather than probed is also the only
/// kind a settings panel can redraw freely, which is what
/// `PermissionsPanelView` does on every app activation.
public enum KeychainPermissionLedger: Sendable {
    /// What this app last learned about its access to `service`.
    public static func status(service: String) -> PermissionStatus {
        switch UserDefaults.standard.string(forKey: key(for: service)) {
        case Self.granted: return .granted
        case Self.denied: return .denied
        default: return .undetermined
        }
    }

    /// Records the outcome of a real read.
    ///
    /// Call this from wherever the app actually touches the item, not only
    /// from the permissions panel — the panel is the least likely place a
    /// grant is first obtained, and a ledger only the panel writes to would
    /// report "not determined" for an app that has been reading the item all
    /// along.
    ///
    /// `.undetermined` erases the record rather than storing a third string,
    /// so "we no longer know" and "we never knew" stay the same state.
    public static func record(_ status: PermissionStatus, service: String) {
        let defaults = UserDefaults.standard
        switch status {
        case .granted: defaults.set(Self.granted, forKey: key(for: service))
        case .denied: defaults.set(Self.denied, forKey: key(for: service))
        case .undetermined: defaults.removeObject(forKey: key(for: service))
        }
    }

    /// Forgets every remembered keychain grant — the reset the permission
    /// walkthrough needs, since a remembered grant would otherwise make a
    /// re-run skip the one permission it cannot re-derive.
    public static func forget(service: String) {
        record(.undetermined, service: service)
    }

    static func key(for service: String) -> String {
        "permission.\(Permission.keychain(service: service).identifierToken).status"
    }

    private static let granted = "granted"
    private static let denied = "denied"
}
