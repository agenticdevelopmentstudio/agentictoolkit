import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// "Terminal" topic: the terminal palette (foreground / background / cursor /
/// selection plus the 16 ANSI colors) and this theme's optional overrides of
/// every option on the Terminal settings panel.
///
/// The overrides are all `Optional` and start out `nil` — a theme carries no
/// terminal options until you set one. So the controls below show the
/// **resolved** value (this theme's override if it has one, otherwise the
/// Terminal settings panel's), and touching a control is what records the
/// override. "Use Terminal Settings" clears them all again.
@MainActor
final class ThemeTerminalTopicPanel: ThemeTopicPanel {

    /// Padding label width, matching the Terminal settings panel so the two
    /// read as the same control in two places.
    private static let paddingLabelWidth: CGFloat = 60

    private enum Side: Int, CaseIterable {
        case top, leading, bottom, trailing

        var label: String {
            switch self {
            case .top: return "Top"
            case .leading: return "Left"
            case .bottom: return "Bottom"
            case .trailing: return "Right"
            }
        }
    }

    private var paddingFields: [Side: NSTextField] = [:]
    private var paddingSteppers: [Side: NSStepper] = [:]
    private let fontButton = ComposableSettings.FontChooserButton(width: 200)
    private let fontSizeField = NSTextField()
    private let shapePopup = NSPopUpButton()
    private let blinkCheckbox = NSButton(checkboxWithTitle: "Blink", target: nil, action: nil)
    private let clearButton = NSButton(title: "Use Terminal Settings", target: nil, action: nil)

    init(context: ThemeEditorContext) {
        super.init(context: context, title: "Terminal", symbol: "terminal")
    }

    override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Theme Options Override the Defaults",
                body: "Everything under Layout, Font and Cursor here overrides the matching "
                    + "option on the Terminal settings panel whenever this theme is active. "
                    + "A theme starts with none of them set, so until you change something "
                    + "the Terminal panel is what decides — which is why the fields open "
                    + "showing its values."
            ),
            .init(
                title: "Going Back to the Defaults",
                body: "\"Use Terminal Settings\" drops every terminal override this theme "
                    + "has, in one go, and the fields fall back to showing the Terminal "
                    + "panel's values again. There is no way to override one side of the "
                    + "padding and inherit the other three — set one and all four are the "
                    + "theme's."
            ),
            .init(
                title: "Palette",
                body: "Foreground, background, cursor and selection, then the 16 ANSI "
                    + "colors: 0–7 on the first row (black, red, green, yellow, blue, "
                    + "magenta, cyan, white) and their bright counterparts, 8–15, on the "
                    + "second. Unlike the options above, these are always the theme's — a "
                    + "terminal palette is what a theme is for."
            )
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addGroup(makePaletteGroup())
        addGroup(makeLayoutGroup())
        addGroup(makeFontGroup())
        addGroup(makeCursorGroup())
        addGroup(makeOverridesGroup())
    }

    // MARK: - Palette

    private func makePaletteGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Palette")
        let theme = context.theme

        let baseRow = row([
            wellColumn("FG", .foreground, theme.foreground),
            wellColumn("BG", .background, theme.background),
            wellColumn("Cursor", .cursor, theme.cursor),
            wellColumn("Sel", .selection, theme.selection)
        ])

        let ansi = column([], spacing: 6)
        for half in 0..<2 {
            let wells = (0..<8).compactMap { offset -> NSView? in
                let index = half * 8 + offset
                guard theme.ansi.indices.contains(index) else { return nil }
                return ansiWell(index, theme.ansi[index])
            }
            ansi.addArrangedSubview(row(wells, spacing: 6))
        }

        group.addSettingSubview(column([baseRow, ansi], spacing: 8))
        return group
    }

    // MARK: - Overridable options

    private func makeLayoutGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Padding")
        let padding = TerminalAppearance.resolvedPadding(theme: context.theme)
        let values: [Side: CGFloat] = [
            .top: padding.top, .leading: padding.leading,
            .bottom: padding.bottom, .trailing: padding.trailing
        ]

        // A column, not a row: the four numbers are the four sides of one box,
        // and stacked with right-aligned labels they read as the box.
        let stack = column([], spacing: 6)
        for side in Side.allCases {
            let field = NSTextField()
            field.integerValue = Int(values[side] ?? 0)
            field.tag = side.rawValue
            field.target = self
            field.action = #selector(paddingChanged(_:))
            field.isEditable = context.isEditable
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 52).isActive = true
            paddingFields[side] = field

            let stepper = NSStepper()
            stepper.minValue = 0
            stepper.maxValue = 80
            stepper.increment = 1
            stepper.integerValue = field.integerValue
            stepper.tag = side.rawValue
            stepper.target = self
            stepper.action = #selector(paddingStepperChanged(_:))
            stepper.isEnabled = context.isEditable
            paddingSteppers[side] = stepper

            stack.addArrangedSubview(
                row([rightLabel(side.label, width: Self.paddingLabelWidth), field, stepper], spacing: 6))
        }
        group.addSettingSubview(stack)
        return group
    }

    private func makeFontGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Font")
        let font = TerminalAppearance.resolvedFont(theme: context.theme)

        fontButton.isEnabled = context.isEditable
        fontButton.onChange = { [weak self] picked in self?.fontPicked(picked) }
        fontButton.accessibilityID("theme.terminal.font")
        showFont(font)

        fontSizeField.doubleValue = Double(font.pointSize)
        fontSizeField.target = self
        fontSizeField.action = #selector(fontChanged(_:))
        fontSizeField.isEditable = context.isEditable
        fontSizeField.translatesAutoresizingMaskIntoConstraints = false
        fontSizeField.widthAnchor.constraint(equalToConstant: 52).isActive = true

        group.addSettingSubview(row([
            rightLabel("Face", width: Self.paddingLabelWidth), fontButton,
            rightLabel("Size"), fontSizeField
        ], spacing: 6))
        return group
    }

    /// The terminal keeps a PostScript name, not a family: telling
    /// `FiraCodeNF-Regular` from `FiraCodeNFP-Regular` is the whole reason a
    /// terminal font is chosen by eye, and a family name cannot.
    private func showFont(_ font: NSFont) {
        fontButton.show(font, title: font.displayName ?? font.fontName)
    }

    private func makeCursorGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Cursor")
        let cursor = TerminalAppearance.resolvedCursor(theme: context.theme)

        for shape in TerminalCursorShape.allCases {
            shapePopup.addItem(withTitle: shape.label)
            shapePopup.lastItem?.representedObject = shape
        }
        if let index = TerminalCursorShape.allCases.firstIndex(of: cursor.shape) {
            shapePopup.selectItem(at: index)
        }
        shapePopup.target = self
        shapePopup.action = #selector(cursorChanged(_:))
        shapePopup.isEnabled = context.isEditable

        blinkCheckbox.state = cursor.blinks ? .on : .off
        blinkCheckbox.target = self
        blinkCheckbox.action = #selector(cursorChanged(_:))
        blinkCheckbox.isEnabled = context.isEditable

        group.addSettingSubview(row([rightLabel("Shape", width: Self.paddingLabelWidth), shapePopup], spacing: 6))
        group.addSettingSubview(blinkCheckbox)
        return group
    }

    private func makeOverridesGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Defaults")
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearOverrides(_:))
        group.addSettingSubview(clearButton)
        refreshClearButton()
        return group
    }

    // MARK: - Edits

    @objc private func paddingStepperChanged(_ sender: NSStepper) {
        guard let side = Side(rawValue: sender.tag) else { return }
        paddingFields[side]?.integerValue = sender.integerValue
        applyPadding()
    }

    @objc private func paddingChanged(_ sender: NSTextField) {
        guard let side = Side(rawValue: sender.tag) else { return }
        let clamped = max(0, min(80, sender.integerValue))
        sender.integerValue = clamped
        paddingSteppers[side]?.integerValue = clamped
        applyPadding()
    }

    private func applyPadding() {
        context.update { theme in
            theme.terminal = (theme.terminal ?? ThemeTerminalOptions()).with {
                $0.paddingTop = self.paddingFields[.top]?.integerValue
                $0.paddingLeading = self.paddingFields[.leading]?.integerValue
                $0.paddingBottom = self.paddingFields[.bottom]?.integerValue
                $0.paddingTrailing = self.paddingFields[.trailing]?.integerValue
            }
        }
        refreshClearButton()
    }

    /// The panel picks a face *and* a size, so a pick fills in the Size field
    /// beside it rather than leaving the two disagreeing.
    private func fontPicked(_ font: NSFont) {
        fontSizeField.doubleValue = Double(font.pointSize)
        applyFont(name: font.fontName)
    }

    @objc private func fontChanged(_ sender: NSControl) {
        applyFont(name: TerminalAppearance.resolvedFont(theme: context.theme).fontName)
    }

    private func applyFont(name: String) {
        let size = max(6, min(72, fontSizeField.doubleValue))
        fontSizeField.doubleValue = size
        context.update { theme in
            theme.terminal = (theme.terminal ?? ThemeTerminalOptions()).with {
                $0.fontName = name.isEmpty ? nil : name
                $0.fontSize = size
            }
        }
        // From the theme, not from what was asked for: a locked theme refuses
        // the edit outright and the button has to keep showing what is stored.
        showFont(TerminalAppearance.resolvedFont(theme: context.theme))
        refreshClearButton()
    }

    @objc private func cursorChanged(_ sender: NSControl) {
        let shape = shapePopup.selectedItem?.representedObject as? TerminalCursorShape
        context.update { theme in
            theme.terminal = (theme.terminal ?? ThemeTerminalOptions()).with {
                $0.cursorShape = shape
                $0.cursorBlinks = self.blinkCheckbox.state == .on
            }
        }
        refreshClearButton()
    }

    @objc private func clearOverrides(_ sender: NSButton) {
        context.update { $0.terminal = nil }
        // Back to inheriting, so the fields have to re-read the Terminal panel's
        // values — they were showing this theme's until a moment ago.
        let padding = TerminalAppearance.resolvedPadding(theme: context.theme)
        let values: [Side: CGFloat] = [
            .top: padding.top, .leading: padding.leading,
            .bottom: padding.bottom, .trailing: padding.trailing
        ]
        for side in Side.allCases {
            paddingFields[side]?.integerValue = Int(values[side] ?? 0)
            paddingSteppers[side]?.integerValue = Int(values[side] ?? 0)
        }
        let font = TerminalAppearance.resolvedFont(theme: context.theme)
        showFont(font)
        fontSizeField.doubleValue = Double(font.pointSize)
        let cursor = TerminalAppearance.resolvedCursor(theme: context.theme)
        if let index = TerminalCursorShape.allCases.firstIndex(of: cursor.shape) {
            shapePopup.selectItem(at: index)
        }
        blinkCheckbox.state = cursor.blinks ? .on : .off
        refreshClearButton()
    }

    /// Only offer "back to the defaults" when there is something to go back
    /// from — an always-enabled button that does nothing is a worse answer than
    /// a disabled one that says why.
    private func refreshClearButton() {
        clearButton.isEnabled = context.isEditable && !(context.theme.terminal?.isEmpty ?? true)
    }
}
