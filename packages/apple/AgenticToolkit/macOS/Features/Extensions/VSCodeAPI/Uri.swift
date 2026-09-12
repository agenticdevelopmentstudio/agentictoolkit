//
//  Uri.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore

/// `vscode.Uri` and its Swift↔JS bridge — shared ceremony for task 5.4a, built
/// once so `workspace`, `window` and every later adaptor construct and read
/// URIs the same way rather than each inventing its own.
///
/// **Why a JS class, not `@convention(block)` accessors.** Every other member
/// this directory installs is a function extension code calls; `vscode.Uri`
/// is a *value type* extension code constructs, reads, compares and passes
/// around by reference — `uri1.with({ path: … }) instanceof vscode.Uri` has to
/// keep being true, `JSON.stringify(uri)` has to go through `toJSON()`, and a
/// `Map` keyed by identity has to see the same object it put in. A
/// `@convention(block)` closure is a function; it cannot be `new`'d, cannot
/// carry instance properties, and cannot be the right-hand side of
/// `instanceof`. What extension code needs here is a real constructor
/// function with a real prototype, which only JavaScript itself can produce.
/// Three consequences follow from that: (1) `scheme`/`authority`/`path` etc.
/// are ordinary prototype accessors, not per-call marshalled arguments; (2)
/// `with()`, `toString()` and `toJSON()` are ordinary prototype methods,
/// callable the way extension code already expects a value type's methods to
/// be callable; (3) a Swift caller that needs to test "is this really a
/// `vscode.Uri`" asks JavaScript's own `instanceof`, via
/// `JSValue.isInstance(of:)`, rather than guessing from shape.
extension VSCodeAPI {

    // MARK: - Installing the class

    /// The global `installUriClass(in:)` caches the class constructor under,
    /// once per context.
    private static nonisolated let uriClassGlobalName = "__vscodeUriClass"

    /// The `Uri` class's own source, evaluated at most once per `JSContext`.
    ///
    /// Written in the same ES5 idiom as `extension-runtime.js` — `var`,
    /// `function`, explicit prototypes — rather than `class`/`let`/arrow
    /// functions, so a reader moving between this file and that one is not
    /// asked to switch style for no reason.
    ///
    /// **Deliberately narrower than real VS Code's `Uri`.** Three
    /// simplifications, each a stated boundary rather than an oversight:
    ///
    ///   1. No Windows drive-letter or UNC handling in `Uri.file` — this host
    ///      only ever runs on macOS, so a POSIX-only path model is the whole
    ///      truth here, not a partial one.
    ///   2. `path` is the percent-*encoded* form parsed straight out of (or
    ///      built straight into) the URI string; `fsPath` is
    ///      `decodeURIComponent(path)`, falling back to `path` unchanged if
    ///      that throws on a malformed escape rather than propagating a
    ///      `URIError` out of a getter. Real VS Code stores components
    ///      decoded internally and re-encodes for `toString()`; this is the
    ///      other way round, and it is enough for `path` to be "the URI
    ///      string's path segment" and `fsPath` to be "that segment, usable
    ///      to open a file" — the two properties this task's tests ask for.
    ///   3. Query and fragment are not decoded at all. Nothing in this task
    ///      reads them for anything but their string form.
    ///
    /// No regex literal (`/…/`) appears anywhere in this pattern on purpose:
    /// a bare `/` inside a regex literal's delimiters ends the literal early
    /// unless escaped, and every group below needs `/` unescaped to match a
    /// URI's own slashes. Building the pattern as a plain string and handing
    /// it to `new RegExp(...)` sidesteps that character entirely — nothing
    /// in it needs escaping in *either* JavaScript's string-literal reader or
    /// Swift's, which is the property worth having when this source cannot
    /// be compiled and exercised before it ships.
    private static nonisolated let uriClassSource = """
    (function () {
        'use strict';
        try {
            var URI_PATTERN = new RegExp(
                '^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)([?]([^#]*))?([#](.*))?'
            );

            function Uri(scheme, authority, path, query, fragment, hasAuthority) {
                this._scheme = scheme || '';
                this._authority = authority || '';
                this._path = path || '';
                this._query = query || '';
                this._fragment = fragment || '';
                this._hasAuthority = Boolean(hasAuthority) || this._authority !== '';
                Object.freeze(this);
            }

            function defineReadOnly(name, getter) {
                Object.defineProperty(Uri.prototype, name, { get: getter, enumerable: true });
            }

            defineReadOnly('scheme', function () { return this._scheme; });
            defineReadOnly('authority', function () { return this._authority; });
            defineReadOnly('path', function () { return this._path; });
            defineReadOnly('query', function () { return this._query; });
            defineReadOnly('fragment', function () { return this._fragment; });
            defineReadOnly('fsPath', function () {
                try {
                    return decodeURIComponent(this._path);
                } catch (malformedEscape) {
                    return this._path;
                }
            });

            Uri.prototype.with = function (change) {
                change = change || {};
                var scheme = change.scheme !== undefined ? change.scheme : this._scheme;
                var authority = change.authority !== undefined ? change.authority : this._authority;
                var path = change.path !== undefined ? change.path : this._path;
                var query = change.query !== undefined ? change.query : this._query;
                var fragment = change.fragment !== undefined ? change.fragment : this._fragment;
                var hasAuthority = this._hasAuthority ||
                    (change.authority !== undefined && change.authority !== '');
                return new Uri(scheme, authority, path, query, fragment, hasAuthority);
            };

            Uri.prototype.toString = function () {
                var result = '';
                if (this._scheme) {
                    result += this._scheme + ':';
                }
                if (this._hasAuthority) {
                    result += '//' + this._authority;
                }
                result += this._path;
                if (this._query) {
                    result += '?' + this._query;
                }
                if (this._fragment) {
                    result += '#' + this._fragment;
                }
                return result;
            };

            Uri.prototype.toJSON = function () {
                return {
                    scheme: this._scheme,
                    authority: this._authority,
                    path: this._path,
                    query: this._query,
                    fragment: this._fragment,
                    fsPath: this.fsPath
                };
            };

            function encodePathSegment(segment) {
                return segment === '' ? '' : encodeURIComponent(segment);
            }

            // Split-encode-join, not a single `encodeURIComponent(path)`:
            // that function escapes '/' along with everything else, which
            // would turn every path separator into '%2F'.
            function encodePath(rawPath) {
                var segments = String(rawPath).split('/');
                var index;
                for (index = 0; index < segments.length; index += 1) {
                    segments[index] = encodePathSegment(segments[index]);
                }
                return segments.join('/');
            }

            Uri.file = function (path) {
                return new Uri('file', '', encodePath(path), '', '', true);
            };

            Uri.parse = function (value) {
                var match = URI_PATTERN.exec(String(value));
                var scheme = (match && match[2]) || '';
                var hasAuthority = Boolean(match && match[3] !== undefined);
                var authority = (match && match[4]) || '';
                var path = (match && match[5]) || '';
                var query = (match && match[7]) || '';
                var fragment = (match && match[9]) || '';
                return new Uri(scheme, authority, path, query, fragment, hasAuthority);
            };

            Uri.joinPath = function (base) {
                var appended = Array.prototype.slice.call(arguments, 1);
                var basePath = (base && base._path) || '';
                var suffix = encodePath(appended.join('/'));
                var joinedPath;
                if (suffix === '') {
                    joinedPath = basePath;
                } else if (basePath === '' || basePath.charAt(basePath.length - 1) === '/') {
                    joinedPath = basePath + suffix;
                } else {
                    joinedPath = basePath + '/' + suffix;
                }
                return new Uri(base._scheme, base._authority, joinedPath, '', '', base._hasAuthority);
            };

            try {
                Object.defineProperty(globalThis, '\(uriClassGlobalName)', {
                    value: Uri,
                    writable: false,
                    enumerable: false,
                    configurable: false
                });
            } catch (ignored) {
                // Caching is an optimisation, exactly as in `helperSource`;
                // the class works without it, just re-evaluated per call.
            }
            return Uri;
        } catch (error) {
            return null;
        }
    })()
    """

    /// The `vscode.Uri` constructor for `context`, evaluating it the first
    /// time and reading it back afterwards — `sharedHelper(in:)`'s exact
    /// pattern, for the same reason: a Swift-side `[ObjectIdentifier: JSValue]`
    /// cache would retain every context it was ever called for.
    ///
    /// This is the class Swift constructs and recognises instances of via
    /// `uriValue(for:in:)` and `url(from:in:)`. `ExtensionHost.installRuntime`
    /// separately installs the *same* object as `vscode.Uri`, so extension
    /// code and this bridge are always looking at one constructor, never two
    /// that happen to look alike.
    public static func installUriClass(in context: JSContext) -> JSValue? {
        if let cached = context.objectForKeyedSubscript(uriClassGlobalName), cached.isObject {
            return cached
        }
        guard let created = context.evaluateScript(uriClassSource), created.isObject else {
            logger.error(
                """
                Could not install the 'vscode.Uri' class in context \
                '\(name(of: context), privacy: .public)'; it stays the shim's not-implemented stub
                """)
            return nil
        }
        return created
    }

    // MARK: - Swift ↔ JS bridging

    /// Reads a `URL` out of a JavaScript value that is either a real
    /// `vscode.Uri` instance or a plain string — the two shapes VS Code's own
    /// API accepts wherever it documents a `Uri | string` parameter — and
    /// answers `nil` for anything else, **without raising**.
    ///
    /// Deliberately not duck-typed. A number, a plain `{ path: '/x' }` object,
    /// or `undefined` all answer `nil` here rather than being read for a
    /// `path`-shaped property: reading properties off an object this bridge
    /// does not control risks running an extension-authored getter, which is
    /// exactly the class of bug `outcome(of:in:)` and `thenFunction(of:in:)`
    /// exist to keep out of `ExtensionHost.pendingException`. Restricting the
    /// accepted shapes to "really is a `Uri`" or "is a string" is what makes
    /// "nil for anything else" a safe default rather than a guess.
    ///
    /// The one property read this function does make on a `Uri` instance —
    /// its `toString` function — is invoked through `call(_:thisArg:arguments:)`
    /// rather than `JSValue.invokeMethod(_:withArguments:)`, so a `toString`
    /// an extension has shadowed (subclassing `vscode.Uri` is unusual, but
    /// nothing here forbids it) is caught the same way a hostile `.then`
    /// getter is, rather than landing its throw in the host's
    /// `pendingException`. Reading the `toString` property itself is not
    /// routed through that same guard — a residual, accepted risk exactly
    /// like the ones `outcome(of:in:)`'s own doc comment names, bounded to
    /// the extension that did it to its own context.
    public static func url(from value: JSValue, in context: JSContext) -> URL? {
        if value.isString {
            guard let string = value.toString() else { return nil }
            return URL(string: string)
        }
        guard let uriClass = installUriClass(in: context), value.isInstance(of: uriClass) else {
            return nil
        }
        guard let toStringFunction = value.forProperty("toString"), toStringFunction.isObject else {
            return nil
        }
        guard case .returned(let result) = call(toStringFunction, thisArg: value, arguments: []),
              let result, result.isString, let string = result.toString() else {
            return nil
        }
        return URL(string: string)
    }

    /// Builds a `vscode.Uri` instance in `context` for `url` — the reverse of
    /// `url(from:in:)`, for a member that hands a `URL` the app already has
    /// back to the extension as a `Uri`.
    ///
    /// Goes through `Uri.parse(url.absoluteString)` rather than
    /// distinguishing file URLs and calling `Uri.file(...)`: a single path
    /// keeps every scheme this bridge is ever asked to carry — `file:`,
    /// `untitled:`, anything a later stage adds — behaving the same way, and
    /// `absoluteString` already carries whatever percent-encoding the `URL`
    /// itself settled on, which `Uri.parse` reads back as this class's own
    /// `path`. Calling `Uri.parse` directly (not through the `call` guard
    /// `url(from:in:)` uses) is safe here for the same reason evaluating
    /// `uriClassSource` itself is: this is host-authored JavaScript, run with
    /// no extension code anywhere on its call stack, not a value extension
    /// code could have reshaped.
    public static func uriValue(for url: URL, in context: JSContext) -> JSValue? {
        guard let uriClass = installUriClass(in: context),
              let parseFunction = uriClass.forProperty("parse"), parseFunction.isObject else {
            return nil
        }
        let result = parseFunction.call(withArguments: [url.absoluteString])
        guard let result, !result.isUndefined, !result.isNull else { return nil }
        return result
    }
}
