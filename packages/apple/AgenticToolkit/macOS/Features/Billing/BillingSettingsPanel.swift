import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// Settings → Billing: the eight knobs `BillingPrefs` reads, stored under the
/// keys of the ``BillingUserSettings`` the host app hands it.
///
/// Four cards rather than one list, because the groups answer different
/// questions — what counts as work, how it is chopped into billables, what it
/// is worth, and what to warn about.
@MainActor
public final class BillingSettingsPanel: ComposableSettings.SettingsPanelViewController {

    /// The two rounding modes, in one place: the project pane (Task 19)
    /// offers the same list for its per-project override.
    public static let roundingModeChoices: [ComposableSettings.ChoiceViewModel<String>.Choice] = [
        .init(label: "Round Up", value: "up"),
        .init(label: "Round to Nearest", value: "nearest")
    ]

    /// Kept so the rate row can be driven from a test and refreshed when the
    /// currency changes under it.
    public private(set) var rateField: ComposableSettings.MoneyFieldView?
    private var currencyField: ComposableSettings.TextEditView?
    private var currencyObserver: UserSettingObserver<String>?
    private let settings: BillingUserSettings

    public init(settings: BillingUserSettings) {
        self.settings = settings
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "Billing",
            icon: NSImage(systemSymbolName: "clock.badge.checkmark", accessibilityDescription: nil)
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override var searchKeywords: [String] {
        ["billing", "rate", "rounding", "timer", "invoice", "client", "project", "currency"]
    }

    public override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Tracked Time",
                body: "Session activity is turned into runs of work. A gap longer than the "
                    + "idle cutoff ends a run; the time inside a run is what gets billed. "
                    + "Nothing is inferred about time spent away from the computer."
            ),
            .init(
                title: "Rounding",
                body: "Each billable is rounded once, when it is written — not per run and "
                    + "again per day. Round up is the common billing convention; round to "
                    + "nearest is there for the increments where it isn't. Each project "
                    + "rounds its own way: the values here are only where a new project "
                    + "starts, and changing them leaves existing projects as they are."
            ),
            .init(
                title: "Rates",
                body: "A rate is looked up branch first, then repo, then project, then this "
                    + "default. The rate in force is copied onto each billable, so changing "
                    + "it here never rewrites what you have already recorded."
            )
        ])
    }

    /// What Round To and Rounding really do. Each project carries its own
    /// rounding and the daemon rounds by that alone, so these two only seed
    /// the projects created after them — the pane has to say so, or a change
    /// here reads as a change to every billable.
    public static let roundingSeedsNewProjects =
        "Where new projects start. Existing projects keep their own rounding."

    public override func viewDidLoad() {
        super.viewDidLoad()

        let tracking = ComposableSettings.GroupView(withTitle: "Tracked Time")
        tracking.addSettingSubview(ComposableSettings.IntegerFieldView(
            viewModel: ComposableSettings.RangeViewModel<Int>(
                title: "Idle Cutoff (minutes)",
                setting: settings.idleCutoffMinutes,
                minValue: BillingLimits.idleCutoffMinutes.lowerBound,
                maxValue: BillingLimits.idleCutoffMinutes.upperBound,
                explanation: "A gap longer than this ends a run of work."
            )
        ))
        tracking.addSettingSubview(ComposableSettings.CheckboxView(
            with: ComposableSettings.ViewModel<Bool>(
                title: "Track Unassigned Repositories",
                setting: settings.trackUnassigned,
                explanation: "Record activity in repositories no project claims, so it can "
                    + "be assigned later instead of being lost."
            )
        ))
        addGroup(tracking)

        let billables = ComposableSettings.GroupView(withTitle: "Billables")
        billables.addSettingSubview(ComposableSettings.PopupMenuChoiceView(
            viewModel: ComposableSettings.ChoiceViewModel<String>(
                title: "Group Time By",
                setting: settings.granularity,
                choices: [
                    .init(label: "Day", value: "day"),
                    .init(label: "Timer Run", value: "run")
                ],
                explanation: "One billable per project per day, or one per run."
            )
        ))
        billables.addSettingSubview(ComposableSettings.IntegerFieldView(
            viewModel: ComposableSettings.RangeViewModel<Int>(
                title: "Round To (minutes)",
                setting: settings.roundingMinutes,
                minValue: BillingLimits.roundingMinutes.lowerBound,
                maxValue: BillingLimits.roundingMinutes.upperBound
            )
        ))
        billables.addSettingSubview(ComposableSettings.PopupMenuChoiceView(
            viewModel: ComposableSettings.ChoiceViewModel<String>(
                title: "Rounding",
                setting: settings.roundingMode,
                choices: Self.roundingModeChoices,
                explanation: Self.roundingSeedsNewProjects
            )
        ))
        addGroup(billables)

        let rates = ComposableSettings.GroupView(withTitle: "Rates")
        let settings = self.settings
        // The same rule as every other rate field: an amount the daemon bills.
        // Anything else leaves the stored rate where it was, and the field
        // re-reads it.
        let rateField = ComposableSettings.MoneyFieldView(
            title: "Default Rate (per hour)",
            range: BillingLimits.defaultRateCents,
            formatter: { MoneyFormatter(currency: settings.currency.value) },
            get: { settings.defaultRateCents.value },
            set: { cents in if let cents { settings.defaultRateCents.value = cents } },
            explanation: "Used when no branch, repository or project names a rate."
        )
        self.rateField = rateField
        rates.addSettingSubview(rateField)
        let currencyField = ComposableSettings.TextEditView(
            with: ComposableSettings.ViewModel<String>(
                title: "Currency",
                get: { settings.currency.value },
                set: { text in
                    guard let code = CurrencyCode.normalized(text) else { return }
                    settings.currency.value = code
                },
                explanation: "Three-letter code, e.g. USD, GBP, EUR."
            )
        )
        self.currencyField = currencyField
        rates.addSettingSubview(currencyField)
        addGroup(rates)

        let safety = ComposableSettings.GroupView(withTitle: "Running Timers")
        safety.addSettingSubview(ComposableSettings.IntegerFieldView(
            viewModel: ComposableSettings.RangeViewModel<Int>(
                title: "Flag Timers Over (hours)",
                setting: settings.manualTimerCapHours,
                minValue: BillingLimits.manualTimerCapHours.lowerBound,
                maxValue: BillingLimits.manualTimerCapHours.upperBound,
                explanation: "A timer left running longer than this is flagged in Billing "
                    + "Activity. It is never stopped or shortened for you."
            )
        ))
        addGroup(safety)

        // A currency change re-renders the rate in the new locale's format.
        currencyObserver = UserSettingObserver(settings.currency) { [weak self] _ in
            MainActor.assumeIsolated { self?.rateField?.refresh() }
        }
    }

    private var rateFormatter: MoneyFormatter {
        MoneyFormatter(currency: settings.currency.value)
    }

    // MARK: - Test seams

    /// Recomputed from the model rather than read off the live `NSTextField`:
    /// the field's own displayed text only catches up with an externally
    /// changed setting on the next main-queue turn (`UserSettingObserver`
    /// hops queues deliberately — see its init), which a synchronous test
    /// never reaches. Reading through the same formatter the field renders
    /// with reports what it *will* show without depending on that turn.
    public var rateFieldText: String {
        guard rateField != nil else { return "" }
        return rateFormatter.editableString(cents: settings.defaultRateCents.value)
    }

    /// Types into the rate field the way a person does — set the text, then
    /// send the field's action, which is what commits it.
    public func setRateFieldText(_ text: String) {
        guard let field = rateField?.textField else { return }
        field.stringValue = text
        field.sendAction(field.action, to: field.target)
    }

    /// Types into the currency field and commits it, as `setRateFieldText` does.
    public func setCurrencyFieldText(_ text: String) {
        guard let field = currencyField?.textField else { return }
        field.stringValue = text
        field.sendAction(field.action, to: field.target)
    }
}
