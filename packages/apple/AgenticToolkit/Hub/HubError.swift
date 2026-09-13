import Foundation

/// The single error type feature modules surface to the UI. Adapters in the app map transport/API failures
/// into these cases; views show `message`.
public enum HubError: Error, Sendable, Equatable {
    case unauthorized
    case forbidden
    case notFound
    case offline
    case conflict(String)
    case validation(String)
    case transport(String)
    case unexpected(String)

    public var message: String {
        switch self {
        case .unauthorized: "You need to sign in again."
        case .forbidden: "You don't have permission to do that."
        case .notFound: "That item no longer exists."
        case .offline: "The hub can't be reached right now."
        case .conflict(let detail): detail
        case .validation(let detail): detail
        case .transport(let detail): "Connection problem: \(detail)"
        case .unexpected(let detail): "Something went wrong: \(detail)"
        }
    }
}

extension HubError: LocalizedError {
    public var errorDescription: String? { message }
}
