//
//  JITAvailability.swift
//  AgenticToolkit
//

import Foundation
import OSLog
import Security

/// Whether a JavaScript engine in this process will be allowed to compile
/// code — and, when it will not, what to tell whoever is wondering why
/// extensions feel slow.
///
/// This exists because the failure it detects has no symptom. Under the
/// hardened runtime, `com.apple.security.cs.allow-jit` is what permits the
/// writable-and-executable mapping a JIT needs. JavaScriptCore does not error
/// when that is refused: it falls back to its interpreter and carries on. So an
/// entitlements tidy-up that drops the key produces extensions that run
/// correctly and slowly, with nothing in the log, nothing on screen, and no
/// failing test — the build is green and signed and wrong.
///
/// **This reads the signature rather than trying the thing.** The obvious
/// implementation — ask for a `MAP_JIT` page and see whether the kernel grants
/// it — was written first and then measured, against one binary signed three
/// ways: hardened and entitled, hardened and bare, and neither. `mmap` with
/// `MAP_JIT` **succeeded in all three**. The check is not performed at mapping
/// time, so a probe built on it can never fail and would have shipped as a
/// check that silently never fires — the same class of defect it was written to
/// catch. The two readings below were measured on those same three binaries and
/// came back `(true, true)`, `(true, false)` and `(false, false)`: they
/// discriminate, which is the whole reason they are what this type reads.
public struct JITAvailability: Sendable, Hashable {

    /// This process's own code signature has the hardened runtime flag set.
    ///
    /// Without it nothing enforces the entitlement, so its absence costs
    /// nothing — which is why this is half of the verdict rather than context.
    public let isHardenedRuntime: Bool

    /// This process's own code signature declares
    /// `com.apple.security.cs.allow-jit`.
    public let hasJITEntitlement: Bool

    public init(isHardenedRuntime: Bool, hasJITEntitlement: Bool) {
        self.isHardenedRuntime = isHardenedRuntime
        self.hasJITEntitlement = hasJITEntitlement
    }

    /// True when a JavaScript engine in this process will be running
    /// interpreted.
    ///
    /// Both halves are needed, and one of them is the reason this does not
    /// warn on every developer's machine all day: a local Debug build is not
    /// hardened, so it has no entitlement and needs none. A warning there would
    /// be on screen constantly, which is how the one warning that matters gets
    /// learned into invisibility.
    public var isDegraded: Bool { isHardenedRuntime && !hasJITEntitlement }

    /// What to tell a person, or `nil` when there is nothing wrong.
    ///
    /// Written as prose rather than as a code, because both surfaces it reaches
    /// — the log and the Extensions settings panel — are read by someone who
    /// has noticed that extensions feel slow and is looking for the reason.
    public var diagnosis: String? {
        guard isDegraded else { return nil }

        return """
            Extensions will run slowly. This build is signed with the hardened \
            runtime but without the com.apple.security.cs.allow-jit \
            entitlement, so the system refuses the executable memory \
            JavaScriptCore needs to compile extension code, and it silently \
            falls back to its interpreter instead. Extensions will work; every \
            one of them will run interpreted. The entitlement belongs in \
            App.entitlements.
            """
    }

    /// The answer for this process, read once.
    ///
    /// Memoized because it cannot change while the process lives — a signature
    /// is fixed at launch — and because a read per call site would let a
    /// process-wide constant disagree with itself.
    public static let current = probe()

    /// Reads both facts off this process's signature, now.
    ///
    /// Public so a test can show the memoized value is the same reading rather
    /// than a separate one; production reads `current`.
    public static func probe() -> JITAvailability {
        JITAvailability(
            isHardenedRuntime: readHardenedRuntimeFlag(),
            hasJITEntitlement: readJITEntitlement()
        )
    }

    /// `kSecCodeSignatureRuntime` — the hardened runtime bit in the signature's
    /// flags word. Named here because the constant is not exposed to Swift.
    private static let hardenedRuntimeFlag: UInt32 = 0x0001_0000

    /// Reads the signing flags of the running process and looks for the
    /// hardened runtime bit.
    ///
    /// Starts from this process's own code object rather than from a path we
    /// guessed at, so an ad-hoc re-sign, a stale `.entitlements` that never
    /// reached the signature, and a copy someone re-signed by hand all read
    /// correctly — each of which is a way this has gone wrong before. An
    /// unreadable signature answers `false`, which is the quiet direction:
    /// this type may not invent a problem it cannot demonstrate.
    private static func readHardenedRuntimeFlag() -> Bool {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess,
              let code
        else { return false }

        // `SecCodeCopySigningInformation` wants the static form. This is the
        // supported conversion; the alternative is a force cast, which is a
        // SwiftLint error here and would be a lie about the type relationship.
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else { return false }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
            let dictionary = information as? [String: Any],
            let flags = dictionary[kSecCodeInfoFlags as String] as? UInt32
        else { return false }

        return flags & hardenedRuntimeFlag != 0
    }

    /// Reads `com.apple.security.cs.allow-jit` off this process's own
    /// signature.
    ///
    /// `SecTaskCreateFromSelf` reads what the kernel actually granted this
    /// process, not what a file on disk says — the same reason the flags above
    /// come from the running code.
    private static func readJITEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.security.cs.allow-jit" as CFString,
            nil
        )
        return (value as? Bool) ?? false
    }
}

extension JITAvailability: Loggable {
    public static nonisolated let logger = makeLogger()

    /// Writes the diagnosis to the log, at most once per process.
    ///
    /// Called from wherever a JavaScript engine is first created. At most once
    /// because the condition is a property of the process: repeating it per
    /// extension would bury the one line that matters under a copy of itself.
    public static func logIfDegraded() {
        _ = hasLogged
    }

    private static let hasLogged: Bool = {
        guard let diagnosis = current.diagnosis else { return true }
        logger.error("\(diagnosis, privacy: .public)")
        return true
    }()
}
