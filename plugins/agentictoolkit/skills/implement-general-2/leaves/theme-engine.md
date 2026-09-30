<!-- leaf: implement-general-2/theme-engine · source: theme-engine.md -->

# Theme Engine

## Overview

This recipe covers the AgenticToolkit (ATK) half of the theme engine. The
theme model itself — `ColorTheme`, `RGBAColor`, `ThemeRole`,
`SemanticPalette`, `ThemeStore`, `ThemeStorage`, `ThemeManager` — ships from
AgenticDeveloperToolkit and is specified by
Theme Engine (ADT). ATK adds
four things on top of it, each in its own source file:

- **`SyntaxRoleOverrides.swift`** — the `SyntaxRole` vocabulary (the ten syntax
  attributes a source editor paints), the `SyntaxStyle` value (colour + bold +
  italic), and the `syntax.<role>[.bold][.italic]` key grammar that stores
  those styles inside `ColorTheme.roleOverrides`, read by
  `ColorTheme.syntaxStyles` and written by `ColorTheme.withSyntaxStyles(_:)`.
- **`VSCodeThemeImporter.swift`** — a caseless namespace that parses a VS Code
  colour-theme JSON(C) file into a `ColorTheme`: palette, appearance, six
  semantic role overrides, `tokenColors`-derived syntax styles, and `include`
  chain resolution with a containment root and a depth bound. It also adds
  `ThemeStore.importVSCodeTheme(contentsOf:label:uiTheme:)`, which stores the
  result as a locked imported theme.
- **`UserSettingsThemeStorage.swift`** — the `ThemeStorage` conformer that
  persists custom themes and the active theme id through ATK's `UserSettings`
  under the historical keys, plus the zero-argument `ThemeStore()`.
- **`ThemeManager+UserSettings.swift`** (macOS) — the zero-argument
  `ThemeManager()` wiring that storage to an `AppKitAppearanceDriver`.

Use it when a host needs VS Code themes, per-role syntax colours that travel
with a theme, or the theme store persisted in `UserSettings`. It has no
visual surface.

