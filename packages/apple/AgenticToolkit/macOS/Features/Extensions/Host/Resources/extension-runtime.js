//
//  extension-runtime.js
//  AgenticToolkit
//
//  The bounded runtime a VS Code *web* extension sees inside its JSContext.
//  ExtensionHost evaluates this once per context, before the extension's own
//  code, and then deletes the two globals it talks to the host through — so an
//  extension can reach exactly what this file hands it and nothing else.
//
//  Three things live here, and only three:
//
//    1. The CommonJS module wrapper and a `require` that resolves `vscode`.
//    2. The small slice of the web platform an extension may legitimately
//       expect from a JSContext, which supplies none of it: console, timers,
//       TextEncoder/TextDecoder, URL and URLSearchParams.
//    3. The NotImplemented stub mechanism — the load-bearing part. Everything
//       the `vscode` namespace does not implement *yet* throws a named error
//       and is recorded, so an extension that reaches for a missing member
//       fails loudly and the user can be told which member it was.
//

'use strict';

(function (global) {
    'use strict';

    // The host's block table. Captured into this closure and deleted from the
    // global object by ExtensionHost immediately after this script runs, so
    // extension code cannot call back into the app through it.
    var host = global.__host;

    // =====================================================================
    // MARK: - Value formatting (console)
    // =====================================================================

    var FORMAT_MAX_DEPTH = 4;

    function formatFunction(value) {
        return value.name ? '[Function: ' + value.name + ']' : '[Function (anonymous)]';
    }

    function formatEntries(parts, open, close) {
        if (parts.length === 0) {
            return open + close;
        }
        return open + ' ' + parts.join(', ') + ' ' + close;
    }

    function formatKey(key) {
        return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(key) ? key : JSON.stringify(key);
    }

    // `console.log({ a: 1 })` must not arrive as `[object Object]`. Node's
    // `util.inspect` shape is what a developer reading a log expects, so this
    // approximates it: quoted strings once nested, cycles marked rather than
    // followed, and a depth cap so a deep object cannot produce a log line
    // nobody can read.
    function format(value, depth, seen) {
        if (value === null) {
            return 'null';
        }
        var type = typeof value;
        if (type === 'undefined') {
            return 'undefined';
        }
        if (type === 'string') {
            return depth === 0 ? value : JSON.stringify(value);
        }
        if (type === 'number' || type === 'boolean' || type === 'bigint') {
            return String(value);
        }
        if (type === 'symbol') {
            return String(value);
        }
        if (type === 'function') {
            return formatFunction(value);
        }

        if (value instanceof Error) {
            var described = (value.name || 'Error') + ': ' + (value.message || '');
            return value.stack ? described + '\n' + value.stack : described;
        }
        if (value instanceof Date) {
            return isNaN(value.getTime()) ? 'Invalid Date' : value.toISOString();
        }
        if (value instanceof RegExp) {
            return String(value);
        }

        if (seen.indexOf(value) !== -1) {
            return '[Circular]';
        }
        if (depth >= FORMAT_MAX_DEPTH) {
            return Array.isArray(value) ? '[Array]' : '[Object]';
        }

        seen.push(value);
        try {
            return formatContainer(value, depth, seen);
        } finally {
            seen.pop();
        }
    }

    function formatContainer(value, depth, seen) {
        var parts = [];
        var index;

        if (Array.isArray(value)) {
            for (index = 0; index < value.length; index += 1) {
                parts.push(format(value[index], depth + 1, seen));
            }
            return formatEntries(parts, '[', ']');
        }
        if (typeof Map !== 'undefined' && value instanceof Map) {
            value.forEach(function (entryValue, entryKey) {
                parts.push(format(entryKey, depth + 1, seen) + ' => ' + format(entryValue, depth + 1, seen));
            });
            return 'Map(' + value.size + ') ' + formatEntries(parts, '{', '}');
        }
        if (typeof Set !== 'undefined' && value instanceof Set) {
            value.forEach(function (entryValue) {
                parts.push(format(entryValue, depth + 1, seen));
            });
            return 'Set(' + value.size + ') ' + formatEntries(parts, '{', '}');
        }

        var keys = Object.keys(value);
        for (index = 0; index < keys.length; index += 1) {
            parts.push(formatKey(keys[index]) + ': ' + format(value[keys[index]], depth + 1, seen));
        }

        // A class instance says which class, the way `util.inspect` does; a
        // plain object says nothing extra.
        var constructorName = value.constructor && value.constructor.name;
        var prefix = constructorName && constructorName !== 'Object' ? constructorName + ' ' : '';
        return prefix + formatEntries(parts, '{', '}');
    }

    function formatArguments(args) {
        var parts = [];
        for (var index = 0; index < args.length; index += 1) {
            parts.push(format(args[index], 0, []));
        }
        return parts.join(' ');
    }

    // =====================================================================
    // MARK: - console
    // =====================================================================

    function makeConsoleMethod(level) {
        return function () {
            host.console(level, formatArguments(arguments));
        };
    }

    global.console = {
        log: makeConsoleMethod('log'),
        info: makeConsoleMethod('info'),
        warn: makeConsoleMethod('warn'),
        error: makeConsoleMethod('error'),
        debug: makeConsoleMethod('debug')
    };

    // =====================================================================
    // MARK: - Timers
    // =====================================================================
    //
    // The callback lives here; the clock lives in Swift. That split is what
    // makes teardown real: ExtensionHost cancels every outstanding timer when
    // it disposes, and a cancelled timer can never reach this table again.

    var nextTimerID = 1;
    var timers = Object.create(null);

    function schedule(callback, delay, args, repeats, apiName) {
        if (typeof callback !== 'function') {
            throw new TypeError(apiName + ' requires a function as its first argument.');
        }
        var delayMilliseconds = Number(delay);
        if (!isFinite(delayMilliseconds) || delayMilliseconds < 0) {
            delayMilliseconds = 0;
        }
        var timerID = nextTimerID;
        nextTimerID += 1;
        timers[timerID] = { callback: callback, args: args, repeats: repeats };
        host.scheduleTimer(timerID, delayMilliseconds, repeats);
        return timerID;
    }

    function cancel(timerID) {
        var key = Number(timerID);
        if (!isFinite(key)) {
            return;
        }
        delete timers[key];
        host.cancelTimer(key);
    }

    function tail(args) {
        return Array.prototype.slice.call(args, 2);
    }

    global.setTimeout = function (callback, delay) {
        return schedule(callback, delay, tail(arguments), false, 'setTimeout');
    };

    global.setInterval = function (callback, delay) {
        return schedule(callback, delay, tail(arguments), true, 'setInterval');
    };

    global.clearTimeout = cancel;
    global.clearInterval = cancel;

    // Called by ExtensionHost when a timer it owns comes due. An exception in
    // the callback is reported rather than propagated: it belongs to the
    // extension, and letting it escape here would surface as an unattributed
    // failure of whatever the host happened to be doing.
    function fireTimer(timerID) {
        var timer = timers[timerID];
        if (!timer) {
            return;
        }
        if (!timer.repeats) {
            delete timers[timerID];
        }
        try {
            timer.callback.apply(undefined, timer.args);
        } catch (error) {
            host.console('error', 'Uncaught exception in a timer callback: ' + format(error, 0, []));
        }
    }

    // =====================================================================
    // MARK: - The NotImplemented contract
    // =====================================================================
    //
    // A stub that returns `undefined` produces an extension that appears to
    // activate and then does nothing, with no way for anyone to learn why.
    // So: reaching for a member this host does not implement records the full
    // member path and throws an error naming it. Property *access* throws,
    // not just invocation, because most of the VS Code API's absent members
    // are values rather than functions — `vscode.workspace.workspaceFolders`
    // handed back as a throwing function would be quiet in exactly the way
    // this mechanism exists to prevent.
    //
    // Replacing a stub with a real implementation is a one-line change: put
    // the value in the namespace's member table (see `vscodeMembers` below).
    // The stub path is only ever reached for keys the table does not hold, so
    // stages 5.3-5.7 each fill in a slice without touching this machinery.

    // Keys the language, the debugger and bundled CommonJS interop shims probe
    // on any object they are handed. Throwing on these would fail an extension
    // before its first statement ran, and none of them is an extension asking
    // for an API member — so they answer `undefined` quietly.
    var PROBE_KEYS = [
        'then', 'toJSON', 'toString', 'valueOf', 'constructor', 'inspect',
        '__esModule', 'prototype', 'nodeType', 'hasOwnProperty'
    ];

    function notImplementedError(memberPath) {
        var error = new Error(
            memberPath + ' is not implemented yet. This extension host implements the VS Code ' +
            'API one member at a time, and ' + memberPath + ' is not available in this build.'
        );
        error.name = 'NotImplementedError';
        error.memberPath = memberPath;
        return error;
    }

    // `members` is the table of members that *are* implemented at `path`.
    // Everything else under `path` is recorded and throws.
    function makeStubNamespace(path, members) {
        var table = members || Object.create(null);
        return new Proxy(Object.create(null), {
            get: function (target, key) {
                // JSC itself reads symbol keys (Symbol.toPrimitive,
                // Symbol.iterator) while coercing and iterating. Never an
                // extension asking for an API member.
                if (typeof key === 'symbol') {
                    return undefined;
                }
                if (key in table) {
                    return table[key];
                }
                if (PROBE_KEYS.indexOf(key) !== -1) {
                    return undefined;
                }
                var memberPath = path + '.' + key;
                host.recordNotImplemented(memberPath);
                throw notImplementedError(memberPath);
            },
            has: function (target, key) {
                return typeof key !== 'symbol' && key in table;
            },
            set: function (target, key) {
                throw new TypeError(
                    'Cannot assign to ' + path + '.' + String(key) + ': the VS Code API is read-only.'
                );
            },
            deleteProperty: function (target, key) {
                throw new TypeError(
                    'Cannot delete ' + path + '.' + String(key) + ': the VS Code API is read-only.'
                );
            },
            ownKeys: function () {
                return Object.keys(table);
            },
            getOwnPropertyDescriptor: function (target, key) {
                if (typeof key === 'symbol' || !(key in table)) {
                    return undefined;
                }
                return { value: table[key], enumerable: true, configurable: true, writable: false };
            }
        });
    }

    // The namespaces stages 5.3-5.7 fill in. Listing one here is what makes
    // `vscode.commands.registerCommand` record the *full* path rather than
    // stopping at `vscode.commands` — the namespace is traversable, its
    // members are not. A name absent from this list (`vscode.Uri`, say) is
    // itself the unimplemented member, which is the honest answer for an API
    // surface this host has made no plan for yet.
    var VSCODE_NAMESPACES = ['commands', 'workspace', 'window', 'languages', 'lm'];

    var vscodeMembers = Object.create(null);
    VSCODE_NAMESPACES.forEach(function (name) {
        // Each namespace gets its own member table. Stage 5.3 implements
        // `vscode.commands.registerCommand` by putting a function in this
        // one — nothing else in this file changes.
        vscodeMembers[name] = makeStubNamespace('vscode.' + name, Object.create(null));
    });
    var vscode = makeStubNamespace('vscode', vscodeMembers);

    // Deliberately not implemented in this task, and this stub is the record
    // of that decision rather than a comment promising one later. Giving
    // arbitrary extension JavaScript unrestricted network access is a
    // user-facing security posture, not a shim detail; it gets its own task
    // with a stated policy. Recorded like any other missing member, so the
    // extension report can tell a user their extension wanted the network.
    global.fetch = function () {
        host.recordNotImplemented('fetch');
        throw notImplementedError('fetch');
    };

    // =====================================================================
    // MARK: - require
    // =====================================================================

    function require(specifier) {
        if (specifier === 'vscode') {
            return vscode;
        }
        // Named, because "module not found" without the name is the least
        // useful thing a bundler-adjacent failure can say.
        var error = new Error(
            "Cannot find module '" + specifier + "'. This extension host resolves only 'vscode'; " +
            'a web extension must be bundled with every other dependency inlined.'
        );
        error.name = 'ModuleNotFoundError';
        error.code = 'MODULE_NOT_FOUND';
        error.specifier = specifier;
        throw error;
    }

    // =====================================================================
    // MARK: - TextEncoder / TextDecoder
    // =====================================================================
    //
    // UTF-8 only, and it says so rather than mis-decoding: a decoder asked for
    // an encoding it does not have would otherwise hand back plausible-looking
    // mojibake that nothing downstream can detect.

    var UTF8_LABELS = [
        'utf-8', 'utf8', 'unicode-1-1-utf-8', 'unicode11utf8', 'unicode20utf8', 'x-unicode20utf8'
    ];
    var REPLACEMENT = String.fromCharCode(0xFFFD);

    function TextEncoder() {}

    Object.defineProperty(TextEncoder.prototype, 'encoding', {
        get: function () { return 'utf-8'; }
    });

    TextEncoder.prototype.encode = function (input) {
        var text = input === undefined ? '' : String(input);
        var bytes = [];
        for (var index = 0; index < text.length; index += 1) {
            var code = text.charCodeAt(index);
            if (code >= 0xD800 && code <= 0xDBFF && index + 1 < text.length) {
                var low = text.charCodeAt(index + 1);
                if (low >= 0xDC00 && low <= 0xDFFF) {
                    code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                    index += 1;
                }
            }
            if (code >= 0xD800 && code <= 0xDFFF) {
                // A lone surrogate is not encodable; the WHATWG encoding
                // standard substitutes U+FFFD rather than emitting garbage.
                code = 0xFFFD;
            }
            if (code < 0x80) {
                bytes.push(code);
            } else if (code < 0x800) {
                bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
            } else if (code < 0x10000) {
                bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
            } else {
                bytes.push(
                    0xF0 | (code >> 18),
                    0x80 | ((code >> 12) & 0x3F),
                    0x80 | ((code >> 6) & 0x3F),
                    0x80 | (code & 0x3F)
                );
            }
        }
        return new Uint8Array(bytes);
    };

    function TextDecoder(label) {
        var requested = label === undefined ? 'utf-8' : String(label).trim().toLowerCase();
        if (UTF8_LABELS.indexOf(requested) === -1) {
            throw new RangeError(
                "TextDecoder: '" + label + "' is not supported. This extension host decodes UTF-8 only."
            );
        }
    }

    Object.defineProperty(TextDecoder.prototype, 'encoding', {
        get: function () { return 'utf-8'; }
    });

    function bytesOf(input) {
        if (input === undefined || input === null) {
            return new Uint8Array(0);
        }
        if (input instanceof Uint8Array) {
            return input;
        }
        if (typeof ArrayBuffer !== 'undefined' && input instanceof ArrayBuffer) {
            return new Uint8Array(input);
        }
        if (input.buffer instanceof ArrayBuffer) {
            return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
        }
        throw new TypeError('TextDecoder.decode expects an ArrayBuffer or a typed array.');
    }

    function sequenceLength(leadByte) {
        if (leadByte < 0x80) { return 1; }
        if ((leadByte & 0xE0) === 0xC0) { return 2; }
        if ((leadByte & 0xF0) === 0xE0) { return 3; }
        if ((leadByte & 0xF8) === 0xF0) { return 4; }
        return 0;
    }

    function leadBits(leadByte, length) {
        if (length === 1) { return leadByte; }
        if (length === 2) { return leadByte & 0x1F; }
        if (length === 3) { return leadByte & 0x0F; }
        return leadByte & 0x07;
    }

    function appendCodePoint(text, codePoint) {
        if (codePoint > 0x10FFFF || (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
            return text + REPLACEMENT;
        }
        if (codePoint > 0xFFFF) {
            var offset = codePoint - 0x10000;
            return text + String.fromCharCode(0xD800 + (offset >> 10), 0xDC00 + (offset & 0x3FF));
        }
        return text + String.fromCharCode(codePoint);
    }

    TextDecoder.prototype.decode = function (input) {
        var bytes = bytesOf(input);
        var text = '';
        var index = 0;
        while (index < bytes.length) {
            var length = sequenceLength(bytes[index]);
            if (length === 0 || index + length > bytes.length) {
                text += REPLACEMENT;
                index += 1;
                continue;
            }
            var codePoint = leadBits(bytes[index], length);
            var valid = true;
            for (var offset = 1; offset < length; offset += 1) {
                var continuation = bytes[index + offset];
                if ((continuation & 0xC0) !== 0x80) {
                    valid = false;
                    break;
                }
                codePoint = (codePoint << 6) | (continuation & 0x3F);
            }
            if (!valid) {
                text += REPLACEMENT;
                index += 1;
                continue;
            }
            index += length;
            text = appendCodePoint(text, codePoint);
        }
        return text;
    };

    global.TextEncoder = TextEncoder;
    global.TextDecoder = TextDecoder;

    // =====================================================================
    // MARK: - URL / URLSearchParams
    // =====================================================================
    //
    // A pragmatic WHATWG subset, not the full parser: enough for the URLs an
    // extension actually builds and takes apart, and a `TypeError` naming the
    // input for anything it cannot parse. Failing loudly on an exotic URL is
    // the same trade the NotImplemented stubs make — a wrong `hostname` read
    // back from a silently mangled parse is the expensive outcome.

    var SPECIAL_PORTS = {
        'http:': '80', 'https:': '443', 'ws:': '80', 'wss:': '443', 'ftp:': '21', 'file:': ''
    };

    function encodeFormComponent(text) {
        return encodeURIComponent(text).replace(/%20/g, '+').replace(/[!'()~]/g, function (character) {
            return '%' + character.charCodeAt(0).toString(16).toUpperCase();
        });
    }

    function decodeFormComponent(text) {
        try {
            return decodeURIComponent(String(text).replace(/\+/g, ' '));
        } catch (error) {
            return String(text);
        }
    }

    function URLSearchParams(init) {
        // `_pairs` is the whole state; every accessor below reads or rewrites
        // it, which is what keeps the spec's insertion order observable
        // through `toString` and the iterators.
        Object.defineProperty(this, '_pairs', { value: [], writable: true, enumerable: false });
        Object.defineProperty(this, '_owner', { value: null, writable: true, enumerable: false });
        if (init === undefined || init === null || init === '') {
            return;
        }
        if (init instanceof URLSearchParams) {
            this._pairs = init._pairs.slice();
            return;
        }
        if (Array.isArray(init)) {
            for (var index = 0; index < init.length; index += 1) {
                this._pairs.push([String(init[index][0]), String(init[index][1])]);
            }
            return;
        }
        if (typeof init === 'object') {
            Object.keys(init).forEach(function (key) {
                this._pairs.push([key, String(init[key])]);
            }, this);
            return;
        }
        var text = String(init);
        if (text.charAt(0) === '?') {
            text = text.slice(1);
        }
        text.split('&').forEach(function (chunk) {
            if (chunk === '') {
                return;
            }
            var split = chunk.indexOf('=');
            if (split === -1) {
                this._pairs.push([decodeFormComponent(chunk), '']);
            } else {
                this._pairs.push([
                    decodeFormComponent(chunk.slice(0, split)),
                    decodeFormComponent(chunk.slice(split + 1))
                ]);
            }
        }, this);
    }

    // A mutation through `url.searchParams` has to reach `url.search` and
    // `url.href`; without this the two disagree the moment anyone calls
    // `set`, and the disagreement is invisible until something serializes.
    URLSearchParams.prototype._changed = function () {
        if (this._owner) {
            this._owner._search = this.toString();
        }
    };

    URLSearchParams.prototype.append = function (name, value) {
        this._pairs.push([String(name), String(value)]);
        this._changed();
    };

    URLSearchParams.prototype.set = function (name, value) {
        var key = String(name);
        var replaced = false;
        var next = [];
        for (var index = 0; index < this._pairs.length; index += 1) {
            if (this._pairs[index][0] !== key) {
                next.push(this._pairs[index]);
            } else if (!replaced) {
                next.push([key, String(value)]);
                replaced = true;
            }
        }
        if (!replaced) {
            next.push([key, String(value)]);
        }
        this._pairs = next;
        this._changed();
    };

    URLSearchParams.prototype.get = function (name) {
        var key = String(name);
        for (var index = 0; index < this._pairs.length; index += 1) {
            if (this._pairs[index][0] === key) {
                return this._pairs[index][1];
            }
        }
        return null;
    };

    URLSearchParams.prototype.getAll = function (name) {
        var key = String(name);
        return this._pairs.filter(function (pair) { return pair[0] === key; })
            .map(function (pair) { return pair[1]; });
    };

    URLSearchParams.prototype.has = function (name) {
        return this.get(name) !== null;
    };

    URLSearchParams.prototype['delete'] = function (name) {
        var key = String(name);
        this._pairs = this._pairs.filter(function (pair) { return pair[0] !== key; });
        this._changed();
    };

    URLSearchParams.prototype.sort = function () {
        this._pairs.sort(function (left, right) {
            if (left[0] < right[0]) { return -1; }
            if (left[0] > right[0]) { return 1; }
            return 0;
        });
        this._changed();
    };

    URLSearchParams.prototype.forEach = function (callback, thisArg) {
        this._pairs.slice().forEach(function (pair) {
            callback.call(thisArg, pair[1], pair[0], this);
        }, this);
    };

    URLSearchParams.prototype.entries = function () {
        return this._pairs.map(function (pair) { return [pair[0], pair[1]]; })[Symbol.iterator]();
    };

    URLSearchParams.prototype.keys = function () {
        return this._pairs.map(function (pair) { return pair[0]; })[Symbol.iterator]();
    };

    URLSearchParams.prototype.values = function () {
        return this._pairs.map(function (pair) { return pair[1]; })[Symbol.iterator]();
    };

    URLSearchParams.prototype[Symbol.iterator] = URLSearchParams.prototype.entries;

    Object.defineProperty(URLSearchParams.prototype, 'size', {
        get: function () { return this._pairs.length; }
    });

    URLSearchParams.prototype.toString = function () {
        return this._pairs.map(function (pair) {
            return encodeFormComponent(pair[0]) + '=' + encodeFormComponent(pair[1]);
        }).join('&');
    };

    // scheme : [//[user[:password]@]host[:port]] path [?query] [#fragment]
    var ABSOLUTE_PATTERN = new RegExp(
        '^([A-Za-z][A-Za-z0-9+.-]*):' +      // scheme
        '(//(?:([^/?#@]*)@)?([^/?#]*))?' +   // authority
        '([^?#]*)' +                         // path
        '(?:\\?([^#]*))?' +                  // query
        '(?:#([\\s\\S]*))?$'                 // fragment
    );

    function splitAuthority(url, authority) {
        var hostText = authority || '';
        var colon = hostText.lastIndexOf(':');
        var bracket = hostText.lastIndexOf(']');
        if (colon !== -1 && colon > bracket) {
            url._port = hostText.slice(colon + 1);
            hostText = hostText.slice(0, colon);
        } else {
            url._port = '';
        }
        url._hostname = hostText.toLowerCase();
        if (url._port !== '' && SPECIAL_PORTS[url._protocol] === url._port) {
            url._port = '';
        }
    }

    function splitCredentials(url, credentials) {
        if (credentials === undefined) {
            url._username = '';
            url._password = '';
            return;
        }
        var colon = credentials.indexOf(':');
        if (colon === -1) {
            url._username = credentials;
            url._password = '';
        } else {
            url._username = credentials.slice(0, colon);
            url._password = credentials.slice(colon + 1);
        }
    }

    // Lexical `.`/`..` removal, RFC 3986 section 5.2.4.
    function normalizePath(path) {
        if (path === '') {
            return '';
        }
        var absolute = path.charAt(0) === '/';
        var trailing = path.charAt(path.length - 1) === '/';
        var output = [];
        path.split('/').forEach(function (segment) {
            if (segment === '' || segment === '.') {
                return;
            }
            if (segment === '..') {
                if (output.length > 0) {
                    output.pop();
                }
                return;
            }
            output.push(segment);
        });
        var joined = output.join('/');
        if (absolute) {
            joined = '/' + joined;
        }
        if (trailing && joined.charAt(joined.length - 1) !== '/') {
            joined += '/';
        }
        return joined;
    }

    function resolveAgainst(base, reference) {
        if (reference === '') {
            return base._pathname;
        }
        if (reference.charAt(0) === '/') {
            return normalizePath(reference);
        }
        var directory = base._pathname.slice(0, base._pathname.lastIndexOf('/') + 1);
        return normalizePath((directory === '' ? '/' : directory) + reference);
    }

    function parseAbsolute(url, match) {
        url._protocol = match[1].toLowerCase() + ':';
        splitCredentials(url, match[3]);
        if (match[2] === undefined) {
            url._hostname = '';
            url._port = '';
        } else {
            splitAuthority(url, match[4]);
        }
        url._pathname = normalizePath(match[5] || '');
        url._search = match[6] === undefined ? '' : match[6];
        url._hash = match[7] === undefined ? '' : match[7];
    }

    function parseRelative(url, text, base) {
        var resolvedBase = base instanceof URL ? base : new URL(String(base));
        var reference = text;

        var hashIndex = reference.indexOf('#');
        url._hash = hashIndex === -1 ? '' : reference.slice(hashIndex + 1);
        if (hashIndex !== -1) {
            reference = reference.slice(0, hashIndex);
        }
        var queryIndex = reference.indexOf('?');
        url._search = queryIndex === -1 ? '' : reference.slice(queryIndex + 1);
        if (queryIndex !== -1) {
            reference = reference.slice(0, queryIndex);
        }

        url._protocol = resolvedBase._protocol;
        url._username = resolvedBase._username;
        url._password = resolvedBase._password;
        url._hostname = resolvedBase._hostname;
        url._port = resolvedBase._port;
        url._pathname = resolveAgainst(resolvedBase, reference);
        if (queryIndex === -1 && reference === '') {
            url._search = resolvedBase._search;
        }
    }

    function URL(input, base) {
        var text = String(input === undefined ? '' : input).trim();
        var match = ABSOLUTE_PATTERN.exec(text);

        if (match) {
            parseAbsolute(this, match);
        } else if (base === undefined || base === null) {
            throw new TypeError("Invalid URL: '" + text + "'");
        } else {
            parseRelative(this, text, base);
        }

        if (this._pathname === '' && this._hostname !== '') {
            this._pathname = '/';
        }

        var params = new URLSearchParams(this._search);
        params._owner = this;
        Object.defineProperty(this, '_params', { value: params, enumerable: false });
    }

    function defineURLAccessor(name, getter, setter) {
        Object.defineProperty(URL.prototype, name, { get: getter, set: setter, enumerable: true });
    }

    defineURLAccessor('protocol', function () { return this._protocol; });
    defineURLAccessor('username', function () { return this._username; });
    defineURLAccessor('password', function () { return this._password; });
    defineURLAccessor('hostname', function () { return this._hostname; });
    defineURLAccessor('port', function () { return this._port; });
    defineURLAccessor('pathname', function () { return this._pathname; });

    defineURLAccessor('host', function () {
        return this._port === '' ? this._hostname : this._hostname + ':' + this._port;
    });

    defineURLAccessor('origin', function () {
        return this._hostname === '' ? 'null' : this._protocol + '//' + this.host;
    });

    defineURLAccessor('search',
        function () { return this._search === '' ? '' : '?' + this._search; },
        function (value) {
            var text = String(value);
            this._search = text.charAt(0) === '?' ? text.slice(1) : text;
            // Re-parse rather than mutate: `search` and `searchParams` are two
            // views of one value, and the setter is the only place they can
            // drift apart.
            this._params._pairs = new URLSearchParams(this._search)._pairs;
        });

    defineURLAccessor('hash',
        function () { return this._hash === '' ? '' : '#' + this._hash; },
        function (value) {
            var text = String(value);
            this._hash = text.charAt(0) === '#' ? text.slice(1) : text;
        });

    defineURLAccessor('searchParams', function () { return this._params; });

    defineURLAccessor('href', function () {
        var text = this._protocol;
        if (this._hostname !== '' || this._protocol === 'file:') {
            text += '//';
            if (this._username !== '') {
                text += this._username;
                if (this._password !== '') {
                    text += ':' + this._password;
                }
                text += '@';
            }
            text += this.host;
        }
        return text + this._pathname + this.search + this.hash;
    });

    URL.prototype.toString = function () { return this.href; };
    URL.prototype.toJSON = function () { return this.href; };

    global.URL = URL;
    global.URLSearchParams = URLSearchParams;

    // =====================================================================
    // MARK: - The module wrapper
    // =====================================================================

    // The CommonJS shape, so both `module.exports = …` and `exports.activate =
    // …` work — the two spellings VS Code extensions actually ship, and an
    // extension that used the other one would otherwise export nothing and
    // "activate" into silence.
    //
    // `new Function` compiles the body in the global scope, so the extension
    // sees exactly the five parameters named here and none of this file's
    // internals.
    function run(source, filename, dirname) {
        var module = { exports: {} };
        var wrapper = new Function('exports', 'require', 'module', '__filename', '__dirname', source);
        wrapper.call(module.exports, module.exports, require, module, filename, dirname);
        return module.exports;
    }

    // ExtensionHost captures this object and then deletes both globals, so
    // nothing an extension can reach leads back to the host.
    global.__extensionRuntime = {
        run: run,
        fireTimer: fireTimer,
        // Used for the argument `activate(context)` receives: a recorded,
        // throwing stub like every other unimplemented surface, so an
        // extension that reaches for `context.subscriptions` today gets told
        // so by name.
        makeStubNamespace: function (path) { return makeStubNamespace(path, Object.create(null)); }
    };
}(this));
