import Foundation

extension HubError {
    /// Modules call data sources that may throw anything; the rail only ever shows `HubError`.
    public static func wrap(_ error: any Error) -> HubError {
        if let hubError = error as? HubError { return hubError }
        return .unexpected(String(describing: error))
    }

    /// Closure form: `let x = try await HubError.wrap { try await dataSource.list() }`.
    public static func wrap<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch { throw wrap(error) }
    }
}
