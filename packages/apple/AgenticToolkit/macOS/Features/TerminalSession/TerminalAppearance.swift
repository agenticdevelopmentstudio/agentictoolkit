import AppKit
import SwiftTerm

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

extension TerminalCursorShape {

    /// Both block shapes map to SwiftTerm's block: the difference between them
    /// is fill, which `ThemedTerminalView` draws, not a different style.
    ///
    /// The shape itself lives in Core (a `ColorTheme` carries one); this mapping
    /// is here because SwiftTerm is a macOS-framework dependency.
    public func cursorStyle(blinking: Bool) -> CursorStyle {
        switch self {
        case .block, .hollowBlock: return blinking ? .blinkBlock : .steadyBlock
        case .underline:           return blinking ? .blinkUnderline : .steadyUnderline
        case .bar:                 return blinking ? .blinkBar : .steadyBar
        }
    }
}

/// The four sides a terminal's padding is set on.
public struct TerminalPadding: Equatable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat
}

/// What a terminal looks like: colors from the app theme, everything else from
/// the terminal settings — unless the active theme overrides it.
///
/// This is the single place the two are combined, so the content view
/// controller has no opinion of its own and the settings panel has nothing to
/// apply. Colors deliberately do *not* get their own settings — a second
/// palette beside `ColorTheme` is exactly the drift that left the terminal
/// looking like a different app (`dry`).
///
/// Every non-color option resolves the same way: `theme.terminal?.x ?? the
/// setting`. A theme carries no terminal options until the user edits them in
/// Theme settings, so the settings panel is what decides by default.
@MainActor
public enum TerminalAppearance {

    /// The two keys ``resolvedFont(theme:)`` falls back to, apart from the rest.
    ///
    /// Named separately because the terminal is no longer the only thing set in
    /// the terminal's face: the chat bubbles are too, and a bubble has no
    /// opinion about padding or caret shape. Watching the whole set there would
    /// re-measure every bubble in a feed because somebody moved the caret one
    /// point left.
    public static let fontSettingKeys: Set<String> = [
        UserSettings.terminalFontName.name,
        UserSettings.terminalFontSize.name
    ]

    /// Every `terminal_*` key, so a change to any of them can be recognized
    /// from `UserSettings.shared.changes` without one observer per setting.
    public static let settingKeys: Set<String> = fontSettingKeys.union([
        UserSettings.terminalPaddingTop.name,
        UserSettings.terminalPaddingLeading.name,
        UserSettings.terminalPaddingBottom.name,
        UserSettings.terminalPaddingTrailing.name,
        UserSettings.terminalCursorShape.name,
        UserSettings.terminalCursorBlinks.name
    ])

    /// The terminal font: the theme's override if it has one, otherwise the
    /// Terminal settings panel's.
    ///
    /// The stored name is a PostScript font name rather than a family, because
    /// the whole point of the picker is telling `FiraCode Nerd Font Mono` from
    /// `FiraCode Nerd Font Propo` — a family name cannot.
    public static func resolvedFont(theme: ColorTheme) -> NSFont {
        let size = CGFloat(theme.terminal?.fontSize ?? UserSettings.terminalFontSize.value)
        let name = theme.terminal?.fontName ?? UserSettings.terminalFontName.value
        return NSFont(name: name, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// How far the terminal grid is held off its container's edges.
    public static func resolvedPadding(theme: ColorTheme) -> TerminalPadding {
        let overrides = theme.terminal
        return TerminalPadding(
            top: CGFloat(overrides?.paddingTop ?? UserSettings.terminalPaddingTop.value),
            leading: CGFloat(overrides?.paddingLeading ?? UserSettings.terminalPaddingLeading.value),
            bottom: CGFloat(overrides?.paddingBottom ?? UserSettings.terminalPaddingBottom.value),
            trailing: CGFloat(overrides?.paddingTrailing ?? UserSettings.terminalPaddingTrailing.value)
        )
    }

    /// The caret shape, and whether it blinks.
    public static func resolvedCursor(theme: ColorTheme) -> (shape: TerminalCursorShape, blinks: Bool) {
        (theme.terminal?.cursorShape ?? UserSettings.terminalCursorShape.value,
         theme.terminal?.cursorBlinks ?? UserSettings.terminalCursorBlinks.value)
    }

    /// Paints `terminalView` with the theme's colors and the resolved font and
    /// caret. Cheap enough to call on every theme or settings change.
    public static func apply(to terminalView: TerminalView, palette: SemanticPalette) {
        terminalView.nativeForegroundColor = palette.nsColor(.primaryText)
        terminalView.nativeBackgroundColor = palette.nsColor(.windowBackground)
        terminalView.selectedTextBackgroundColor = palette.nsColor(.selection)

        let ansi = palette.theme.ansi.map(Self.swiftTermColor)
        if ansi.count == ColorTheme.ansiColorCount {
            terminalView.installColors(ansi)
        }

        terminalView.font = resolvedFont(theme: palette.theme)

        applyCaret(to: terminalView, palette: palette)

        terminalView.needsDisplay = true
    }

    /// `setCursorStyle` only moves the `Terminal`'s own state; the AppKit caret
    /// is repainted by the view's `cursorStyleChanged`. Calling just the first
    /// is why changing the shape used to do nothing visible.
    private static func applyCaret(to terminalView: TerminalView, palette: SemanticPalette) {
        let cursor = resolvedCursor(theme: palette.theme)
        let style = cursor.shape.cursorStyle(blinking: cursor.blinks)

        // SwiftTerm's caret ignores its style entirely while the view is
        // unfocused — it strokes a hollow rectangle and returns. Which meant the
        // shape setting looked broken exactly when the user was looking at it:
        // picking a shape in Settings takes focus off the terminal. The caret
        // does say which pane the user is working in, but keyed to Whippet's
        // own active pane rather than to AppKit focus, so that opening Settings
        // does not hollow out every caret on screen at once.
        terminalView.caretViewTracksFocus = false

        let terminal = terminalView.getTerminal()
        terminal.setCursorStyle(style)
        terminalView.cursorStyleChanged(source: terminal, newStyle: style)

        let cursorColor = palette.nsColor(.cursor)

        if let themed = terminalView as? ThemedTerminalView {
            // A full block is the shape that says which pane you are in: solid
            // in the active one, an outline elsewhere. An outline caret is
            // already an outline everywhere, and a bar or an underline is too
            // thin for fill to say anything.
            themed.caretAppearance = ThemedTerminalView.CaretAppearance(
                color: cursorColor,
                textColor: palette.nsColor(.primaryText),
                isAlwaysHollow: cursor.shape == .hollowBlock,
                marksActivePane: cursor.shape == .block)
        } else {
            // No outline to draw without the subclass, so the shape is all
            // there is: fill it, unless it asked to be hollow.
            let hollow = cursor.shape == .hollowBlock
            terminalView.caretColor = hollow ? .clear : cursorColor
            terminalView.caretTextColor = hollow ? palette.nsColor(.primaryText) : nil
        }
    }

    /// `RGBAColor` is normalized [0, 1]; SwiftTerm wants 16-bit channels.
    private static func swiftTermColor(_ color: RGBAColor) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16((color.red * 65_535).rounded()),
            green: UInt16((color.green * 65_535).rounded()),
            blue: UInt16((color.blue * 65_535).rounded())
        )
    }
}

extension UserSettings {

    /// Inset between the terminal grid and its container, per side, in points.
    /// Four settings rather than one because a terminal under a tab bar wants
    /// more room at the top than at the bottom, and that is not derivable.
    static public var terminalPaddingTop = UserSetting<Int>("terminal_padding_top", default: 10)
    static public var terminalPaddingLeading = UserSetting<Int>("terminal_padding_leading", default: 10)
    static public var terminalPaddingBottom = UserSetting<Int>("terminal_padding_bottom", default: 10)
    static public var terminalPaddingTrailing = UserSetting<Int>("terminal_padding_trailing", default: 10)

    /// PostScript font name for the terminal.
    static public var terminalFontName = UserSetting<String>("terminal_font_name", default: "Menlo-Regular")

    /// Terminal font size, in points.
    static public var terminalFontSize = UserSetting<Double>("terminal_font_size", default: 13)

    /// Caret shape: block, hollow block, underline or bar.
    static public var terminalCursorShape =
        UserSetting<TerminalCursorShape>("terminal_cursor_shape", default: .block)

    /// Whether the caret blinks.
    static public var terminalCursorBlinks = UserSetting<Bool>("terminal_cursor_blinks", default: true)
}
