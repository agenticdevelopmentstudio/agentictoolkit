import AppKit
import Combine

import AgenticToolkitCore

/// One editor pane's answer to the three display options — either its own, or
/// silence, which means whatever the app says.
///
/// Modelled on `PaneSpacingOverride`, and for the same reason: absence and
/// "the same value as the default" are different states, and only one of them
/// keeps following the app. Each option is independently absent, so pinning
/// line numbers does not silently pin the minimap too.
@MainActor
public final class EditorOptionsOverride: ObservableObject {

    /// Stored under the pane's own prefix, so it cannot collide with the
    /// chrome keys `ProjectPaneStateStore` writes by default.
    public static let stateKey = "options"

    private struct Stored: Codable {
        var showLineNumbers: Bool?
        var showOverview: Bool?
        var showInvisibles: Bool?

        var isEmpty: Bool {
            showLineNumbers == nil && showOverview == nil && showInvisibles == nil
        }
    }

    private let store: PaneStateStore
    private var stored: Stored
    private var pendingPersist: DispatchWorkItem?
    private static let persistDelay: DispatchTimeInterval = .milliseconds(300)
    private var globalObservers: [UserSettingObserver<Bool>] = []

    /// Fires with the *resolved* state whenever it changes, from either scope —
    /// so a listener applies what it is given and never asks which scope won.
    public var onChange: (() -> Void)?

    public init(store: PaneStateStore = EphemeralPaneStateStore()) {
        self.store = store
        self.stored = Self.read(from: store)
        observeGlobals()
    }

    private func observeGlobals() {
        globalObservers = [
            UserSettingObserver(UserSettings.editorShowLineNumbers) { [weak self] _ in self?.publish() },
            UserSettingObserver(UserSettings.editorShowOverview) { [weak self] _ in self?.publish() },
            UserSettingObserver(UserSettings.editorShowInvisibles) { [weak self] _ in self?.publish() }
        ]
    }

    // MARK: - Resolved values

    public var showLineNumbers: Bool { stored.showLineNumbers ?? UserSettings.editorShowLineNumbers.value }
    public var showOverview: Bool { stored.showOverview ?? UserSettings.editorShowOverview.value }
    public var showInvisibles: Bool { stored.showInvisibles ?? UserSettings.editorShowInvisibles.value }

    public var isOverridden: Bool { !stored.isEmpty }

    // MARK: - Setting

    public func setShowLineNumbers(_ value: Bool) {
        stored.showLineNumbers = value
        schedulePersist()
        publish()
    }

    public func setShowOverview(_ value: Bool) {
        stored.showOverview = value
        schedulePersist()
        publish()
    }

    public func setShowInvisibles(_ value: Bool) {
        stored.showInvisibles = value
        schedulePersist()
        publish()
    }

    /// Back to inheriting all three. The row is deleted, not overwritten with
    /// the current globals — a pane reset once would otherwise stop following
    /// the app from that moment on, which is the opposite of what the button
    /// says.
    public func reset() {
        stored = Stored()
        pendingPersist?.cancel()
        pendingPersist = nil
        store.setPaneStateValue(nil, forKey: Self.stateKey)
        publish()
    }

    /// Writes a coalesced override now instead of when its timer says so.
    /// Nothing pending is a no-op, so it is always safe to call.
    public func flushPendingPersist() {
        pendingPersist?.cancel()
        pendingPersist = nil
        writeNow()
    }

    // MARK: - Persistence

    private func schedulePersist() {
        pendingPersist?.cancel()
        let work = DispatchWorkItem { [self] in
            pendingPersist = nil
            writeNow()
        }
        pendingPersist = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.persistDelay, execute: work)
    }

    private func writeNow() {
        guard !stored.isEmpty else {
            store.setPaneStateValue(nil, forKey: Self.stateKey)
            return
        }
        guard let data = try? JSONEncoder().encode(stored),
              let json = String(data: data, encoding: .utf8) else { return }
        store.setPaneStateValue(json, forKey: Self.stateKey)
    }

    private func publish() {
        objectWillChange.send()
        onChange?()
    }

    /// A row that no longer parses — written by an older build, or edited by
    /// hand — is read as "no override". The cost of being wrong is an editor
    /// that looks like the rest of the app, so there is nothing here worth
    /// stopping for.
    private static func read(from store: PaneStateStore) -> Stored {
        guard let json = store.paneStateValue(forKey: stateKey),
              let data = json.data(using: .utf8),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return Stored() }
        return stored
    }
}
