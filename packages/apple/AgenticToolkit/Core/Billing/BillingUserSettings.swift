import Foundation

/// The eight billing knobs as live ``UserSetting``s, stored under one app's
/// ``BillingSettingsKeys``.
///
/// The billing windows and the Billing settings pane read and write these; the
/// app decides only the key prefix — and so the namespace in the settings
/// table — by building one instance from its own keys. The defaults are
/// ``BillingDefaults``, the same numbers the daemon falls back to, so the pane,
/// the wire and the deriver are one set of values rather than three.
@MainActor
public final class BillingUserSettings {

    /// The keys every setting here is stored under.
    public let keys: BillingSettingsKeys

    /// A gap longer than this ends a run. The one knob that changes what gets
    /// derived rather than how it is presented.
    public let idleCutoffMinutes: UserSetting<Int>

    /// `day` (one entry per project per day) or `run` (one per segment).
    /// Presentation only: segments are always stored whole, so this is
    /// switchable at any time with nothing lost.
    public let granularity: UserSetting<String>

    /// The increment a new project's billables are rounded to, in minutes.
    public let roundingMinutes: UserSetting<Int>

    /// `up` or `nearest`, for new projects.
    public let roundingMode: UserSetting<String>

    /// The rate used when neither the branch, the repo nor the project names
    /// one. Integer cents per hour — never a `Double`.
    public let defaultRateCents: UserSetting<Int>

    /// ISO 4217 code. Labels every amount and is copied onto new entries.
    public let currency: UserSetting<String>

    /// A manual timer running longer than this is flagged. Flagged, never
    /// truncated.
    public let manualTimerCapHours: UserSetting<Int>

    /// Whether activity in a repo no project claims is recorded as
    /// "Unassigned" rather than dropped.
    public let trackUnassigned: UserSetting<Bool>

    public init(keys: BillingSettingsKeys) {
        self.keys = keys
        idleCutoffMinutes = UserSetting(keys.idleCutoffMinutes, default: BillingDefaults.idleCutoffMinutes)
        granularity = UserSetting(keys.granularity, default: BillingDefaults.granularity)
        roundingMinutes = UserSetting(keys.roundingMinutes, default: BillingDefaults.roundingMinutes)
        roundingMode = UserSetting(keys.roundingMode, default: BillingDefaults.roundingMode)
        defaultRateCents = UserSetting(keys.defaultRateCents, default: BillingDefaults.defaultRateCents)
        currency = UserSetting(keys.currency, default: BillingDefaults.currency)
        manualTimerCapHours = UserSetting(
            keys.manualTimerCapHours, default: BillingDefaults.manualTimerCapHours
        )
        trackUnassigned = UserSetting(keys.trackUnassigned, default: BillingDefaults.trackUnassigned)
    }
}
