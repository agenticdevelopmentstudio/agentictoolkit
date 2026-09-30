<!-- leaf: implement-general-view-3/themed-terminal-view--part-2 · source: themed-terminal-view.md -->

# Themed Terminal View (Hollow Caret) — continued (part 2)

**Rules** (cite as `implement-general-view-3/themed-terminal-view--part-2#<slug>`):

- `decision` MUST — main-actor-isolation has no runtime conformance vector; it is verified by the Swift compiler's @MainActor isolation …

## Platform Notes

- **SwiftUI**: There is no SwiftUI-native terminal emulator equivalent to `LocalProcessTerminalView`; wrap it (or another terminal engine) in an `NSViewRepresentable`, exposing `CaretAppearance` as a `Binding` the representable's `updateNSView(_:context:)` writes into the wrapped `ThemedTerminalView`'s `caretAppearance` property on every SwiftUI update, rather than re-deriving the hollow/filled decision in SwiftUI itself.
- **Compose**: Wrap an Android terminal-emulation view (there is no Jetpack Compose-native equivalent) in an `AndroidView`, and reproduce the caret decision as a small `Drawable`/custom `View` overlay whose stroke is toggled on/off the same way this file toggles `layer.borderWidth`; drive it from a `mutableStateOf<CaretAppearance>` the same way `caretAppearance`'s `didSet` drives `updateCaret()`.
- **React/Web**: xterm.js exposes `cursorStyle: 'block' | 'underline' | 'bar'` and theme colors (`cursor`, `cursorAccent`) but no built-in hollow-block style either; reproduce the outline by setting the cursor cell's CSS to a transparent background with a `1px solid` outline/border color, toggled by the same `isAlwaysHollow`/`marksActivePane`-equivalent booleans, and drive `cursorAccent` the way this file drives `caretTextColor`.
- **AppKit / UIKit (source)**: `ThemedTerminalView.swift` is macOS-only (`import AppKit`); there is no UIKit counterpart in this file. It subclasses SwiftTerm's `LocalProcessTerminalView`, is declared `internal` specifically to avoid an Objective-C header conflict with the Swift-only `SwiftTerm` module, locates SwiftTerm's private caret subview by matching its runtime type name's `"CaretView"` suffix (with a weak, superview-validated cache), and separates "recompute the hollow/filled decision" (`updateCaret()`, run on appearance/window/notification changes) from "just repaint the border" (`applyOutline()`, run on every SwiftTerm cursor callback) to avoid rewriting SwiftTerm's caret color properties on every cursor movement.
- **WinUI 3**: If hosting a real terminal buffer, `Microsoft.Terminal.Control.TermControl` (from the Windows Terminal control package) is understood to expose some cursor-styling options through its settings, but this recipe has no cited source confirming whether it offers anything like a hollow-outline style, so treat that specific claim as unverified. Independent of what `TermControl` offers natively, the same border-overlay technique used here can be reproduced generically: track the active cell's caret with a `Border` element layered over the terminal surface, and toggle between a filled state (`Border.Background` set to the caret color, `BorderThickness="0"`) and a hollow state (`Border.Background` set to `Transparent`, `BorderThickness="1"`, `BorderBrush` set to the caret color) through a `VisualStateManager` `VisualState`, mirroring this file's `borderWidth`/`borderColor` toggle. Use a shared static event (or `WeakEventManager`) as the WinUI analog of `NotificationCenter.default.publisher(for: ComposableTabsActivePane.didChangeNotification)` for broadcasting an active-pane change to every terminal control that needs to repaint its caret — this class has no key-window handling of its own to draw an analogy from.

## Design Decisions

**Decision**: The class is declared `internal` rather than `public` or `open`.
**Rationale**: Per source: "a *public* NSView subclass would name `LocalProcessTerminalView` in the framework's generated Objective-C header, which then cannot find the Swift-only `SwiftTerm` module."
**Approved**: pending

**Decision**: `showCursor(source:)` and `cursorStyleChanged(source:newStyle:)` call only `applyOutline()`, reusing the last-computed `isHollow`, rather than calling `updateCaret()` (which would recompute `isHollow` and rewrite `caretColor`/`caretTextColor`).
**Rationale**: Per source: "Deliberately *not* on the `showCursor` path, which runs on every cursor movement: the two colours below are properties SwiftTerm holds on to, so they want writing when the answer changes rather than once a frame."
**Approved**: pending

**Decision**: SwiftTerm's caret subview is located by matching a runtime type-name suffix (`"CaretView"`) rather than a typed accessor, and the match is weakly cached.
**Rationale**: Per source: "SwiftTerm adds its caret as a direct subview but exposes no accessor for it, so it is recognized by class name... Cached, because the search is not free and the caller is not rare... a per-keystroke cost for an answer that changes when SwiftTerm rebuilds its subviews and at no other time."
**Approved**: pending

**Decision**: `main-actor-isolation` has no runtime conformance vector; it is verified by the Swift compiler's `@MainActor` isolation checking at compile time.
**Rationale**: A MUST requirement enforced entirely by the type system needs no runtime test to demonstrate — violating it is a compile error, not an outcome a test vector could observe.
**Approved**: pending

**Decision**: `ThemedTerminalView` relies on `ComposableTabsActivePane.isInActivePane` treating a view with no `ComposableTabsPaneBackgroundView` ancestor as "in the active pane" (see `agentictoolkit://recipes/composable-tabs-active-pane#requirements/view-outside-any-pane-counts-as-active`), so `marksActivePane` never hollows such a caret.
**Rationale**: The consequence for this file: a `ThemedTerminalView` used outside any composable-tabs pane with `marksActivePane == true` stays filled rather than hollow, because it is never "not in" an active pane by that dependency's own rule. The rule itself, and why it treats an unclaimed view as active, belongs to `composable-tabs-active-pane` and is not restated here.
**Approved**: pending

**Decision**: `CaretAppearance.color` and `CaretAppearance.textColor` default to the literal `NSColor.white` rather than a semantic theme-color token.
**Rationale**: No rationale is given in source for this specific choice, and no call site in this codebase overrides it with a semantic token — nothing marks it deliberate, and nothing records a plan to pay it down. It should become whichever semantic accent/foreground color token the app's theme system exposes for this purpose once one exists; see the `platform-theming` compliance status below.
**Approved**: pending
