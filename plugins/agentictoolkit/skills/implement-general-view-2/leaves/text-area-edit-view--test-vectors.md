<!-- leaf: implement-general-view-2/text-area-edit-view--test-vectors · source: text-area-edit-view.md -->

# TextAreaEditView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| text-area-edit-view-001 | initializer-parameters | Construct with only `viewModel` supplied | `visibleLines == 6` and `monospaced == false` |
| text-area-edit-view-002 | row-label-text | `viewModel.title = "Prompt"` | `label.stringValue == "Prompt"` after init |
| text-area-edit-view-003 | editor-font-role | Construct with `monospaced: true`, then trigger a theme change | `textView.font` equals the theme's `.code`-role font both immediately after construction and after the theme change |
| text-area-edit-view-004 | initial-editor-text | `viewModel.value = "hello"` | `textView.string == "hello"` after init |
| text-area-edit-view-005 | editor-theme-colors | Construct the view, then trigger a theme change | `textView.textColor`, `backgroundColor`, `insertionPointColor`, and `selectedTextAttributes` all equal the theme's corresponding colors, both immediately after construction and after the change |
| text-area-edit-view-006 | text-view-delegate | Construct the component | `textView.delegate === view` |
| text-area-edit-view-007 | plain-text-mode | Construct the component | `textView.isRichText == false` |
| text-area-edit-view-008 | undo-support | Construct the component | `textView.allowsUndo == true` |
| text-area-edit-view-009 | automatic-substitution-suppression | Construct the component | `isAutomaticQuoteSubstitutionEnabled`, `isAutomaticDashSubstitutionEnabled`, `isAutomaticTextReplacementEnabled` are all `false` |
| text-area-edit-view-010 | vertical-growth | Construct the component | `isVerticallyResizable == true`, `isHorizontallyResizable == false`, `autoresizingMask == [.width]` |
| text-area-edit-view-011 | text-wrapping | Construct the component | `textView.textContainer.widthTracksTextView == true`; `containerSize.height == .greatestFiniteMagnitude` |
| text-area-edit-view-012 | text-container-inset | Construct the component | `textView.textContainerInset == NSSize(width: 4, height: 4)` |
| text-area-edit-view-013 | scrolling-container | Construct the component | `textView.enclosingScrollView`'s `documentView === textView`, `hasVerticalScroller == true`, `borderType == .bezelBorder` |
| text-area-edit-view-014 | scroll-view-theme-background | Construct the view, then trigger a theme change | Scroll view's `drawsBackground == true` and `backgroundColor` equals the theme's `controlBackground` color both times |
| text-area-edit-view-015 | label-scroll-view-layout | Construct the component | `label` precedes the scroll view in a single vertical `NSStackView` with `spacing == 8`, pinned to the component's edges |
| text-area-edit-view-016 | visible-height | Construct with `visibleLines: 6` and a known font | Scroll view's height constraint constant equals `(lineHeight * 6).rounded() + 8`; its width constraint equals the stack's width |
| text-area-edit-view-017 | superview-width-claim | Add the component to a superview | A width constraint equal to the superview's width is active at priority `999` |
| text-area-edit-view-018 | label-resync | Invoke `viewModel.onChange(newValue)` | `label.stringValue == viewModel.title` after the call |
| text-area-edit-view-019 | self-inflicted-onchange-guard | Call `commit()` while `textView.string` differs from `settingObserver.value` | During the resulting `onChange` echo, `textView.string` is not overwritten and the caret is not moved |
| text-area-edit-view-020 | external-value-adoption | With no `commit()` in progress, externally set `viewModel`'s backing value and invoke `onChange(newValue)` where `newValue != textView.string` | `textView.string == newValue` after the call |
| text-area-edit-view-021 | caret-position-on-external-change | Make `textView` first responder, then trigger an external `onChange(newValue)` | `textView.selectedRange == NSRange(location: newValue.count, length: 0)` |
| text-area-edit-view-022 | accessibility-label | Construct with `viewModel.title = "Script"` | `textView.accessibilityLabel() == "Script"` |
| text-area-edit-view-023 | end-editing-commit | Set `textView.string = "new"` where `settingObserver.value == "old"`, then post `NSText.didEndEditingNotification` (deliver `textDidEndEditing`) | `settingObserver.value == "new"` |
| text-area-edit-view-024 | window-detachment-commit | With `textView.string` differing from `settingObserver.value`, move the component to a `nil` window | `settingObserver.value` equals `textView.string` after the move |
| text-area-edit-view-025 | teardown-notification-observers | Attach the component to a window, diverge `textView.string` from `settingObserver.value`, then post that window's `willCloseNotification` | `settingObserver.value` equals `textView.string` after the notification |
| text-area-edit-view-026 | stale-observer-deregistration | Move the component from window A to window B, then post window A's `willCloseNotification` | `commit()` is not triggered by window A's notification after the move |
| text-area-edit-view-027 | redundant-commit-guard | Wrap `settingObserver` with a write-counting observer; set `settingObserver.value = "same"` and `textView.string = "same"`; call `commit()` | The write-counting observer records zero additional writes; `settingObserver.value` remains `"same"` |
| text-area-edit-view-028 | commit-echo-guard | Wrap `settingObserver` with a write-counting observer; set `textView.string` to a value different from `settingObserver.value`; call `commit()` | The write-counting observer records exactly one write, carrying the new value |
| text-area-edit-view-029 | frame-init-rejection | Attempt `TextAreaEditView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| text-area-edit-view-030 | coder-init | Attempt `TextAreaEditView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| text-area-edit-view-031 | main-actor-confinement | Attempt to construct or mutate a `TextAreaEditView` from off the main actor | Compiler rejects the call under Swift's `@MainActor` isolation checking |
| text-area-edit-view-032 | constituent-view-exposure | Construct the component, then access `.label` and `.textView` externally | Both properties are accessible and return the instances built during init |
