import Foundation
import Testing
@testable import AgenticToolkitCore

/// The predicate that decides whether a string off a third party's manifest may
/// be spliced into a path or a URL.
///
/// Two call sites splice it: `VSIXInstaller` builds a directory name under the
/// extensions folder, and `OpenVSXClient.detail` builds a registry URL. Both
/// are reachable from a manifest nobody here wrote, and the rule had no test of
/// its own — each caller's suite exercised the couple of shapes that caller
/// happened to think of.
///
/// The rule is a denylist, so the tests come in pairs: every refusal is worth
/// little without the neighbouring name it must *not* refuse. A predicate that
/// rejects everything is perfectly safe and perfectly useless, and only the
/// acceptance half can tell the two apart.
@Suite
struct ExtensionIdentityComponentTests {

    // MARK: - The names the catalog is actually full of

    @Test("the ordinary shapes of an identifier and a version are accepted")
    func ordinaryNamesAreAccepted() {
        #expect(ExtensionIdentityComponent.isSafe("ms-python"))
        #expect(ExtensionIdentityComponent.isSafe("python"))
        #expect(ExtensionIdentityComponent.isSafe("ms-python.python"))
        #expect(ExtensionIdentityComponent.isSafe("1.0.0"))
        #expect(ExtensionIdentityComponent.isSafe("2024.1.0-rc.1"))
        #expect(ExtensionIdentityComponent.isSafe("vscode-icons-team"))
        #expect(ExtensionIdentityComponent.isSafe("_underscore"))
        #expect(ExtensionIdentityComponent.isSafe("7"))
    }

    /// The reason the rule is a denylist rather than an allowlist, stated as a
    /// test: publisher and extension names are internationalised, and an
    /// allowlist of characters refuses a legitimate Japanese or Cyrillic name
    /// long before it refuses a hostile ASCII one.
    @Test("a name outside ASCII is accepted")
    func internationalisedNamesAreAccepted() {
        #expect(ExtensionIdentityComponent.isSafe("日本語パック"))
        #expect(ExtensionIdentityComponent.isSafe("расширение"))
        #expect(ExtensionIdentityComponent.isSafe("café-thème"))
        #expect(ExtensionIdentityComponent.isSafe("emoji-🎉-pack"))
    }

    /// An interior dot is in nearly every identifier and every version string,
    /// so only the leading one is structural. This is the pair to
    /// `aLeadingDotIsRefused` below and the one that stops the fix for it from
    /// being "refuse dots".
    @Test("an interior dot is not structural and is accepted")
    func interiorDotsAreAccepted() {
        #expect(ExtensionIdentityComponent.isSafe("a.b"))
        #expect(ExtensionIdentityComponent.isSafe("a..b"))
        #expect(ExtensionIdentityComponent.isSafe("trailing."))
    }

    // MARK: - Names that would point somewhere else

    /// Empty is its own refusal and not a special case of the others: an empty
    /// component joined into a path collapses out of it entirely, so
    /// `<extensions>/<id>-<version>` silently becomes a name the caller never
    /// asked for rather than a name it can see is wrong.
    @Test("an empty component is refused")
    func emptyIsRefused() {
        #expect(!ExtensionIdentityComponent.isSafe(""))
    }

    /// Both of the things a leading dot does: `..` climbs out of the directory,
    /// and a single leading dot hides the result from every listing that has to
    /// show it.
    @Test("a leading dot is refused, whether it climbs or only hides")
    func aLeadingDotIsRefused() {
        #expect(!ExtensionIdentityComponent.isSafe("."))
        #expect(!ExtensionIdentityComponent.isSafe(".."))
        #expect(!ExtensionIdentityComponent.isSafe("../../etc"))
        #expect(!ExtensionIdentityComponent.isSafe(".hidden"))
        #expect(!ExtensionIdentityComponent.isSafe(".ssh"))
    }

    /// The three separators, and why there are three rather than one. `/` is
    /// the path separator and the URL one; `\` is neither on this platform but
    /// is what a name copied from a Windows manifest carries, and a value that
    /// is not a separator *here* is still one wherever this string is written
    /// down next; `:` is still mapped to `/` by the HFS-era APIs a file name
    /// can reach.
    @Test("a separator of any of the three kinds is refused")
    func separatorsAreRefused() {
        #expect(!ExtensionIdentityComponent.isSafe("a/b"))
        #expect(!ExtensionIdentityComponent.isSafe("/absolute"))
        #expect(!ExtensionIdentityComponent.isSafe("trailing/"))
        #expect(!ExtensionIdentityComponent.isSafe("a\\b"))
        #expect(!ExtensionIdentityComponent.isSafe("..\\..\\windows"))
        #expect(!ExtensionIdentityComponent.isSafe("a:b"))
        #expect(!ExtensionIdentityComponent.isSafe("Macintosh HD:Users"))
    }

    /// A newline in a name that ends up in a URL is a request smuggling
    /// primitive, and one in a name that ends up in the settings list is a row
    /// that can forge the row beneath it. Neither is visible to whoever reads
    /// the manifest.
    @Test("a control character anywhere in the name is refused")
    func controlCharactersAreRefused() {
        #expect(!ExtensionIdentityComponent.isSafe("a\nb"))
        #expect(!ExtensionIdentityComponent.isSafe("a\rb"))
        #expect(!ExtensionIdentityComponent.isSafe("a\tb"))
        #expect(!ExtensionIdentityComponent.isSafe("a\u{0}b"))
        #expect(!ExtensionIdentityComponent.isSafe("\u{7F}"))
        #expect(!ExtensionIdentityComponent.isSafe("trailing-newline\n"))
    }

    /// The exact edges of the control-character range, because an off-by-one
    /// here is either a refused space — which no manifest expects — or an
    /// accepted `US` separator.
    @Test("the control-character range stops exactly where it should")
    func theControlRangeEdgesAreRight() {
        #expect(!ExtensionIdentityComponent.isSafe("a\u{1F}b"))
        #expect(ExtensionIdentityComponent.isSafe("a\u{20}b"))
        #expect(ExtensionIdentityComponent.isSafe("a\u{7E}b"))
        #expect(!ExtensionIdentityComponent.isSafe("a\u{7F}b"))
        // Not a control character by this rule, and deliberately: `U+0080` and
        // its neighbours are C1, but refusing them would start the allowlist
        // this rule exists to avoid — and none of them is a separator.
        #expect(ExtensionIdentityComponent.isSafe("a\u{80}b"))
    }

    /// A percent-encoded separator is not a separator *here*, which is the
    /// point worth pinning: this predicate refuses rather than escapes, so the
    /// string it lets through is spliced verbatim. A caller that decoded before
    /// splicing would reintroduce the separator behind the check.
    @Test("an already-encoded separator is accepted, because nothing decodes it")
    func anEncodedSeparatorIsNotASeparator() {
        #expect(ExtensionIdentityComponent.isSafe("a%2Fb"))
        #expect(ExtensionIdentityComponent.isSafe("a%2E%2E"))
    }
}
