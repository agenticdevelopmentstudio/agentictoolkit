import Foundation
import Testing
@testable import AgenticToolkitCore

/// The options a `createWebviewPanel` call carries, and the two rules that are
/// easy to get subtly wrong: forms default to whatever scripts did, and an
/// extension that declared *no* resource roots is not the same as one that
/// declared none at all.
@Suite
struct WebviewPanelOptionsTests {

    private let extensionDirectory =
        URL(fileURLWithPath: "/Users/someone/.agenticextensions/vendor.preview")
    private let workspace = URL(fileURLWithPath: "/Users/someone/Development/whippet")
    private let secondWorkspace = URL(fileURLWithPath: "/Users/someone/Development/other")

    @Test("scripts are off unless the panel asked for them")
    func scriptsAreOffUnlessAskedFor() {
        #expect(
            WebviewPanelOptions(enableScripts: nil, enableForms: nil, localResourceRoots: nil)
                .enableScripts == false)
        #expect(
            WebviewPanelOptions(enableScripts: true, enableForms: nil, localResourceRoots: nil)
                .enableScripts)
    }

    /// `vscode.d.ts`: "Defaults to true if scripts are enabled. Otherwise
    /// defaults to false." A scripted page whose forms are silently refused
    /// fails invisibly — the click does nothing and only a content-policy
    /// console line says why.
    @Test("forms default to whatever scripts did")
    func formsFollowScripts() {
        #expect(
            WebviewPanelOptions(enableScripts: true, enableForms: nil, localResourceRoots: nil)
                .enableForms)
        #expect(
            WebviewPanelOptions(enableScripts: false, enableForms: nil, localResourceRoots: nil)
                .enableForms == false)
    }

    @Test("an explicit forms option beats the default in both directions")
    func formsCanBeSetAgainstScripts() {
        #expect(
            WebviewPanelOptions(enableScripts: false, enableForms: true, localResourceRoots: nil)
                .enableForms)
        #expect(
            WebviewPanelOptions(enableScripts: true, enableForms: false, localResourceRoots: nil)
                .enableForms == false)
    }

    /// Upstream's default, and the smallest one that gets a preview on screen:
    /// an extension renders its own stylesheet *and* the user's images.
    @Test("a panel that declared no roots gets its extension and the workspace")
    func undeclaredRootsAreTheExtensionAndTheWorkspace() {
        let options = WebviewPanelOptions(
            enableScripts: nil, enableForms: nil, localResourceRoots: nil)

        let roots = options.resourceRoots(
            extensionDirectory: extensionDirectory, workspaceRoots: [workspace, secondWorkspace])

        #expect(roots.count == 3)
        #expect(roots.first?.path == extensionDirectory.path)
        #expect(roots.map(\.path).contains(workspace.path))
    }

    @Test("declared roots replace the default rather than adding to it")
    func declaredRootsAreTheOnlyRoots() {
        let options = WebviewPanelOptions(
            enableScripts: nil, enableForms: nil, localResourceRoots: [workspace])

        let roots = options.resourceRoots(
            extensionDirectory: extensionDirectory, workspaceRoots: [secondWorkspace])

        #expect(roots.map(\.path) == [workspace.path])
    }

    /// The distinction the `nil` in `declaredLocalResourceRoots` exists for:
    /// an extension that deliberately renounced file access must not be handed
    /// the whole workspace by a default meant for one that never mentioned it.
    @Test("an empty declaration means no file access at all")
    func anEmptyDeclarationIsNoAccess() {
        let options = WebviewPanelOptions(
            enableScripts: nil, enableForms: nil, localResourceRoots: [])

        let roots = options.resourceRoots(
            extensionDirectory: extensionDirectory, workspaceRoots: [workspace])

        #expect(roots.isEmpty)
    }

    @Test("a repeated root is listed once, in the place it was first seen")
    func rootsAreDeduplicated() {
        let options = WebviewPanelOptions(
            enableScripts: nil, enableForms: nil, localResourceRoots: nil)

        let roots = options.resourceRoots(
            extensionDirectory: extensionDirectory,
            workspaceRoots: [workspace, workspace, extensionDirectory])

        #expect(roots.count == 2)
        #expect(roots.first?.path == extensionDirectory.path)
    }

    /// Deduplicated by the same canonical form the containment check downstream
    /// uses, so two entries this left in place could never be read as one root
    /// there.
    @Test("four spellings of one directory are one root")
    func spellingsOfOneDirectoryAreOneRoot() {
        let options = WebviewPanelOptions(
            enableScripts: nil, enableForms: nil,
            localResourceRoots: [
                workspace,
                URL(fileURLWithPath: workspace.path + "/"),
                URL(fileURLWithPath: workspace.path + "/./"),
                workspace.appendingPathComponent("Sources").appendingPathComponent("..")
            ])

        let roots = options.resourceRoots(extensionDirectory: extensionDirectory, workspaceRoots: [])

        #expect(roots.count == 1)
    }

    @Test("the policy shuts the same three doors either way", arguments: [true, false])
    func theContentPolicyAlwaysShutsTheSameThreeDoors(_ allowingForms: Bool) {
        let policy = WebviewPanelOptions.contentSecurityPolicy(allowingForms: allowingForms)

        #expect(policy.contains("object-src 'none'"))
        #expect(policy.contains("base-uri 'none'"))
        #expect(policy.contains("frame-ancestors 'none'"))
    }

    /// Lifted by *omission*, not by widening to `'self'`: a directive this
    /// policy names is one the page's own CSP can no longer loosen, and an
    /// extension that turned forms on is entitled to say where they go.
    @Test("form-action follows the forms option")
    func formActionFollowsTheFormsOption() {
        #expect(
            WebviewPanelOptions.contentSecurityPolicy(allowingForms: false)
                .contains("form-action 'none'"))
        #expect(
            WebviewPanelOptions.contentSecurityPolicy(allowingForms: true)
                .contains("form-action") == false)
    }

    @Test("a panel's own policy reflects the forms it defaulted to")
    func thePolicyIsWhatThePanelAskedFor() {
        let options = WebviewPanelOptions(
            enableScripts: true, enableForms: nil, localResourceRoots: nil)

        #expect(options.contentSecurityPolicy.contains("form-action") == false)
    }
}
