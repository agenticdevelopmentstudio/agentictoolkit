#if canImport(AppKit)
import AgenticToolkitHubService
import AgenticDeveloperToolkit
import AgenticDeveloperToolkitUI
import AppKit

extension NSStackView {
    /// Pins every arranged subview's leading/trailing edges to this stack
    /// view's own edges, so a `.vertical` stack's controls actually fill its
    /// width edge-to-edge.
    ///
    /// `alignment = .width` alone does **not** do this: for a vertical stack
    /// it only ties the arranged subviews' widths to one another, not to the
    /// stack view's own width. `NSTextField`'s low default horizontal
    /// content-hugging priority happens to let it stretch to whatever common
    /// width that sibling relationship settles on, but nothing forces that
    /// common width to equal the stack view's — and `NSButton`'s higher
    /// default hugging priority keeps push buttons at their intrinsic
    /// (title-driven) width regardless, so they stay short and collapse to
    /// one edge. Explicit edge constraints make every arranged subview obey
    /// the same rule, independent of its own hugging priority.
    func pinArrangedSubviewsToFullWidth() {
        for subview in arrangedSubviews {
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }
    }
}

/// AppKit sign-in screen (spec §5.2). Renders `SignInViewModel.state`; every
/// control forwards to a view-model intent. No business logic here.
public final class SignInViewController: NSViewController, NSTextFieldDelegate {
    private let viewModel: SignInViewModel

    private let emailField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let signInButton = SignInViewController.makeColumnButton(title: "Sign In", isPrimary: true)
    private let passkeyButton = SignInViewController.makeColumnButton(title: "Use Passkey")
    private var socialButtons: [NSButton] = []
    private let credentialsStack = NSStackView()

    private let mfaHeading = ThemedLabel(string: "Two-factor authentication", textRole: .heading)
    private let methodPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let codeField = NSTextField()
    private let sendCodeButton = SignInViewController.makeColumnButton(title: "Send Code")
    private let verifyButton = SignInViewController.makeColumnButton(title: "Verify", isPrimary: true)
    private let mfaPasskeyButton = SignInViewController.makeColumnButton(title: "Use Passkey")
    private let backButton = SignInViewController.makeColumnButton(title: "Back")
    private let mfaStack = NSStackView()

    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()

    /// Which role the message is currently wearing — `danger` for an error,
    /// `secondaryText` for information. It is state rather than a colour set at
    /// the point of writing because the message has to survive a palette
    /// change: the theme observer reads this, so switching themes repaints the
    /// message without waiting for the next render.
    private var messageRole: ThemeRole = .danger

    public init(viewModel: SignInViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        title = "Sign In"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Single construction path for every push button laid out in one of this
    /// screen's stacks, so the "Sign In" / "Use Passkey" / MFA buttons and the
    /// loop-created social buttons are never built two different ways.
    private static func makeColumnButton(
        title: String,
        isPrimary: Bool = false,
        target: AnyObject? = nil,
        action: Selector? = nil
    ) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        // These stay stock `NSButton`s rather than `ThemedActionButton`s
        // because two of them carry a Return key equivalent, which AppKit only
        // honours on a stock push button. Painting them from the palette is
        // what keeps the column looking like one control set anyway.
        button.observeTheme { button, palette in
            if isPrimary {
                button.applyPrimaryActionTheme(palette)
            } else {
                button.applySecondaryActionTheme(palette)
            }
        }
        return button
    }

    public override func loadView() {
        emailField.setAccessibilityIdentifier("sign-in.email")
        passwordField.setAccessibilityIdentifier("sign-in.password")
        signInButton.setAccessibilityIdentifier("sign-in.submit")
        passkeyButton.setAccessibilityIdentifier("sign-in.passkey")
        mfaHeading.setAccessibilityIdentifier("sign-in.mfa.heading")
        methodPopup.setAccessibilityIdentifier("sign-in.mfa.method")
        codeField.setAccessibilityIdentifier("sign-in.mfa.code")
        sendCodeButton.setAccessibilityIdentifier("sign-in.mfa.send-code")
        verifyButton.setAccessibilityIdentifier("sign-in.mfa.verify")
        mfaPasskeyButton.setAccessibilityIdentifier("sign-in.mfa.passkey")
        backButton.setAccessibilityIdentifier("sign-in.mfa.back")
        messageLabel.setAccessibilityIdentifier("sign-in.message")
        spinner.setAccessibilityIdentifier("sign-in.spinner")
        emailField.placeholderString = "Email"
        emailField.delegate = self
        passwordField.placeholderString = "Password"
        passwordField.delegate = self
        // The three text fields stay `NSTextField`/`NSSecureTextField` — one is
        // secure and all three are wired to this controller as delegate — so
        // they take the editable-field paint job rather than `ThemedTextField`.
        for field in [emailField, passwordField, codeField] {
            field.observeTheme { field, palette in field.applyEditableFieldTheme(palette) }
        }
        signInButton.target = self
        signInButton.action = #selector(signInTapped)
        signInButton.keyEquivalent = "\r"
        passkeyButton.target = self
        passkeyButton.action = #selector(passkeyTapped)
        socialButtons = SignInViewModel.socialProviders.map { provider in
            let button = SignInViewController.makeColumnButton(
                title: "Continue with \(provider.label)",
                target: self,
                action: #selector(socialTapped(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(provider.rawValue)
            button.setAccessibilityIdentifier("sign-in.social.\(provider.rawValue)")
            return button
        }
        credentialsStack.orientation = .vertical
        credentialsStack.spacing = 8
        credentialsStack.alignment = .width
        [emailField, passwordField, signInButton, passkeyButton].forEach(credentialsStack.addArrangedSubview)
        socialButtons.forEach(credentialsStack.addArrangedSubview)
        credentialsStack.pinArrangedSubviewsToFullWidth()

        methodPopup.target = self
        methodPopup.action = #selector(methodChanged)
        codeField.placeholderString = "Code"
        codeField.delegate = self
        sendCodeButton.target = self
        sendCodeButton.action = #selector(sendCodeTapped)
        verifyButton.target = self
        verifyButton.action = #selector(verifyTapped)
        verifyButton.keyEquivalent = "\r"
        mfaPasskeyButton.target = self
        mfaPasskeyButton.action = #selector(passkeyTapped)
        backButton.target = self
        backButton.action = #selector(backTapped)
        methodPopup.observeTheme { popup, palette in popup.font = palette.font(.button) }
        let methodLabel = ThemedLabel(string: "Method", role: .secondaryText, textRole: .caption)
        let methodRow = NSStackView(views: [methodLabel, methodPopup])
        methodRow.orientation = .horizontal
        mfaStack.orientation = .vertical
        mfaStack.spacing = 8
        mfaStack.alignment = .width
        let mfaViews = [mfaHeading, methodRow, codeField, sendCodeButton, verifyButton, mfaPasskeyButton, backButton]
        mfaViews.forEach(mfaStack.addArrangedSubview)
        mfaStack.pinArrangedSubviewsToFullWidth()

        // A wrapping label is the one thing `ThemedLabel` is not, so it reads
        // the palette directly — through ``messageRole``, which says what the
        // message currently means.
        messageLabel.observeTheme { [weak self] label, palette in
            label.textColor = palette.nsColor(self?.messageRole ?? .danger)
            label.font = palette.font(.caption)
        }
        messageLabel.maximumNumberOfLines = 3
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let column = NSStackView(views: [credentialsStack, mfaStack, messageLabel, spinner])
        column.orientation = .vertical
        column.spacing = 12
        column.alignment = .width
        column.translatesAutoresizingMaskIntoConstraints = false
        column.pinArrangedSubviewsToFullWidth()
        let container = ThemedBackgroundView(role: .windowBackground)
        container.addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            column.widthAnchor.constraint(equalToConstant: 320)
        ])
        view = container

        viewModel.onChange = { [weak self] state in self?.render(state) }
        render(viewModel.state)
    }

    // MARK: Rendering

    private func render(_ state: SignInViewModel.State) {
        let inMfa: Bool
        if case .mfa = state.mode { inMfa = true } else { inMfa = false }
        credentialsStack.isHidden = inMfa
        mfaStack.isHidden = !inMfa

        if emailField.stringValue != state.email { emailField.stringValue = state.email }
        if passwordField.stringValue != state.password { passwordField.stringValue = state.password }
        if codeField.stringValue != state.code { codeField.stringValue = state.code }
        signInButton.isEnabled = state.canSubmitCredentials
        passkeyButton.isEnabled = !state.isBusy
        socialButtons.forEach { $0.isEnabled = !state.isBusy }

        let menu = state.methodMenu
        if methodPopup.itemTitles != menu.items.map(\.title) {
            methodPopup.removeAllItems()
            methodPopup.addItems(withTitles: menu.items.map(\.title))
        }
        if let index = menu.items.firstIndex(where: \.isSelected) {
            methodPopup.selectItem(at: index)
        }
        codeField.isHidden = !state.showsCodeField
        verifyButton.isHidden = !state.showsCodeField
        verifyButton.isEnabled = state.canSubmitCode
        sendCodeButton.isHidden = !state.showsSendCode
        sendCodeButton.isEnabled = !state.isBusy
        mfaPasskeyButton.isHidden = !state.showsUsePasskey
        mfaPasskeyButton.isEnabled = !state.isBusy
        backButton.isEnabled = !state.isBusy

        if let error = state.errorMessage {
            setMessage(error, role: .danger)
        } else if let info = state.infoMessage {
            setMessage(info, role: .secondaryText)
        } else {
            setMessage("", role: .danger)
        }
        if state.isBusy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    /// Writes the message and records what it means, so both the colour now
    /// and the colour after a theme change come from the same one place.
    private func setMessage(_ text: String, role: ThemeRole) {
        messageRole = role
        messageLabel.stringValue = text
        messageLabel.textColor = view.resolvedThemeScope.palette.nsColor(role)
    }

    // MARK: NSTextFieldDelegate

    public func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === emailField { viewModel.setEmail(field.stringValue) }
        if field === passwordField { viewModel.setPassword(field.stringValue) }
        if field === codeField { viewModel.setCode(field.stringValue) }
    }

    // MARK: Actions

    @objc private func signInTapped() { Task { await viewModel.submitCredentials() } }
    @objc private func passkeyTapped() { Task { await viewModel.usePasskey() } }
    @objc private func verifyTapped() { Task { await viewModel.submitCode() } }
    @objc private func sendCodeTapped() { Task { await viewModel.sendCode() } }
    @objc private func backTapped() { viewModel.cancelMfa() }

    @objc private func methodChanged() {
        let methods = viewModel.state.availableMethods
        guard methodPopup.indexOfSelectedItem >= 0, methodPopup.indexOfSelectedItem < methods.count else { return }
        viewModel.selectMethod(methods[methodPopup.indexOfSelectedItem])
    }

    @objc private func socialTapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let provider = SocialProvider(rawValue: raw) else { return }
        Task { await viewModel.signInWithSocial(provider) }
    }

    // MARK: Scripting

    /// This screen's half of a `HubUIState` snapshot.
    ///
    /// Read off `viewModel.state`, not off the controls: the state is what the
    /// controls render, so a snapshot taken from it can never disagree with
    /// what a subsequent scripted action will act on. `message` applies
    /// `render`'s own error-then-info precedence, so what it reports is the one
    /// line on screen rather than whichever of the two fields is set.
    public var scriptState: HubUIState.SignIn {
        let state = viewModel.state
        let mode: String
        if case .mfa = state.mode { mode = "mfa" } else { mode = "credentials" }
        let menu = state.methodMenu
        return HubUIState.SignIn(
            mode: mode,
            email: state.email,
            code: state.code,
            message: state.errorMessage ?? state.infoMessage,
            isBusy: state.isBusy,
            socialProviders: SignInViewModel.socialProviders.map(\.rawValue),
            methods: menu.items.map(\.title),
            selectedMethod: menu.items.first(where: \.isSelected)?.title
        )
    }

    /// Types into one of the three text fields, through the view-model intent
    /// the field's delegate callback uses.
    public func scriptSetField(_ field: HubScripting.Field, to value: String) {
        _ = view
        switch field {
        case .email: viewModel.setEmail(value)
        case .password: viewModel.setPassword(value)
        case .code: viewModel.setCode(value)
        }
    }

    /// Presses one of this screen's buttons, by calling what the button calls.
    ///
    /// Not `button.performClick(nil)`: a hidden or disabled button swallows a
    /// click silently, and which buttons those are is a rendering detail that
    /// changes with the MFA method. Going to the intent means a script gets the
    /// view model's own answer — most intents guard on `state` and do nothing
    /// when they should — instead of a click that vanished for a reason nobody
    /// can see from outside.
    public func scriptPerform(_ action: HubScripting.Action) {
        _ = view
        switch action {
        case .signIn: Task { await viewModel.submitCredentials() }
        case .passkey: Task { await viewModel.usePasskey() }
        case .sendCode: Task { await viewModel.sendCode() }
        case .verify: Task { await viewModel.submitCode() }
        case .back: viewModel.cancelMfa()
        case .social(let provider): Task { await viewModel.signInWithSocial(provider) }
        }
    }

    /// Chooses an MFA method by the title the popup shows, which is the only
    /// name for it a script can see (`MfaChallengeMethod` is not in the
    /// snapshot; its label is).
    ///
    /// - Returns: whether a method with that title was available.
    @discardableResult
    public func scriptSelectMethod(title: String) -> Bool {
        _ = view
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let method = viewModel.state.availableMethods.first(where: { $0.label == wanted })
        else { return false }
        viewModel.selectMethod(method)
        return true
    }
}
#endif
