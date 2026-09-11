import AppKit
import AgenticToolkitPermissions

/// Drop-in settings panel: one `PermissionRowView` card per supplied
/// permission, with live status and a button that triggers the grant flow.
///
/// Refreshes when it appears and whenever the app reactivates (e.g. the user
/// returns from System Settings) — no polling timer. Free of any settings
/// framework, so any app or window can host it.
@MainActor
public final class PermissionsPanelView: NSView {

    private let permissions: [Permission]
    private let checker: any PermissionChecking
    private var rows: [PermissionRowView] = []
    private var isObserving = false

    /// The refresh in flight, so the next one can cancel it.
    ///
    /// Three things ask for a refresh — appearing, the app reactivating, and an
    /// action finishing — and each row's status read is a cross-process round
    /// trip they suspend on. Unserialised, whichever *resumed* last won: the
    /// user granted a permission, came back, and the pre-grant snapshot landed
    /// after the post-grant one, leaving the row reading "Not Granted" until
    /// the next activation. The newest read wins now, which is the one that was
    /// asked for last.
    private var refreshTask: Task<Void, Never>?

    public init(permissions: [Permission], checker: any PermissionChecking = SystemPermissionChecker()) {
        self.permissions = permissions
        self.checker = checker
        super.init(frame: .zero)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        refreshTask?.cancel()
        // Selector-based observers are auto-zeroed on dealloc since macOS 10.11,
        // but remove explicitly so a view deallocated while still in a window
        // doesn't leave a dangling registration.
        NotificationCenter.default.removeObserver(self)
    }

    /// Re-reads the grant state of every row.
    public func refresh() async {
        for row in rows {
            guard !Task.isCancelled else { return }
            await row.refresh()
        }
    }

    /// Starts a refresh, cancelling any still running. Every internal trigger
    /// goes through here; `refresh()` stays public for a host that wants to
    /// await one.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    private func buildLayout() {
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        for permission in permissions {
            let row = PermissionRowView(permission: permission, checker: checker) { [weak self] permission, status in
                self?.handleAction(permission, shownAs: status)
            }
            rows.append(row)
            stack.addArrangedSubview(row)
            // A vertical NSStackView doesn't stretch arranged subviews across its
            // width (alignment governs cross-axis *positioning*, not fill), so each
            // row's width is pinned to the stack explicitly.
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func handleAction(_ permission: Permission, shownAs status: PermissionStatus) {
        Task { @MainActor in
            await PermissionPresenter.present(permission, shownAs: status, using: checker)
            // Scheduled, not awaited: returning from System Settings has
            // already fired a refresh through the activation notification, and
            // this one — being later — is the one that should land.
            scheduleRefresh()
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startObservingActivation()
            scheduleRefresh()
        }
    }

    private func startObservingActivation() {
        guard !isObserving else { return }
        isObserving = true
        // Refresh when *our* app becomes active (e.g. the user returns from
        // System Settings) — not on every app switch system-wide, which
        // `NSWorkspace.didActivateApplicationNotification` would do.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        scheduleRefresh()
    }
}
