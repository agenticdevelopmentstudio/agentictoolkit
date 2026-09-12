import AppKit
import Combine
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// A chat view with transcript, message bubbles, typing indicator, and input field.
public final class ChatView: NSView, NSTextFieldDelegate {
    private let viewModel: AIChatViewModel
    private var cancellables = Set<AnyCancellable>()

    private let transcriptScroll = NSScrollView()
    private let transcriptStack = NSStackView()
    private let inputField = NSTextField()
    private let sendButton = NSButton()
    private var isAtBottom = true

    /// The transcript width the bubbles were last laid out for. Bubbles bake in a
    /// fixed width at build time (their text is pre-measured), so we rebuild them
    /// when the width changes — see `layout()` — to keep them proportional on resize.
    private var lastTranscriptWidth: CGFloat = 0

    /// Bubbles cap at this fraction of the transcript width, so they read as chat
    /// bubbles and grow/shrink with the window rather than spanning it.
    private static let maxBubbleWidthFraction: CGFloat = 0.75

    /// Whether the composer accepts input at all.
    ///
    /// A transcript that is being *watched* rather than talked to (a feed, a
    /// log, a replay) sets this false: the composer stays in the window, greyed,
    /// because removing it would make the view a different shape depending on
    /// what it is showing — and because a chat with nowhere to type reads as
    /// broken, while a chat with a disabled composer reads as read-only.
    public var isComposerEnabled = true {
        didSet { applyComposerEnablement() }
    }

    /// Called when a transcript row is clicked. Only rows that carry a
    /// ``ChatMessage/attribution`` are clickable — in a merged transcript a row
    /// came from somewhere, and going there is the obvious thing to want.
    public var onRowTap: ((ChatMessage) -> Void)?

    public init(viewModel: AIChatViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        setupViews()
        bindViewModel()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func setupViews() {
        transcriptStack.orientation = .vertical
        transcriptStack.spacing = 12
        transcriptStack.alignment = .leading
        transcriptStack.edgeInsets = NSEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        transcriptStack.translatesAutoresizingMaskIntoConstraints = false

        transcriptScroll.documentView = transcriptStack
        transcriptScroll.hasVerticalScroller = true
        transcriptScroll.automaticallyAdjustsContentInsets = false
        transcriptScroll.drawsBackground = false
        transcriptScroll.translatesAutoresizingMaskIntoConstraints = false

        transcriptScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(transcriptDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: transcriptScroll.contentView
        )

        let divider = ThemedSeparatorView(role: .divider)
        divider.translatesAutoresizingMaskIntoConstraints = false

        inputField.observeTheme { field, palette in
            field.font = palette.font(.body)
            field.textColor = palette.nsColor(.primaryText)
            field.placeholderAttributedString = NSAttributedString(
                string: "Type a message...",
                attributes: [
                    .font: palette.font(.body),
                    .foregroundColor: palette.nsColor(.placeholderText)
                ]
            )
        }
        inputField.isBordered = false
        inputField.focusRingType = .none
        inputField.drawsBackground = false
        inputField.delegate = self
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.accessibilityID("ai-chat.input")

        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Send")
        sendButton.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        sendButton.isBordered = false
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.accessibilityID("ai-chat.send-button")
        sendButton.observeTheme { [weak self] _, palette in
            self?.applySendButtonTint(palette)
        }

        observeTheme { view, palette in
            view.wantsLayer = true
            view.layer?.backgroundColor = palette.nsColor(.chatSurface).cgColor
        }

        let inputRow = NSStackView(views: [inputField, sendButton])
        inputRow.orientation = .horizontal
        inputRow.spacing = 10
        inputRow.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        inputRow.translatesAutoresizingMaskIntoConstraints = false

        let topAnchorView: NSView = self

        addSubview(transcriptScroll)
        addSubview(divider)
        addSubview(inputRow)

        NSLayoutConstraint.activate([
            transcriptScroll.topAnchor.constraint(equalTo: topAnchorView.topAnchor),
            transcriptScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            transcriptScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            transcriptScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            transcriptStack.widthAnchor.constraint(equalTo: transcriptScroll.widthAnchor),
            divider.topAnchor.constraint(equalTo: transcriptScroll.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputRow.topAnchor.constraint(equalTo: divider.bottomAnchor),
            inputRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputRow.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Rebuild the transcript when the transcript width changes (window resize),
    /// so the pre-measured bubbles reflow to the new proportional width. Guarded on
    /// a width delta so the rebuild's own relayout doesn't recurse.
    public override func layout() {
        super.layout()
        let width = transcriptScroll.contentView.bounds.width
        if width > 0, abs(width - lastTranscriptWidth) > 1 {
            lastTranscriptWidth = width
            rebuildTranscript()
        }
    }

    /// Makes the input field the window's first responder. Returns `false` when the
    /// view is not in a window yet, or the window declined the change.
    @discardableResult
    public func focusInput() -> Bool {
        window?.makeFirstResponder(inputField) ?? false
    }

    private func bindViewModel() {
        viewModel.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRender() }
            .store(in: &cancellables)

        viewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRender() }
            .store(in: &cancellables)
    }

    /// Coalesce high-frequency delta updates into one rebuild per runloop tick.
    private var renderScheduled = false
    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderScheduled = false
            self.rebuildTranscript()
        }
    }

    // MARK: - Transcript

    private func rebuildTranscript() {
        transcriptStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let scrollWidth = transcriptScroll.contentView.bounds.width
        let maxBubbleWidth = max(scrollWidth * Self.maxBubbleWidthFraction, 200)

        let topSpacer = NSView()
        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        topSpacer.setContentHuggingPriority(.init(1), for: .vertical)
        topSpacer.setContentCompressionResistancePriority(.init(1), for: .vertical)
        transcriptStack.addArrangedSubview(topSpacer)

        for message in viewModel.messages {
            // A message that names its own speaker gets the fuller row: icon,
            // header line, timestamp underneath. Only a merged transcript
            // produces those, so an ordinary chat is untouched by this.
            if message.attribution != nil {
                let row = ChatTranscriptRowView(
                    message: message, maxBubbleWidth: maxBubbleWidth, onTap: onRowTap)
                transcriptStack.addArrangedSubview(row)
                row.widthAnchor.constraint(
                    equalTo: transcriptStack.widthAnchor, constant: -32).isActive = true
                continue
            }

            let bubble = AIChatBubbleView(message: message, maxWidth: maxBubbleWidth)
            bubble.setContentHuggingPriority(.required, for: .horizontal)

            if message.role == .user {
                let spacer = NSView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
                let hStack = NSStackView(views: [spacer, bubble])
                hStack.orientation = .horizontal
                hStack.alignment = .top
                hStack.spacing = 0
                transcriptStack.addArrangedSubview(hStack)
                hStack.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor, constant: -32).isActive = true
            } else if message.role == .notice {
                // Center status lines (e.g. "Model changed to …") between the two
                // conversational columns.
                let leading = NSView()
                let trailing = NSView()
                for spacer in [leading, trailing] {
                    spacer.translatesAutoresizingMaskIntoConstraints = false
                    spacer.setContentHuggingPriority(.init(1), for: .horizontal)
                }
                let hStack = NSStackView(views: [leading, bubble, trailing])
                hStack.orientation = .horizontal
                hStack.alignment = .top
                hStack.spacing = 0
                leading.widthAnchor.constraint(equalTo: trailing.widthAnchor).isActive = true
                transcriptStack.addArrangedSubview(hStack)
                hStack.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor, constant: -32).isActive = true
            } else {
                transcriptStack.addArrangedSubview(bubble)
            }
        }

        let responding = viewModel.state == .responding
        if responding {
            let indicator = TypingIndicatorView()
            transcriptStack.addArrangedSubview(indicator)
            indicator.startAnimating()
        }

        applyComposerEnablement()

        if isAtBottom {
            DispatchQueue.main.async { [weak self] in self?.scrollToBottom() }
        }
    }

    /// Disabled while a turn is in flight, so rapid sends can't overlap turns —
    /// and disabled outright when the transcript is read-only.
    private func applyComposerEnablement() {
        let enabled = isComposerEnabled && viewModel.state != .responding
        inputField.isEnabled = enabled
        sendButton.isEnabled = enabled
        applySendButtonTint(resolvedThemeScope.palette)
    }

    /// No tint at all when the composer is off, rather than a dimmer one: AppKit
    /// draws a template image at the full strength of whatever
    /// `contentTintColor` names, disabled or not, so an accent-tinted arrow over
    /// a dead text field reads as a chat you can still send into. Handing the
    /// tint back to AppKit is what restores the greyed-out look.
    private func applySendButtonTint(_ palette: SemanticPalette) {
        sendButton.contentTintColor = sendButton.isEnabled ? palette.nsColor(.accent) : nil
    }

    // MARK: - Scroll

    @objc private func transcriptDidScroll() {
        guard let docView = transcriptScroll.documentView else { return }
        let clip = transcriptScroll.contentView
        let visibleBottom = clip.bounds.origin.y + clip.bounds.height
        let contentHeight = docView.bounds.height
        isAtBottom = contentHeight - visibleBottom < 30
    }

    private func scrollToBottom() {
        guard let docView = transcriptScroll.documentView else { return }
        let maxScroll = max(docView.bounds.height - transcriptScroll.contentView.bounds.height, 0)
        transcriptScroll.contentView.scroll(to: NSPoint(x: 0, y: maxScroll))
        transcriptScroll.reflectScrolledClipView(transcriptScroll.contentView)
    }

    // MARK: - Input

    @objc private func sendTapped() {
        let text = inputField.stringValue
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.sendMessage(text)
        inputField.stringValue = ""
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            sendTapped()
            return true
        }
        return false
    }
}
