import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// "Typography" topic: the overall size scale, plus font / size / weight for
/// each text role.
@MainActor
final class ThemeTypographyTopicPanel: ThemeTopicPanel {

    /// Width of the font button, so every role's sample starts and ends in the
    /// same place however long its name is.
    private static let fontButtonWidth: CGFloat = 150

    private var sizeFields: [TextRole: NSTextField] = [:]
    private var sizeSteppers: [TextRole: NSStepper] = [:]
    private var weightPopups: [TextRole: NSPopUpButton] = [:]
    private var fontButtons: [TextRole: ComposableSettings.FontChooserButton] = [:]
    private var resetButtons: [TextRole: NSButton] = [:]
    private let scaleLabel = NSTextField(labelWithString: "100%")

    init(context: ThemeEditorContext) {
        super.init(context: context, title: "Typography", symbol: "textformat")
    }

    override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Text Size",
                body: "One multiplier over every size below, so a theme can be made larger "
                    + "or smaller as a whole without re-typing eight numbers and losing the "
                    + "relationships between them. It stacks with the app-wide text size in "
                    + "Appearance settings."
            ),
            .init(
                title: "Roles",
                body: "Each row is a role the app draws text in — title, body, caption, "
                    + "button, code, and so on — not a particular label. A role showing "
                    + "\"System\" uses the system font, which is the right answer for most "
                    + "roles; roles that are monospaced by nature stay monospaced whatever "
                    + "you pick."
            ),
            .init(
                title: "Fonts",
                body: "Click a role's font to open the system font panel and pick a face by "
                    + "eye. Picking one sets the family, the size and the weight together, "
                    + "so the three columns always agree with the sample beside them. The "
                    + "arrow next to a font puts that role back on the system font."
            ),
            .init(
                title: "Sizes",
                body: "Sizes are in points and clamped to 8–48. A value outside that range "
                    + "snaps to the nearest end as you commit it, so the field always shows "
                    + "what is actually being drawn."
            )
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let group = ComposableSettings.GroupView(withTitle: "Typography")
        group.addSettingSubview(makeScaleRow())
        group.addSettingSubview(makeRolesGrid())
        addGroup(group)
    }

    private func makeScaleRow() -> NSView {
        let scale = NSSlider(value: context.theme.typography.sizeScale, minValue: 0.8, maxValue: 1.6,
                             target: self, action: #selector(scaleChanged(_:)))
        scale.isEnabled = context.isEditable
        scale.translatesAutoresizingMaskIntoConstraints = false
        scale.widthAnchor.constraint(equalToConstant: 160).isActive = true
        scaleLabel.stringValue = "\(Int((context.theme.typography.sizeScale * 100).rounded()))%"
        return row([captionLabel("Text size", 64), scale, scaleLabel])
    }

    private func makeRolesGrid() -> NSView {
        let grid = NSGridView()
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.addRow(with: [captionLabel("", 60), captionLabel("Size", 76),
                           captionLabel("Weight", 110), captionLabel("Font", 176)])
        for role in TextRole.allCases {
            grid.addRow(with: typographyCells(role))
        }
        grid.column(at: 0).xPlacement = .leading
        return grid
    }

    private func typographyCells(_ role: TextRole) -> [NSView] {
        let editable = context.isEditable
        let style = context.theme.typography.style(role)
        let roleID = NSUserInterfaceItemIdentifier(role.rawValue)

        let sizeField = NSTextField()
        sizeField.doubleValue = style.size
        sizeField.identifier = roleID
        sizeField.target = self
        sizeField.action = #selector(typographyChanged(_:))
        sizeField.isEditable = editable
        sizeField.translatesAutoresizingMaskIntoConstraints = false
        sizeField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        sizeFields[role] = sizeField

        let stepper = NSStepper()
        stepper.minValue = 8
        stepper.maxValue = 48
        stepper.increment = 1
        stepper.doubleValue = style.size
        stepper.identifier = roleID
        stepper.target = self
        stepper.action = #selector(sizeStepperChanged(_:))
        stepper.isEnabled = editable
        sizeSteppers[role] = stepper

        let weightPopup = NSPopUpButton()
        for weight in FontWeight.allCases {
            weightPopup.addItem(withTitle: weight.rawValue.capitalized)
            weightPopup.lastItem?.representedObject = weight
        }
        weightPopup.identifier = roleID
        weightPopup.target = self
        weightPopup.action = #selector(typographyChanged(_:))
        weightPopup.isEnabled = editable
        if let index = FontWeight.allCases.firstIndex(of: style.weight) {
            weightPopup.selectItem(at: index)
        }
        weightPopups[role] = weightPopup

        let fontButton = ComposableSettings.FontChooserButton(width: Self.fontButtonWidth)
        fontButton.isEnabled = editable
        fontButton.onChange = { [weak self] font in self?.fontPicked(font, for: role) }
        fontButton.accessibilityID("theme.typography.font.\(role.rawValue)")
        fontButtons[role] = fontButton

        let reset = NSButton()
        reset.image = NSImage(systemSymbolName: "arrow.uturn.backward",
                              accessibilityDescription: "Use the system font")
        reset.imagePosition = .imageOnly
        reset.isBordered = false
        reset.toolTip = "Use the system font"
        reset.identifier = roleID
        reset.target = self
        reset.action = #selector(resetFont(_:))
        reset.accessibilityID("theme.typography.font-reset.\(role.rawValue)")
        resetButtons[role] = reset

        let fontCell = row([fontButton, reset], spacing: 4)
        refreshFontRow(role)

        return [NSTextField(labelWithString: role.rawValue.capitalized),
                row([sizeField, stepper], spacing: 2), weightPopup, fontCell]
    }

    // MARK: - Edits

    @objc private func scaleChanged(_ sender: NSSlider) {
        scaleLabel.stringValue = "\(Int((sender.doubleValue * 100).rounded()))%"
        context.update { $0.typography.sizeScale = sender.doubleValue }
    }

    @objc private func sizeStepperChanged(_ sender: NSStepper) {
        guard let raw = sender.identifier?.rawValue, let role = TextRole(rawValue: raw) else { return }
        sizeFields[role]?.doubleValue = sender.doubleValue
        applyTypography(for: role, family: context.theme.typography.style(role).family)
    }

    @objc private func typographyChanged(_ sender: NSControl) {
        guard let raw = sender.identifier?.rawValue, let role = TextRole(rawValue: raw) else { return }
        if let field = sizeFields[role] { sizeSteppers[role]?.doubleValue = field.doubleValue }
        applyTypography(for: role, family: context.theme.typography.style(role).family)
    }

    /// The font panel hands back a whole face — "Avenir Next Demi Bold" at 15 pt
    /// — while the theme stores a family, a size and a weight separately. So all
    /// three columns move together: a picker that set the family and left Weight
    /// reading "Regular" beside a visibly bold sample would be lying about what
    /// is stored (`principle-of-least-astonishment`).
    private func fontPicked(_ font: NSFont, for role: TextRole) {
        sizeFields[role]?.doubleValue = Double(font.pointSize)
        sizeSteppers[role]?.doubleValue = Double(font.pointSize)
        if let index = FontWeight.allCases.firstIndex(of: Self.weight(of: font)) {
            weightPopups[role]?.selectItem(at: index)
        }
        applyTypography(for: role, family: font.familyName ?? font.fontName)
    }

    @objc private func resetFont(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let role = TextRole(rawValue: raw) else { return }
        applyTypography(for: role, family: nil)
    }

    private func applyTypography(for role: TextRole, family: String?) {
        let size = max(8, min(48, sizeFields[role]?.doubleValue ?? ThemeTypography.defaultStyle(role).size))
        // Reflect the clamp back so the field/stepper show what's actually applied
        // (typing "100" lands on 48, not a stale out-of-range "100").
        sizeFields[role]?.doubleValue = size
        sizeSteppers[role]?.doubleValue = size
        let weight = (weightPopups[role]?.selectedItem?.representedObject as? FontWeight) ?? .regular
        let isMono = ThemeTypography.defaultStyle(role).monospaced
        context.update {
            $0.typography.styles[role.rawValue] = FontStyle(
                family: family, size: size, weight: weight, monospaced: isMono)
        }
        // From the context, not from `family`: a locked theme refuses the edit
        // outright, and the button has to keep showing what is really stored.
        refreshFontRow(role)
    }

    /// Redraw a role's font button from what the theme now holds, and show the
    /// reset arrow only when there is a family to reset — an always-visible
    /// button that does nothing is a worse answer than one that isn't there.
    private func refreshFontRow(_ role: TextRole) {
        let style = context.theme.typography.style(role)
        fontButtons[role]?.show(style.nsFont(scaledSize: CGFloat(style.size)),
                                title: style.family ?? "System")
        resetButtons[role]?.isHidden = style.family == nil || !context.isEditable
    }

    /// The theme weight closest to a picked face's own weight.
    ///
    /// Read off the descriptor's weight trait rather than the face's name,
    /// because the names are a free-for-all — "Demi Bold", "Book", "Oblique" —
    /// while the trait is a number every family reports on the same scale.
    private static func weight(of font: NSFont) -> FontWeight {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let picked = (traits?[.weight] as? NSNumber)?.doubleValue ?? 0
        return FontWeight.allCases.min {
            abs(Double($0.nsWeight.rawValue) - picked) < abs(Double($1.nsWeight.rawValue) - picked)
        } ?? .regular
    }
}
