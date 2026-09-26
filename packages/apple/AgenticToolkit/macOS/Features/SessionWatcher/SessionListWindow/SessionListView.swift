import AppKit
import Combine
import AgenticToolkitCore
import AgenticToolkitCoreUI
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

        /// The rows currently in the stack, by session id, with the order they are
        /// in — together these say whether an incoming snapshot is the same list
        /// with newer content (update in place) or a different list (rebuild).
        private var rows: [String: SessionWatcherRowAppKitView] = [:]
        private var displayedSessionIds: [String] = []
        /// Whether the rows in the stack were built with a summary line, which
        /// decides whether they can be reused when the setting changes.
        private var displayedSummariesEnabled = false

        public init(viewModel: SessionListViewModel) {
            self.viewModel = viewModel
            super.init(frame: .zero)
            accessibilityID("session-panel.list")
            setupViews()
            bindViewModel()
            // The row's width budget depends on the scroller style (see
            // `minimumContentWidth`), and the style changes under a running app
            // when "Show scroll bars" does. The host re-fits on this list's
            // content-size notification, so a style change is posted as one.
            NotificationCenter.default.addObserver(
                self, selector: #selector(preferredScrollerStyleChanged),
                name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        }

        @objc private func preferredScrollerStyleChanged() {
            // AppKit re-applies the preferred style to the scroll view on this
            // same notification; hop once so the width is read after it has.
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.contentSizeDidChangeNotification, object: self)
            }
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

        /// The narrowest the list can be with every row's breadcrumb shown whole.
        /// Hosts keep their window at least this wide; zero when there are no rows.
        ///
        /// Rows are as wide as the *clip* view, and each already keeps a lane
        /// clear for an overlay scroller. A legacy scroller floats over nothing:
        /// it takes its width out of the clip view, so a list measured without
        /// it came up one scroller short and the widest breadcrumb truncated.
        public var minimumContentWidth: CGFloat {
            guard let widest = rows.values.map(\.minimumWidth).max() else { return 0 }
            return widest + legacyScrollerWidth
        }

        /// What a legacy scroller takes out of the clip view's width; nothing
        /// under overlay scrollers. Counted whether or not it is currently
        /// shown: it appears the moment the list outgrows the window, and a
        /// minimum that moved with it would shift the window sideways then.
        private var legacyScrollerWidth: CGFloat {
            guard scrollView.hasVerticalScroller, scrollView.scrollerStyle == .legacy else { return 0 }
            return NSScroller.scrollerWidth(
                for: scrollView.verticalScroller?.controlSize ?? .regular,
                scrollerStyle: .legacy)
        }

        private func setupViews() {
            // One flat list: rows separated by hairlines rather than by cards. The
            // rows carry their own padding, which is the space either side of each
            // hairline, so the stack itself adds none.
            stackView.orientation = .vertical
            stackView.spacing = 0
            stackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
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

                // The *clip* view's width, not the scroll view's. They are the
                // same under overlay scrollers, and differ by the scroller's
                // width under legacy ones — and which of the two is in force is
                // not ours to decide: `scrollerStyle` follows
                // `NSScroller.preferredScrollerStyle`, which AppKit re-applies
                // when the user changes "Show scroll bars" in System Settings.
                // Measured against the scroll view, a legacy scroller pushed the
                // rows' right edge underneath itself.
                stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

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

            // The highlight follows the frontmost window, which moves without
            // the session list changing — so it redraws on its own signal.
            // Hopping to main also lets the property settle: `@Published`
            // publishes from `willSet`, and the rows read the property back.
            viewModel.$frontmostSessionId
                .removeDuplicates()
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.updateContent(sessions: self.viewModel.sessions, isEmpty: self.viewModel.isEmpty)
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
            let summariesEnabled = viewModel.summariesEnabled()

            if isEmpty {
                rebuildRows(sessions: [], summariesEnabled: summariesEnabled)
                scrollView.isHidden = true
                emptyStateView.isHidden = false
            } else {
                scrollView.isHidden = false
                emptyStateView.isHidden = true
                if !refreshRowsInPlace(sessions: sessions, summariesEnabled: summariesEnabled) {
                    rebuildRows(sessions: sessions, summariesEnabled: summariesEnabled)
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

        /// The common case: the same sessions, in the same order, with newer
        /// content. Returns false when the list's *shape* changed and the caller
        /// has to rebuild.
        ///
        /// This is why the window stopped churning. The source polls the daemon
        /// every three seconds and publishes whenever any field of any session
        /// differs — and a live session's `last_output` differs almost every time.
        /// Rebuilding the stack on each of those tore down every row and built a
        /// new one, which reset the scroll position, dropped whatever row the
        /// pointer was over, and restarted each working session's spinner from zero
        /// because layer animations do not survive leaving the window. None of that
        /// was a content change; it was the same eighteen rows, reprinted.
        private func refreshRowsInPlace(
            sessions: [SessionWatcherSession],
            summariesEnabled: Bool
        ) -> Bool {
            guard summariesEnabled == displayedSummariesEnabled,
                  sessions.map(\.sessionId) == displayedSessionIds
            else { return false }
            let frontmostId = viewModel.frontmostSessionId
            let summarizing = viewModel.summarizingSessionIds
            for session in sessions {
                guard let row = rows[session.sessionId],
                      row.update(
                          session: session,
                          isSummarizing: summarizing.contains(session.sessionId),
                          isFrontmost: session.sessionId == frontmostId,
                          summariesEnabled: summariesEnabled
                      )
                else { return false }
            }
            return true
        }

        /// Throws the whole list away and builds it again — for a genuine change of
        /// membership, order, or row shape, which is what a rebuild is actually for.
        private func rebuildRows(sessions: [SessionWatcherSession], summariesEnabled: Bool) {
            stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            rows.removeAll(keepingCapacity: true)
            displayedSessionIds = sessions.map(\.sessionId)
            displayedSummariesEnabled = summariesEnabled

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
                rows[session.sessionId] = row
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

    /// A themed hairline: between two rows, above a row's summary, and under the
    /// Sessions window's header. The list draws these instead of giving each row a
    /// border, so a run of rows reads as one list rather than a stack of cards.
    public final class SessionWatcherListSeparator: NSView {
        private var themeObserver: ThemePaletteObserver?

        public init() {
            super.init(frame: .zero)
            wantsLayer = true
            translatesAutoresizingMaskIntoConstraints = false
            heightAnchor.constraint(equalToConstant: 1).isActive = true
            themeObserver = ThemePaletteObserver(host: self) { [weak self] palette in
                self?.layer?.backgroundColor = palette.dividerColor.cgColor
            }
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError() }
    }

    // MARK: - SessionWatcherSession Row View

    public final class SessionWatcherRowAppKitView: NSView {
        private var session: SessionWatcherSession
        private let onTap: ((SessionWatcherSession) -> Void)?
        private var isSummarizing: Bool
        private let onSummarize: ((SessionWatcherSession) -> Void)?
        private var isFrontmost: Bool
        private let summariesEnabled: Bool
        private var trackingArea: NSTrackingArea?

        /// Which session this row is showing — the identity `update(...)` is keyed
        /// on, so the list can match a row to its session across a refresh.
        public var sessionId: String { session.sessionId }

        // Theme-sensitive subviews
        /// `[app] project » branch » session name … [activity]`. The
        /// Conversations feed and its shelf head their rows with the same view,
        /// which is what keeps the three windows reading as one description of
        /// the same sessions.
        private var headerView: SessionHeaderView!
        private var activityIcon: SessionWatcherActivityIconView!

        /// The trail inside the header — what the tests measure, and what the
        /// prose under it lines up with.
        var breadcrumb: SessionBreadcrumbView { headerView.breadcrumb }
        /// The inset "terminal" the agent's last output is printed into.
        private var terminalView: NSView!
        private(set) var outputLabel: NSTextField!
        private var outputHeight: NSLayoutConstraint!
        private var summaryLabel: NSTextField?
        private var summaryHeight: NSLayoutConstraint?
        private var themeObserver: ThemePaletteObserver?

        /// The row's spacing, in one place so `minimumWidth` measures exactly the
        /// layout `setupViews` builds.
        enum Metrics {
            static let horizontalPadding: CGFloat = 14
            static let verticalPadding: CGFloat = 12
            /// Room kept clear after the row's content for the overlay scroller
            /// to float in. The scroller fades out when the list fits, but
            /// while it is on screen it draws *over* the right end of the row —
            /// which is exactly where the activity icon sits, so the one thing
            /// the row puts furthest right is the one thing the knob covers.
            ///
            /// 15 is AppKit's own overlay scroller width
            /// (`NSScroller.scrollerWidth(for: .regular, scrollerStyle:
            /// .overlay)`), written out rather than called: `NSScroller` is
            /// main-actor isolated and a `static let` here is initialised
            /// wherever it is first touched.
            static let scrollerGutter: CGFloat = 15
            /// What the row's content actually stops at on the right: its own
            /// margin plus the scroller's lane. Only the right side has one —
            /// the list scrolls vertically, so nothing floats over the left.
            static let trailingPadding: CGFloat = horizontalPadding + scrollerGutter
            /// The same icon at the same size as the header over a bubble in the
            /// Conversations feed. It used to be 44 and a column of its own
            /// beside the row's prose; on the header's line, at the feed's size,
            /// it reads as part of the trail it heads — and the terminal under
            /// it gets the width the column was spending.
            static let iconSide: CGFloat = 28
            /// Air between the icon and the first crumb — the feed's gap, for
            /// the same reason as the size.
            static let iconToText: CGFloat = 8
            /// The least room left between the breadcrumb and the activity icon.
            static let headerToActivity: CGFloat = 12
            static let headerToOutput: CGFloat = 8
            static let terminalInsetX: CGFloat = 10
            static let terminalInsetY: CGFloat = 7
            static let outputLines = 4
            static let dividerGap: CGFloat = 10
            static let summaryLines = 2
        }

        /// The terminal prompt the last output is printed after.
        static let outputPrompt = "> "

        /// Horizontal compression-resistance priorities for the row's prose, in
        /// the order it gives way: the agent's last output first, then the AI
        /// summary. Both sit under every segment of the breadcrumb, which is what
        /// identifies the row (``SessionBreadcrumbView`` sets those, and its
        /// `segmentPriority` carries the reasoning for the whole scale).
        ///
        /// Every one of them sits **below** `.fittingSizeCompression` (50): a
        /// label above that demands its full intrinsic width in `fittingSize`,
        /// and a single long `last_output` line dragged the Sessions window out
        /// to forty thousand points wide.
        private enum TextPriority {
            static let output = NSLayoutConstraint.Priority(rawValue: 20)
            static let summary = NSLayoutConstraint.Priority(rawValue: 10)
        }

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
            super.init(frame: .zero)
            accessibilityID("session-panel.row.\(session.sessionId)")
            wantsLayer = true
            setupViews()
            setupContextMenu()
            themeObserver = ThemePaletteObserver(host: self) { [weak self] palette in self?.applyTheme(palette) }
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError() }

        /// Moves this row to a newer snapshot of the same session in place, and
        /// reports whether it could. `false` means the change is structural and the
        /// caller must build a fresh row: the header's "»"-separated segments exist
        /// only for the fields that are non-empty, so a branch or a session name
        /// that appeared or vanished changes how many labels the row has, and
        /// `summariesEnabled` decides whether the summary exists at all.
        ///
        /// Everything that actually moves poll to poll — what the agent last said,
        /// its activity, its summary, whether it is the frontmost session, and the
        /// branch and session name themselves — is a string or a colour on a label
        /// that is already there.
        public func update(
            session newSession: SessionWatcherSession,
            isSummarizing newIsSummarizing: Bool,
            isFrontmost newIsFrontmost: Bool,
            summariesEnabled newSummariesEnabled: Bool
        ) -> Bool {
            guard newSession.sessionId == session.sessionId,
                  newSummariesEnabled == summariesEnabled,
                  Self.crumbs(for: newSession).hasSameShape(as: Self.crumbs(for: session))
            else { return false }

            // The list re-applies every row whenever any one session changed, which
            // with a live session is every poll. An unchanged row keeps what it
            // shows; re-theming it re-parsed its whole last output as markdown —
            // tens of KB per row, every few seconds, for text that had not moved.
            // Only the tooltip reads the clock ("2m ago"), so it alone is redone.
            if newSession == session, newIsSummarizing == isSummarizing, newIsFrontmost == isFrontmost {
                toolTip = Self.infoText(for: newSession)
                return true
            }

            session = newSession
            isSummarizing = newIsSummarizing
            isFrontmost = newIsFrontmost

            headerView.crumbs = Self.crumbs(for: newSession)
            activityIcon.update(activity: newSession.activity, isSummarizing: newIsSummarizing)
            summaryLabel?.stringValue = summaryText()
            toolTip = Self.infoText(for: newSession)
            // Summarize is the one item whose enablement tracks live state.
            menu?.items.first { $0.action == #selector(summarizeAction) }?.isEnabled = !newIsSummarizing
            // The output is an attributed string built from the palette, text colour
            // depends on whether these fields are empty, and the resting background
            // on `isFrontmost` — all of which just changed.
            applyTheme(resolvedThemeScope.palette)
            return true
        }

        /// The narrowest this row can be and still show its whole breadcrumb —
        /// project, branch and session name untruncated, with the activity icon
        /// after them. The Sessions window keeps itself at least this wide.
        ///
        /// Measured from the labels' own text widths rather than `fittingSize`: the
        /// breadcrumb's labels deliberately abstain from the fitting width, so a
        /// fitting size would squeeze them to nothing.
        public var minimumWidth: CGFloat {
            headerView.minimumWidth + Metrics.horizontalPadding + Metrics.trailingPadding
        }

        /// The session as a breadcrumb: project, branch, name — each segment
        /// present only when the session has it.
        ///
        /// `update(...)` compares two of these by *shape*, never by text: a
        /// renamed branch or session still has the label to write the new name
        /// into, and comparing the text there sent every rename down the rebuild
        /// path the in-place update exists to avoid.
        private static func crumbs(for session: SessionWatcherSession) -> SessionBreadcrumbView.Crumbs {
            .init(
                project: session.projectGroupName,
                branch: session.gitBranch,
                name: session.sessionName
            )
        }

        /// The row's resting background. A list row has no border of its own — the
        /// hairlines between rows do that job — so the frontmost session is marked by
        /// an accent wash instead, the one row-level cue left.
        private func restingBackground(_ palette: SemanticPalette) -> CGColor {
            isFrontmost
                ? palette.accentColor.withAlphaComponent(0.14).cgColor
                : NSColor.clear.cgColor
        }

        private func applyTheme(_ palette: SemanticPalette) {
            layer?.backgroundColor = restingBackground(palette)

            // Reaches the trail and the activity icon both — the header owns
            // them, and theming them from here would be theming them twice.
            headerView.applyTheme(palette)

            // The agent's last output, printed into a terminal after a prompt.
            TerminalBoxStyle.apply(palette, to: terminalView.layer)
            let codeFont = palette.font(.code)
            outputLabel.attributedStringValue = Self.terminalText(
                Self.outputText(for: session),
                font: codeFont,
                promptColor: palette.accentColor,
                textColor: session.lastOutput.isEmpty ? palette.tertiaryTextColor : palette.secondaryTextColor
            )
            outputHeight.constant = Self.height(ofLines: Metrics.outputLines, in: codeFont)

            // Summary (only present when the summaries feature is on).
            let summaryFont = palette.font(.caption)
            summaryLabel?.textColor = session.summary.isEmpty
                ? palette.tertiaryTextColor
                : palette.secondaryTextColor
            summaryLabel?.font = summaryFont
            summaryHeight?.constant = Self.height(ofLines: Metrics.summaryLines, in: summaryFont)
        }

        /// `text` after a terminal prompt, wrapped with a hanging indent so every
        /// continuation line lines up under the text rather than under the prompt.
        static func terminalText(
            _ text: String,
            font: NSFont,
            promptColor: NSColor,
            textColor: NSColor
        ) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.headIndent = ceil((outputPrompt as NSString).size(withAttributes: [.font: font]).width)
            let result = NSMutableAttributedString(
                string: outputPrompt,
                attributes: [.font: font, .foregroundColor: promptColor, .paragraphStyle: paragraph]
            )
            result.append(NSAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph]
            ))
            return result
        }

        /// The height `lines` lines of `font` set, so a block is exactly that many
        /// lines tall whatever it holds and every row in the list lines up.
        static func height(ofLines lines: Int, in font: NSFont) -> CGFloat {
            ceil(NSLayoutManager().defaultLineHeight(for: font) * CGFloat(lines))
        }

        private func setupViews() {
            typealias Layout = Metrics

            // --- Line 1: [app] project » branch » session name … [activity] ---
            // The same control the Conversations shelf lists sessions with and the
            // Conversations feed heads each bubble with, so the three windows read
            // as one description of the same sessions rather than as three
            // arrangements of the same three facts.
            let activity = SessionWatcherActivityIconView(
                activity: session.activity,
                isSummarizing: isSummarizing
            )
            activityIcon = activity

            // The project *root*'s name heads it, not the cwd's: a session run from
            // inside a submodule or a linked worktree belongs to the tree above it,
            // and labelling it "agentictoolkit" or "background-tests" names a
            // directory the user never thinks of as the project. The window keeps
            // itself wide enough for the whole trail (`minimumWidth`); while it
            // catches up, the session name gives way first and the project survives.
            let header = SessionHeaderView(
                crumbs: Self.crumbs(for: session),
                icon: .init(
                    appIdentity: session.termProgram,
                    side: Layout.iconSide,
                    gap: Layout.iconToText,
                    isActionable: true),
                accessory: activity,
                accessoryGap: Layout.headerToActivity
            )
            headerView = header

            // The icon is the *only* thing in the row that navigates — clicking the
            // text is not a shortcut for it, so a click meant for the context menu or
            // for selecting a line can't yank the user into another terminal. The
            // pointing-hand cursor over it is what says so.
            if let iconButton = header.iconButton {
                iconButton.target = self
                iconButton.action = #selector(goToSessionAction)
                iconButton.toolTip = session.termProgram.isEmpty
                    ? "Go to session"
                    : "Go to session in \(session.termProgram)"
                iconButton.accessibilityID("session-panel.row.\(session.sessionId).app-icon")
            }

            addSubview(header)

            // --- The agent's last output: four lines in an inset terminal, after a
            // prompt. Always four lines tall, so the rows line up down the list.
            let terminal = NSView()
            terminal.wantsLayer = true
            TerminalBoxStyle.shape(terminal.layer)
            terminal.translatesAutoresizingMaskIntoConstraints = false
            addSubview(terminal)
            terminalView = terminal

            let outputLbl = NSTextField(wrappingLabelWithString: "")
            outputLbl.maximumNumberOfLines = Layout.outputLines
            outputLbl.cell?.truncatesLastVisibleLine = true
            outputLbl.setContentCompressionResistancePriority(TextPriority.output, for: .horizontal)
            outputLbl.setContentCompressionResistancePriority(.init(rawValue: 1), for: .vertical)
            outputLbl.setContentHuggingPriority(.init(rawValue: 1), for: .vertical)
            outputLbl.translatesAutoresizingMaskIntoConstraints = false
            terminal.addSubview(outputLbl)
            outputLabel = outputLbl
            outputHeight = outputLbl.heightAnchor.constraint(equalToConstant: 0)

            // The ids and paths the old detail lines showed now live in the tooltip
            // (and in the context menu's Show Info), keeping the row compact.
            toolTip = Self.infoText(for: session)

            // The prose starts at the row's own margin now that the icon is on the
            // header's line rather than in a gutter beside the whole row — so the
            // terminal gets the width that column was spending.
            var lastAnchor = terminal.bottomAnchor

            // --- The AI summary under a divider, two lines, only when the feature is on ---
            if summariesEnabled {
                let divider = SessionWatcherListSeparator()
                addSubview(divider)

                let summaryLbl = NSTextField(wrappingLabelWithString: summaryText())
                summaryLbl.maximumNumberOfLines = Layout.summaryLines
                summaryLbl.cell?.truncatesLastVisibleLine = true
                summaryLbl.setContentCompressionResistancePriority(TextPriority.summary, for: .horizontal)
                summaryLbl.setContentCompressionResistancePriority(.init(rawValue: 1), for: .vertical)
                summaryLbl.setContentHuggingPriority(.init(rawValue: 1), for: .vertical)
                summaryLbl.translatesAutoresizingMaskIntoConstraints = false
                addSubview(summaryLbl)
                summaryLabel = summaryLbl
                let height = summaryLbl.heightAnchor.constraint(equalToConstant: 0)
                summaryHeight = height
                NSLayoutConstraint.activate([
                    divider.topAnchor.constraint(equalTo: terminal.bottomAnchor, constant: Layout.dividerGap),
                    divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalPadding),
                    divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.trailingPadding),

                    summaryLbl.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: Layout.dividerGap),
                    summaryLbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalPadding),
                    summaryLbl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.trailingPadding),
                    height
                ])
                lastAnchor = summaryLbl.bottomAnchor
            }

            NSLayoutConstraint.activate([
                header.topAnchor.constraint(equalTo: topAnchor, constant: Layout.verticalPadding),
                header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalPadding),
                header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.trailingPadding),

                terminal.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Layout.headerToOutput),
                terminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalPadding),
                terminal.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.trailingPadding),

                outputLbl.topAnchor.constraint(equalTo: terminal.topAnchor, constant: Layout.terminalInsetY),
                outputLbl.leadingAnchor.constraint(equalTo: terminal.leadingAnchor, constant: Layout.terminalInsetX),
                outputLbl.trailingAnchor.constraint(equalTo: terminal.trailingAnchor, constant: -Layout.terminalInsetX),
                outputLbl.bottomAnchor.constraint(equalTo: terminal.bottomAnchor, constant: -Layout.terminalInsetY),
                outputHeight,

                bottomAnchor.constraint(equalTo: lastAnchor, constant: Layout.verticalPadding)
            ])
        }

        /// The terminal's text: what the agent last said, or a placeholder for a
        /// session that hasn't said anything yet.
        ///
        /// The agent writes markdown, and the label showed its syntax verbatim —
        /// `**Shipped.**`, backticked hashes, list dashes — so the output read as
        /// noise. The markdown is parsed to its text, one space between blocks (the
        /// parser itself drops block boundaries, which glued a heading to the
        /// paragraph under it), and whitespace collapsed so blank lines and list
        /// breaks don't spend the terminal's four lines. Show Info keeps the raw text.
        static func outputText(for session: SessionWatcherSession) -> String {
            guard !session.lastOutput.isEmpty else { return "No output yet." }
            return plainText(fromMarkdown: session.lastOutput)
        }

        /// `markdown` as one line of plain text. A message the parser rejects is shown
        /// as written, whitespace collapsed.
        static func plainText(fromMarkdown markdown: String) -> String {
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
            guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
                return collapsingWhitespace(markdown)
            }
            var blocks: [String] = []
            var current = ""
            var currentIntent: PresentationIntent?
            for run in parsed.runs {
                if run.presentationIntent != currentIntent, !current.isEmpty {
                    blocks.append(current)
                    current = ""
                }
                currentIntent = run.presentationIntent
                current += String(parsed[run.range].characters)
            }
            blocks.append(current)
            return collapsingWhitespace(blocks.joined(separator: " "))
        }

        private static func collapsingWhitespace(_ text: String) -> String {
            text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }

        /// The summary's text. This used to read "thinking..." for every session without a
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

        /// Everything the row can't show — ids, paths, model, timing. Used
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
