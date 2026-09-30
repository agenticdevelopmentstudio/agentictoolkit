import CoreGraphics

public enum DisplayError: Error, Equatable, Sendable {
    case configurationFailed(step: String, code: Int32)
    case displayNotFound(CGDirectDisplayID)
    case modeNotAvailable(ModeSpec)
    /// `arrange(origins:)` needs exactly one display at (0,0): that one becomes main.
    case noMainOrigin
}
