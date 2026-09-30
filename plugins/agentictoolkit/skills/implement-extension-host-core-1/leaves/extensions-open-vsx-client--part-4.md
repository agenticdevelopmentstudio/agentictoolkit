<!-- leaf: implement-extension-host-core-1/extensions-open-vsx-client--part-4 · source: extension-host-core-extensions-open-vsx-client.md -->

# OpenVSXClient — continued (part 4)

## Design Decisions

**Decision**: Read the response body through a delegate-based
`URLSessionDataTask` (`BoundedBodyLoader`) rather than `session.data(from:)`
or `URLSession.bytes(from:)`.
**Rationale**: `data(from:)` cannot be bounded — by the time it returns,
however much a stranger decided to send is already in memory. `bytes(from:)`
can be bounded but its `AsyncBytes` yields one byte per `await`, measured at
23.8 MB/s against 2.5 GB/s for whole-chunk delivery — a cost this type pays
on every keystroke of a search field, not only on a 512 MB download
(`BoundedBodyLoader.swift` doc comment; source doc comment on
`body`).
**Approved**: pending

**Decision**: Check the HTTP status of a failure response before reporting
a body that exceeded its ceiling as too large.
**Rationale**: A 500 or 404 commonly arrives with an error document larger
than the metadata ceiling; reporting that as "the answer was too large"
sends whoever reads the error looking for a setting to raise, when the
actual situation is a registry outage or a missing extension (source
comment on `body`; tests `anErrorStatusOutranksTheCeiling`,
`aMissingArtifactIsReportedAsMissing`).
**Approved**: pending

**Decision**: Give artifact downloads and metadata reads two independent
byte ceilings, three orders of magnitude apart, rather than one shared
number.
**Rationale**: A search page or a detail record is a JSON document
describing an extension, never the extension itself, so 8 MB is generously
above any honest metadata answer; a `.vsix` legitimately reaches hundreds of
megabytes. One number for both would either make the metadata ceiling
decorative or make the download ceiling impossible (source doc comment on
`defaultMaximumMetadataBytes`).
**Approved**: pending

**Decision**: Restrict the scheme and host of an artifact URL
(`requireFetchable`), but never restrict `registryBase` to the same rule.
**Rationale**: `registryBase` is typed by whoever configures the client, not
supplied by a response, so an organisation's decision to run its own
registry over plain HTTP inside its own network is theirs to make. What a
registry *names* in a `files`/`downloads` map is a different thing entirely
— `URLSession` implements the `file:` and `data:` schemes, so an unchecked
artifact URL would let a compromised or misconfigured registry answer make
this client read a local file or an inline payload and hand it back as a
"download" (source comment on `requireFetchable`'s call sites).
**Approved**: pending

**Decision**: Hold no cache; re-fetch on every call.
**Rationale**: A memoizing client would hand a settings panel a stale
"latest version" answer for an update check whose entire purpose is to be
current (doc comment on `OpenVSXClient`).
**Approved**: pending

**Decision**: Construct `BoundedBodyLoader` from the caller's
`session.configuration` rather than from the `session` instance itself.
**Rationale**: The loader needs a session of its own to be the delegate of —
`URLSession` retains its delegate until invalidated, so a loader that were
its own delegate could never deallocate and invalidate itself. Deriving from
the configuration, not the session, is what lets an injected
`protocolClasses` (how every test here stands the registry up) still apply
to the new session (source comment in `init`;
`BoundedBodyLoader.swift` comment).
**Approved**: pending
