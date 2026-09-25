import Foundation

/// Every billing knob, read together.
///
/// Read once per pass rather than per session: they are global values, and
/// re-reading them mid-pass let one session derive at a 15-minute cutoff and
/// the next at 60. Values live in the host's settings table, under the host's
/// ``BillingSettingsKeys``, and are read *live* — changing a knob takes effect
/// on the next pass with no restart. Text is read into values by
/// ``RawSetting``, the one set of rules every setting read shares.
public enum BillingPrefs {

    public struct Snapshot: Sendable, Equatable {
        public let idleCutoffSeconds: Int
        public let granularity: BillingGranularity
        public let defaultRateCents: Int
        public let currency: String
        public let roundingMinutes: Int
        public let roundingMode: String
        /// A manual timer left running longer than this is flagged, never
        /// truncated.
        public let manualTimerCapSeconds: Int
        public let trackUnassigned: Bool

        public init(
            idleCutoffSeconds: Int, granularity: BillingGranularity, defaultRateCents: Int,
            currency: String, roundingMinutes: Int, roundingMode: String,
            manualTimerCapSeconds: Int, trackUnassigned: Bool
        ) {
            self.idleCutoffSeconds = idleCutoffSeconds
            self.granularity = granularity
            self.defaultRateCents = defaultRateCents
            self.currency = currency
            self.roundingMinutes = roundingMinutes
            self.roundingMode = roundingMode
            self.manualTimerCapSeconds = manualTimerCapSeconds
            self.trackUnassigned = trackUnassigned
        }

        public var rollupOptions: BillingRollupOptions {
            BillingRollupOptions(
                granularity: granularity, defaultRateCents: defaultRateCents, currency: currency
            )
        }

        /// The form `billingSetPreferences` replies with — minutes and hours
        /// again, because that is what the app's controls are in.
        public var wireForm: BillingPreferencesDTO {
            BillingPreferencesDTO(
                idleCutoffMinutes: idleCutoffSeconds / 60,
                granularity: granularity.rawValue,
                roundingMinutes: roundingMinutes,
                roundingMode: roundingMode,
                defaultRateCents: defaultRateCents,
                currency: currency,
                manualTimerCapHours: manualTimerCapSeconds / 3600,
                trackUnassigned: trackUnassigned
            )
        }
    }

    /// Throws when the settings table cannot be read. A read failure used to
    /// fall back to the defaults silently, so one locked read could derive a
    /// pass at the default cutoff and price it at the default rate.
    public static func snapshot(_ database: any BillingPersistence) throws -> Snapshot {
        let keys = database.billingSettingsKeys
        func int(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) throws -> Int {
            RawSetting.int(try database.setting(for: key), default: fallback, range: range)
        }
        func string(_ key: String, _ fallback: String) throws -> String {
            RawSetting.string(try database.setting(for: key), default: fallback)
        }
        return try Snapshot(
            idleCutoffSeconds: int(
                keys.idleCutoffMinutes, BillingDefaults.idleCutoffMinutes, BillingLimits.idleCutoffMinutes
            ) * 60,
            granularity: BillingGranularity(
                rawValue: string(keys.granularity, BillingDefaults.granularity)
            ) ?? .day,
            defaultRateCents: int(
                keys.defaultRateCents, BillingDefaults.defaultRateCents, BillingLimits.defaultRateCents
            ),
            currency: string(keys.currency, BillingDefaults.currency),
            roundingMinutes: int(
                keys.roundingMinutes, BillingDefaults.roundingMinutes, BillingLimits.roundingMinutes
            ),
            roundingMode: string(keys.roundingMode, BillingDefaults.roundingMode),
            manualTimerCapSeconds: int(
                keys.manualTimerCapHours, BillingDefaults.manualTimerCapHours, BillingLimits.manualTimerCapHours
            ) * 3600,
            trackUnassigned: RawSetting.bool(
                try database.setting(for: keys.trackUnassigned), default: BillingDefaults.trackUnassigned
            )
        )
    }

    /// Writes whichever billing keys `fields` carries and returns the
    /// snapshot now in force — all in one write transaction, so a failure
    /// leaves no half-applied settings and is reported rather than swallowed.
    ///
    /// Values are stored verbatim and clamped on *read*, in `snapshot`.
    /// Clamping here as well would put the range in two places.
    ///
    /// A change to the effective idle cutoff re-derives history: every session
    /// with derived time has its watermark forgotten, so all of it is re-split
    /// at the new cutoff rather than only the sessions a pass happens to
    /// re-select.
    @discardableResult
    public static func apply(_ fields: [String: String], database: any BillingPersistence) throws -> Snapshot {
        var result: Snapshot?
        let allowed = database.billingSettingsKeys.all
        try database.transaction {
            let before = try snapshot(database)
            for (key, value) in fields where allowed.contains(key) {
                try database.setSetting(key, value)
            }
            let after = try snapshot(database)
            if after.idleCutoffSeconds != before.idleCutoffSeconds {
                try database.resetBillingDerivationOfDerivedSessions()
            }
            result = after
        }
        return try result ?? snapshot(database)
    }
}
