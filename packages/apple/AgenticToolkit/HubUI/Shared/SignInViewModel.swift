import AgenticToolkitHubService
import Foundation

/// Platform-independent state machine behind both sign-in screens (spec §5.2).
/// The view controllers render `state` and call the intent methods; every
/// transition is unit-tested here so the view layers stay dumb.
@MainActor
public final class SignInViewModel {
    public enum Mode: Equatable, Sendable {
        case credentials
        case mfa(MfaChallengeInfo)
    }

    public struct State: Equatable, Sendable {
        /// Platform-independent model for the MFA method menu/popup. UIKit's
        /// `UIButton.menu` throws `NSInternalInconsistencyException` if
        /// `changesSelectionAsPrimaryAction` is true and the menu has no element
        /// it can select by default, so this guarantees exactly one selected item
        /// whenever `items` is non-empty — and an empty `items` is the signal to
        /// the view that it must not offer a selection menu at all.
        public struct MethodMenu: Equatable, Sendable {
            public struct Item: Equatable, Sendable {
                public var method: MfaChallengeMethod
                public var title: String
                public var isSelected: Bool
            }

            public var items: [Item]
            public var title: String
        }

        public var mode: Mode = .credentials
        public var email = ""
        public var password = ""
        public var selectedMethod: MfaChallengeMethod?
        public var code = ""
        public var isBusy = false
        public var errorMessage: String?
        public var infoMessage: String?

        public var availableMethods: [MfaChallengeMethod] {
            if case .mfa(let challenge) = mode { return challenge.methods }
            return []
        }

        /// Exactly one item is selected whenever `items` is non-empty: the one
        /// matching `selectedMethod` when it is present in `availableMethods`,
        /// otherwise the first item (mirrors the fallback in
        /// `submitCredentials()` below).
        public var methodMenu: MethodMenu {
            let methods = availableMethods
            let selected: MfaChallengeMethod?
            if let selectedMethod, methods.contains(selectedMethod) {
                selected = selectedMethod
            } else {
                selected = methods.first
            }
            let items = methods.map { method in
                MethodMenu.Item(method: method, title: method.label, isSelected: method == selected)
            }
            return MethodMenu(items: items, title: selected?.label ?? "Method")
        }

        public var canSubmitCredentials: Bool {
            !isBusy && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
        }

        public var showsCodeField: Bool {
            switch selectedMethod {
            case .sms, .totp, .recovery: true
            case .webauthn, nil: false
            }
        }

        public var showsSendCode: Bool { selectedMethod == .sms }
        public var showsUsePasskey: Bool { selectedMethod == .webauthn }

        public var canSubmitCode: Bool {
            !isBusy && showsCodeField && !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        public init() {}
    }

    public static let socialProviders: [SocialProvider] = SocialProvider.allCases
    public static let codeSentMessage = "Code sent."
    public static let passkeyNeedsEmailMessage = "Enter your email to use a passkey."

    public private(set) var state = State() {
        didSet { if state != oldValue { onChange(state) } }
    }

    public var onChange: @MainActor (State) -> Void = { _ in }
    public var onSignedIn: @MainActor (HubUser) -> Void = { _ in }

    private let session: SessionController
    private let passkeys: any PasskeyAssertionProvider
    private let social: any SocialSignInProvider

    public init(session: SessionController, passkeys: any PasskeyAssertionProvider, social: any SocialSignInProvider) {
        self.session = session
        self.passkeys = passkeys
        self.social = social
    }

    // MARK: Field edits

    public func setEmail(_ value: String) { state.email = value }
    public func setPassword(_ value: String) { state.password = value }
    public func setCode(_ value: String) { state.code = value }

    public func selectMethod(_ method: MfaChallengeMethod) {
        guard state.availableMethods.contains(method) else { return }
        state.selectedMethod = method
        state.code = ""
        state.errorMessage = nil
        state.infoMessage = nil
    }

    public func cancelMfa() {
        state.mode = .credentials
        state.selectedMethod = nil
        state.code = ""
        state.errorMessage = nil
        state.infoMessage = nil
    }

    // MARK: Intents

    public func submitCredentials() async {
        guard state.canSubmitCredentials else { return }
        let email = state.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = state.password
        await run {
            switch try await session.signIn(email: email, password: password) {
            case .done(let user):
                onSignedIn(user)
            case .mfa(let challenge):
                state.mode = .mfa(challenge)
                state.selectedMethod = challenge.methods.first
                state.password = ""
                state.code = ""
            }
        }
    }

    public func submitCode() async {
        guard state.canSubmitCode, case .mfa(let challenge) = state.mode, let method = state.selectedMethod else {
            return
        }
        let code = state.code.trimmingCharacters(in: .whitespacesAndNewlines)
        await run {
            let user = try await session.completeMfa(challenge: challenge, method: method, code: code)
            onSignedIn(user)
        }
    }

    public func sendCode() async {
        guard !state.isBusy, case .mfa(let challenge) = state.mode, state.showsSendCode else { return }
        await run {
            try await session.sendMfaSms(challenge: challenge)
            state.infoMessage = Self.codeSentMessage
        }
    }

    public func usePasskey() async {
        guard !state.isBusy else { return }
        switch state.mode {
        case .credentials:
            let identifier = state.email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty else {
                state.errorMessage = Self.passkeyNeedsEmailMessage
                return
            }
            await run {
                let user = try await session.signInWithPasskey(identifier: identifier, provider: passkeys)
                onSignedIn(user)
            }
        case .mfa(let challenge):
            await run {
                let user = try await session.completeMfaWithPasskey(challenge: challenge, provider: passkeys)
                onSignedIn(user)
            }
        }
    }

    public func signInWithSocial(_ provider: SocialProvider) async {
        guard !state.isBusy else { return }
        await run {
            let user = try await session.signInWithSocial(provider, using: social)
            onSignedIn(user)
        }
    }

    // MARK: Private

    /// Wraps one async intent: busy flag on, messages cleared, errors mapped.
    /// A `CancellationError` (the user dismissed a passkey or web sheet) is
    /// silent by design — nothing went wrong that the user does not know about.
    private func run(_ body: () async throws -> Void) async {
        state.isBusy = true
        state.errorMessage = nil
        state.infoMessage = nil
        defer { state.isBusy = false }
        do {
            try await body()
        } catch is CancellationError {
            return
        } catch {
            state.errorMessage = SessionController.userMessage(for: error)
        }
    }
}
