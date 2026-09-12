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
/// Mirrors `extension-runtime.js`'s own (frozen) `makeStubNamespace` contract,
/// including recording: `subNamespace(path:members:in:)` takes two optional
/// trailing `recordMiss`/`recordProbe` blocks, invoked by the underlying
/// Proxy trap at exactly the point it would otherwise only throw or only
/// answer a probe value — see `subNamespaceFactorySource`'s own doc comment
/// in `VSCodeAPI.swift` for where those two blocks come from on a live
/// `ExtensionHost`. Most tests below call `makeNamespace(members:in:)`, which
/// passes neither, and that remains a fully valid, unrecorded namespace —
/// existing call sites are not required to opt in.
/// `aMissIsRecordedWhenARecorderIsSupplied` and
/// `aProbeIsRecordedWhenARecorderIsSupplied` below are what exercise the
/// recording half directly.
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
    /// iterating a value — answers `undefined` quietly rather than throwing,
    /// and never reaches `recordMiss`/`recordProbe` either: the Proxy trap's
    /// `typeof key === 'symbol'` branch returns before either recorder would
    /// be consulted, the same as it returns before the `NotImplementedError`
    /// branch. This factory call passes no recorders at all, so there is
    /// nothing to observe not being called — `aMissIsRecordedWhenARecorderIsSupplied`
    /// and `aProbeIsRecordedWhenARecorderIsSupplied` are the tests that
    /// exercise the recorders directly.
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

    /// A `members` value can be a `@convention(block)` closure, not just a
    /// bridgeable data value — the shape every real adaptor actually passes
    /// (`ExtensionHost.defineVSCodeMember`'s own `implementation` parameter is
    /// exactly this), so this factory must hand such a value through
    /// JavaScriptCore's bridging unchanged rather than merely tolerating
    /// strings and numbers in a test.
    @Test
    func aConventionBlockClosurePassedThroughMembersIsCallable() throws {
        let context = try makeContext()
        let readFile: @convention(block) (String) -> String = { path in "contents of \(path)" }
        _ = try makeNamespace(members: ["readFile": readFile], in: context)
        let result = try #require(context.evaluateScript("ns.readFile('/a/b')"))
        #expect(result.toString() == "contents of /a/b")
    }

    /// `recordMiss`, when supplied, is called with `path + '.' + key` for
    /// every member `subNamespace` did not implement — and the throw the
    /// caller's own `try`/`catch` sees is unaffected: recording augments the
    /// report, it does not replace the error.
    @Test
    func aMissIsRecordedWhenARecorderIsSupplied() throws {
        let context = try makeContext()
        let recorder = RecordedPaths()
        let recordMiss: @convention(block) (String) -> Void = { [recorder] path in
            MainActor.assumeIsolated { recorder.append(path) }
        }
        let namespace = try #require(VSCodeAPI.subNamespace(
            path: "vscode.workspace.fs", members: [:], in: context, recordMiss: recordMiss))
        context.setObject(namespace, forKeyedSubscript: "ns" as NSString)

        let result = try #require(context.evaluateScript(
            """
            (function () {
                try {
                    ns.writeFile;
                    return { threw: false };
                } catch (error) {
                    return { threw: true, memberPath: error.memberPath };
                }
            })()
            """
        ))
        #expect(result.forProperty("threw")?.toBool() == true)
        #expect(result.forProperty("memberPath")?.toString() == "vscode.workspace.fs.writeFile")
        #expect(recorder.paths == ["vscode.workspace.fs.writeFile"])
    }

    /// `recordProbe`, when supplied, is called with `path + '.' + key` for
    /// every probe key a caller reaches — feature-detection like `then` or
    /// `toString` — and the quiet probe value is still returned, unaffected.
    @Test
    func aProbeIsRecordedWhenARecorderIsSupplied() throws {
        let context = try makeContext()
        let recorder = RecordedPaths()
        let recordProbe: @convention(block) (String) -> Void = { [recorder] path in
            MainActor.assumeIsolated { recorder.append(path) }
        }
        let namespace = try #require(VSCodeAPI.subNamespace(
            path: "vscode.workspace.fs", members: [:], in: context, recordProbe: recordProbe))
        context.setObject(namespace, forKeyedSubscript: "ns" as NSString)

        let thenResult = try #require(context.evaluateScript("typeof ns.then"))
        #expect(thenResult.toString() == "undefined")
        let stringResult = try #require(context.evaluateScript("String(ns)"))
        #expect(stringResult.toString() == "[VSCodeNamespace vscode.workspace.fs]")
        #expect(recorder.paths == ["vscode.workspace.fs.then", "vscode.workspace.fs.toString"])
    }
}

/// A small reference-type box for a `@convention(block)` recorder closure to
/// mutate — mirrors the class-based recorders already used elsewhere in this
/// test tree (`ConsoleRecorder`, for one) rather than a `var` captured
/// directly by an escaping block, which is the shape every other recording
/// callback in this codebase already avoids.
@MainActor
private final class RecordedPaths {
    private(set) var paths: [String] = []

    func append(_ path: String) {
        paths.append(path)
    }
}
