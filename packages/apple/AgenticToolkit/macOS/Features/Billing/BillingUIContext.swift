import Foundation
import AgenticToolkitCore

/// Everything the billing windows and the Billing settings pane need from the
/// app that hosts them: the model they are views of and the settings they read
/// their defaults from.
///
/// Injected, never looked up. The windows are the toolkit's, so they cannot
/// know which daemon the app talks to or which namespace it keeps its settings
/// in; the app builds one of these from its own service and keys and hands it
/// to each window it opens.
@MainActor
public struct BillingUIContext {
    /// The model every billing window is a consumer of.
    public let model: BillingModel
    /// The eight billing knobs, under the app's keys.
    public let settings: BillingUserSettings

    public init(model: BillingModel, settings: BillingUserSettings) {
        self.model = model
        self.settings = settings
    }
}
