import Foundation
import AgenticToolkitCore

/// The contract a `ComposableSettings.ViewModel` needs from its storage: read a
/// value, write a value, hear about changes. `UserSettingObserver` was that
/// contract's only implementation for as long as every settings row was backed
/// by `UserDefaults`; a row can equally be backed by a database or a remote
/// service, so the dependency is inverted here rather than duplicating thirty
/// row views.
///
/// `@MainActor`, because `UserSettingObserver` already is
/// (`Core/SettingStorage/UserSetting.swift:46`) and under Swift 6 strict
/// concurrency an actor-isolated `var value` cannot satisfy a nonisolated
/// protocol requirement — the conformance below would not compile. Every
/// implementor and every holder is a view or a view model, all of which are
/// main-actor already, so this costs nothing and states what was true anyway.
@MainActor
public protocol SettingObserving<Value>: AnyObject {
    associatedtype Value

    var value: Value { get set }
    var onChange: ((_ newValue: Value) -> Void)? { get set }
}

extension UserSettingObserver: SettingObserving {}

/// A `SettingObserving` over an arbitrary get/set pair — a row bound to a
/// database record, an in-memory draft, or any other store.
///
/// `onChange` is delivered on the next main-queue turn, *after* the setter has
/// run, for the same reason `UserSettingObserver` hops queues: views re-read
/// `viewModel.value` from the callback instead of trusting the parameter, and
/// firing inline would hand them the pre-write value. The main *dispatch queue*
/// specifically — `RunLoop.main` enqueues in `.default` mode only and would
/// stall for the whole of a mouse-down.
@MainActor
public final class ClosureSettingObserver<Value>: SettingObserving {

    private let getter: () -> Value
    private let setter: (Value) -> Void

    /// Called on the main queue after each write through `value`.
    public var onChange: ((_ newValue: Value) -> Void)?

    /// An observer reading through `get`, writing through `set`.
    public init(
        get: @escaping () -> Value,
        set: @escaping (Value) -> Void,
        onChange: ((_ newValue: Value) -> Void)? = nil
    ) {
        self.getter = get
        self.setter = set
        self.onChange = onChange
    }

    /// Reads through `get`; a write goes through `set` and then reports `onChange`.
    public var value: Value {
        get { getter() }
        set {
            setter(newValue)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onChange?(newValue) }
            }
        }
    }
}
