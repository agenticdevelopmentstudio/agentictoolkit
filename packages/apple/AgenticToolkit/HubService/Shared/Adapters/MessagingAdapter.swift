import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes

/// `MessagingDataSource` over `/messaging/…`. A failed send is HTTP 422 carrying a
/// `MessagingSendResult`; that body is returned (not thrown) so the topic can show the provider error.
@MainActor
public final class MessagingAdapter: MessagingDataSource {
    private let api: HubAPI
    private let environment: HubEnvironment
    private let workspace: HubWorkspace

    public init(environment: HubEnvironment, workspace: HubWorkspace) {
        self.api = HubAPI(environment: environment)
        self.environment = environment
        self.workspace = workspace
    }

    private func path(_ ecosystemID: String, _ rest: String) -> String {
        "/messaging/ecosystems/\(ecosystemID)/\(rest)"
    }

    public func status(ecosystemID: String) async throws -> MessagingStatus {
        try await api.get(path(ecosystemID, "status"), query: workspace.query, as: MessagingStatus.self)
    }

    public func templates() async throws -> [MessagingTemplate] {
        try await api.get("/messaging/templates", query: workspace.query, as: [MessagingTemplate].self)
    }

    public func log(ecosystemID: String, page: Int, pageSize: Int) async throws -> MessagingLogPage {
        let query = workspace.query.merging(["page": String(page), "pageSize": String(pageSize)]) { _, new in new }
        return try await api.get(path(ecosystemID, "log"), query: query, as: MessagingLogPage.self)
    }

    public func send(ecosystemID: String, _ message: MessagingSend) async throws -> MessagingSendResult {
        let sendPath = path(ecosystemID, "send")
        let body: Data
        do {
            body = try HubAPI.encoder.encode(message)
        } catch {
            throw HubError.unexpected("Unencodable request for POST \(sendPath): \(error)")
        }
        do {
            let response = try await environment.client.rawJSON(
                method: .post, path: sendPath, query: workspace.query, body: body
            )
            return try response.decode(MessagingSendResult.self)
        } catch RawRequestError.http(let status, let data) where status == 422 {
            // The provider refused the message: the body is a result, not a validation problem.
            if let result = try? JSONDecoder.adhDefault.decode(MessagingSendResult.self, from: data) { return result }
            throw HubError.fromStatus(status, body: data)
        } catch let error as DecodingError {
            throw HubError.unexpected("Unreadable response for POST \(sendPath): \(error)")
        } catch {
            throw HubError.from(error)
        }
    }
}
