import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// A multi-line editor for settings whose value is a body of text rather than
    /// a field's worth — an LLM prompt, a template, a script snippet.
    ///
    /// Unlike ``TextEditView`` (one `NSTextField`, commits on Return), the value is
    /// written back when editing *ends* — focus leaves, or the panel closes. Return
    /// inserts a newline here, so committing per keystroke or per Return would be
    /// wrong twice over: it would fight the user mid-sentence, and for settings that
    /// are pushed somewhere on change it would emit a write per character.
    @MainActor
    public class TextAreaEditView: NSView, SettingsViewProtocol, NSTextViewDelegate {

        public let label: NSTextField
        public let textView: NSTextView

        private let viewModel: ViewModel<String>

        /// The view model's ``AbstractViewModel/explanation``, which the
        /// ``GroupView`` this is placed in draws under the row.
        public var settingExplanation: String? { viewModel.explanation }
        private let scrollView = NSScrollView()
        /// Set while `commit` writes, so the setting's echo back through `onChange`
        /// isn't mistaken for an external edit.
        private var isCommitting = false

        /// - Parameters:
        ///   - viewModel: supplies the title and the backing setting.
        ///   - visibleLines: height of the editor, in lines of the editing font.
        ///     Text beyond it scrolls.
        ///   - monospaced: use a fixed-width font — right for prompts and code,
        ///     wrong for prose.
        public init(with viewModel: ViewModel<String>, visibleLines: Int = 6, monospaced: Bool = false) {
            self.viewModel = viewModel
            self.label = TextEditView.createLabel(title: viewModel.title)
            self.textView = NSTextView()

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            let palette = self.resolvedThemeScope.palette
            let font = palette.font(monospaced ? .code : .body)
            self.textView.font = font
            self.textView.string = viewModel.value
            // An `NSTextView` has no themed subclass — it is the document, not a
            // control — so it carries its own observer for the four colors that
            // otherwise stay AppKit's.
            self.textView.observeTheme { [monospaced] view, palette in
                view.font = palette.font(monospaced ? .code : .body)
                view.textColor = palette.primaryTextColor
                view.backgroundColor = palette.controlBackgroundColor
                view.insertionPointColor = palette.cursorColor
                view.selectedTextAttributes = [
                    .backgroundColor: palette.selectionColor,
                    .foregroundColor: palette.selectionTextColor
                ]
            }
            self.textView.delegate = self
            self.textView.isRichText = false
            self.textView.allowsUndo = true
            // Editing a prompt is prose typing, not code entry: the automatic
            // substitutions would silently swap quotes and dashes into text that
            // gets sent to a model verbatim.
            self.textView.isAutomaticQuoteSubstitutionEnabled = false
            self.textView.isAutomaticDashSubstitutionEnabled = false
            self.textView.isAutomaticTextReplacementEnabled = false
            self.textView.textContainerInset = NSSize(width: 4, height: 4)
            // The documented programmatic setup for a text view that grows
            // downward inside a scroll view and wraps to its width.
            self.textView.minSize = NSSize(width: 0, height: 0)
            self.textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            self.textView.isVerticallyResizable = true
            self.textView.isHorizontallyResizable = false
            self.textView.autoresizingMask = [.width]
            self.textView.textContainer?.containerSize = NSSize(
                width: 0, height: CGFloat.greatestFiniteMagnitude)
            self.textView.textContainer?.widthTracksTextView = true

            self.scrollView.translatesAutoresizingMaskIntoConstraints = false
            self.scrollView.documentView = self.textView
            self.scrollView.hasVerticalScroller = true
            self.scrollView.borderType = .bezelBorder
            self.scrollView.drawsBackground = true
            self.scrollView.observeTheme { view, palette in
                view.backgroundColor = palette.controlBackgroundColor
            }

            let stack = NSStackView(views: [self.label, self.scrollView])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = SettingsLayout.default[.rowSpacing]
            stack.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(stack)
            Self.pinToEdges(stack, of: self)

            let lineHeight = font.boundingRectForFont.height
            NSLayoutConstraint.activate([
                self.scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
                self.scrollView.heightAnchor.constraint(
                    equalToConstant: (lineHeight * CGFloat(visibleLines)).rounded() + 8)
            ])

            viewModel.onChange = { [weak self] _ in
                guard let self else { return }
                self.label.stringValue = viewModel.title
                // Our own `commit` echoes back through here; adopting it would reset
                // the caret mid-edit for no change in content.
                guard !self.isCommitting, self.textView.string != viewModel.value else { return }
                // Anything else is an external write — a "Reset to Defaults" press,
                // another window, a daemon-side reconcile — and it wins even while
                // this editor holds focus. Ignoring it left stale text on screen that
                // `commit` then wrote back, silently undoing the reset.
                self.textView.string = viewModel.value
                if self.window?.firstResponder === self.textView {
                    self.textView.setSelectedRange(NSRange(location: viewModel.value.count, length: 0))
                }
            }

            viewModel.refreshHandler = { [weak self] force in
                guard let self else { return }
                if force {
                    FieldSync.force(self.textView, viewModel.value)
                } else {
                    FieldSync.load(self.textView, viewModel.value)
                }
            }

            // The visible label isn't associated with the text view by AppKit, so
            // VoiceOver would otherwise announce an unnamed editor.
            self.textView.setAccessibilityLabel(viewModel.title)
        }

        /// The enclosing stack aligns `.leading`, so claim the full width — a text
        /// area that is only as wide as its longest line is unusable for editing.
        ///
        /// One below required: a host that insets its hosted controls (a popover
        /// pinning `width == stack.width - 32`) would otherwise have two required
        /// width constraints in conflict, and AppKit breaks whichever it likes.
        public override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            guard let parent = self.superview else { return }
            let fullWidth = self.widthAnchor.constraint(equalTo: parent.widthAnchor)
            fullWidth.priority = .required - 1
            fullWidth.isActive = true
        }

        /// Editing here only ends on focus change, so a window closing (or the app
        /// quitting) with the caret still in the editor would drop the edit entirely:
        /// `textDidEndEditing` never fires for a view that is torn down.
        public override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            NotificationCenter.default.removeObserver(
                self, name: NSWindow.willCloseNotification, object: self.window)
            NotificationCenter.default.removeObserver(
                self, name: NSApplication.willTerminateNotification, object: nil)
            if newWindow == nil { commit() }
        }

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = self.window else { return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(commitBeforeTeardown),
                name: NSWindow.willCloseNotification, object: window)
            NotificationCenter.default.addObserver(
                self, selector: #selector(commitBeforeTeardown),
                name: NSApplication.willTerminateNotification, object: nil)
        }

        @objc private func commitBeforeTeardown(_ notification: Notification) {
            commit()
        }

        public func textDidEndEditing(_ notification: Notification) {
            commit()
        }

        /// Write the editor's text to the setting. Called when editing ends; also
        /// callable by a host that has to persist before the field resigns first
        /// responder (closing a window out from under an active editor).
        public func commit() {
            let newValue = self.textView.string
            if viewModel.settingObserver.value != newValue {
                self.isCommitting = true
                viewModel.settingObserver.value = newValue
                self.isCommitting = false
            }
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame frameRect: NSRect")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

extension ComposableSettings.TextAreaEditView: ComposableSettings.ExplainedSettingsView {}
