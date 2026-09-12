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
            // Stack view for session groups
            stackView.orientation = .vertical
            stackView.spacing = 6
            stackView.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
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
            viewModel.$groups
                .combineLatest(viewModel.$isEmpty)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] groups, isEmpty in
                    self?.updateContent(groups: groups, isEmpty: isEmpty)
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

        private func updateContent(groups: [SessionWatcherGroup], isEmpty: Bool) {
            stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

            if isEmpty {
                scrollView.isHidden = true
                emptyStateView.isHidden = false
            } else {
                scrollView.isHidden = false
                emptyStateView.isHidden = true

                for group in groups {
                    let groupView = SessionWatcherGroupCardView(
                        group: group,
                        onSessionClick: { [weak self] session in self?.viewModel.handleSessionClick(session) },
                        summarizingSessionIds: viewModel.summarizingSessionIds,
                        onSummarize: { [weak self] session in self?.viewModel.summarizeSession(session) },
                        frontmostSessionId: viewModel.frontmostSessionId,
                        summariesEnabled: viewModel.summariesEnabled()
                    )
                    stackView.addArrangedSubview(groupView)
                    groupView.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -16).isActive = true
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

    // MARK: - SessionWatcherSession Group Card View

    public final class SessionWatcherGroupCardView: NSView {
        private let group: SessionWatcherGroup
        private let onSessionClick: ((SessionWatcherSession) -> Void)?
        private let summarizingSessionIds: Set<String>
        private let onSummarize: ((SessionWatcherSession) -> Void)?
        private let frontmostSessionId: String?
        private let summariesEnabled: Bool

        // Theme-sensitive subviews
        private var folderIconView: NSImageView!
        private var titleLabel: NSTextField!
        private var countLabel: NSTextField!
        private var dividerView: NSBox!
        private var noneLabel: NSTextField?
        private var themeObserver: ThemePaletteObserver?

        public init(
            group: SessionWatcherGroup,
            onSessionClick: ((SessionWatcherSession) -> Void)?,
            summarizingSessionIds: Set<String>,
            onSummarize: ((SessionWatcherSession) -> Void)?,
            frontmostSessionId: String?,
            summariesEnabled: Bool
        ) {
            self.group = group
            self.onSessionClick = onSessionClick
            self.summarizingSessionIds = summarizingSessionIds
            self.onSummarize = onSummarize
            self.frontmostSessionId = frontmostSessionId
            self.summariesEnabled = summariesEnabled
            super.init(frame: .zero)
            accessibilityID("session-panel.group.\(AccessibilityID.slug(group.projectName))")
            wantsLayer = true
            layer?.cornerRadius = 8
            setupViews()
            themeObserver = ThemePaletteObserver(host: self) { [weak self] palette in self?.applyTheme(palette) }
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError() }

        private func applyTheme(_ palette: SemanticPalette) {
            layer?.backgroundColor = palette.surfaceColor.cgColor
            layer?.borderColor = palette.borderColor.cgColor
            layer?.borderWidth = 0.5
            folderIconView.contentTintColor = palette.secondaryTextColor
            titleLabel.textColor = palette.primaryTextColor
            titleLabel.font = palette.font(.heading)
            countLabel.textColor = palette.tertiaryTextColor
            countLabel.font = palette.font(.caption)
            noneLabel?.textColor = palette.tertiaryTextColor
            noneLabel?.font = palette.font(.caption)
            // NSBox separator color is driven by the system; tint via layer instead
            dividerView.alphaValue = 0.3
        }

        private func setupViews() {
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.spacing = 0
            stack.translatesAutoresizingMaskIntoConstraints = false

            // Header
            let header = makeSessionHeader()
            stack.addArrangedSubview(header)

            let divider = makeDivider()
            dividerView = divider
            stack.addArrangedSubview(divider)

            // Sessions
            if group.sessions.isEmpty {
                let none = NSTextField(labelWithString: "None")
                noneLabel = none
                let wrapper = NSView()
                wrapper.translatesAutoresizingMaskIntoConstraints = false
                none.translatesAutoresizingMaskIntoConstraints = false
                wrapper.addSubview(none)
                NSLayoutConstraint.activate([
                    none.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
                    none.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 6),
                    none.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -6)
                ])
                stack.addArrangedSubview(wrapper)
            } else {
                // Breathing room between the divider and the first row, and between
                // rows — the cards each draw a border, so butting them together
                // reads as one box rather than a list.
                stack.setCustomSpacing(4, after: divider)
                for session in group.sessions {
                    let row = SessionWatcherRowAppKitView(
                        session: session,
                        onTap: onSessionClick,
                        isSummarizing: summarizingSessionIds.contains(session.sessionId),
                        onSummarize: onSummarize,
                        isFrontmost: session.sessionId == frontmostSessionId,
                        summariesEnabled: summariesEnabled
                    )
                    row.translatesAutoresizingMaskIntoConstraints = false
                    stack.addArrangedSubview(row)
                    row.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 6).isActive = true
                    row.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -6).isActive = true
                    stack.setCustomSpacing(4, after: row)
                }
            }

            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        private func makeSessionHeader() -> NSView {
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false

            // Folder icon — the group is a project (git) directory now.
            let iconView = NSImageView()
            iconView.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            iconView.symbolConfiguration = .init(pointSize: 13, weight: .regular)
            iconView.toolTip = group.id  // full project-root path
            iconView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(iconView)
            folderIconView = iconView

            let title = NSTextField(labelWithString: group.projectName)
            title.lineBreakMode = .byTruncatingTail
            title.maximumNumberOfLines = 1
            title.toolTip = group.id
            title.translatesAutoresizingMaskIntoConstraints = false
            titleLabel = title

            let suffix = group.sessions.count == 1 ? "" : "s"
            let count = NSTextField(labelWithString: "\(group.sessions.count) session\(suffix)")
            count.setContentCompressionResistancePriority(.required, for: .horizontal)
            count.translatesAutoresizingMaskIntoConstraints = false
            countLabel = count

            container.addSubview(title)
            container.addSubview(count)

            NSLayoutConstraint.activate([
                container.heightAnchor.constraint(greaterThanOrEqualToConstant: 26),

                iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 16),
                iconView.heightAnchor.constraint(equalToConstant: 16),

                title.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
                title.centerYAnchor.constraint(equalTo: container.centerYAnchor),

                count.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
                count.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                count.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 5)
            ])

            return container
        }

        private func makeDivider() -> NSBox {
            let divider = NSBox()
            divider.boxType = .separator
            divider.alphaValue = 0.15
            divider.translatesAutoresizingMaskIntoConstraints = false
            return divider
        }
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
        private var isHovered = false

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
            layer?.cornerRadius = 6
            setupViews()
            setupContextMenu()
            themeObserver = ThemePaletteObserver(host: self) { [weak self] palette in self?.applyTheme(palette) }
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError() }

        private func applyTheme(_ palette: SemanticPalette) {
            // Card background: subtle surface tint (idle). The frontmost session's
            // row carries the accent on its border — the status dot it used to be
            // shown by is gone, its job now done by the activity icon.
            layer?.backgroundColor = palette.surfaceColor.withAlphaComponent(0.5).cgColor
            layer?.borderColor = (isFrontmostSession ? palette.accentColor : palette.borderColor).cgColor
            layer?.borderWidth = isFrontmostSession ? 1.0 : 0.5

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
            let vPadding: CGFloat = 6

            // --- App icon: the "go to session" affordance, spanning both text lines.
            // A button rather than an image view so the icon itself is clickable;
            // the whole row still is too, via mouseUp.
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

            let projLabel = NSTextField(labelWithString: session.projectName)
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
            let title = session.projectName
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

        public override func mouseEntered(with event: NSEvent) {
            isHovered = true
            let palette = resolvedThemeScope.palette
            layer?.backgroundColor = palette.selectionColor.withAlphaComponent(0.18).cgColor
        }

        public override func mouseExited(with event: NSEvent) {
            isHovered = false
            let palette = resolvedThemeScope.palette
            layer?.backgroundColor = palette.surfaceColor.withAlphaComponent(0.5).cgColor
        }

        public override func mouseDown(with event: NSEvent) {
            let palette = resolvedThemeScope.palette
            layer?.backgroundColor = palette.selectionColor.withAlphaComponent(0.35).cgColor
        }

        public override func mouseUp(with event: NSEvent) {
            let palette = resolvedThemeScope.palette
            layer?.backgroundColor = isHovered
                ? palette.selectionColor.withAlphaComponent(0.18).cgColor
                : palette.surfaceColor.withAlphaComponent(0.5).cgColor
            let location = convert(event.locationInWindow, from: nil)
            if bounds.contains(location) {
                onTap?(session)
            }
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
