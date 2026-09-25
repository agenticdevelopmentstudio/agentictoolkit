import Foundation

/// Spins the main actor until `condition` is true or `timeout` elapses.
/// Used wherever production code hops work onto the main actor with a
/// detached `Task` (transport observers, expiry callbacks).
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
