#if canImport(AppKit)
import AgenticToolkitHTDV
import AgenticToolkitHubService
import AgenticToolkitScripting
import AppKit
import Foundation

// MARK: - Introspection

/// `ui state` — the whole window's content as one JSON snapshot.
@objc(HubUIStateCommand)
final class HubUIStateCommand: HubScriptCommand, @unchecked Sendable {
    override func performMain() -> Any? {
        guard let state = HubFeature.current?.mainWindow?.captureUIState() else { return "{}" }
        return state.jsonString()
    }
}

// MARK: - The signed-in shell

/// `select workspace` — switch workspace by slug or by the popup's label.
@objc(HubSelectWorkspaceCommand)
final class HubSelectWorkspaceCommand: HubScriptCommand, @unchecked Sendable {
    override func performMain() -> Any? {
        guard let text = requireText() else { return nil }
        guard let coordinator = HubFeature.current?.composition?.coordinator else {
            fail(NSInternalScriptError, "The app is still starting up.")
            return false
        }
        guard let slug = HubScripting.workspaceSlug(matching: text, in: coordinator.workspaces.workspaces) else {
            fail(NSArgumentsWrongScriptError, "No workspace matches “\(text)”.")
            return false
        }
        Task { await coordinator.selectWorkspace(slug: slug) }
        return true
    }
}

/// `choose account item` — pick from the account menu.
@objc(HubChooseAccountItemCommand)
final class HubChooseAccountItemCommand: HubScriptCommand, @unchecked Sendable {
    override func performMain() -> Any? {
        guard let text = requireText() else { return nil }
        guard let item = AccountMenuModel.Item.parse(text) else {
            let known = AccountMenuModel.Item.allCases.map(\.rawValue).joined(separator: ", ")
            fail(NSArgumentsWrongScriptError, "Unknown account menu item “\(text)”. Known items: \(known).")
            return false
        }
        guard let root = requireRoot() else { return false }
        return root.scriptChooseAccountItem(item)
    }
}

/// `select item` — select a row in the hierarchical detail view.
@objc(HubSelectItemCommand)
final class HubSelectItemCommand: HubScriptCommand, @unchecked Sendable {
    override func performMain() -> Any? {
        guard let itemID = requireText() else { return nil }
        let level = (evaluatedArguments?["atLevel"] as? NSNumber)?.intValue ?? 0
        guard level >= 0 else {
            fail(NSArgumentsWrongScriptError, "The level index must not be negative.")
            return false
        }
        guard let controller = requireHTDV() else { return false }
        Task { await controller.select(itemID: itemID, atLevel: level) }
        return true
    }
}

/// `pop to level` — drop every level to the right of the given one.
@objc(HubPopToLevelCommand)
final class HubPopToLevelCommand: HubScriptCommand, @unchecked Sendable {
    override func performMain() -> Any? {
        guard let level = (directParameter as? NSNumber)?.intValue else {
            fail(NSArgumentsWrongScriptError, "This command takes an integer level index.")
            return nil
        }
        guard level >= 0 else {
            fail(NSArgumentsWrongScriptError, "The level index must not be negative.")
            return false
        }
        guard let controller = requireHTDV() else { return false }
        controller.popToLevel(level)
        return true
    }
}

/// `reload` — reload the hierarchical detail view from its data source.
@objc(HubReloadCommand)
final class HubReloadCommand: HubScriptCommand, @unchecked Sendable {
    override func performMain() -> Any? {
        guard let controller = requireHTDV() else { return false }
        Task { await controller.load() }
        return true
    }
}

// MARK: - Sign-in

/// `set sign in field` — type into one of the sign-in screen's fields.
@objc(HubSetSignInFieldCommand)
final class HubSetSignInFieldCommand: HubScriptCommand, @unchecked Sendable {
    override func performMain() -> Any? {
        // Not `requireText()`: clearing a field is a thing a script does, and
        // the empty string is how it says so.
        guard let value = directParameter as? String else {
            fail(NSArgumentsWrongScriptError, "This command takes the text to put in the field.")
            return nil
        }
        guard let rawField = evaluatedArguments?["field"] as? String else {
            fail(NSRequiredArgumentsMissingScriptError, "This command needs a `field` argument.")
            return nil
        }
        guard let field = HubScripting.Field.parse(rawField) else {
            let known = HubScripting.Field.allCases.map(\.rawValue).joined(separator: ", ")
            fail(NSArgumentsWrongScriptError, "Unknown field “\(rawField)”. Known fields: \(known).")
            return false
        }
        guard let signIn = requireSignIn() else { return false }
        signIn.scriptSetField(field, to: value)
        return true
    }
}

/// `perform sign in action` — press one of the sign-in screen's buttons.
@objc(HubPerformSignInActionCommand)
final class HubPerformSignInActionCommand: HubScriptCommand, @unchecked Sendable {
    override func performMain() -> Any? {
        guard let text = requireText() else { return nil }
        guard let action = HubScripting.Action.parse(text) else {
            fail(
                NSArgumentsWrongScriptError,
                "Unknown sign-in action “\(text)”. Known actions: sign-in, passkey, send-code,"
                    + " verify, back, social:<provider>."
            )
            return false
        }
        guard let signIn = requireSignIn() else { return false }
        signIn.scriptPerform(action)
        return true
    }
}

/// `select mfa method` — choose a two-factor method by its popup title.
@objc(HubSelectMFAMethodCommand)
final class HubSelectMFAMethodCommand: HubScriptCommand, @unchecked Sendable {
    override func performMain() -> Any? {
        guard let title = requireText() else { return nil }
        guard let signIn = requireSignIn() else { return false }
        return signIn.scriptSelectMethod(title: title)
    }
}

// MARK: - Permissions

/// `run permission walkthrough` — show the alert whatever the flag says.
@objc(HubRunPermissionWalkthroughCommand)
final class HubRunPermissionWalkthroughCommand: HubScriptCommand, @unchecked Sendable {
    override func performMain() -> Any? {
        guard let feature = HubFeature.current else {
            fail(NSInternalScriptError, "The permission walkthrough has not been built.")
            return false
        }
        // `run`, not `runIfNeeded`: asking for the walkthrough is the whole point.
        return feature.runPermissionWalkthrough()
    }
}

/// `reset permission walkthrough` — forget that it has run.
@objc(HubResetPermissionWalkthroughCommand)
final class HubResetPermissionWalkthroughCommand: HubScriptCommand, @unchecked Sendable {
    override func performMain() -> Any? {
        guard let feature = HubFeature.current else {
            fail(NSInternalScriptError, "The hub has not been built.")
            return false
        }
        feature.resetPermissionWalkthrough()
        return true
    }
}
#endif
