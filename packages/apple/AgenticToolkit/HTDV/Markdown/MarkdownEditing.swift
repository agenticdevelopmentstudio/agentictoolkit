import Foundation
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Factory for markdown editor/viewer view controllers. The hub app injects the real markdown editor through
/// `HubModules.markdownEditing`; `PlainTextMarkdownEditing` is the default until then.
public protocol MarkdownEditing: Sendable {
    @MainActor
    func makeEditor(initialText: String, onChange: @escaping @MainActor (String) -> Void) -> PlatformViewController

    @MainActor
    func makeViewer(text: String) -> PlatformViewController
}

/// An editor produced by `MarkdownEditing.makeEditor` whose text can be replaced programmatically —
/// what Revert needs to push a restored value back into the editor without knowing its concrete type.
@MainActor
public protocol MarkdownTextReplacing: AnyObject {
    func replaceText(with newText: String)
}

/// Monospaced plain-text editing with no rendering. Adequate for configuration notes until the markdown module lands.
public struct PlainTextMarkdownEditing: MarkdownEditing {
    public init() {}

    @MainActor
    public func makeEditor(
        initialText: String, onChange: @escaping @MainActor (String) -> Void
    ) -> PlatformViewController {
        PlainTextEditorViewController(initialText: initialText, onChange: onChange)
    }

    @MainActor
    public func makeViewer(text: String) -> PlatformViewController {
        PlainTextViewerViewController(text: text)
    }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)

public final class PlainTextEditorViewController: NSViewController, NSTextViewDelegate, MarkdownTextReplacing {
    let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let onChange: @MainActor (String) -> Void
    private let initialText: String

    public var text: String { textView.string }

    init(initialText: String, onChange: @escaping @MainActor (String) -> Void) {
        self.initialText = initialText
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override public func loadView() {
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.string = initialText
        textView.delegate = self
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        view = scrollView
    }

    /// Programmatic replacement that also notifies `onChange` (used by tests and by "revert").
    public func replaceText(with newText: String) {
        textView.string = newText
        onChange(newText)
    }

    public func textDidChange(_ notification: Notification) {
        onChange(textView.string)
    }
}

public final class PlainTextViewerViewController: NSViewController {
    let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let initialText: String

    public var text: String { textView.string }

    init(text: String) {
        self.initialText = text
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override public func loadView() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.string = initialText
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        view = scrollView
    }
}

#elseif canImport(UIKit)

public final class PlainTextEditorViewController: UIViewController, UITextViewDelegate, MarkdownTextReplacing {
    let textView = UITextView()
    private let onChange: @MainActor (String) -> Void
    private let initialText: String

    public var text: String { textView.text ?? "" }

    init(initialText: String, onChange: @escaping @MainActor (String) -> Void) {
        self.initialText = initialText
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override public func loadView() {
        textView.font = .monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.text = initialText
        textView.delegate = self
        view = textView
    }

    public func replaceText(with newText: String) {
        textView.text = newText
        onChange(newText)
    }

    public func textViewDidChange(_ textView: UITextView) {
        onChange(textView.text ?? "")
    }
}

public final class PlainTextViewerViewController: UIViewController {
    let textView = UITextView()
    private let initialText: String

    public var text: String { textView.text ?? "" }

    init(text: String) {
        self.initialText = text
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override public func loadView() {
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)
        textView.text = initialText
        view = textView
    }
}

#endif
