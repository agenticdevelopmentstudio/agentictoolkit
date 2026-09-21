import AppKit

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// A picture of the thing being spaced: the arrows stand on the line they move,
/// and each number sits outside the frame, in line with the arrows that change
/// it.
///
/// Four text fields and a column of labels can say the same thing, but they
/// cannot say *which* edge is which without the reader building the picture in
/// their head. Here the diagram is the control.
///
/// The number is outside because the line belongs to the arrows. They are
/// attached to it and travel with it, and a number sharing that line pushed all
/// three along the edge and away from the middle of it. Out beyond the frame the
/// number holds still and is centred on the side it names, which is what a label
/// on an edge should do.
///
/// **Every arrow stands against the line it moves, and points the way that line
/// travels** — `->|` and `|<-`. So the arrow that adds room at an edge is the
/// one pointing *into* the view: growing the top inset is what sends the view's
/// top edge down. Reading it the other way round — an arrow pointing out of the
/// frame to add room — puts the arrow and the line it moves in opposite
/// directions, which is exactly the thing a picture is here to avoid.
///
/// Two flavors, chosen by `SpacingDiagram`, and they are the *same* control:
/// same size, same inset, same chips, same code — only the diagram inside
/// differs, so a panel showing one of each gets two pictures that line up and
/// behave alike.
/// - `.frame` — one view inside its container. Each of the four edges of the
///   view carries two arrows meeting tip to tip on the line, and a number
///   beyond the container, centred on that edge.
/// - `.paneDividers` — four panes and the two dividers between them. A divider
///   has two edges, one per pane, so it carries **four** arrows: a pair closing
///   the gap, a pair opening it, each arrow against the pane edge it moves. A
///   divider is shared by the panes either side of it, so ten points means ten
///   points of gap, not ten from each side — which is why both arrows of a pair
///   change the same number.
///
/// The control knows nothing about settings or about what it is spacing. It
/// holds a `Spacing` and reports changes; wiring that to a setting, and
/// applying it to a window, is the caller's job (`separation-of-concerns`).
@MainActor
public final class SpacingControl: NSView, NSTextFieldDelegate {

    public typealias Style = SpacingDiagram

    /// Fired when the *user* changes the value — clicking an arrow, typing a
    /// number, or pressing an arrow key in a field. Assigning `value` does not
    /// fire it, so a control bound to a setting cannot feed its own write back
    /// to itself.
    public var onChange: ((Spacing) -> Void)?

    /// The spacing shown. Setting it redraws; it does not call `onChange`.
    public var value: Spacing {
        didSet {
            guard value != oldValue else { return }
            sync()
        }
    }

    public let style: Style

    /// Whatever keeps this control's numbers in sync with wherever they are
    /// stored. Held here so `boundToSettings` can hand back one object rather
    /// than a pair the caller has to keep together.
    var retainedBinding: AnyObject?

    /// What the fields and the arrows will accept. Zero is a legitimate answer
    /// — "no gap at all" is a look — so the floor is 0, not 1.
    public let range: ClosedRange<Int>

    // MARK: - Metrics

    /// The diagram's geometry, which lives with the rules that use it.
    private typealias Metrics = SpacingControlLayout

    /// The overall size of **both** flavors. Wide enough that the two divider
    /// controls stay clear of each other: each sits in the middle of a
    /// different pane, and the room between those two middles is what this
    /// number buys. Reset needs no room of its own — it rides the row the
    /// bottom number sits on, which the chrome already allows for.
    private static let controlSize = CGSize(width: 420, height: 250)

    /// The arrows are bare glyphs in the highlight colour — no chip, no box,
    /// no weight. Four of them meet on a divider and two on every edge, and
    /// anything drawn *around* an arrow at that density stops being a button
    /// and becomes a wall along the line the arrow is pointing at. The colour
    /// is what says these are the controls; the shape says which way.
    private static let arrowSymbolPointSize: CGFloat = 12

    /// Room outside the diagram for what hangs off it — the same on both
    /// flavors, so the two draw the same rectangle in the same place.
    ///
    /// At zero spacing an arrow standing outside an edge reaches a full arrow
    /// length past the frame line, and the number and its stepper stand beyond
    /// that again. Adding those up is ``SpacingControlLayout/chrome``'s job,
    /// since it is what places them.
    private static let diagramInset = Metrics.chrome

    // MARK: - Subviews

    private enum ArrowAction {
        case edge(SpacingEdge, Int)
        case gutter(SpacingGutter, Int)
    }

    private enum FieldTarget {
        case edge(SpacingEdge)
        case gutter(SpacingGutter)
    }

    private var edgeFields: [SpacingEdge: NSTextField] = [:]
    private var gutterFields: [SpacingGutter: NSTextField] = [:]
    /// The up/down control against each number's right edge. The arrows on the
    /// diagram say *which* line moves; these say *by one*, in the place every
    /// other number field on the panel puts them.
    private var edgeSteppers: [SpacingEdge: NSStepper] = [:]
    private var gutterSteppers: [SpacingGutter: NSStepper] = [:]
    /// Sets every number this flavor edits back to zero in one press. Standing
    /// under the lower-right corner, outside the diagram, so it is plainly a
    /// command about the picture rather than a part of it.
    private var resetButton: NSButton?
    /// Per edge: the arrow that adds room and the arrow that takes it away.
    private var edgeButtons: [SpacingEdge: (more: NSButton, less: NSButton)] = [:]
    /// Per divider: the two arrows that close the gap and the two that open it,
    /// one of each standing against each of the panes either side.
    ///
    /// A single button carrying a *pair* of arrows on one glyph said the same
    /// thing in half the buttons, but it was one control touching neither edge.
    /// These touch the edges they move.
    private var gutterButtons: [SpacingGutter: GutterArrows] = [:]

    /// `near` is the pane before the divider — the left one, or the lower one;
    /// `far` is the one after it.
    private struct GutterArrows {
        let narrowerNear: NSButton
        let narrowerFar: NSButton
        let widerNear: NSButton
        let widerFar: NSButton
    }

    /// The pair of arrows that stand on one line, in a view of their own —
    /// what the user grabs to drag that line straight to where they want it.
    /// A divider has two pairs, one either side of its number, so it has two.
    private var edgeHandles: [SpacingEdge: SpacingHandle] = [:]
    private var gutterHandles: [SpacingGutter: (narrower: SpacingHandle, wider: SpacingHandle)] = [:]

    /// The value the drag in progress started from, and which way *out* was
    /// when it started. Every step of a drag is measured from these rather
    /// than added to the last one, so a rounded half point cannot accumulate
    /// into a drift over a long drag.
    private var dragOrigin = Spacing()
    private var dragOutward: CGFloat = 1

    private var arrowActions: [ObjectIdentifier: ArrowAction] = [:]
    /// Which way each arrow points — the one fact its placement and its box are
    /// both derived from, so neither can disagree with the glyph.
    private var arrowDirections: [ObjectIdentifier: SpacingArrow] = [:]
    /// Which number a field **or** a stepper edits. One map, because the two
    /// are two ways of typing the same value and every lookup wants the same
    /// answer.
    private var numberTargets: [ObjectIdentifier: FieldTarget] = [:]

    private var palette: SemanticPalette = ThemePaletteObserver.currentPalette

    // MARK: - Init

    public init(style: Style, value: Spacing = Spacing(), range: ClosedRange<Int> = 0...40) {
        self.style = style
        self.value = value
        self.range = range
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        // AppKit ignores a plain `NSView`: it hands the children to the parent
        // and takes the view's identifier with them, so an identifier a caller
        // sets on this control is not there to be found afterwards — and the
        // eight numbers arrive at the panel as eight loose fields belonging to
        // nothing. A group is what this is, so a group is what it says it is
        // (`explicit-over-implicit`). It stays a container, not a leaf: the
        // parts inside keep their own elements and their own identifiers.
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        switch style {
        case .frame: buildEdgeControls()
        case .paneDividers: buildDividerControls()
        }
        buildResetControl()

        observeTheme { control, palette in
            control.palette = palette
            control.needsDisplay = true
        }

        sync()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: Self.controlSize.width, height: Self.controlSize.height)
    }

    // MARK: - Building

    private func buildEdgeControls() {
        for edge in SpacingEdge.allCases {
            let field = makeField(accessibility: "spacing.\(edge.rawValue)")
            field.toolTip = "\(edge.displayName) — points between the edge and what is inside it"
            numberTargets[ObjectIdentifier(field)] = .edge(edge)
            edgeFields[edge] = field
            addSubview(field)

            let stepper = makeStepper(accessibility: "spacing.\(edge.rawValue).stepper")
            stepper.toolTip = field.toolTip
            numberTargets[ObjectIdentifier(stepper)] = .edge(edge)
            edgeSteppers[edge] = stepper
            addSubview(stepper)

            let more = makeArrowButton(
                arrow: edge.growing,
                accessibility: "spacing.edge.\(edge.rawValue).more",
                tooltip: "More \(edge.displayName.lowercased()) space"
            )
            let less = makeArrowButton(
                arrow: edge.shrinking,
                accessibility: "spacing.edge.\(edge.rawValue).less",
                tooltip: "Less \(edge.displayName.lowercased()) space"
            )
            arrowActions[ObjectIdentifier(more)] = .edge(edge, 1)
            arrowActions[ObjectIdentifier(less)] = .edge(edge, -1)
            edgeButtons[edge] = (more, less)

            let handle = makeHandle(
                axis: edge.dragAxis,
                accessibility: "spacing.edge.\(edge.rawValue).handle",
                holding: [more, less]
            )
            handle.onDragBegan = { [weak self] _ in
                guard let self else { return }
                dragOrigin = value
            }
            handle.onDrag = { [weak self] travelled in
                guard let self else { return }
                let moved = Int((travelled * edge.dragGain).rounded())
                apply(dragOrigin.setting(edge, to: dragOrigin[edge] + moved, in: range))
            }
            edgeHandles[edge] = handle
        }
    }

    private func buildDividerControls() {
        for gutter in SpacingGutter.allCases {
            let field = makeField(accessibility: "spacing.\(gutter.rawValue)")
            field.toolTip = Self.gutterDescription(gutter)
            numberTargets[ObjectIdentifier(field)] = .gutter(gutter)
            gutterFields[gutter] = field
            addSubview(field)

            let stepper = makeStepper(accessibility: "spacing.\(gutter.rawValue).stepper")
            stepper.toolTip = field.toolTip
            numberTargets[ObjectIdentifier(stepper)] = .gutter(gutter)
            gutterSteppers[gutter] = stepper
            addSubview(stepper)

            func arrow(near: Bool, narrower: Bool) -> NSButton {
                let button = makeArrowButton(
                    arrow: Self.gutterArrow(gutter, near: near, narrower: narrower),
                    accessibility: "spacing.gutter.\(gutter.rawValue)"
                        + ".\(narrower ? "narrower" : "wider").\(near ? "near" : "far")",
                    tooltip: "\(narrower ? "Narrower" : "Wider") gap between \(gutter.displayName)"
                )
                arrowActions[ObjectIdentifier(button)] = .gutter(gutter, narrower ? -1 : 1)
                return button
            }

            let arrows = GutterArrows(
                narrowerNear: arrow(near: true, narrower: true),
                narrowerFar: arrow(near: false, narrower: true),
                widerNear: arrow(near: true, narrower: false),
                widerFar: arrow(near: false, narrower: false)
            )
            gutterButtons[gutter] = arrows

            gutterHandles[gutter] = (
                narrower: makeGutterHandle(
                    gutter, named: "narrower", holding: [arrows.narrowerNear, arrows.narrowerFar]
                ),
                wider: makeGutterHandle(
                    gutter, named: "wider", holding: [arrows.widerNear, arrows.widerFar]
                )
            )
        }
    }

    /// A pair of arrows in a view of their own, which is itself a control: the
    /// arrows say "by one", the view they sit in is dragged to say "to here".
    /// Both live in the same place on the picture because they move the same
    /// line — a pair that had to be grabbed somewhere *other* than its arrows
    /// would be a second target for the same job, in a spot with nothing on it.
    ///
    /// The handle draws nothing. What is underneath is a picture of a container
    /// and its panes, and a box drawn around a pair of arrows standing on a
    /// pane edge reads as one more edge.
    private func makeHandle(
        axis: SpacingAxis,
        accessibility: String,
        holding arrows: [NSButton]
    ) -> SpacingHandle {
        let handle = SpacingHandle(axis: axis)
        for arrow in arrows { handle.addSubview(arrow) }
        addSubview(handle)
        return handle.accessibilityID(accessibility)
    }

    /// One of a divider's two pairs, dragging the gap open and shut.
    ///
    /// Which way is *open* depends on which side of the divider the pointer
    /// grabbed: the pair straddles the gutter, so one arrow of it moves the
    /// left pane's edge and the other the right pane's, and the drag follows
    /// whichever one the pointer came down on.
    private func makeGutterHandle(
        _ gutter: SpacingGutter,
        named name: String,
        holding arrows: [NSButton]
    ) -> SpacingHandle {
        let handle = makeHandle(
            axis: gutter.dragAxis,
            accessibility: "spacing.gutter.\(gutter.rawValue).\(name).handle",
            holding: arrows
        )
        handle.onDragBegan = { [weak self] grab in
            guard let self else { return }
            dragOrigin = value
            let centre = layoutPlan.position(of: gutter)
            let past = gutter.dragAxis == .horizontal ? grab.x - centre.x : grab.y - centre.y
            dragOutward = past < 0 ? -1 : 1
        }
        handle.onDrag = { [weak self] travelled in
            guard let self else { return }
            let moved = Int((travelled * dragOutward * SpacingGutter.outwardDragGain).rounded())
            apply(dragOrigin.setting(gutter, to: dragOrigin[gutter] + moved, in: range))
        }
        return handle
    }

    /// One button, whichever flavor is showing, and it zeroes only the numbers
    /// that flavor actually edits — a frame control resetting the gutters would
    /// silently change a setting it does not show.
    private func buildResetControl() {
        let button = NSButton(title: "Reset", target: self, action: #selector(resetClicked))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.toolTip = "Set every number here back to zero"
        button.translatesAutoresizingMaskIntoConstraints = true
        button.observeTheme { button, palette in
            button.font = palette.font(.body)
        }
        resetButton = button.accessibilityID("spacing.reset")
        addSubview(button)
    }

    /// Which way one of a divider's four arrows points: the way the pane edge
    /// it stands against travels.
    ///
    /// Closing the gap brings both edges towards the divider and opening it
    /// takes them both away, so the near arrow and the far arrow of a pair
    /// point at each other or away from each other — which is what makes the
    /// pair read as *close* or *open* without a label on it.
    private static func gutterArrow(_ gutter: SpacingGutter, near: Bool, narrower: Bool) -> SpacingArrow {
        switch gutter {
        case .betweenColumns: return near == narrower ? .right : .left
        case .betweenRows: return near == narrower ? .up : .down
        }
    }

    private static func gutterDescription(_ gutter: SpacingGutter) -> String {
        switch gutter {
        case .betweenColumns:
            return "Points between two panes side by side. The gap is shared, so this is the whole gap."
        case .betweenRows:
            return "Points between two panes stacked. The gap is shared, so this is the whole gap."
        }
    }

    /// The formatter says "whole number" and stops there. It deliberately does
    /// **not** carry the range: a `NumberFormatter` with a `maximum` refuses the
    /// text outright rather than clamping it, and AppKit answers a refusal by
    /// declining to end editing — so typing a number too large emptied the field
    /// and trapped the caret in it, with no number on screen to say what had
    /// happened. The range belongs to the value (`Spacing.setting(_:in:)`
    /// clamps every write), which is the one place that can clamp instead of
    /// reject; enforcing it twice is what made the second place a trap.
    private func makeField(accessibility: String) -> NSTextField {
        let field = NSTextField()
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        field.formatter = formatter
        field.alignment = .center
        field.delegate = self
        field.target = self
        field.action = #selector(fieldChanged(_:))
        field.translatesAutoresizingMaskIntoConstraints = true
        field.observeTheme { field, palette in
            field.font = palette.font(.code)
            field.textColor = palette.nsColor(.primaryText)
        }
        return field.accessibilityID(accessibility)
    }

    /// A stepper is the plain way to say "one more" on a number field, and it
    /// stands where every other number field on the panel puts it: against the
    /// field's right edge. It is a value control, not a nudge — its own
    /// `integerValue` is the setting, clamped by the same range the field uses.
    private func makeStepper(accessibility: String) -> NSStepper {
        let stepper = NSStepper()
        stepper.controlSize = .small
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.increment = 1
        // Wrapping would turn "one below the floor" into the ceiling, which is
        // never what a spacing of zero is one step away from.
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(stepperChanged(_:))
        stepper.translatesAutoresizingMaskIntoConstraints = true
        // Tab is for the numbers. A stepper in the loop would double every stop.
        stepper.refusesFirstResponder = true
        return stepper.accessibilityID(accessibility)
    }

    /// The button is placed in `layout()`, so the caller passes only what the
    /// button *is* and which way it points — never where it goes.
    private func makeArrowButton(arrow: SpacingArrow, accessibility: String, tooltip: String) -> NSButton {
        // `scaleProportionallyDown` never scales *up*, so a bigger box on its
        // own buys nothing — the symbol has to be asked for at the size it is
        // meant to be drawn, and at the weight it is meant to be read at.
        let image = NSImage(systemSymbolName: arrow.symbolName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: Self.arrowSymbolPointSize, weight: .regular))
        let button = ArrowButton()
        button.image = image ?? NSImage()
        button.imagePosition = .imageOnly
        button.title = ""
        button.target = self
        button.action = #selector(arrowClicked(_:))
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = true
        // Held down, an arrow repeats — a control that moves by one point is
        // otherwise a click per point.
        button.isContinuous = true
        button.setPeriodicDelay(0.45, interval: 0.06)
        // Tab is for the numbers; an arrow in the loop would put four stops
        // between two fields.
        button.refusesFirstResponder = true
        button.observeTheme { button, palette in
            button.contentTintColor = palette.nsColor(.accent)
        }
        arrowDirections[ObjectIdentifier(button)] = arrow
        return button.accessibilityID(accessibility)
    }

    /// The box an arrow is drawn in: shaped like the glyph on it, so a row of
    /// arrows takes only the room the arrows need.
    private func box(of button: NSButton) -> CGSize {
        guard let arrow = arrowDirections[ObjectIdentifier(button)], arrow.isHorizontal else {
            return CGSize(width: Metrics.arrowBreadth, height: Metrics.arrowLength)
        }
        return CGSize(width: Metrics.arrowLength, height: Metrics.arrowBreadth)
    }

    // MARK: - Actions

    @objc private func arrowClicked(_ sender: NSButton) {
        guard let action = arrowActions[ObjectIdentifier(sender)] else { return }
        switch action {
        case .edge(let edge, let delta):
            apply(value.adjusting(edge, by: delta, in: range))
        case .gutter(let gutter, let delta):
            apply(value.adjusting(gutter, by: delta, in: range))
        }
    }

    @objc private func fieldChanged(_ sender: NSTextField) {
        commit(sender)
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        guard let target = numberTargets[ObjectIdentifier(sender)] else { return }
        switch target {
        case .edge(let edge):
            apply(value.setting(edge, to: sender.integerValue, in: range))
        case .gutter(let gutter):
            apply(value.setting(gutter, to: sender.integerValue, in: range))
        }
    }

    /// Zero every number this flavor shows, in one write, so the change reaches
    /// whatever is bound to it as a single edit rather than four or six.
    @objc private func resetClicked() {
        var zeroed = value
        switch style {
        case .frame:
            for edge in SpacingEdge.allCases {
                zeroed = zeroed.setting(edge, to: 0, in: range)
            }
        case .paneDividers:
            for gutter in SpacingGutter.allCases {
                zeroed = zeroed.setting(gutter, to: 0, in: range)
            }
        }
        apply(zeroed)
    }

    /// Committing on every keystroke would fight the user mid-number (a "1" on
    /// the way to "12"), so a typed value lands when editing ends — Return, Tab
    /// or clicking away.
    public func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        commit(field)
    }

    /// Up and down adjust the focused field by a point. Left and right are left
    /// to the caret: they are how you edit the number that is already there.
    /// Tab walks from one number to the next.
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard let field = control as? NSTextField,
              let target = numberTargets[ObjectIdentifier(field)] else { return false }
        switch selector {
        case #selector(NSResponder.insertTab(_:)): return moveFocus(from: field, by: 1)
        case #selector(NSResponder.insertBacktab(_:)): return moveFocus(from: field, by: -1)
        default: break
        }
        let delta: Int
        switch selector {
        case #selector(NSResponder.moveUp(_:)): delta = 1
        case #selector(NSResponder.moveDown(_:)): delta = -1
        default: return false
        }
        switch target {
        case .edge(let edge):
            apply(value.adjusting(edge, by: delta, in: range))
        case .gutter(let gutter):
            apply(value.adjusting(gutter, by: delta, in: range))
        }
        // `sync` has already caught the field editor up — see `show`.
        return true
    }

    /// Text that is not a number at all — a pasted word, a stray keystroke —
    /// still fails to format, and AppKit's default answer is to keep the caret
    /// where it is until the text is fixed. That leaves a field the user cannot
    /// click away from and, having no object value, nothing legible in it
    /// either. So the entry is answered instead of refused.
    public func control(
        _ control: NSControl, didFailToFormatString string: String, errorDescription: String?
    ) -> Bool {
        guard let field = control as? NSTextField else { return false }
        return settle(field)
    }

    /// The number this control holds for `field`, or nil if the field is not
    /// one of its own.
    private func heldNumber(for field: NSTextField) -> Int? {
        switch numberTargets[ObjectIdentifier(field)] {
        case .edge(let edge): return value[edge]
        case .gutter(let gutter): return value[gutter]
        case nil: return nil
        }
    }

    /// Put a number the formatter will accept back into `field`, so that ending
    /// editing cannot fail.
    ///
    /// What was typed is kept whenever it reads as a number at all — clamped,
    /// because the range lives here rather than on the formatter — and replaced
    /// by the number already held when it does not. Either way the field ends
    /// up showing a number, which is the whole contract the caller needs: a
    /// field that cannot fail to format is a field the caret can leave.
    @discardableResult
    private func settle(_ field: NSTextField) -> Bool {
        guard let held = heldNumber(for: field) else { return false }
        let typed = (field.currentEditor()?.string ?? field.stringValue)
            .trimmingCharacters(in: .whitespaces)
        let number = parsed(typed, in: field).map { $0.clamped(to: range) } ?? held
        shownNumbers[ObjectIdentifier(field)] = number
        field.integerValue = number
        if let editor = field.currentEditor() {
            editor.string = field.stringValue
            editor.selectedRange = NSRange(location: field.stringValue.count, length: 0)
        }
        return true
    }

    /// Read a typed number back the same way the field wrote it.
    ///
    /// `field.integerValue` renders through the field's `NumberFormatter`,
    /// which is locale-aware, while `Int(_:)` reads ASCII digits and nothing
    /// else. Where the two disagree — a locale whose digits are not `0`–`9` —
    /// the field's own text parses as no number at all, so a number the user
    /// typed was quietly replaced by the one already held. Asking the formatter
    /// keeps the reading and the writing on the same side of the locale.
    /// `Int(_:)` remains the answer for a field with no formatter at all.
    private func parsed(_ text: String, in field: NSTextField) -> Int? {
        guard let formatter = field.formatter as? NumberFormatter else { return Int(text) }
        return formatter.number(from: text)?.intValue ?? Int(text)
    }

    /// The order Tab walks the numbers in: round the picture the way it reads
    /// — the top, the two sides, then the bottom — rather than in whatever
    /// order the dictionary happens to hold them.
    private var tabOrder: [NSTextField] {
        switch style {
        case .frame:
            return [SpacingEdge.top, .leading, .trailing, .bottom].compactMap { edgeFields[$0] }
        case .paneDividers:
            return SpacingGutter.allCases.compactMap { gutterFields[$0] }
        }
    }

    /// The number Tab arrives at first, and the one it leaves from — the two
    /// ends a panel showing more than one of these joins together.
    ///
    /// The join is the panel's to make, not this control's: which control comes
    /// next is a fact about the panel, and a control that reached for its own
    /// successor would have to know it had one. Handing back the two ends is
    /// enough, and it is the same thing `nextKeyView` asks for anywhere else.
    public var firstNumberField: NSView? { tabOrder.first }
    public var lastNumberField: NSView? { tabOrder.last }

    /// AppKit infers the key view loop from where subviews *are*, and these are
    /// placed by frame rather than by constraints — so the loop it works out
    /// threads this control's numbers in among whatever else the panel happens
    /// to be showing, and Tab in a number field went somewhere that looked like
    /// nowhere. Tab is answered here instead.
    ///
    /// Only *within* the control: at either end the key is handed back, so
    /// focus still leaves the control the way it leaves anything else — down
    /// whatever `nextKeyView` the panel joined the two ends to. A ring would
    /// have been the easy version and is the wrong one — a closed ring is a
    /// trap, and the panel around this has fields of its own.
    private func moveFocus(from field: NSTextField, by step: Int) -> Bool {
        let fields = tabOrder
        guard let index = fields.firstIndex(of: field),
              fields.indices.contains(index + step) else { return false }
        // Settle first: AppKit asks the field to end editing on the way out, and
        // a refusal there cancels the move silently, so Tab on unparseable text
        // would be swallowed and the user would have to press it twice.
        settle(field)
        window?.makeFirstResponder(fields[index + step])
        return true
    }

    private func commit(_ field: NSTextField) {
        guard let target = numberTargets[ObjectIdentifier(field)] else { return }
        switch target {
        case .edge(let edge):
            apply(value.setting(edge, to: field.integerValue, in: range))
        case .gutter(let gutter):
            apply(value.setting(gutter, to: field.integerValue, in: range))
        }
        // A typed value out of range was clamped; show what was actually taken.
        sync(forcing: field)
    }

    private func apply(_ newValue: Spacing) {
        guard newValue != value else { return }
        value = newValue
        onChange?(newValue)
    }

    // MARK: - Sync and layout

    /// `forced` is the field whose text has just been committed: it is shown
    /// again even when its number did not change, because a typed value that
    /// was clamped back to the number already held is the one case where the
    /// text on screen and the value disagree without the value moving.
    private func sync(forcing forced: NSTextField? = nil) {
        for (edge, field) in edgeFields {
            show(value[edge], in: field, force: field === forced)
            edgeSteppers[edge]?.integerValue = value[edge]
        }
        for (gutter, field) in gutterFields {
            show(value[gutter], in: field, force: field === forced)
            gutterSteppers[gutter]?.integerValue = value[gutter]
        }
        needsLayout = true
        needsDisplay = true
    }

    /// The number each field was last shown, so `show` can tell "this field's
    /// value changed" from "some other field's did". `field.integerValue` cannot
    /// answer that: while a field is being edited it reports what is in the
    /// field editor, which is whatever the user has typed so far.
    private var shownNumbers: [ObjectIdentifier: Int] = [:]

    /// A field being typed in keeps its text in the window's field editor, not
    /// in the field, so assigning the value alone leaves the old number on
    /// screen. Every arrow is that case: a borderless momentary button never
    /// takes focus, so whichever field the user last clicked in is still
    /// editing when the arrow changes its number — and the number is the whole
    /// point of pressing the arrow. So the editor is told too, whenever there
    /// is one.
    ///
    /// **Only when this field's own number moved.** One arrow press re-shows
    /// all six fields, and writing the editor of a field whose number did not
    /// change would throw away what the user is halfway through typing in it —
    /// click into Top, type `1`, press Left's arrow, and the `1` is gone.
    private func show(_ number: Int, in field: NSTextField, force: Bool = false) {
        let id = ObjectIdentifier(field)
        let moved = shownNumbers[id] != number
        shownNumbers[id] = number
        guard let editor = field.currentEditor() else {
            field.integerValue = number
            return
        }
        guard moved || force else { return }
        field.integerValue = number
        guard editor.string != field.stringValue else { return }
        editor.string = field.stringValue
        editor.selectedRange = NSRange(location: field.stringValue.count, length: 0)
    }

    /// Below this the picture stops being readable and the arrows start to
    /// overlap; the control clips rather than shrinking further, which is a
    /// legible failure instead of an illegible one.
    ///
    /// Two floors, and the larger wins: three number groups across, which is
    /// what keeps the chrome legible, and ``Metrics/minimumDiagramSize``, which
    /// is what keeps the top of the range drawable. The second is the taller of
    /// the two — the chrome floor left 63 points of diagram for a range that
    /// asks for 80 — so a squeezed control now stops shrinking while the
    /// picture can still move over every value the user can type.
    private static let minimumSize = CGSize(
        width: diagramInset.width * 2
            + max(Metrics.minimumDiagramSize.width, Metrics.fieldGroupSize.width * 3),
        height: diagramInset.height * 2
            + max(Metrics.minimumDiagramSize.height, Metrics.fieldGroupSize.height * 3)
    )

    /// Measured from `bounds`, not from `controlSize`.
    ///
    /// `intrinsicContentSize` *asks* for `controlSize`, but asking is all it
    /// does: a settings panel pins its content to the panel width with a
    /// required constraint, and default compression resistance loses to that.
    /// A diagram drawn to a box wider than `bounds` puts the right-hand number
    /// and its arrows outside the view, where `hitTest` refuses them — so they
    /// are not merely clipped, they cannot be clicked at all, and a pinned
    /// scroll view means there is no scrolling to them either. A slightly
    /// smaller picture is the better failure.
    private var diagramRect: CGRect {
        let size = CGSize(
            width: max(bounds.width, Self.minimumSize.width),
            height: max(bounds.height, Self.minimumSize.height)
        )
        return CGRect(
            x: Self.diagramInset.width,
            y: Self.diagramInset.height,
            width: size.width - Self.diagramInset.width * 2,
            height: size.height - Self.diagramInset.height * 2
        )
    }

    private var layoutPlan: SpacingControlLayout {
        SpacingControlLayout(diagram: diagramRect, spacing: value, style: style)
    }

    /// The diagram is measured from `bounds`, so a resize moves every subview
    /// and repaints the drawing under them.
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
        needsDisplay = true
    }

    public override func layout() {
        super.layout()
        let plan = layoutPlan
        layoutEdgeControls(plan)
        layoutDividerControls(plan)
        layoutReset(plan)
    }

    /// On the row the bottom number rides, right edge flush with the frame's.
    ///
    /// Both flavors leave the same room below the diagram for a number, and
    /// only the frame flavor puts one there — so Reset on that line lands
    /// beside the bottom number rather than under it, and lands in the same
    /// place in the picture that has no bottom number. It used to stand in a
    /// footer of its own below everything, which put it one distance from the
    /// frame control's numbers and a different one from the divider control's.
    ///
    /// Read off the plan rather than off `bounds`, so it stays with the picture
    /// when the control is given less room than it asked for.
    private func layoutReset(_ plan: SpacingControlLayout) {
        guard let resetButton else { return }
        let size = Metrics.resetSize
        let row = plan.fieldPosition(of: .bottom).y
        resetButton.frame = CGRect(
            x: (plan.outerFrame.maxX - size.width).rounded(),
            y: (row - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    /// One step out from a line, along the axis an arrow points: half an arrow,
    /// so the arrow's tip lands exactly on the line.
    private static let attachment: CGFloat = Metrics.arrowLength / 2

    /// Where an arrow's centre goes if its **tip** is to touch `line` on the
    /// cross axis: half an arrow back along the way it points, which puts the
    /// body on the far side from where it is aimed — `->|`.
    private func attached(_ arrow: SpacingArrow, to centre: CGPoint) -> CGPoint {
        switch arrow {
        case .up: return CGPoint(x: centre.x, y: centre.y - Self.attachment)
        case .down: return CGPoint(x: centre.x, y: centre.y + Self.attachment)
        case .left: return CGPoint(x: centre.x + Self.attachment, y: centre.y)
        case .right: return CGPoint(x: centre.x - Self.attachment, y: centre.y)
        }
    }

    /// Between a divider's two pairs of arrows, from the divider's centre to
    /// each pair: half an arrow's breadth and half the gap, so the closing pair
    /// and the opening pair stand clear of each other with nothing between them.
    /// There used to be a number there, and this is what shrank when it moved
    /// outside.
    private static let pairOffset: CGFloat = (Metrics.arrowBreadth + Metrics.arrowGap) / 2

    /// Both of an edge's arrows sit on the middle of that edge of the **view**,
    /// tips meeting on the line and bodies on opposite sides of it — `->| |<-`.
    /// Press one and the line moves the way it is aimed. The number stands out
    /// beyond the container, centred on the same edge.
    private func layoutEdgeControls(_ plan: SpacingControlLayout) {
        for (edge, field) in edgeFields {
            placeNumber(field, edgeSteppers[edge], at: plan.fieldPosition(of: edge))
            guard let buttons = edgeButtons[edge], let handle = edgeHandles[edge] else { continue }
            let line = plan.position(of: edge)
            var seats: [(NSView, CGRect)] = []
            for (button, arrow) in [(buttons.more, edge.growing), (buttons.less, edge.shrinking)] {
                seats.append((button, seatRect(of: button, centredAt: attached(arrow, to: line))))
            }
            seat(handle, holding: seats)
        }
    }

    /// A divider has two edges, one per pane, so it carries two *pairs* of
    /// arrows: the closing pair one way along the divider, the opening pair the
    /// other, straddling the middle of the panes they separate. Each arrow
    /// stands against its own pane's edge, outside the gutter — there is no room
    /// to stand one inside a gap that is a hairline at zero, so the opening pair
    /// is drawn from the outside too. The number stands outside the container,
    /// in line with the divider.
    private func layoutDividerControls(_ plan: SpacingControlLayout) {
        for (gutter, field) in gutterFields {
            let centre = plan.position(of: gutter)
            placeNumber(field, gutterSteppers[gutter], at: plan.fieldPosition(of: gutter))
            guard let buttons = gutterButtons[gutter],
                  let handles = gutterHandles[gutter] else { continue }
            let across = gutter == .betweenColumns ? plan.columnGutter : plan.rowGutter
            let along = Self.pairOffset
            let pairs = [(-along, buttons.widerNear, buttons.widerFar, handles.wider),
                         (along, buttons.narrowerNear, buttons.narrowerFar, handles.narrower)]
            for (offset, near, far, handle) in pairs {
                var seats: [(NSView, CGRect)] = []
                for (button, isNear) in [(near, true), (far, false)] {
                    let point = Self.gutterSeat(
                        gutter, on: centre, in: across, along: offset, near: isNear
                    )
                    seats.append((button, seatRect(of: button, centredAt: point)))
                }
                seat(handle, holding: seats)
            }
        }
    }

    /// One of a divider's four arrow seats: `along` picks the pair (the closing
    /// pair sits above the number on the column divider and to its left on the
    /// row divider), `near` picks which side of the gutter.
    private static func gutterSeat(
        _ gutter: SpacingGutter,
        on centre: CGPoint,
        in across: CGRect,
        along: CGFloat,
        near: Bool
    ) -> CGPoint {
        switch gutter {
        case .betweenColumns:
            let side = near
                ? across.minX - attachment
                : across.maxX + attachment
            return CGPoint(x: side, y: centre.y + along)
        case .betweenRows:
            let side = near
                ? across.minY - attachment
                : across.maxY + attachment
            return CGPoint(x: centre.x - along, y: side)
        }
    }

    /// A number and its stepper are one block, centred together on the point
    /// the layout hands back: the field takes the left of it, the stepper the
    /// right. Centring the field alone would leave the stepper hanging past the
    /// edge it belongs to, and the block is what has to line up.
    private func placeNumber(_ field: NSTextField, _ stepper: NSStepper?, at centre: CGPoint) {
        let group = Metrics.fieldGroupSize
        let left = centre.x - group.width / 2
        place(field, at: CGPoint(x: left + Metrics.fieldSize.width / 2, y: centre.y))
        place(
            stepper,
            at: CGPoint(x: left + group.width - Metrics.stepperSize.width / 2, y: centre.y),
            size: Metrics.stepperSize
        )
    }

    private func place(_ view: NSView?, at center: CGPoint, size: CGSize? = nil) {
        guard let view else { return }
        let box = size ?? Metrics.fieldSize
        view.frame = CGRect(
            x: (center.x - box.width / 2).rounded(),
            y: (center.y - box.height / 2).rounded(),
            width: box.width,
            height: box.height
        )
    }

    /// Where an arrow stands, in the control's own coordinates — worked out
    /// before its handle is drawn around it, because the handle is exactly the
    /// room its pair needs and nothing else.
    private func seatRect(of button: NSButton, centredAt centre: CGPoint) -> CGRect {
        let size = box(of: button)
        return CGRect(
            x: (centre.x - size.width / 2).rounded(),
            y: (centre.y - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    /// Put the handle around its pair and the arrows inside it, so the thing
    /// the user drags is exactly the thing they see.
    ///
    /// A pressed arrow freezes the whole pair, handle and all: an arrow held
    /// down repeats, and re-seating it mid-press would walk it out from under
    /// the pointer and stop the repeat dead. It is what lets the diagram move
    /// one-to-one with the number over the whole range.
    private func seat(_ handle: SpacingHandle, holding seats: [(NSView, CGRect)]) {
        guard !handle.holdsPressedArrow, let first = seats.first else { return }
        let bounds = seats.dropFirst().reduce(first.1) { $0.union($1.1) }
        handle.frame = bounds
        for (arrow, rect) in seats {
            arrow.frame = rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        }
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let plan = layoutPlan

        // Three layers, and the middle one is the setting: the container is
        // filled, the panes are filled over it, and what shows between them is
        // the space being edited. An outline alone left the padding the same
        // colour as the panel, which made the one thing the diagram exists to
        // show the one thing it did not.
        // The outer frame is drawn, and has to be: frame spacing is the room
        // *between* it and the pane, so without it the picture shows a lone
        // rectangle and the number beside it measures nothing visible.
        //
        // The colours are the project window's own, not generic control
        // colours: the backdrop a project paints behind its panes, and the
        // window background a pane paints itself. So the diagram is a small
        // picture of the thing being edited rather than a diagram of it, and
        // recolouring the scheme recolours both together.
        let frame = NSBezierPath(rect: plan.outerFrame.insetBy(dx: 0.5, dy: 0.5))
        NSColor(palette.projectPaneBackdrop).setFill()
        frame.fill()
        palette.nsColor(.border).setStroke()
        frame.lineWidth = 1
        frame.stroke()

        let fill = palette.nsColor(.windowBackground)
        let border = NSColor(palette.projectPaneOutline)
        for pane in plan.panes where pane.width > 0 && pane.height > 0 {
            let path = NSBezierPath(rect: pane.insetBy(dx: 0.5, dy: 0.5))
            fill.setFill()
            path.fill()
            border.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

/// An arrow that holds its ground while it is held down.
///
/// `mouseDown` runs AppKit's tracking loop to completion before it returns, so
/// the flag is set for exactly as long as the press lasts and `place` can read
/// it synchronously — no timer, no state to reset if the press is cancelled.
private final class ArrowButton: NSButton {

    private(set) var isPressed = false

    override func mouseDown(with event: NSEvent) {
        // The pair's handle is directly underneath and the two arrows cover
        // it, so a press that turns into a drag has to be handed over here —
        // otherwise the only draggable part of a pair would be the pixels
        // between its arrows, and on an edge there are none.
        if let handle = superview as? SpacingHandle, handle.claimsPress(event, on: self) { return }
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
        // Every layout that ran during the press left this one pair behind;
        // one more puts it back on the line it just finished moving.
        superview?.superview?.needsLayout = true
    }
}

/// The two arrows that move one line, in a view of their own — and that view is
/// itself a control: drag it and the line goes with the pointer, which is the
/// direct way to say what the arrows say one point at a time.
///
/// It draws nothing at all. What is underneath is a picture of a container and
/// its panes, and a box around a pair of arrows standing on a pane edge reads
/// as one more edge.
///
/// The drag is tracked by hand rather than through a gesture recognizer because
/// the arrows cover the handle: the press lands on a button, and the button has
/// to keep it when the pointer never moves — an arrow held down repeats.
/// ``claimsPress`` is that decision, and it is taken on the first event.
private final class SpacingHandle: NSView {

    /// How far the pointer has to travel before a press stops being a click.
    private static let slop: CGFloat = 3

    /// How long a *still* press is watched before it is handed back to the
    /// arrow under it. An arrow does not begin repeating for 0.45s, so a wait
    /// this short costs a held arrow nothing.
    private static let grace: TimeInterval = 0.12

    /// The longest the whole decision may take, however many events arrive.
    ///
    /// The grace is restarted by each event, and a finger resting on a trackpad
    /// is not a pointer sending nothing — it is a pointer sending a steady
    /// trickle of sub-point jitter. Every one of those restarted the clock, so
    /// on a trackpad the wait never ended and the arrow never got its press
    /// back: hold-to-repeat was unreachable there, while a mouse, which really
    /// does go silent, worked. This bounds the wait so a press that has not
    /// travelled ``slop`` is a hold whether or not the pointer is quiet, and it
    /// stays under the 0.45s an arrow waits before repeating, so nothing is
    /// lost at the other end either.
    private static let patience: TimeInterval = 0.3

    /// Which way this handle moves. It is also the cursor it shows, so the
    /// pointer says the pair is draggable before anything is pressed.
    private let axis: SpacingAxis

    /// The pointer's grab point, in the control's coordinates. Which side of a
    /// divider it landed on is what tells a gutter drag which way is *out*.
    var onDragBegan: ((CGPoint) -> Void)?

    /// How far the pointer has travelled along ``axis`` since the grab. Always
    /// measured from the start, never as a step, so rounding cannot drift.
    var onDrag: ((CGFloat) -> Void)?

    init(axis: SpacingAxis) {
        self.axis = axis
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var holdsPressedArrow: Bool {
        subviews.contains { ($0 as? ArrowButton)?.isPressed == true }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    /// A press that lands between the arrows — the gap a divider's pair leaves
    /// over the gutter itself — is a drag from the first event.
    override func mouseDown(with event: NSEvent) {
        track(from: event)
    }

    /// Whether this handle takes a press that landed on one of its arrows.
    ///
    /// A press that moves is a drag, one that is let go is a click, and one
    /// that lies still is a hold the arrow should have back so it can repeat.
    /// The grace measures the *stillness*, not the whole press: every mouse
    /// event that arrives puts the clock back, so a drag begun slowly is still
    /// a drag. Timing the press alone handed a slow drag to the button, which
    /// then had the press and could do nothing with it but click.
    ///
    /// ``patience`` is what keeps that from being unbounded: a trackpad's
    /// resting jitter is a stream of events that never travels ``slop``, and
    /// restarting the clock on each of them waits forever.
    func claimsPress(_ event: NSEvent, on button: NSButton) -> Bool {
        guard let window else { return false }
        let start = event.locationInWindow
        let expiry = Date().addingTimeInterval(Self.patience)
        var deadline = min(Date().addingTimeInterval(Self.grace), expiry)
        while let next = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: deadline,
            inMode: .eventTracking,
            dequeue: true
        ) {
            guard next.type == .leftMouseDragged else {
                // Pressed and let go without moving: an ordinary click, which
                // is the arrow's own job. The press has already been taken off
                // the queue, so the click is sent rather than handed back.
                button.performClick(nil)
                return true
            }
            let moved = hypot(
                next.locationInWindow.x - start.x,
                next.locationInWindow.y - start.y
            )
            if moved >= Self.slop {
                track(from: event, continuing: next)
                return true
            }
            deadline = min(Date().addingTimeInterval(Self.grace), expiry)
            // An expired deadline does not end the loop on its own: an event
            // already sitting in the queue is handed over regardless of the
            // date, which on a trackpad is a backlog that never runs dry.
            if deadline <= Date() { break }
        }
        return false
    }

    /// The drag itself: every mouse event until the button comes up, reported
    /// as a distance from where the press started.
    private func track(from press: NSEvent, continuing first: NSEvent? = nil) {
        guard let window else { return }
        let start = press.locationInWindow
        onDragBegan?(superview?.convert(start, from: nil) ?? start)
        var event = first ?? window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp])
        while let current = event, current.type == .leftMouseDragged {
            onDrag?(travelled(from: start, to: current.locationInWindow))
            // The control lays out and repaints between events of its own
            // accord only once this loop lets go of the run loop; asking for
            // both here is what makes the line keep up with the pointer.
            superview?.layoutSubtreeIfNeeded()
            superview?.displayIfNeeded()
            event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp])
        }
    }

    private func travelled(from start: CGPoint, to point: CGPoint) -> CGFloat {
        axis == .horizontal ? point.x - start.x : point.y - start.y
    }
}
