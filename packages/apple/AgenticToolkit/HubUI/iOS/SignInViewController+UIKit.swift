#if canImport(UIKit)
import AgenticToolkitHubService
import AgenticDeveloperToolkit
import AgenticDeveloperToolkitUI
import UIKit

/// UIKit sign-in screen (spec §5.2), mirror of the AppKit one: renders
/// `SignInViewModel.state`, forwards every control to a view-model intent.
public final class SignInViewController: UIViewController {
    private let viewModel: SignInViewModel

    private let emailField = ThemedTextField()
    private let passwordField = ThemedTextField()
    private let signInButton = UIButton(configuration: .filled())
    private let passkeyButton = UIButton(configuration: .bordered())
    private var socialButtons: [UIButton] = []
    private let credentialsStack = UIStackView()

    private let mfaHeading = ThemedLabel(string: "Two-factor authentication", textRole: .heading)
    private let methodButton = UIButton(configuration: .bordered())
    private let codeField = ThemedTextField()
    private let sendCodeButton = UIButton(configuration: .bordered())
    private let verifyButton = UIButton(configuration: .filled())
    private let mfaPasskeyButton = UIButton(configuration: .bordered())
    private let backButton = UIButton(configuration: .plain())
    private let mfaStack = UIStackView()

    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

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

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.observeTheme { view, palette in view.backgroundColor = palette.windowBackgroundColor }

        configure(emailField, placeholder: "Email", secure: false, keyboard: .emailAddress, content: .username)
        configure(passwordField, placeholder: "Password", secure: true, keyboard: .default, content: .password)
        configure(
            codeField,
            placeholder: "Code",
            secure: false,
            keyboard: .numbersAndPunctuation,
            content: .oneTimeCode
        )
        Self.applyColumnTheme(signInButton, isFilled: true)
        signInButton.configuration?.title = "Sign In"
        signInButton.addAction(
            UIAction { [weak self] _ in Task { await self?.viewModel.submitCredentials() } },
            for: .touchUpInside
        )
        Self.applyColumnTheme(passkeyButton, isFilled: false)
        passkeyButton.configuration?.title = "Use Passkey"
        passkeyButton.addAction(
            UIAction { [weak self] _ in Task { await self?.viewModel.usePasskey() } },
            for: .touchUpInside
        )
        socialButtons = SignInViewModel.socialProviders.map { provider in
            let button = UIButton(configuration: .bordered())
            Self.applyColumnTheme(button, isFilled: false)
            button.configuration?.title = "Continue with \(provider.label)"
            button.addAction(
                UIAction { [weak self] _ in Task { await self?.viewModel.signInWithSocial(provider) } },
                for: .touchUpInside
            )
            return button
        }
        credentialsStack.axis = .vertical
        credentialsStack.spacing = 8
        [emailField, passwordField, signInButton, passkeyButton].forEach(credentialsStack.addArrangedSubview)
        socialButtons.forEach(credentialsStack.addArrangedSubview)

        methodButton.showsMenuAsPrimaryAction = true
        Self.applyColumnTheme(methodButton, isFilled: false)
        Self.applyColumnTheme(sendCodeButton, isFilled: false)
        sendCodeButton.configuration?.title = "Send Code"
        sendCodeButton.addAction(
            UIAction { [weak self] _ in Task { await self?.viewModel.sendCode() } },
            for: .touchUpInside
        )
        Self.applyColumnTheme(verifyButton, isFilled: true)
        verifyButton.configuration?.title = "Verify"
        verifyButton.addAction(
            UIAction { [weak self] _ in Task { await self?.viewModel.submitCode() } },
            for: .touchUpInside
        )
        Self.applyColumnTheme(mfaPasskeyButton, isFilled: false)
        mfaPasskeyButton.configuration?.title = "Use Passkey"
        mfaPasskeyButton.addAction(
            UIAction { [weak self] _ in Task { await self?.viewModel.usePasskey() } },
            for: .touchUpInside
        )
        Self.applyColumnTheme(backButton, isFilled: false)
        backButton.configuration?.title = "Back"
        backButton.addAction(UIAction { [weak self] _ in self?.viewModel.cancelMfa() }, for: .touchUpInside)
        let methodLabel = ThemedLabel(string: "Method", role: .secondaryText, textRole: .caption)
        let methodRow = UIStackView(arrangedSubviews: [methodLabel, methodButton])
        methodRow.axis = .horizontal
        methodRow.spacing = 8
        mfaStack.axis = .vertical
        mfaStack.spacing = 8
        let mfaViews = [mfaHeading, methodRow, codeField, sendCodeButton, verifyButton, mfaPasskeyButton, backButton]
        mfaViews.forEach(mfaStack.addArrangedSubview)

        messageLabel.numberOfLines = 3
        // A wrapping label is the one thing `ThemedLabel` is not, so it reads
        // the palette directly — through ``messageRole``, which says what the
        // message currently means.
        messageLabel.observeTheme { [weak self] label, palette in
            label.textColor = palette.uiColor(self?.messageRole ?? .danger)
            label.font = palette.font(.caption)
        }
        spinner.observeTheme { spinner, palette in spinner.color = palette.accentColor }
        spinner.hidesWhenStopped = true

        let column = UIStackView(arrangedSubviews: [credentialsStack, mfaStack, messageLabel, spinner])
        column.axis = .vertical
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)
        scroll.addSubview(column)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            column.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            column.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            column.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            column.widthAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            column.widthAnchor
                .constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
                .withPriority(.defaultHigh)
        ])

        viewModel.onChange = { [weak self] state in self?.render(state) }
        render(viewModel.state)
    }

    /// Paints one of the column's buttons from the palette.
    ///
    /// These stay `UIButton`s carrying a UIKit configuration rather than
    /// becoming `ThemedButton`s, because the configuration is what draws the
    /// filled and bordered looks in the first place (`native-controls`). A
    /// filled button wears the accent as its fill and the on-accent colour as
    /// its title; a bordered or plain one carries the accent as its tint.
    private static func applyColumnTheme(_ button: UIButton, isFilled: Bool) {
        button.observeTheme { button, palette in
            button.configuration?.baseBackgroundColor = isFilled ? palette.accentColor : .clear
            button.configuration?.baseForegroundColor =
                isFilled ? palette.onAccentTextColor : palette.accentColor
            button.configuration?.titleTextAttributesTransformer =
                UIConfigurationTextAttributesTransformer { incoming in
                    var outgoing = incoming
                    outgoing.font = palette.font(.button)
                    return outgoing
                }
            button.setNeedsUpdateConfiguration()
        }
    }

    private func configure(
        _ field: ThemedTextField,
        placeholder: String,
        secure: Bool,
        keyboard: UIKeyboardType,
        content: UITextContentType
    ) {
        // `ThemedTextField` re-themes when `placeholder` is set, and sets the
        // rounded border itself.
        field.placeholder = placeholder
        field.isSecureTextEntry = secure
        field.keyboardType = keyboard
        field.textContentType = content
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.addAction(UIAction { [weak self, weak field] _ in
            guard let self, let field else { return }
            let text = field.text ?? ""
            if field === self.emailField { self.viewModel.setEmail(text) }
            if field === self.passwordField { self.viewModel.setPassword(text) }
            if field === self.codeField { self.viewModel.setCode(text) }
        }, for: .editingChanged)
    }

    // MARK: Rendering

    private func render(_ state: SignInViewModel.State) {
        let inMfa: Bool
        if case .mfa = state.mode { inMfa = true } else { inMfa = false }
        credentialsStack.isHidden = inMfa
        mfaStack.isHidden = !inMfa

        if emailField.text != state.email { emailField.text = state.email }
        if passwordField.text != state.password { passwordField.text = state.password }
        if codeField.text != state.code { codeField.text = state.code }
        signInButton.isEnabled = state.canSubmitCredentials
        passkeyButton.isEnabled = !state.isBusy
        socialButtons.forEach { $0.isEnabled = !state.isBusy }

        let menu = state.methodMenu
        methodButton.changesSelectionAsPrimaryAction = false
        if menu.items.isEmpty {
            methodButton.menu = nil
            methodButton.configuration?.title = menu.title
        } else {
            methodButton.menu = UIMenu(children: menu.items.map { item in
                UIAction(title: item.title, state: item.isSelected ? .on : .off) { [weak self] _ in
                    self?.viewModel.selectMethod(item.method)
                }
            })
            methodButton.changesSelectionAsPrimaryAction = true
            methodButton.configuration?.title = menu.title
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
            setMessage(nil, role: .danger)
        }
        if state.isBusy { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    /// Writes the message and records what it means, so both the colour now and
    /// the colour after a theme change come from the same one place.
    private func setMessage(_ text: String?, role: ThemeRole) {
        messageRole = role
        messageLabel.text = text
        messageLabel.textColor = view.resolvedThemeScope.palette.uiColor(role)
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
#endif
