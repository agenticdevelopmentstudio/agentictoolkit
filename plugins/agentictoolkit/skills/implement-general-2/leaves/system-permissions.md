<!-- leaf: implement-general-2/system-permissions · source: system-permissions.md -->

# SystemPermissions

## Overview

SystemPermissions is the Foundation-level (AppKit-free, daemon-linkable) permissions layer of AgenticToolkit. It consists of:

- `Permission` — an enum of the macOS privacy grants a host app may need (`accessibility`, `notifications`, `automation(targetBundleID:)`, `location`, `microphone`, `screenCapture`, `keychain(service:)`) with per-case metadata: `displayName`, `identifierToken`, `systemImageName`, `explanation`, `settingsPaneURL`, `actionTitle`.
- `PermissionStatus` — the tri-state result `granted` / `denied` / `undetermined`.
- `PermissionChecking` — the protocol with `status(_:)` (never prompts) and `request(_:)` (surfaces the system flow), plus the `isGranted(_:)` convenience.
- `SystemPermissionChecker` — the production conformance over the real macOS APIs, with the Apple Events probe injected through `AutomationProbing` (`SystemAutomationProbe` in production).
- `KeychainPermissionLedger` — a `UserDefaults`-backed record of what the app last learned about reading a given keychain item, because macOS offers no way to ask.

Use it wherever an app or daemon has to show or obtain a privacy grant; the UI that renders it lives in PermissionRowView and PermissionsPanelView.

