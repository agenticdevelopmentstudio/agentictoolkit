import AgenticToolkitHubService
import AgenticToolkitHub
import Foundation

/// The registration seam between the shell (Plan 2) and the feature modules (Plans 4 and 5).
/// Each feature registers a factory that builds its toolkit module around app adapters for the
/// selected workspace. `registeredIDs` lists the ids this build wires, in rail order, so a test can
/// assert nothing is silently missing.
public enum FeatureModules {
    public static let registeredIDs: [String] = ["personas", "ecosystems", "authentication"]

    @MainActor
    public static func registerAll(in registry: FeatureModuleRegistry, environment: HubEnvironment) {
        registry.register(id: "personas") { workspace in
            PersonasModule(dataSource: PersonasAdapter(environment: environment, workspace: workspace))
        }
        registry.register(id: "ecosystems") { workspace in
            EcosystemsModule(dataSource: EcosystemsAdapter(environment: environment, workspace: workspace),
                             topics: productTopics(environment: environment, workspace: workspace))
        }
        registry.register(id: "authentication") { workspace in
            AuthenticationModule(apiTokens: ApiTokensAdapter(environment: environment, workspace: workspace),
                                 storageTokens: StorageTokensAdapter(environment: environment, workspace: workspace))
        }
    }

    /// The per-product topic rail, in the order the spec lists (settings, children, then the grouped topics).
    /// Plan 5 appends its `gamification` and `game` providers to the end of this array.
    @MainActor
    public static func productTopics(
        environment: HubEnvironment, workspace: HubWorkspace
    ) -> [any EcosystemTopicProvider] {
        let ecosystems = EcosystemsAdapter(environment: environment, workspace: workspace)
        let buckets = BucketsAdapter(environment: environment, workspace: workspace)
        let invitations = InvitationsAdapter(environment: environment, workspace: workspace)

        let storage = EcosystemTopicGroup(id: "storage", label: "Storage", systemImage: "internaldrive", children: [
            BucketsTopic(dataSource: buckets),
            AccessListsTopic(
                dataSource: BucketAccessAdapter(environment: environment, workspace: workspace), buckets: buckets
            ),
            EcosystemNoticeTopic(
                entry: EcosystemTopicEntry(id: "all-data", label: "All Data", systemImage: "tablecells",
                                           description: "Browse and edit the raw rows behind every bucket.",
                                           leadsTo: .detail),
                message: FormDetails.unavailableMessage)
        ])
        let users = EcosystemTopicGroup(id: "invitations", label: "Users", systemImage: "person.2", children: [
            CustomersTopic(dataSource: CustomersAdapter(environment: environment, workspace: workspace)),
            RequestsTopic(dataSource: invitations),
            PendingUsersTopic(dataSource: invitations),
            InvitesTopic(dataSource: invitations)
        ])
        let authentication = EcosystemTopicGroup(
            id: "authentication", label: "Authentication", systemImage: "person.badge.key",
            children: [
                AuthSettingsTopic(dataSource: AuthSettingsAdapter(environment: environment, workspace: workspace)),
                SigninAppsTopic(dataSource: SigninAppsAdapter(environment: environment, workspace: workspace)),
                EcosystemNoticeTopic(
                    entry: EcosystemTopicEntry(
                        id: "email-signup", label: "Email Signup", systemImage: "envelope.badge",
                        description: "Waitlists and campaigns for people signing up before they can get in.",
                        leadsTo: .detail),
                    message: FormDetails.unavailableMessage)
            ])
        let config = EcosystemTopicGroup(id: "config", label: "Configuration", systemImage: "gearshape.2",
                                         children: [
            FeatureFlagsTopic(dataSource: FeatureFlagsAdapter(environment: environment, workspace: workspace)),
            ServerBagsTopic(dataSource: ServerBagsAdapter(environment: environment, workspace: workspace)),
            StorageTokensTopic(dataSource: StorageTokensAdapter(environment: environment, workspace: workspace)),
            EcosystemNoticeTopic(
                entry: EcosystemTopicEntry(id: "billing", label: "Billing", systemImage: "creditcard",
                                           description: "Plans and invoices for this product.", leadsTo: .detail),
                message: FormDetails.unavailableMessage)
        ])

        return [
            EcosystemSettingsTopic(dataSource: ecosystems),
            ChildEcosystemsTopic(dataSource: ecosystems),
            storage,
            users,
            authentication,
            ApplicationsTopic(
                dataSource: ApplicationsAdapter(environment: environment, workspace: workspace), buckets: buckets
            ),
            MessagingTopic(dataSource: MessagingAdapter(environment: environment, workspace: workspace)),
            config
        ]
    }
}
