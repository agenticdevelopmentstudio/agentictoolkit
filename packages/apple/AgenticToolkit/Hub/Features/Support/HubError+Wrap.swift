import Foundation

extension HubError {
    /// Modules call data sources that may throw anything; the rail only ever shows `HubError`.
    public static func wrap(_ error: any Error) -> HubError {
        if let hubError = error as? HubError { return hubError }
        return .unexpected(String(describing: error))
    }

    /// Closure form: `let x = try await HubError.wrap { try await dataSource.list() }`. The `isolation`
    /// parameter is defaulted via `#isolation` so the closure keeps the caller's actor isolation instead
    /// of being forced `nonisolated` — a `@MainActor` caller whose closure captures `self` still compiles
    /// under Swift 6 strict concurrency without hoisting reads out or wrapping writes in `MainActor.run`.
    public static func wrap<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async throws -> T {
        do { return try await body() } catch { throw wrap(error) }
    }
}
