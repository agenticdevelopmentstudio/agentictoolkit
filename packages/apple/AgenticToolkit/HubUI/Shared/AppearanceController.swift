import AgenticToolkitHubService
import AgenticDeveloperHubClient

public enum HubColorMode: String, Sendable, Equatable, CaseIterable {
    case auto, light, dark
}

/// Spec §2.1: read `/me/appearance` and apply the color mode. Only the
/// color mode has a native equivalent; the other prefs are web-only.
///
/// "Apply" is deliberately indirect. The native app's look is the *theme's* to
/// decide — a theme pinned light or dark is those colours, and forcing the
/// opposite system appearance over it puts light system chrome on a dark
/// surface. So this preference is what a theme making no claim of its own
/// (`.auto`) defers to, which is what `ThemeAppearanceDriver.autoAppearance`
/// means; the shell re-drives the theme when it changes rather than writing
/// `NSApp.appearance` behind the theme's back.
@MainActor
public final class AppearanceController {
    public private(set) var colorMode: HubColorMode = .auto {
        didSet {
            Self.current = colorMode
            if colorMode != oldValue { onChange(colorMode) }
        }
    }

    /// The mode in effect, readable without a reference to the controller.
    ///
    /// The theme's appearance driver asks "what does an `.auto` theme resolve
    /// to?" through a closure installed at launch — before any composition
    /// exists — while the controller that answers is built per session and
    /// replaced at sign-out. A static is what spans that, and there is only
    /// ever one signed-in user to hold a preference.
    public private(set) static var current: HubColorMode = .auto

    public var onChange: @MainActor (HubColorMode) -> Void = { _ in }

    private let environment: HubEnvironment

    public init(environment: HubEnvironment) {
        self.environment = environment
    }

    /// Best-effort: a failure of any kind leaves the current mode in place.
    public func refresh() async {
        do {
            switch try await environment.client.api.getMeAppearance(.init()) {
            case .ok(let response):
                colorMode = Self.mode(from: try response.body.json)
            case .unauthorized, .undocumented:
                return
            }
        } catch {
            return
        }
    }

    public func reset() {
        colorMode = .auto
    }

    public static func mode(from settings: Components.Schemas.AppearanceSettings) -> HubColorMode {
        switch settings.prefs.colorMode {
        case .light: .light
        case .dark: .dark
        case .auto, nil: .auto
        }
    }
}
