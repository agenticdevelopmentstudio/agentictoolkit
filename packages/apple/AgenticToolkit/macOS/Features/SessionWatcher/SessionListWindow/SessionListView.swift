import AppKit
import Combine
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticToolkitPermissions

extension SessionWatcher {
    /// The main AppKit view displayed inside the floating session palette.
    public final class SessionListView: NSView {
        private let viewModel: SessionListViewModel
        private var cancellables = Set<AnyCancellable>()

        private let scrollView = NSScrollView()
        private let stackView = NSStackView()
        private let emptyStateView = SessionWatcherEmptyStateView()
        private var errorBanner: SessionWatcherErrorBanner?

        public init(viewModel: SessionListViewModel) {
            self.viewModel = viewModel
            super.init(frame: .zero)
            accessibilityID("session-panel.list")
            setupViews()
            bindViewModel()
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError() }

        /// Notification posted when content changes and the panel should resize.
        public static let contentSizeDidChangeNotification = Notification.Name("SessionContentViewContentSizeDidChange")

        public override var intrinsicContentSize: NSSize {
            // No session cards → the empty-state view is what's visible. Report its
            // height so the host window sizes to show it. Reporting the empty stack's
            // collapsed inset height instead would shrink the list area to nothing and
            // the centered "No Active Sessions" content would overflow up into the
            // header (the empty-state UI the user saw as "mangled").
            if stackView.arrangedSubviews.isEmpty {
                return NSSize(width: NSView.noIntrinsicMetric, height: emptyStateView.intrinsicContentSize.height)
            }
            let contentHeight = stackView.fittingSize.height
            return NSSize(width: NSView.noIntrinsicMetric, height: contentHeight)
        }

        private func setupViews() {
            // One flat list: rows butted together, separated by hairlines rather than
            // by gaps or cards. The rows carry their own horizontal padding, so the
            // stack insets only the ends.
            stackView.orientation = .vertical
            stackView.spacing = 0
            stackView.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
            stackView.translatesAutoresizingMaskIntoConstraints = false

            // Scroll view wrapping the stack
            scrollView.documentView = stackView
            scrollView.hasVerticalScroller = true
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasHorizontalScroller = false
            scrollView.drawsBackground = false
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            scrollView.translatesAutoresizingMaskIntoConstraints = false

            // Empty state
            emptyStateView.translatesAutoresizingMaskIntoConstraints = false
            emptyStateView.isHidden = true
            // Hidden views still hold their constraints, and this one is pinned to all
            // four edges — so its hugging priority is an opinion about how tall the
            // whole list may be. At the default 250 it outranks a host that has
            // deliberately made the list the view that yields (Stenographer's window
            // caps the list at the screen bottom), and the session rows collapse to the
            // empty state's own height. It has no business having that opinion.
            emptyStateView.setContentHuggingPriority(.init(rawValue: 1), for: .vertical)
            emptyStateView.setContentCompressionResistancePriority(.init(rawValue: 1), for: .vertical)

            addSubview(scrollView)
            addSubview(emptyStateView)

            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

                stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

                emptyStateView.topAnchor.constraint(equalTo: topAnchor),
                emptyStateView.leadingAnchor.constraint(equalTo: leadingAnchor),
                emptyStateView.trailingAnchor.constraint(equalTo: trailingAnchor),
                emptyStateView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        private func bindViewModel() {
            viewModel.$sessions
                .combineLatest(viewModel.$isEmpty)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] sessions, isEmpty in
                    self?.updateContent(sessions: sessions, isEmpty: isEmpty)
                }
                .store(in: &cancellables)

            viewModel.$lastActionError
                .combineLatest(viewModel.$lastRequiredPermission)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] error, permission in
                    self?.updateErrorBanner(error: error, requiredPermission: permission)
                }
                .store(in: &cancellables)
        }

        private func updateContent(sessions: [SessionWatcherSession], isEmpty: Bool) {
            stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

            if isEmpty {
                scrollView.isHidden = true
                emptyStateView.isHidden = false
            } else {
                scrollView.isHidden = false
                emptyStateView.isHidden = true

                let summariesEnabled = viewModel.summariesEnabled()
                for (index, session) in sessions.enumerated() {
                    if index > 0 {
                        let separator = SessionWatcherListSeparator()
                        stackView.addArrangedSubview(separator)
                        separator.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
                    }
                    let row = SessionWatcherRowAppKitView(
                        session: session,
                        onTap: { [weak self] session in self?.viewModel.handleSessionClick(session) },
                        isSummarizing: viewModel.summarizingSessionIds.contains(session.sessionId),
                        onSummarize: { [weak self] session in self?.viewModel.summarizeSession(session) },
                        isFrontmost: session.sessionId == viewModel.frontmostSessionId,
                        summariesEnabled: summariesEnabled
                    )
                    stackView.addArrangedSubview(row)
                    row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
                }
            }
            invalidateIntrinsicContentSize()

            // Post after layout so the panel controller can resize
            DispatchQueue.main.async {
                self.needsLayout = true
                self.layoutSubtreeIfNeeded()
                NotificationCenter.default.post(
                    name: Self.contentSizeDidChangeNotification,
                    object: self
                )
            }
        }

        private func updateErrorBanner(error: String?, requiredPermission: AgenticToolkitPermissions.Permission?) {
            errorBanner?.removeFromSuperview()
            errorBanner = nil

            guard let error else { return }

            let banner = SessionWatcherErrorBanner(
                message: error,
                isPermissionError: requiredPermission != nil,
                onOpenSettings: { [weak self] in self?.viewModel.openPermissionSettings() }
            )
            banner.translatesAutoresizingMaskIntoConstraints = false
            addSubview(banner)

            NSLayoutConstraint.activate([
                banner.leadingAnchor.constraint(equalTo: leadingAnchor),
                banner.trailingAnchor.constraint(equalTo: trailingAnchor),
                banner.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            errorBanner = banner
        }
    }

    // MARK: - Empty State View

    public final class SessionWatcherEmptyStateView: NSView {
        /// Natural footprint for the empty state: the dog icon + "No Active Sessions"
        /// label centered with comfortable vertical breathing room. Vended as the
        /// view's intrinsic height so the host window sizes to display it instead of
        /// collapsing the list area to nothing (which crushes the centered content up
        /// into the header above). See `SessionListView.intrinsicContentSize`.
        public static let preferredHeight: CGFloat = 80

        private var iconView: NSImageView!
        private var label: NSTextField!
        private var themeObserver: ThemePaletteObserver?

        public override init(frame: NSRect) {
            super.init(frame: frame)
            accessibilityID("session-panel.empty-state")
            setupViews()
            themeObserver = ThemePaletteObserver(host: self) { [weak self] palette in self?.applyTheme(palette) }
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError() }

        public override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
        }

        private func setupViews() {
            iconView = NSImageView()
            iconView.image = NSImage(systemSymbolName: "dog.fill", accessibilityDescription: nil)
            iconView.symbolConfiguration = .init(pointSize: 24, weight: .regular)
            iconView.translatesAutoresizingMaskIntoConstraints = false

            label = NSTextField(labelWithString: "No Active Sessions")
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false

            let stack = NSStackView(views: [iconView, label])
            stack.orientation = .vertical
            stack.spacing = 8
            stack.alignment = .centerX
            stack.translatesAutoresizingMaskIntoConstraints = false

            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }

        private func applyTheme(_ palette: SemanticPalette) {
            iconView.contentTintColor = palette.secondaryTextColor
            label.textColor = palette.secondaryTextColor
            label.font = palette.font(.caption)
        }
    }

    // MARK: - List Separator

    /// The hairline between two rows. The list draws these instead of giving each
    /// row a border, so a run of rows reads as one list rather than a stack of cards.
    public final class SessionWatcherListSeparator: NSView {
        private var themeObserver: ThemePaletteObserver?

        public init() {
            super.init(frame: .zero)
            wantsLayer = true
            translatesAutoresizingMaskIntoConstraints = false
            heightAnchor.constraint(equalToConstant: 1).isActive = true
            themeObserver = ThemePaletteObserver(host: self) { [weak self] palette in
                self?.layer?.backgroundColor = palette.borderColor.withAlphaComponent(0.5).cgColor
            }
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError() }
    }

    // MARK: - SessionWatcherSession Row View

    public final class SessionWatcherRowAppKitView: NSView {
        private let session: SessionWatcherSession
        private let onTap: ((SessionWatcherSession) -> Void)?
        private let isSummarizing: Bool
        private let onSummarize: ((SessionWatcherSession) -> Void)?
        private let isFrontmost: Bool
        private let summariesEnabled: Bool
        private var trackingArea: NSTrackingArea?

        // Theme-sensitive subviews
        private var projectLabel: NSTextField!
        /// The "»" glyphs between the header's three segments.
        private var separatorLabels: [NSTextField] = []
        /// Git branch and session name — the header's dimmer segments.
        private var subtitleLabels: [NSTextField] = []
        private var activityIcon: SessionWatcherActivityIconView!
        private var outputLabel: NSTextField!
        private var summaryLabel: NSTextField?
        private var themeObserver: ThemePaletteObserver?

        private let isFrontmostSession: Bool

        public init(
            session: SessionWatcherSession,
            onTap: ((SessionWatcherSession) -> Void)?,
            isSummarizing: Bool,
            onSummarize: ((SessionWatcherSession) -> Void)?,
            isFrontmost: Bool,
            summariesEnabled: Bool
        ) {
            self.session = session
            self.onTap = onTap
            self.isSummarizing = isSummarizing
            self.onSummarize = onSummarize
            self.isFrontmost = isFrontmost
            self.summariesEnabled = summariesEnabled
            self.isFrontmostSession = isFrontmost
            super.init(frame: .zero)
            accessibilityID("session-panel.row.\(session.sessionId)")
            wantsLayer = true
            setupViews()
            setupContextMenu()
            themeObserver = ThemePaletteObserver(host: self) { [weak self] palette in self?.applyTheme(palette) }
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError() }

        /// The row's resting background. A list row has no border of its own — the
        /// hairlines between rows do that job — so the frontmost session is marked by
        /// an accent wash instead, the one row-level cue left.
        private func restingBackground(_ palette: SemanticPalette) -> CGColor {
            isFrontmostSession
                ? palette.accentColor.withAlphaComponent(0.14).cgColor
                : NSColor.clear.cgColor
        }

        private func applyTheme(_ palette: SemanticPalette) {
            layer?.backgroundColor = restingBackground(palette)

            // Header line: the project leads, branch and session name follow dimmer.
            projectLabel.textColor = palette.primaryTextColor
            projectLabel.font = palette.font(.body)
            for lbl in subtitleLabels {
                lbl.textColor = palette.secondaryTextColor
                lbl.font = palette.font(.caption)
            }
            for lbl in separatorLabels {
                lbl.textColor = palette.tertiaryTextColor
                lbl.font = palette.font(.caption)
            }

            activityIcon.applyTheme(palette)

            // Second line: the agent's last word.
            outputLabel.textColor = session.lastOutput.isEmpty
                ? palette.tertiaryTextColor
                : palette.secondaryTextColor
            outputLabel.font = palette.font(.caption)

            // Summary line (only present when the summaries feature is on).
            summaryLabel?.textColor = session.summary.isEmpty
                ? palette.tertiaryTextColor
                : palette.secondaryTextColor
            summaryLabel?.font = palette.font(.caption)
        }

        /// App icon for the terminal a session runs in, from its `TERM_PROGRAM`.
        /// Prefers a running instance's icon, falls back to the installed app
        /// bundle, then a generic terminal glyph for unknown/empty terminals.
        private static func appIcon(forTermProgram termProgram: String) -> NSImage? {
            let bundleIDs: [String: String] = [
                "iTerm.app": "com.googlecode.iterm2",
                "Apple_Terminal": "com.apple.Terminal",
                "WarpTerminal": "dev.warp.Warp-Stable",
                "vscode": "com.microsoft.VSCode",
                "tmux": "com.apple.Terminal"
            ]
            if let bundleID = bundleIDs[termProgram] {
                if let running = NSRunningApplication
                    .runningApplications(withBundleIdentifier: bundleID).first?.icon {
                    return running
                }
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    return NSWorkspace.shared.icon(forFile: url.path)
                }
            }
            return NSImage(systemSymbolName: "terminal", accessibilityDescription: "terminal")
        }

        private func setupViews() {
            let hPadding: CGFloat = 8
            let vPadding: CGFloat = 5

            // --- App icon: the "go to session" affordance, spanning both text lines.
            // The icon is the *only* thing in the row that navigates — clicking the
            // text is not a shortcut for it, so a click meant for the context menu or
            // for selecting a line can't yank the user into another terminal.
            let iconButton = NSButton()
            iconButton.image = Self.appIcon(forTermProgram: session.termProgram)
            iconButton.imagePosition = .imageOnly
            iconButton.imageScaling = .scaleProportionallyUpOrDown
            iconButton.isBordered = false
            iconButton.bezelStyle = .shadowlessSquare
            iconButton.target = self
            iconButton.action = #selector(goToSessionAction)
            iconButton.toolTip = session.termProgram.isEmpty
                ? "Go to session"
                : "Go to session in \(session.termProgram)"
            iconButton.accessibilityID("session-panel.row.\(session.sessionId).app-icon")
            iconButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconButton)

            // --- Line 1: project » branch » session name, then the activity icon ---
            let headerRow = NSStackView()
            headerRow.orientation = .horizontal
            headerRow.spacing = 4
            headerRow.alignment = .centerY
            headerRow.translatesAutoresizingMaskIntoConstraints = false

            // The project *root*'s name, not the cwd's: a session run from inside a
            // submodule or a linked worktree belongs to the tree above it, and
            // labelling it "agentictoolkit" or "background-tests" names a directory
            // the user never thinks of as the project.
            let projLabel = NSTextField(labelWithString: session.projectGroupName)
            projLabel.lineBreakMode = .byTruncatingTail
            projLabel.maximumNumberOfLines = 1
            projLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            headerRow.addArrangedSubview(projLabel)
            projectLabel = projLabel

            // Branch and session name are both optional — a session outside a git
            // tree has no branch, one nobody has named has no name — and each
            // separator goes with its segment rather than leaving a dangling "»".
            for (index, text) in [session.gitBranch, session.sessionName].enumerated() where !text.isEmpty {
                let sep = NSTextField(labelWithString: "»")
                sep.setContentCompressionResistancePriority(.required, for: .horizontal)
                headerRow.addArrangedSubview(sep)
                separatorLabels.append(sep)

                let lbl = NSTextField(labelWithString: text)
                lbl.lineBreakMode = .byTruncatingTail
                lbl.maximumNumberOfLines = 1
                // In a narrow window the session name gives way first, then the
                // branch; the project name is the segment that must survive.
                lbl.setContentCompressionResistancePriority(
                    index == 0 ? .init(rawValue: 240) : .defaultLow,
                    for: .horizontal
                )
                headerRow.addArrangedSubview(lbl)
                subtitleLabels.append(lbl)
            }

            let spacer = NSView()
            spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            headerRow.addArrangedSubview(spacer)

            let activity = SessionWatcherActivityIconView(
                activity: session.activity,
                isSummarizing: isSummarizing
            )
            headerRow.addArrangedSubview(activity)
            activityIcon = activity

            addSubview(headerRow)

            // --- Line 2: the agent's last output, one line ---
            let outputLbl = NSTextField(labelWithString: Self.outputText(for: session))
            outputLbl.lineBreakMode = .byTruncatingTail
            outputLbl.maximumNumberOfLines = 1
            outputLbl.translatesAutoresizingMaskIntoConstraints = false
            addSubview(outputLbl)
            outputLabel = outputLbl

            // The ids and paths the old detail lines showed now live in the tooltip
            // (and in the context menu's Show Info), keeping the row two lines tall.
            toolTip = Self.infoText(for: session)

            var lastAnchor = outputLbl.bottomAnchor

            // --- Line 3: the AI summary, only when the feature is on ---
            if summariesEnabled {
                let summaryLbl = NSTextField(wrappingLabelWithString: summaryText())
                summaryLbl.maximumNumberOfLines = 2
                summaryLbl.lineBreakMode = .byTruncatingTail
                summaryLbl.translatesAutoresizingMaskIntoConstraints = false
                addSubview(summaryLbl)
                summaryLabel = summaryLbl
                NSLayoutConstraint.activate([
                    summaryLbl.topAnchor.constraint(equalTo: outputLbl.bottomAnchor, constant: 3),
                    summaryLbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPadding),
                    summaryLbl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPadding)
                ])
                lastAnchor = summaryLbl.bottomAnchor
            }

            NSLayoutConstraint.activate([
                iconButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPadding),
                // Centred on the seam between the two text lines, so it reads as
                // belonging to both of them.
                iconButton.centerYAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 1),
                iconButton.widthAnchor.constraint(equalToConstant: 22),
                iconButton.heightAnchor.constraint(equalToConstant: 22),

                headerRow.topAnchor.constraint(equalTo: topAnchor, constant: vPadding),
                headerRow.leadingAnchor.constraint(equalTo: iconButton.trailingAnchor, constant: 6),
                headerRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPadding),

                outputLbl.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 1),
                outputLbl.leadingAnchor.constraint(equalTo: iconButton.trailingAnchor, constant: 6),
                outputLbl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPadding),

                bottomAnchor.constraint(equalTo: lastAnchor, constant: vPadding)
            ])
        }

        /// Line 2's text: what the agent last said, or a placeholder for a session
        /// that hasn't said anything yet.
        private static func outputText(for session: SessionWatcherSession) -> String {
            session.lastOutput.isEmpty ? "No output yet." : session.lastOutput
        }

        /// Line 3's text. This used to read "thinking..." for every session without a
        /// summary, which conflated three different states: summarized, waiting on the
        /// summarizer, and nothing to summarize in the first place.
        private func summaryText() -> String {
            if !session.summary.isEmpty { return session.summary }
            // No agent output and no tool use: there is no transcript to describe,
            // and saying "Summarizing..." would promise a summary that never comes.
            if !isSummarizing, session.lastOutput.isEmpty, session.lastTool.isEmpty {
                return "Nothing to summarize."
            }
            return "Summarizing..."
        }

        /// Everything the two-line row can't show — ids, paths, model, timing. Used
        /// as the row's tooltip and as the body of the context menu's Show Info.
        private static func infoText(for session: SessionWatcherSession) -> String {
            var fields: [(String, String)] = [
                ("Session ID", session.sessionId),
                ("Name", session.sessionName),
                ("Project", session.projectGroupName),
                ("Project Root", session.projectRoot),
                ("Working Dir", session.cwd),
                ("Git Branch", session.gitBranch),
                ("Model", session.model),
                ("Status", session.status.rawValue),
                ("Activity", session.activity.rawValue),
                ("Last Event", session.lastEventType),
                ("Last Tool", session.lastTool),
                ("Started", session.startedAt),
                ("Last Activity", lastActivityDescription(session)),
                ("Terminal", session.termProgram),
                ("Term Session", session.termSessionId),
                ("PID", session.pid == 0 ? "" : String(session.pid)),
                ("Last Output", session.lastOutput),
                ("Summary", session.summary)
            ]
            fields.removeAll { $0.1.isEmpty }
            return fields.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        }

        private static func lastActivityDescription(_ session: SessionWatcherSession) -> String {
            let relative = relativeTime(session.lastActivityAt)
            guard !relative.isEmpty else { return session.lastActivityAt }
            return "\(session.lastActivityAt) (\(relative))"
        }

        // MARK: - Context menu

        private func setupContextMenu() {
            let menu = NSMenu()
            // Hand-managed enablement: with autoenabling on, AppKit ignores
            // `isEnabled` and asks the responder chain instead.
            menu.autoenablesItems = false
            let hasPath = !session.cwd.isEmpty
            menu.addItem(menuItem("Go to Session", #selector(goToSessionAction)))
            menu.addItem(menuItem("Reveal in Finder", #selector(revealInFinderAction), enabled: hasPath))
            menu.addItem(menuItem("Copy Path", #selector(copyPathAction), enabled: hasPath))
            menu.addItem(menuItem("Show Info", #selector(showInfoAction)))
            menu.addItem(.separator())
            menu.addItem(menuItem("Summarize with AI", #selector(summarizeAction), enabled: !isSummarizing))
            self.menu = menu
        }

        private func menuItem(_ title: String, _ action: Selector, enabled: Bool = true) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            return item
        }

        @objc private func goToSessionAction() {
            onTap?(session)
        }

        @objc private func revealInFinderAction() {
            guard !session.cwd.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.cwd)])
        }

        @objc private func copyPathAction() {
            guard !session.cwd.isEmpty else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(session.cwd, forType: .string)
        }

        @objc private func showInfoAction() {
            let title = session.projectGroupName
            let body = Self.infoText(for: session)
            // Deferred: running a modal from inside menu tracking leaves the alert's
            // controls unresponsive until tracking unwinds.
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = title
                alert.informativeText = body
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Copy")
                if alert.runModal() == .alertSecondButtonReturn {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(body, forType: .string)
                }
            }
        }

        @objc private func summarizeAction() {
            onSummarize?(session)
        }

        // MARK: - Mouse handling

        public override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea { removeTrackingArea(existing) }
            trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow],
                owner: self, userInfo: nil
            )
            addTrackingArea(trackingArea!)
        }

        // Hover is the only thing the row body reacts to — it says which row a
        // right-click or a summarize would land on. There is deliberately no
        // mouseDown/mouseUp handling: pressing a row is not a navigation gesture,
        // and a press highlight would promise that it is.
        public override func mouseEntered(with event: NSEvent) {
            let palette = resolvedThemeScope.palette
            layer?.backgroundColor = palette.selectionColor.withAlphaComponent(0.14).cgColor
        }

        public override func mouseExited(with event: NSEvent) {
            layer?.backgroundColor = restingBackground(resolvedThemeScope.palette)
        }

        // MARK: - Helpers

        private static func relativeTime(_ timestamp: String) -> String {
            guard !timestamp.isEmpty else { return "" }
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: timestamp) {
                return relativeTimeFromDate(date)
            }
            formatter.formatOptions.remove(.withFractionalSeconds)
            if let date = formatter.date(from: timestamp) {
                return relativeTimeFromDate(date)
            }
            return ""
        }

        private static func relativeTimeFromDate(_ date: Date) -> String {
            let interval = Date().timeIntervalSince(date)
            if interval < 60 { return "now" }
            if interval < 3600 { return "\(Int(interval / 60))m" }
            if interval < 86400 { return "\(Int(interval / 3600))h" }
            return "\(Int(interval / 86400))d"
        }

    }

    // MARK: - Error Banner

    public final class SessionWatcherErrorBanner: NSView {
        private var onOpenSettingsAction: (() -> Void)?
        private let isPermissionError: Bool
        private var bannerLabel: NSTextField!
        private var warningIcon: NSImageView!
        private var themeObserver: ThemePaletteObserver?

        public init(message: String, isPermissionError: Bool, onOpenSettings: (() -> Void)?) {
            self.onOpenSettingsAction = onOpenSettings
            self.isPermissionError = isPermissionError
            super.init(frame: .zero)
            accessibilityID("session-panel.error-banner")
            wantsLayer = true
            setupViews(message: message, isPermissionError: isPermissionError)
            themeObserver = ThemePaletteObserver(host: self) { [weak self] palette in self?.applyTheme(palette) }
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError() }

        private func applyTheme(_ palette: SemanticPalette) {
            let bgColor = isPermissionError
                ? palette.warningColor.withAlphaComponent(0.15)
                : palette.dangerColor.withAlphaComponent(0.15)
            layer?.backgroundColor = bgColor.cgColor
            bannerLabel.textColor = palette.primaryTextColor
            bannerLabel.font = palette.font(.caption)
            warningIcon.contentTintColor = palette.warningColor
        }

        private func setupViews(message: String, isPermissionError: Bool) {
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false

            // Message row
            let messageRow = NSStackView()
            messageRow.orientation = .horizontal
            messageRow.spacing = 6

            let icon = NSImageView()
            icon.image = NSImage(
                systemSymbolName: isPermissionError ? "lock.shield" : "exclamationmark.triangle.fill",
                accessibilityDescription: nil
            )
            icon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16)
            ])
            warningIcon = icon

            let lbl = NSTextField(wrappingLabelWithString: message)
            lbl.maximumNumberOfLines = 3
            bannerLabel = lbl

            messageRow.addArrangedSubview(icon)
            messageRow.addArrangedSubview(lbl)
            stack.addArrangedSubview(messageRow)

            if isPermissionError {
                let button = NSButton(
                    title: "Open System Settings",
                    target: self,
                    action: #selector(openSettingsClicked)
                )
                // Sized with the banner text it sits under, not with the app's
                // default control label.
                button.observeTheme { btn, palette in btn.font = palette.font(.caption) }
                button.bezelStyle = .recessed
                button.accessibilityID("session-panel.error-banner.open-settings")
                stack.addArrangedSubview(button)
            }

            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
            ])
        }

        @objc private func openSettingsClicked() {
            onOpenSettingsAction?()
        }
    }
}
