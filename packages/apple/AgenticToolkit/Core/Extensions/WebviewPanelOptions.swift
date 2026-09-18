//
//  WebviewPanelOptions.swift
//  AgenticToolkit
//

import Foundation

/// What `vscode.window.createWebviewPanel`'s options argument amounts to once
/// the defaults are applied.
///
/// Three fields out of upstream's eight, and the absences are the interesting
/// part — each of the five left out is left out for its own reason, not for a
/// shared "not yet":
///
///   * `retainContextWhenHidden` is *always* on here and cannot be turned off.
///     It asks an editor not to tear a hidden webview down; a pane in this app
///     keeps its view controller whether or not it is the visible tab, so
///     there is nothing to ask for. An option whose only honest implementation
///     is "already true" is a field nothing may read (`yagni`).
///   * `enableFindWidget` has no find widget to enable.
///   * `enableCommandUris` would let a page's `command:` links dispatch into
///     the command registry. That is a real capability with a real hole in it,
///     and it is not built: `WebviewPanelViewController`'s navigation delegate
///     cancels every scheme but its own. `MainThreadWindow` records the reach
///     in the `NotImplementedLedger` rather than carrying a flag nothing
///     honours.
///   * `portMapping` maps localhost ports for a page talking to a local
///     server. Nothing in this host serves one.
///   * `iconPath` is pane chrome, and `WebviewPanelViewController` answers its
///     pane's title, not its icon.
///
/// Immutable, because an option is what the panel was *created* with. VS Code
/// lets `webview.options` be reassigned; the one field an extension genuinely
/// re-narrows at runtime is `localResourceRoots`, and that is a settable
/// property on the panel itself (see `WebviewPanelViewController`), not a
/// second copy of this struct.
public struct WebviewPanelOptions: Equatable, Sendable {

    /// `WebviewOptions.enableScripts`. Off unless asked for, matching both
    /// upstream's default and the only safe posture: a panel that never said
    /// it runs code should not.
    public let enableScripts: Bool

    /// `WebviewOptions.enableForms` — "Defaults to true if scripts are
    /// enabled. Otherwise defaults to false."
    ///
    /// The default follows scripts rather than being independently `false`
    /// because a scripted page that cannot submit a form fails in a way its
    /// author cannot see: the click does nothing and the console says only
    /// that a content policy refused it.
    public let enableForms: Bool

    /// Exactly what the extension declared, including the difference between
    /// declaring nothing and declaring none.
    ///
    /// `nil` means the option was absent, which takes the default below.
    /// `[]` means the extension asked for no file access at all, and is
    /// honoured as written — collapsing the two would hand a panel that
    /// deliberately renounced file access the whole workspace.
    public let declaredLocalResourceRoots: [URL]?

    /// - Parameters:
    ///   - enableScripts: The option as written, or `nil` if absent.
    ///   - enableForms: The option as written, or `nil` if absent — in which
    ///     case it follows `enableScripts`.
    ///   - localResourceRoots: The option as written, or `nil` if absent.
    public init(enableScripts: Bool?, enableForms: Bool?, localResourceRoots: [URL]?) {
        let scripts = enableScripts ?? false
        self.enableScripts = scripts
        self.enableForms = enableForms ?? scripts
        self.declaredLocalResourceRoots = localResourceRoots
    }

    // MARK: - Where the panel may read from

    /// The directories this panel may load files from.
    ///
    /// The default when nothing was declared is upstream's: the extension's
    /// own installation directory, plus every open workspace folder. A preview
    /// extension renders its own stylesheet *and* the user's images, and
    /// neither alone is enough to get a Markdown preview on screen.
    ///
    /// The extension's directory comes first because it is the one root the
    /// panel certainly needs, and a reader scanning a log line should see the
    /// answer to "can it load its own assets?" first.
    ///
    /// - Parameters:
    ///   - extensionDirectory: Where the owning extension is installed.
    ///   - workspaceRoots: Every open workspace folder, or empty when no
    ///     project is open.
    public func resourceRoots(extensionDirectory: URL, workspaceRoots: [URL]) -> [URL] {
        Self.deduplicated(declaredLocalResourceRoots ?? ([extensionDirectory] + workspaceRoots))
    }

    /// Keeps the first spelling of each directory and drops every later one.
    ///
    /// Compared canonically — `ExtensionResourcePath.canonicalDirectory` is
    /// the same normalisation `WebviewResourceURL.target(of:panelID:localResourceRoots:)`
    /// applies before it decides containment, and deduplicating by any other
    /// rule would leave two entries that the check downstream reads as one.
    ///
    /// The list is short (an extension directory and a workspace folder or
    /// two), so the quadratic scan a `Set` would avoid is not worth carrying a
    /// second representation of the same list for.
    private static func deduplicated(_ roots: [URL]) -> [URL] {
        var seen: Set<String> = []
        return roots.filter { seen.insert(ExtensionResourcePath.canonicalDirectory($0).path).inserted }
    }

    // MARK: - The content policy

    /// The policy header this panel's resources are served with.
    public var contentSecurityPolicy: String {
        Self.contentSecurityPolicy(allowingForms: enableForms)
    }

    /// The floor under every webview, deliberately naming only directives no
    /// webview legitimately uses.
    ///
    /// It is tempting to send a real policy here, and wrong. A meta CSP an
    /// extension declares *intersects* with this one, so anything said about
    /// `script-src`, `style-src`, `img-src` or `connect-src` either has to be
    /// permissive enough to be theatre — `'unsafe-inline'`, which is the whole
    /// hole — or strict enough to break the extensions this stage exists to
    /// run, since an extension's own nonce is not in our policy and never can
    /// be. VS Code makes the same call: the content policy is the extension's
    /// to declare, and the containment this app provides is the custom scheme
    /// plus `localResourceRoots`, both of which hold whatever the page's CSP
    /// says.
    ///
    /// What is left is the set no webview gives up anything by losing:
    ///
    ///   * `object-src 'none'` — no plugin content.
    ///   * `base-uri 'none'` — a `<base>` element injected through whatever
    ///     the extension renders cannot re-point every relative URL in the
    ///     document at somewhere else.
    ///   * `form-action 'none'` — a form POST out of a webview is exfiltration
    ///     wearing a form; extensions talk to their host through
    ///     `postMessage`. This is the one directive an extension can ask to
    ///     have lifted, by declaring `enableForms`, and lifting it means
    ///     *omitting* it rather than widening it to `'self'`: a policy that
    ///     names a directive at all is a policy that overrides nothing the
    ///     page's own CSP says about it, and an extension that turned forms on
    ///     is entitled to decide where they go.
    ///   * `frame-ancestors 'none'` — nothing embeds a panel, and saying so
    ///     costs nothing.
    public static func contentSecurityPolicy(allowingForms: Bool) -> String {
        var directives = ["object-src 'none'", "base-uri 'none'"]
        if !allowingForms {
            directives.append("form-action 'none'")
        }
        directives.append("frame-ancestors 'none'")
        return directives.joined(separator: "; ")
    }
}
