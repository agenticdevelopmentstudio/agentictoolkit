import AppKit
import KeyboardShortcuts
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// One command's settings row:
/// `[title] … [click-to-record field] [✓ | ✗] [on/off]`, with the
/// available/unavailable readout appearing underneath while an edit is pending.
///
/// The row — not the field — owns the edit. A captured chord is pending until
/// the user commits it, and focus can leave in the middle of that (they click
/// the checkmark, after all), so the state that decides whether ✓ and ✗ are on
/// screen cannot live in the thing that loses focus.
@MainActor
public final class KeyCommandRowView: NSView {

    private let registry: KeyCommandRegistry
    private let command: KeyCommandDescriptor

    private let titleLabel: ThemedLabel
    private let captureField = KeyCommandCaptureField()
    private let confirmCancel = ConfirmCancelControl()
    private let toggle = NSSwitch()
    private let statusLabel: ThemedLabel
    private let readoutRow: NSStackView

    /// The chord captured but not committed, and the reason the ✓/✗ pair and
    /// the readout are on screen at all.
    private var pendingShortcut: KeyboardShortcuts.Shortcut?

    private var isEditing = false {
        didSet {
            guard isEditing != oldValue else { return }
            if isEditing { refusal = nil }
            confirmCancel.isHidden = !isEditing
            updateReadoutVisibility()
        }
    }

    /// Why the switch was just refused, shown in the readout until the next
    /// edit. The switch snapping back by itself would otherwise read as a
    /// control that is broken rather than one that said no.
    private var refusal: String? {
        didSet { updateReadoutVisibility() }
    }

    private var bindingsObserver: NSObjectProtocol?

    public init(command: KeyCommandDescriptor, registry: KeyCommandRegistry) {
        self.registry = registry
        self.command = command
        self.titleLabel = ComposableSettings.makeRowLabel("\(command.title):")
        self.statusLabel = ComposableSettings.makeValueLabel()
        self.readoutRow = NSView.makeRow([ComposableSettings.makeValueLabel(), statusLabel])

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        toggle.target = self
        toggle.action = #selector(toggleChanged)
        toggle.setAccessibilityTitleUIElement(titleLabel)

        captureField.accessibilityID("settings.key-commands.\(command.id).recorder")
        toggle.accessibilityID("settings.key-commands.\(command.id).enabled")

        let mainRow = NSView.makeRow([titleLabel, captureField, confirmCancel, toggle])

        let stack = NSStackView(views: [mainRow, readoutRow])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        Self.pinToEdges(stack, of: self)

        confirmCancel.isHidden = true
        readoutRow.isHidden = true

        wireUp()
        refresh()

        // Another row taking a chord changes what this one may have.
        bindingsObserver = NotificationCenter.default.addObserver(
            forName: KeyCommandRegistry.bindingsDidChangeNotification,
            object: registry, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    isolated deinit {
        if let bindingsObserver {
            NotificationCenter.default.removeObserver(bindingsObserver)
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Wiring

    private func wireUp() {
        captureField.onCapture = { [weak self] shortcut in
            guard let self else { return }
            self.pendingShortcut = shortcut
            self.captureField.pendingShortcut = shortcut
            self.isEditing = true
            self.refreshAvailability()
        }

        captureField.onCancel = { [weak self] in self?.cancelEdit() }
        captureField.onCommit = { [weak self] in self?.commitEdit() }

        captureField.onRecordingChanged = { [weak self] isRecording in
            guard let self else { return }
            self.registry.isRecordingChord = isRecording
            if isRecording {
                self.isEditing = true
                self.refreshAvailability()
            } else if self.pendingShortcut == nil {
                // Clicked in and straight back out without pressing anything:
                // there is nothing to confirm, so the pair should not linger.
                self.isEditing = false
            }
        }

        confirmCancel.onConfirm = { [weak self] in self?.commitEdit() }
        confirmCancel.onCancel = { [weak self] in self?.cancelEdit() }
    }

    // MARK: - Editing

    private func commitEdit() {
        guard let shortcut = pendingShortcut else { return }
        guard registry.availability(of: shortcut, for: command.id).isAvailable else {
            // Taken since it was pressed — by another row, or a menu. Say so
            // rather than letting ✓ do nothing.
            refreshAvailability()
            return
        }

        let current = registry.binding(for: command.id)
        // Recording a chord is unambiguous intent to use it, so the command
        // comes on — unless the user themselves switched it off, in which case
        // the switch stays where they put it. A shipped "off" is not the user's
        // choice: the suggested global chords ship off, and recording over one
        // must not save a chord that silently never fires.
        let isEnabled = registry.hasAuthoredBinding(for: command.id) && current.shortcut != nil
            ? current.isEnabled
            : true

        registry.setBinding(
            KeyCommandBinding(shortcut: shortcut, isEnabled: isEnabled),
            for: command.id)

        endEdit()
        refresh()
    }

    private func cancelEdit() {
        endEdit()
        refresh()
    }

    private func endEdit() {
        pendingShortcut = nil
        captureField.pendingShortcut = nil
        captureField.endRecording()
        isEditing = false
    }

    @objc private func toggleChanged() {
        let current = registry.binding(for: command.id)
        let isOn = toggle.state == .on
        // Switching on puts the chord back in play, so it has to be free: a
        // chord two commands hold fires both, and switching either off then
        // unregisters the hotkey the other still relies on.
        if isOn, case .unavailable(let reason) = registry.availability(of: current.shortcut, for: command.id) {
            toggle.state = .off
            refusal = "can’t switch on — \(reason)"
            refreshAvailability()
            return
        }
        refusal = nil
        registry.setBinding(
            KeyCommandBinding(shortcut: current.shortcut, isEnabled: isOn),
            for: command.id)
        refresh()
    }

    // MARK: - Display

    /// Pull the row back into line with what the registry holds.
    public func refresh() {
        let binding = registry.binding(for: command.id)
        captureField.displayedShortcut = binding.shortcut
        captureField.placeholder = binding.shortcut == nil ? "Click to record" : ""
        toggle.state = binding.isEnabled ? .on : .off
        // Nothing to switch on when no chord has been recorded — which is how
        // the windows listed without a key command read.
        toggle.isEnabled = binding.shortcut != nil
        refreshAvailability()
    }

    private func updateReadoutVisibility() {
        readoutRow.isHidden = !isEditing && refusal == nil
    }

    private func refreshAvailability() {
        let availability = registry.availability(of: pendingShortcut, for: command.id)
        confirmCancel.isConfirmEnabled = availability.isAvailable

        if let refusal, !isEditing {
            statusLabel.stringValue = refusal
            statusLabel.role = .danger
            return
        }

        if let reason = availability.reason, pendingShortcut != nil {
            statusLabel.stringValue = "\(availability.label) — \(reason)"
        } else if pendingShortcut == nil {
            statusLabel.stringValue = "press a key combination"
        } else {
            statusLabel.stringValue = availability.label
        }

        // The colour is the role, not a painted `textColor`: `ThemedLabel`
        // repaints itself from its role on every theme change, so setting a
        // colour here would be undone the next time the palette moved.
        statusLabel.role = pendingShortcut == nil
            ? .secondaryText
            : (availability.isAvailable ? .success : .danger)
    }
}
