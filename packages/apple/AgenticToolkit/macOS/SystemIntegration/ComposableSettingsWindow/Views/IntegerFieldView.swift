import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// A short label and a narrow integer text field, clamped to the view
    /// model's range.
    ///
    /// A slider is the wrong control for a number the user already knows —
    /// "12 points on the left" is typed, not dragged — and `StepperView` makes
    /// you click twelve times to say it.
    ///
    /// The behaviour now lives in `NumberFieldView<Int>`, which takes its
    /// bounds one at a time instead of demanding a `RangeViewModel` that has
    /// both. This name stays because it is public API of a framework other
    /// repos link: a bounded integer field is still exactly this call.
    @MainActor
    public final class IntegerFieldView: NSView, SettingsViewProtocol, NSTextFieldDelegate {

        public let label: NSTextField
        public let textField: NSTextField

        private let field: NumberFieldView<Int>

        /// - Parameters:
        ///   - fieldWidth: Width of the number field.
        ///   - labelWidth: When set, the label is pinned to this width and
        ///     right-aligned. That is what lets a *column* of these read as one
        ///     form — four sides of a padding box, say — with the fields lined
        ///     up under each other instead of stepping in and out with the
        ///     length of each name.
        public init(
            viewModel: RangeViewModel<Int>,
            fieldWidth: CGFloat = 52,
            labelWidth: CGFloat? = nil
        ) {
            self.field = NumberFieldView(
                viewModel: viewModel,
                minimum: viewModel.minValue,
                maximum: viewModel.maxValue,
                fieldWidth: fieldWidth,
                labelWidth: labelWidth
            )
            self.label = self.field.label
            self.textField = self.field.textField

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            self.addSubview(self.field)
            Self.pinToEdges(self.field, of: self)
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame frameRect: NSRect)")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Kept because it was public, and forwards for the same reason. The
        /// text field's delegate is the inner view, so AppKit calls that one;
        /// anything holding an `IntegerFieldView` as a delegate still commits.
        public func controlTextDidEndEditing(_ obj: Notification) {
            field.commit()
        }
    }
}
