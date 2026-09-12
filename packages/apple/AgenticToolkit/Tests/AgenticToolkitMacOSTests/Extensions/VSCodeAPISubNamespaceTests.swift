import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitMacOS

/// `VSCodeAPI.subNamespace(path:members:in:)` (task 5.4a): the shared
/// throw-on-unimplemented-member namespace builder that later sub-tasks
/// (5.4b/5.4c) and stages 5.5–5.7 build their own sub-namespaces on — such as
/// `vscode.workspace.fs`, used as this suite's `path` throughout because it is
/// the sub-namespace the surface survey names as the first real consumer,
/// though this task builds no `workspace` member itself.
///
/// Mirrors `extension-runtime.js`'s own (frozen) `makeStubNamespace` contract
/// except for recording, which `subNamespaceFactorySource`'s own doc comment
/// in `VSCodeAPI.swift` explains has no Swift-reachable counterpart here:
/// `VSCodeAPI` is a stateless, caseless enum with no `ExtensionHost` or
/// `NotImplementedLedger` handle, and `__host` — the one bridge back to a
/// host's recording methods — is deleted from `globalThis` before any
/// extension code runs. So "without recording" below is a structural fact
/// about this factory (there is nothing it could record into), not a
/// side effect a test can observe the way it could through a real
/// `NotImplementedLedger` — see `aSymbolKeyAnswersUndefinedWithoutRecording`'s
/// own doc comment.
///
/// A bare `JSContext`, for the same reason `UriTests` uses one:
/// `subNamespace(path:members:in:)` takes a `JSContext` and nothing else.
@MainActor
@Suite
struct VSCodeAPISubNamespaceTests {

    private func makeContext() throws -> JSContext {
        try #require(JSContext())
    }

    /// Builds a sub-namespace at `"vscode.workspace.fs"` with `members`, and
    /// exposes it as the global `ns` so a test's own script can read it.
    private func makeNamespace(members: [String: Any], in context: JSContext) throws -> JSValue {
        let namespace = try #require(VSCodeAPI.subNamespace(
            path: "vscode.workspace.fs", members: members, in: context))
        context.setObject(namespace, forKeyedSubscript: "ns" as NSString)
        return namespace
    }

    /// A key present in `members` resolves to exactly the value it was given
    /// — the "implemented" half of the contract.
    @Test
    func anImplementedMemberResolvesToItsProvidedValue() throws {
        let context = try makeContext()
        _ = try makeNamespace(members: ["greeting": "hello"], in: context)
        let value = try #require(context.evaluateScript("ns.greeting"))
        #expect(value.toString() == "hello")
    }

    /// A key absent from `members` throws a `NotImplementedError` naming
    /// `path + '.' + key` as its `memberPath` — the same shape
    /// `extension-runtime.js`'s `makeStubNamespace` throws for `vscode`
    /// itself, so an extension's `try`/`catch` around either sees one
    /// contract regardless of which builder produced the namespace.
    @Test
    func anUnimplementedMemberThrowsANotImplementedErrorNamingItsPath() throws {
        let context = try makeContext()
        _ = try makeNamespace(members: [:], in: context)
        let result = try #require(context.evaluateScript(
            """
            (function () {
                try {
                    ns.readFile;
                    return { threw: false };
                } catch (error) {
                    return { threw: true, name: error.name, memberPath: error.memberPath };
                }
            })()
            """
        ))
        #expect(result.forProperty("threw")?.toBool() == true)
        #expect(result.forProperty("name")?.toString() == "NotImplementedError")
        #expect(result.forProperty("memberPath")?.toString() == "vscode.workspace.fs.readFile")
    }

    /// A symbol key — the shape JavaScriptCore itself reads while coercing or
    /// iterating a value — answers `undefined` quietly rather than throwing.
    ///
    /// "Without recording" is not separately observable at this layer: this
    /// factory has no ledger reference to record into in the first place (see
    /// this file's own header comment), so the only thing a test can pin here
    /// is the behavior a caller actually sees — a quiet `undefined`, not a
    /// thrown `NotImplementedError` — which is what the brief's "recording"
    /// requirement reduces to once the recording half is structurally absent.
    @Test
    func aSymbolKeyAnswersUndefinedWithoutRecording() throws {
        let context = try makeContext()
        _ = try makeNamespace(members: [:], in: context)
        let result = try #require(context.evaluateScript("typeof ns[Symbol.iterator]"))
        #expect(result.toString() == "undefined")
    }

    /// A key in the shim's `PROBE_KEYS` — `then`, here — answers a quiet
    /// feature-detection value instead of throwing: an `await`-ing caller's
    /// `typeof x.then === 'function'` check must run to completion without
    /// landing in a `catch`.
    @Test
    func aProbeKeyAnswersQuietlyRatherThanThrowing() throws {
        let context = try makeContext()
        _ = try makeNamespace(members: [:], in: context)
        let result = try #require(context.evaluateScript("typeof ns.then"))
        #expect(result.toString() == "undefined")
    }

    /// `toString` is also a probe key, and answers a value naming the
    /// namespace's own path rather than throwing or falling back to
    /// `[object Object]` — further proof the probe path answers a real value
    /// on request, not merely "doesn't throw".
    @Test
    func toStringNamesTheNamespacesOwnPath() throws {
        let context = try makeContext()
        _ = try makeNamespace(members: [:], in: context)
        let result = try #require(context.evaluateScript("String(ns)"))
        #expect(result.toString() == "[VSCodeNamespace vscode.workspace.fs]")
    }

    /// An implemented member takes priority over a same-named probe key: a
    /// caller that supplies its own `toString` in `members` is not shadowed
    /// by the factory's generic one.
    @Test
    func anImplementedMemberShadowsASameNamedProbeKey() throws {
        let context = try makeContext()
        _ = try makeNamespace(members: ["toString": "not a function, deliberately"], in: context)
        let value = try #require(context.evaluateScript("ns.toString"))
        #expect(value.toString() == "not a function, deliberately")
    }
}
