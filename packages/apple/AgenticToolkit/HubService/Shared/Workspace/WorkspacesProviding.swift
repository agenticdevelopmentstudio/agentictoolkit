import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes

public protocol WorkspacesProviding: Sendable {
    func listWorkspaces() async throws -> [HubWorkspace]
    func preferredSlug() async throws -> String?
    func setPreferredSlug(_ slug: String) async throws
}

/// `GET /workspaces` through the generated client; `/me/workspace-prefs`
/// through `rawJSON` because the OpenAPI document does not describe it
/// (spec §7.2). Errors surface as `HubError`.
@MainActor
public final class WorkspacesAdapter: WorkspacesProviding {
    private struct PrefsEnvelope: Decodable {
        struct Prefs: Decodable { let slug: String? }
        let prefs: Prefs
    }

    private let environment: HubEnvironment

    public init(environment: HubEnvironment) {
        self.environment = environment
    }

    public func listWorkspaces() async throws -> [HubWorkspace] {
        do {
            switch try await environment.client.api.getWorkspaces(.init()) {
            case .ok(let response):
                return try response.body.json.map { generated in
                    HubWorkspace(
                        slug: generated.slug,
                        name: generated.name,
                        type: HubWorkspaceType(rawValue: generated._type.rawValue) ?? .individual
                    )
                }
            case .unauthorized:
                throw HubError.unauthorized
            case .undocumented(let status, _):
                throw HubError.fromStatus(status, body: Data())
            }
        } catch {
            throw HubError.from(error)
        }
    }

    public func preferredSlug() async throws -> String? {
        do {
            let response = try await environment.client.rawJSON(method: .get, path: "/me/workspace-prefs")
            let slug = try response.decode(PrefsEnvelope.self).prefs.slug
            return (slug?.isEmpty ?? true) ? nil : slug
        } catch {
            throw HubError.from(error)
        }
    }

    public func setPreferredSlug(_ slug: String) async throws {
        do {
            let body = try JSONEncoder().encode(["slug": slug])
            _ = try await environment.client.rawJSON(method: .put, path: "/me/workspace-prefs", body: body)
        } catch {
            throw HubError.from(error)
        }
    }
}
