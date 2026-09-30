<!-- leaf: implement-general-1/font-chooser-button--test-vectors · source: font-chooser-button.md -->

# FontChooserButton

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| font-chooser-button-001 | system-placeholder | Construct `FontChooserButton()` with no further calls | `title == "System"`, `selectedFont == nil`, `font?.pointSize == FontChooserButton.sampleSize` |
| font-chooser-button-002 | rounded-momentary-bezel | Construct `FontChooserButton()` | `bezelStyle == .rounded`; the button's cell reports `.momentaryPushIn` type |
| font-chooser-button-003 | title-alignment | Construct `FontChooserButton()` | `alignment == .left` |
| font-chooser-button-004 | tail-truncation | Construct `FontChooserButton()` | `(cell as? NSButtonCell)?.lineBreakMode == .byTruncatingTail` |
| font-chooser-button-005 | compression-resistance | Construct `FontChooserButton()` | `contentCompressionResistancePriority(for: .horizontal) == .defaultLow` |
| font-chooser-button-006 | content-hugging | Construct `FontChooserButton()` | `contentHuggingPriority(for: .horizontal) == .defaultLow` |
| font-chooser-button-007 | autoresizing-mask-translation | Construct `FontChooserButton()` | `translatesAutoresizingMaskIntoConstraints == false` |
| font-chooser-button-008 | fixed-width-constraint | `FontChooserButton(width: 200)`, laid out | An active constraint pins width to exactly 200pt |
| font-chooser-button-009 | no-width-constraint | `FontChooserButton(width: nil)` and `FontChooserButton()` | Neither instance has a width constraint added by the component itself |
| font-chooser-button-010 | coder-init | Attempt `FontChooserButton(coder: someCoder)` | The call traps via `fatalError`; no instance is returned |
| font-chooser-button-011 | sample-size | `show(NSFont(name: "Menlo", size: 48), title: "Menlo — 48 pt")` | `font?.pointSize == FontChooserButton.sampleSize` and `font?.familyName == "Menlo"` |
| font-chooser-button-012 | system-font-fallback | `show(nil, title: "System")` | `font?.pointSize == FontChooserButton.sampleSize` and `font` is the system font |
| font-chooser-button-013 | selected-font-size | `show(NSFont(name: "Menlo", size: 48), title: "Menlo — 48 pt")` | `selectedFont?.pointSize == 48` (unchanged by the sample-size drawing) |
| font-chooser-button-014 | caller-supplied-title | `show(nil, title: "Custom Title")` | `title == "Custom Title"` |
| font-chooser-button-015 | font-persistence | Static/source review of `FontChooserButton.swift`: search for any `UserDefaults`, file, or theme-store write | No such call exists anywhere in the type; `show(_:title:)` only assigns `selectedFont`, `font`, and `title` |
| font-chooser-button-016 | font-panel-trigger | Simulate a click on the button | `openFontPanel(_:)` runs (observable via its side effects in font-chooser-button-017 through -019) |
| font-chooser-button-017 | font-manager-target | Trigger `openFontPanel(_:)` | `NSFontManager.shared.target === button` |
| font-chooser-button-018 | panel-seed | `show(menlo48, title:)`, then trigger `openFontPanel(_:)` | `NSFontManager.shared.selectedFont` reflects `menlo48` at its own size (48pt), not the sample size |
| font-chooser-button-019 | panel-order-front | Trigger `openFontPanel(_:)` with an injected/spied stand-in for `NSFontManager.shared` | `orderFrontFontPanel(_:)` is recorded as called on the font manager, rather than asserting `NSFontPanel.shared.isVisible`, which is unreliable in a headless test run |
| font-chooser-button-020 | panel-modes | Call `validModesForFontPanel(NSFontPanel.shared)` | Result contains `.face`, `.size`, `.collection` and none of `.shadowEffect`, `.underlineEffect`, `.strikethroughEffect`, `.textColorEffect` |
| font-chooser-button-021 | font-change-forwarding | `show(NSFont(name: "Menlo", size: 48), title:)`, trigger `openFontPanel(_:)`, then `NSFontManager.shared.setSelectedFont(NSFont(name: "Menlo", size: 60)!, isMultiple: false)` to simulate a size change picked in the panel, then call `changeFont(NSFontManager.shared)` | `onChange` is invoked with `NSFontManager.shared.convert(menlo48)` — the button's own `selectedFont` (Menlo at 48pt) carrying the panel's newly-picked 60pt size, not the font manager's `selectedFont` substituted directly |
| font-chooser-button-022 | nil-sender | Set `onChange` to a closure that flips a flag; call `changeFont(nil)` | The flag remains unflipped; no crash |
| font-chooser-button-023 | font-manager-target-release | Add the button to a window, set `NSFontManager.shared.target` to it, then `removeFromSuperview()` | `NSFontManager.shared.target == nil` afterward |
| font-chooser-button-024 | main-actor-confinement | Attempt to construct or mutate a `FontChooserButton` from off the main actor | The compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| font-chooser-button-025 | selected-font-access | Construct the button, call `show(font:title:)`, then read `.selectedFont` from outside the type | The property is externally readable and reflects the last `show` call; it has no externally-accessible setter |
| font-chooser-button-026 | change-callback-access | Assign a closure to `.onChange` from outside the type | The assignment compiles and the closure is the one invoked in font-chooser-button-021 |
