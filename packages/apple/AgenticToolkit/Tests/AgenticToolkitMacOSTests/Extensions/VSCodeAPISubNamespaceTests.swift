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
/// trailing `recordMiss`/`recordProbe` blocks. `recordMiss` is invoked from
/// the throwing branch of `get`; `recordProbe` is invoked from `has` and
/// `getOwnPropertyDescriptor` for a key that is neither implemented nor one of
/// the shim's own `PROBE_KEYS` — never from a `get` of a `PROBE_KEYS` name,
/// which answers its quiet value unrecorded — see `subNamespaceFactorySource`'s
/// own doc comment in `VSCodeAPI.swift` for where those two blocks come from
/// on a live `ExtensionHost`, and for why the two recordings sit on those
/// particular traps. Most tests below call `makeNamespace(members:in:)`,
/// which passes neither, and that remains a fully valid, unrecorded namespace
/// — existing call sites are not required to opt in.
/// `aMissIsRecordedWhenARecorderIsSupplied`, `aProbeKeyGetNeverRecordsAProbe`
/// and `anInOrGetOwnPropertyDescriptorMissOfANonProbeKeyRecordsAProbe` below
/// are what exercise the recording half directly.
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
    /// and never reaches `recordMiss` either: the Proxy trap's
    /// `typeof key === 'symbol'` branch returns before `get`'s `recordMiss`
    /// call would be reached, the same as it returns before the
    /// `NotImplementedError` branch. (`recordProbe` is never reachable from
    /// `get` for any key, symbol or not — it is only ever called from `has`
    /// and `getOwnPropertyDescriptor` — so `probeRecorder.paths.isEmpty`
    /// below holds regardless of this branch and is not itself evidence about
    /// the symbol guard; measured directly under `node`: a `get` of a symbol
    /// key, a probe key, a real miss, and an implemented member all leave
    /// `probes` empty.) Recorders are supplied here (unlike most tests in
    /// this file) so "without recording" is an observed empty array rather
    /// than an absence of anything that could have recorded — a real
    /// regression this closes is a *miss* recording being added to the
    /// symbol path; a deleted symbol branch is instead caught by the
    /// `#expect(result.toString() == "undefined")` assertion below, since a
    /// symbol key falling through to the ordinary miss path throws
    /// `TypeError: Cannot convert a Symbol value to a string` while building
    /// `path + '.' + key`, not `undefined`.
    @Test
    func aSymbolKeyAnswersUndefinedWithoutRecording() throws {
        let context = try makeContext()
        let missRecorder = RecordedPaths()
        let probeRecorder = RecordedPaths()
        let recordMiss: @convention(block) (String) -> Void = { [missRecorder] path in
            MainActor.assumeIsolated { missRecorder.append(path) }
        }
        let recordProbe: @convention(block) (String) -> Void = { [probeRecorder] path in
            MainActor.assumeIsolated { probeRecorder.append(path) }
        }
        let namespace = try #require(VSCodeAPI.subNamespace(
            path: "vscode.workspace.fs", members: [:], in: context,
            recordMiss: recordMiss, recordProbe: recordProbe))
        context.setObject(namespace, forKeyedSubscript: "ns" as NSString)

        let result = try #require(context.evaluateScript("typeof ns[Symbol.iterator]"))
        #expect(result.toString() == "undefined")
        #expect(missRecorder.paths.isEmpty)
        #expect(probeRecorder.paths.isEmpty)
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

    /// A `get` of a `PROBE_KEYS` name never calls `recordProbe`, no matter how
    /// it is reached — `typeof ns.then` and `String(ns)` (which reads
    /// `toString`) are both interop machinery touching the namespace, not an
    /// extension stating which member it wanted, and recording them is
    /// exactly the noise `extension-runtime.js`'s own `makeStubNamespace`
    /// never produces from `get`. The quiet probe *value* is still returned,
    /// unaffected — only the recording is suppressed.
    @Test
    func aProbeKeyGetNeverRecordsAProbe() throws {
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
        #expect(recorder.paths.isEmpty)
    }

    /// `'someMember' in ns` and `Object.getOwnPropertyDescriptor(ns, 'someMember')`
    /// are the other half of the split: a key that is neither implemented nor
    /// one of the shim's `PROBE_KEYS` calls `recordProbe` with
    /// `path + '.' + key` from `has` and from `getOwnPropertyDescriptor` —
    /// mirroring `extension-runtime.js`'s own `recordNegativeProbe`, which is
    /// called only from those two traps — while still answering `false` /
    /// `undefined` exactly as it always did. This is the signal task 5.8's
    /// report is actually built for: an extension that looked for a member by
    /// name and quietly took its fallback path.
    @Test
    func anInOrGetOwnPropertyDescriptorMissOfANonProbeKeyRecordsAProbe() throws {
        let context = try makeContext()
        let recorder = RecordedPaths()
        let recordProbe: @convention(block) (String) -> Void = { [recorder] path in
            MainActor.assumeIsolated { recorder.append(path) }
        }
        let namespace = try #require(VSCodeAPI.subNamespace(
            path: "vscode.workspace.fs", members: [:], in: context, recordProbe: recordProbe))
        context.setObject(namespace, forKeyedSubscript: "ns" as NSString)

        let inResult = try #require(context.evaluateScript("'writeFile' in ns"))
        #expect(inResult.toBool() == false)
        let descriptorResult = context.evaluateScript("Object.getOwnPropertyDescriptor(ns, 'writeFile')")
        #expect(descriptorResult == nil || descriptorResult!.isUndefined)
        #expect(recorder.paths == [
            "vscode.workspace.fs.writeFile", "vscode.workspace.fs.writeFile"
        ])
    }

    /// A key that *is* one of the shim's `PROBE_KEYS` — `then`, here — is
    /// never recorded from `has` or `getOwnPropertyDescriptor` either, the
    /// same guard `extension-runtime.js`'s own `recordNegativeProbe` applies
    /// before its one call site. This is not about `await`: measured directly
    /// under `node`, `await x`, `Promise.resolve(x)`, `Promise.all([x])` and
    /// `new Promise(r => r(x))` all reach a thenable only through a `get` of
    /// `then` (`["get:then", "get:then", "get:then", "get:then"]`, not one
    /// `has`) — promise adoption is already covered by the *other* probe test,
    /// `aProbeKeyGetNeverRecordsAProbe`, and was already correct before this
    /// round. What this test guards is an extension doing its own explicit
    /// feature detection — `'then' in ns`, `'workspaceFolders' in ns` — which
    /// genuinely does reach `has`. Without this guard, that code would write a
    /// row for `vscode.workspace.fs.then` even though `then` is interop
    /// vocabulary, not a real member an extension could ever implement.
    @Test
    func anInOrGetOwnPropertyDescriptorOfAProbeKeyNeverRecordsAProbe() throws {
        let context = try makeContext()
        let recorder = RecordedPaths()
        let recordProbe: @convention(block) (String) -> Void = { [recorder] path in
            MainActor.assumeIsolated { recorder.append(path) }
        }
        let namespace = try #require(VSCodeAPI.subNamespace(
            path: "vscode.workspace.fs", members: [:], in: context, recordProbe: recordProbe))
        context.setObject(namespace, forKeyedSubscript: "ns" as NSString)

        let inResult = try #require(context.evaluateScript("'then' in ns"))
        #expect(inResult.toBool() == false)
        let descriptorResult = context.evaluateScript("Object.getOwnPropertyDescriptor(ns, 'toString')")
        #expect(descriptorResult == nil || descriptorResult!.isUndefined)
        #expect(recorder.paths.isEmpty)
    }

    /// A symbol key reaching `has` or `getOwnPropertyDescriptor` — not `get`,
    /// which already has its own symbol branch and its own test above —
    /// records nothing, the same guard `recordNegativeProbe` applies to a
    /// `PROBE_KEYS` name. Kills the mutation that deletes that guard's
    /// `typeof key === 'symbol'` check: without it, `recordNegativeProbe`
    /// would try to build `path + '.' + key` with a symbol `key`, which
    /// throws `TypeError: Cannot convert a Symbol value to a string` —
    /// measured directly under `node` against the shipped factory with that
    /// check removed, both `in` and `getOwnPropertyDescriptor` throw instead
    /// of answering `false`/`undefined`, so this test's assertions that
    /// neither throws and that nothing is recorded both fail against that
    /// mutant.
    @Test
    func aSymbolKeyThroughInOrGetOwnPropertyDescriptorNeverRecordsAProbe() throws {
        let context = try makeContext()
        let recorder = RecordedPaths()
        let recordProbe: @convention(block) (String) -> Void = { [recorder] path in
            MainActor.assumeIsolated { recorder.append(path) }
        }
        let namespace = try #require(VSCodeAPI.subNamespace(
            path: "vscode.workspace.fs", members: [:], in: context, recordProbe: recordProbe))
        context.setObject(namespace, forKeyedSubscript: "ns" as NSString)

        let result = try #require(context.evaluateScript(
            """
            (function () {
                var sym = Symbol('probe');
                return {
                    inResult: sym in ns,
                    gopdResult: Object.getOwnPropertyDescriptor(ns, sym)
                };
            })()
            """
        ))
        #expect(result.forProperty("inResult")?.toBool() == false)
        let gopdResult = result.forProperty("gopdResult")
        #expect(gopdResult == nil || gopdResult!.isUndefined)
        #expect(recorder.paths.isEmpty)
    }

    /// A `recordMiss` block that throws must not replace the
    /// `NotImplementedError` the extension is entitled to see — the factory
    /// swallows the throw and raises its own error exactly as if no recorder
    /// had been supplied. Kills the mutation that deletes the `try`/`catch`
    /// around the `recordMiss` call: without it, the recorder's own thrown
    /// error propagates instead, so `error.name` is not `"NotImplementedError"`
    /// — measured directly under `node` against the shipped factory with that
    /// `try`/`catch` removed, the thrown error is the recorder's own
    /// (`Error: recorder blew up`), not a `NotImplementedError`, so this
    /// test's assertion on `error.name` fails against that mutant.
    @Test
    func aThrowingRecordMissDoesNotReplaceTheNotImplementedError() throws {
        let context = try makeContext()
        let recordMiss: @convention(block) (String) -> Void = { [context] _ in
            MainActor.assumeIsolated { VSCodeAPI.raise("recorder blew up", in: context) }
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
                    return { threw: true, name: error.name, memberPath: error.memberPath };
                }
            })()
            """
        ))
        #expect(result.forProperty("threw")?.toBool() == true)
        #expect(result.forProperty("name")?.toString() == "NotImplementedError")
        #expect(result.forProperty("memberPath")?.toString() == "vscode.workspace.fs.writeFile")
    }

    /// A `recordProbe` block that throws must not turn `has` or
    /// `getOwnPropertyDescriptor`'s honest `false`/`undefined` answer into an
    /// uncaught error. Kills the mutation that deletes the `try`/`catch`
    /// around the `recordProbe` call inside `recordNegativeProbe`: without
    /// it, the recorder's own thrown error propagates out of `has`/
    /// `getOwnPropertyDescriptor` instead — measured directly under `node`
    /// against the shipped factory with that `try`/`catch` removed, both
    /// `in` and `getOwnPropertyDescriptor` throw instead of answering, so
    /// this test's assertions that neither throws fail against that mutant.
    @Test
    func aThrowingRecordProbeStillAnswersFalseOrUndefined() throws {
        let context = try makeContext()
        let recordProbe: @convention(block) (String) -> Void = { [context] _ in
            MainActor.assumeIsolated { VSCodeAPI.raise("recorder blew up", in: context) }
        }
        let namespace = try #require(VSCodeAPI.subNamespace(
            path: "vscode.workspace.fs", members: [:], in: context, recordProbe: recordProbe))
        context.setObject(namespace, forKeyedSubscript: "ns" as NSString)

        let result = try #require(context.evaluateScript(
            """
            (function () {
                return {
                    inResult: 'writeFile' in ns,
                    gopdResult: Object.getOwnPropertyDescriptor(ns, 'writeFile')
                };
            })()
            """
        ))
        #expect(result.forProperty("inResult")?.toBool() == false)
        let gopdResult = result.forProperty("gopdResult")
        #expect(gopdResult == nil || gopdResult!.isUndefined)
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
