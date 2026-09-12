import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitMacOS

/// `vscode.Uri` (task 5.4a): the installed JS class itself
/// (`VSCodeAPI.installUriClass(in:)`), and the Swift↔JS bridge built on top of
/// it (`VSCodeAPI.url(from:in:)` / `VSCodeAPI.uriValue(for:in:)`).
///
/// A bare `JSContext`, not an `ExtensionHost`: every function under test here
/// takes a `JSContext` and nothing else, so a suite exercising them needs no
/// extension, no manifest and no activation — the ceremony this file tests is
/// deliberately usable before any of that exists. `MainThreadCommandsTests`
/// covers the same class reached through a real host's `vscode.Uri` member;
/// this suite covers the class and the bridge directly.
@MainActor
@Suite
struct UriTests {

    /// A fresh context with the `Uri` class installed and exposed as a plain
    /// global `Uri`, so a test's own script can read it the way extension
    /// code would read `vscode.Uri` — without repeating the install call in
    /// every test.
    private func makeContext() throws -> JSContext {
        let context = try #require(JSContext())
        let uriClass = try #require(VSCodeAPI.installUriClass(in: context))
        context.setObject(uriClass, forKeyedSubscript: "Uri" as NSString)
        return context
    }

    // MARK: - Uri.file

    /// `Uri.file` sets `scheme` to `'file'`, leaves `authority` empty, and
    /// carries the path through unchanged when it needs no percent-encoding.
    @Test
    func uriFileSetsSchemeAndPath() throws {
        let context = try makeContext()
        let uri = try #require(context.evaluateScript("Uri.file('/tmp/example.txt')"))
        #expect(uri.forProperty("scheme")?.toString() == "file")
        #expect(uri.forProperty("path")?.toString() == "/tmp/example.txt")
        #expect(uri.forProperty("authority")?.toString() == "")
    }

    /// A space in the path is percent-encoded in `path`, and the segment
    /// separators (`/`) survive the encoding — proof `encodePath` splits,
    /// encodes each segment, and rejoins rather than calling
    /// `encodeURIComponent` on the whole path (which would turn every `/`
    /// into `%2F`).
    @Test
    func uriFilePercentEncodesASpaceButNotTheSlashes() throws {
        let context = try makeContext()
        let uri = try #require(context.evaluateScript("Uri.file('/tmp/a b/c.txt')"))
        #expect(uri.forProperty("path")?.toString() == "/tmp/a%20b/c.txt")
    }

    // MARK: - Uri.parse

    /// `Uri.parse` splits a URI string into `scheme`, `authority`, `path`,
    /// `query` and `fragment`.
    @Test
    func uriParseSplitsSchemeAuthorityPathQueryAndFragment() throws {
        let context = try makeContext()
        let uri = try #require(context.evaluateScript("Uri.parse('https://example.com/a/b?x=1#frag')"))
        #expect(uri.forProperty("scheme")?.toString() == "https")
        #expect(uri.forProperty("authority")?.toString() == "example.com")
        #expect(uri.forProperty("path")?.toString() == "/a/b")
        #expect(uri.forProperty("query")?.toString() == "x=1")
        #expect(uri.forProperty("fragment")?.toString() == "frag")
    }

    /// A scheme with no `//` authority marker (`mailto:`) parses with an
    /// empty `authority`, and — the point this test exists to pin — its
    /// `toString()` does not reintroduce a `//` that was never there.
    @Test
    func uriParseWithNoAuthorityMarkerOmitsTheSlashesOnToString() throws {
        let context = try makeContext()
        let uri = try #require(context.evaluateScript("Uri.parse('mailto:a@b.com')"))
        #expect(uri.forProperty("authority")?.toString() == "")
        #expect(uri.forProperty("scheme")?.toString() == "mailto")
        let asString = try #require(uri.invokeMethod("toString", withArguments: []))
        #expect(asString.toString() == "mailto:a@b.com")
    }

    // MARK: - fsPath vs. path

    /// `fsPath` is `path` decoded — the two differ exactly where a percent
    /// escape was in the path.
    @Test
    func fsPathDecodesWherePathIsEncoded() throws {
        let context = try makeContext()
        let uri = try #require(context.evaluateScript("Uri.parse('file:///a%20b')"))
        #expect(uri.forProperty("path")?.toString() == "/a%20b")
        #expect(uri.forProperty("fsPath")?.toString() == "/a b")
    }

    /// `fsPath` stays sane (a plain, usable string) for a non-`file` scheme
    /// too — it is not `file`-scheme-specific, just "`path`, decoded".
    @Test
    func fsPathIsSaneForANonFileScheme() throws {
        let context = try makeContext()
        let uri = try #require(context.evaluateScript("Uri.parse('untitled:Untitled-1')"))
        #expect(uri.forProperty("path")?.toString() == "Untitled-1")
        #expect(uri.forProperty("fsPath")?.toString() == "Untitled-1")
    }

    // MARK: - with()

    /// `with()` replaces only the fields named in its argument; everything
    /// else — here, `scheme` — carries over from the receiver.
    @Test
    func withReplacesOnlyWhatIsGiven() throws {
        let context = try makeContext()
        let uri = try #require(context.evaluateScript("Uri.file('/a/b').with({ path: '/a/c' })"))
        #expect(uri.forProperty("path")?.toString() == "/a/c")
        #expect(uri.forProperty("scheme")?.toString() == "file")
    }

    /// `with()` answers a new instance; the receiver is untouched — a `Uri`
    /// is a value type, and `Object.freeze(this)` in the constructor is what
    /// makes that true even under a hostile caller.
    @Test
    func withLeavesTheReceiverUntouched() throws {
        let context = try makeContext()
        context.evaluateScript("var base = Uri.file('/a/b'); var changed = base.with({ path: '/a/c' });")
        let base = try #require(context.evaluateScript("base"))
        #expect(base.forProperty("path")?.toString() == "/a/b")
    }

    // MARK: - toString() round-trips through Uri.parse

    /// `Uri.parse(x.toString())` reproduces every component of `x` — the
    /// round trip a `Map` key or a serialised command argument depends on.
    @Test
    func toStringRoundTripsThroughParseToAnEqualUri() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var original = Uri.parse('https://example.com/a/b?x=1#frag');
                var roundTripped = Uri.parse(original.toString());
                return original.scheme === roundTripped.scheme &&
                    original.authority === roundTripped.authority &&
                    original.path === roundTripped.path &&
                    original.query === roundTripped.query &&
                    original.fragment === roundTripped.fragment;
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    /// The same round trip holds for a no-authority scheme, where a naive
    /// "authority is truthy, so show `//`" implementation would drop the
    /// distinction `_hasAuthority` exists to preserve.
    @Test
    func toStringRoundTripsForANoAuthorityScheme() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var original = Uri.parse('mailto:a@b.com');
                var roundTripped = Uri.parse(original.toString());
                return original.toString() === roundTripped.toString();
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    // MARK: - Uri.joinPath

    /// `joinPath` inserts a `/` between the base and the appended segments
    /// when the base has no trailing one.
    @Test
    func joinPathInsertsASlashWhenTheBaseHasNoTrailingOne() throws {
        let context = try makeContext()
        let uri = try #require(context.evaluateScript("Uri.joinPath(Uri.file('/a/b'), 'c', 'd.txt')"))
        #expect(uri.forProperty("path")?.toString() == "/a/b/c/d.txt")
    }

    /// `joinPath` does not double the slash when the base already ends with
    /// one.
    @Test
    func joinPathDoesNotDoubleASlashWhenTheBaseAlreadyHasATrailingOne() throws {
        let context = try makeContext()
        let uri = try #require(context.evaluateScript("Uri.joinPath(Uri.file('/a/b/'), 'c.txt')"))
        #expect(uri.forProperty("path")?.toString() == "/a/b/c.txt")
    }

    // MARK: - Swift bridge: url(from:in:)

    /// A real `Uri` instance bridges to the `URL` its `toString()` names.
    @Test
    func urlFromAcceptsARealUriInstance() throws {
        let context = try makeContext()
        let uri = try #require(context.evaluateScript("Uri.file('/tmp/example.txt')"))
        let url = VSCodeAPI.url(from: uri, in: context)
        #expect(url?.path == "/tmp/example.txt")
    }

    /// A bare string bridges too — the other shape VS Code's own API accepts
    /// wherever it documents a `Uri | string` parameter.
    @Test
    func urlFromAcceptsABareString() throws {
        let context = try makeContext()
        let value = try #require(context.evaluateScript("'https://example.com/a'"))
        let url = VSCodeAPI.url(from: value, in: context)
        #expect(url?.absoluteString == "https://example.com/a")
    }

    /// A number answers `nil` — not a wrong `URL` guessed from some coercion
    /// of it.
    @Test
    func urlFromAnswersNilForANumberRatherThanAWrongURL() throws {
        let context = try makeContext()
        let value = try #require(JSValue(double: 42, in: context))
        #expect(VSCodeAPI.url(from: value, in: context) == nil)
    }

    /// A plain object shaped like a `Uri` (same property names) still answers
    /// `nil`: this bridge is not duck-typed, and never reads a `path`-shaped
    /// property off an object it does not control.
    @Test
    func urlFromAnswersNilForAnArbitraryObject() throws {
        let context = try makeContext()
        let value = try #require(context.evaluateScript("({ path: '/a/b', scheme: 'file' })"))
        #expect(VSCodeAPI.url(from: value, in: context) == nil)
    }

    /// `undefined` answers `nil` rather than crashing or being read as an
    /// empty string.
    @Test
    func urlFromAnswersNilForUndefined() throws {
        let context = try makeContext()
        let value = try #require(JSValue(undefinedIn: context))
        #expect(VSCodeAPI.url(from: value, in: context) == nil)
    }

    // MARK: - Swift bridge: uriValue(for:in:) and the full round trip

    /// A `URL` built in Swift, handed to `uriValue(for:in:)`, and read back
    /// through `url(from:in:)` comes back unchanged.
    @Test
    func aUrlCrossingToJSAndBackIsUnchanged() throws {
        let context = try makeContext()
        let original = try #require(URL(string: "https://example.com/a/b?x=1#frag"))
        let jsValue = try #require(VSCodeAPI.uriValue(for: original, in: context))
        let roundTripped = try #require(VSCodeAPI.url(from: jsValue, in: context))
        #expect(roundTripped.absoluteString == original.absoluteString)
    }
}
