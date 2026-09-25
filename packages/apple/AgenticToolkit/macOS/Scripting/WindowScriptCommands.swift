import AppKit
import Foundation

// MARK: - Introspection

/// `window list` — every window this process owns.
///
/// From `NSApp.windows`, not `CGWindowListCopyWindowInfo`. A window sunk behind
/// the desktop picture by quiet presentation is absent from any CoreGraphics
/// query that passes `kCGWindowListExcludeDesktopElements`, which is exactly
/// the window an automated session most needs to see; and asking AppKit for
/// this process's own windows needs no Screen Recording grant.
@objc(ScriptWindowListCommand)
public final class ScriptWindowListCommand: ScriptWindowCommand, @unchecked Sendable {
    public override func performMain() -> Any? { Self.reply() }

    @MainActor
    static func reply() -> String {
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let windows: [[String: Any]] = NSApp.windows.map { window in
            [
                "number": window.windowNumber,
                "title": window.title,
                "class": String(describing: type(of: window)),
                "visible": window.isVisible,
                "key": window.isKeyWindow,
                "level": window.level.rawValue,
                "sunk": window.level.rawValue <= desktopLevel,
                "frame": [
                    "x": Double(window.frame.origin.x),
                    "y": Double(window.frame.origin.y),
                    "width": Double(window.frame.size.width),
                    "height": Double(window.frame.size.height)
                ]
            ]
        }
        // The host's own facts first, so the built-in keys below always win —
        // a host fact named "pid" or "windows" never shadows the real answer.
        var reply = ScriptWindows.processFacts()
        reply["pid"] = ProcessInfo.processInfo.processIdentifier
        reply["bundle_path"] = Bundle.main.bundlePath
        reply["windows"] = windows
        return ScriptJSON.string(from: reply)
    }
}

/// `accessibility ids` — every identified control in a window, plus the menu.
///
/// The menu goes with the views because a menu item has no view and so appears
/// in no view-tree walk, while being just as much a thing a script clicks.
@objc(ScriptAccessibilityIDsCommand)
public final class ScriptAccessibilityIDsCommand: ScriptWindowCommand, @unchecked Sendable {
    public override func performMain() -> Any? {
        guard let entry = requireWindow(defaultingToFirst: true) else { return nil }
        guard let window = entry.window(), window.isVisible else { return "{}" }
        var views: [[String: Any]] = []
        let windowIdentifier = window.accessibilityIdentifier()
        if !windowIdentifier.isEmpty {
            views.append([
                "id": windowIdentifier,
                "role": NSAccessibility.Role.window.rawValue,
                "title": window.title,
                "enabled": true,
                "frame": ScriptJSON.frame(window.frame)
            ])
        }
        if let content = window.contentView {
            ScriptAccessibilityIDsCommand.collect(content, into: &views)
        }
        return ScriptJSON.string(from: [
            "window": entry.name,
            "views": views,
            "menu": ScriptAccessibilityIDsCommand.menuItems()
        ])
    }

    /// Depth-first, so the order a reader sees matches the order the controls
    /// are laid out in.
    @MainActor
    private static func collect(_ view: NSView, into views: inout [[String: Any]]) {
        let identifier = view.accessibilityIdentifier()
        if !identifier.isEmpty {
            var entry: [String: Any] = [
                "id": identifier,
                "role": view.accessibilityRole()?.rawValue ?? String(describing: type(of: view)),
                "enabled": (view as? NSControl)?.isEnabled ?? true,
                "hidden": view.isHiddenOrHasHiddenAncestor,
                "frame": ScriptJSON.frame(view.frame)
            ]
            if let title = view.accessibilityTitle(), !title.isEmpty { entry["title"] = title }
            if let value = displayValue(of: view) { entry["value"] = value }
            views.append(entry)
        }
        for subview in view.subviews {
            collect(subview, into: &views)
        }
    }

    /// What the control is showing, read from the control rather than from the
    /// accessibility layer, which answers `Any?` and would put a stringified
    /// `Optional(...)` in the JSON for anything it did not recognise.
    ///
    /// Ordered most-specific first: `NSPopUpButton` is an `NSButton`, and a
    /// popup's value is the item it has selected, not its own title.
    @MainActor
    private static func displayValue(of view: NSView) -> String? {
        if let popup = view as? NSPopUpButton { return popup.titleOfSelectedItem }
        if let field = view as? NSTextField { return field.stringValue }
        if let button = view as? NSButton { return button.title }
        return nil
    }

    /// Every item in the main menu that carries an identifier, submenus
    /// included. Separators have none and so drop out on their own.
    @MainActor
    private static func menuItems() -> [[String: Any]] {
        guard let mainMenu = NSApp.mainMenu else { return [] }
        var result: [[String: Any]] = []
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                let identifier = item.accessibilityIdentifier()
                if !identifier.isEmpty {
                    result.append([
                        "id": identifier,
                        "title": item.title,
                        "enabled": item.isEnabled
                    ])
                }
                if let submenu = item.submenu { walk(submenu) }
            }
        }
        walk(mainMenu)
        return result
    }
}

/// `screenshot window` — a PNG of one of this process's own windows.
@objc(ScriptScreenshotWindowCommand)
public final class ScriptScreenshotWindowCommand: ScriptWindowCommand, @unchecked Sendable {
    public override func performMain() -> Any? {
        guard let entry = requireWindow() else { return nil }
        guard let window = entry.window(), window.isVisible else { return "" }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = Self.destination(
            windowName: entry.name,
            processName: ScriptWindows.screenshotPrefix,
            stamp: stamp
        )
        // The empty string rather than a path, on failure: a caller handed a
        // path assumes a file is there.
        guard WindowScreenshot.writePNG(of: window, to: url) else { return "" }
        return url.path
    }

    /// `/tmp/<prefix>-<window>-<stamp>.png`. `processName` is the prefix
    /// (`ScriptWindows.screenshotPrefix` at the call site), lowercased with
    /// spaces as hyphens so the path needs no quoting.
    static func destination(windowName: String, processName: String, stamp: String) -> URL {
        let process = processName.lowercased().replacingOccurrences(of: " ", with: "-")
        return URL(fileURLWithPath: "/tmp/\(process)-\(windowName)-\(stamp).png")
    }
}

// MARK: - Windows

/// `open window` — put a named window on screen.
@objc(ScriptOpenWindowCommand)
public final class ScriptOpenWindowCommand: ScriptWindowCommand, @unchecked Sendable {
    public override func performMain() -> Any? {
        guard let entry = requireWindow() else { return nil }
        entry.present()
        guard let window = entry.window() else {
            fail(NSInternalScriptError, "The \(entry.name) window has not been built.")
            return false
        }
        return window.isVisible
    }
}

/// `close window` — take a named window off screen.
///
/// Closing a host's last window can quit the app, if that host's own
/// `applicationShouldTerminateAfterLastWindowClosed` says so. A script that
/// wants the window gone but the app alive should open another window first.
@objc(ScriptCloseWindowCommand)
public final class ScriptCloseWindowCommand: ScriptWindowCommand, @unchecked Sendable {
    public override func performMain() -> Any? {
        guard let entry = requireWindow() else { return nil }
        guard let window = entry.window() else { return true }
        window.close()
        return !window.isVisible
    }
}
