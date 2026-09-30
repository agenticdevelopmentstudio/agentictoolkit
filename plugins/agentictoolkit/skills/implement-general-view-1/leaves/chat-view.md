<!-- leaf: implement-general-view-1/chat-view · source: chat-view.md -->

# ChatView

## Overview

`ChatView` is a macOS, AppKit `NSView` subclass (`NSTextFieldDelegate`) that combines a scrollable message transcript — with per-day banners and an animated typing indicator — with a footer holding an optional status line, an optional composer prompt, a text-entry composer field, and a send button. It is driven by an injected `AIChatViewModel`, which publishes the message list and session state; the view coalesces those updates into batched, equality-guarded transcript rebuilds, preserves the reader's scroll position and any messages they have opened out ("expanded") across a rebuild, and — when `isRowSelectionEnabled` is turned on for a merged, multi-conversation feed — supports keyboard-driven row selection, expansion, and navigation back to a row's originating conversation.

