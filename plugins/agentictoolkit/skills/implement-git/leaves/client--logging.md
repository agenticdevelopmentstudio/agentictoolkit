<!-- leaf: implement-git/client--logging · source: git-client.md -->

# Git Client

**Rules** (cite as `implement-git/client--logging#<slug>`):

- `gitcommandlog-record-not-log-process-standard-output` MUST — GitCommandLog.record MUST NOT log the process's standard output or standard error — only that a call happened and where …

## Logging

Subsystem/category are whatever `GitCommandLog`'s `Loggable` conformance
configures via `makeLogger()` (`GitCommandLog.swift`).

| Event | Level | Message shape |
|-------|-------|---------------|
| Every invocation attempt, regardless of outcome | info | `` `git <verb> <redacted-arguments> cwd=<path> from=<file>:<function> <ms>ms status=<exitStatus-or-"unfinished">` `` (`GitCommandLog.swift`) |

`GitCommandLog.record` MUST NOT log the process's standard output or
standard error — only that a call happened and where it came from, so git
usage can be counted, attributed, and audited without the log becoming a
copy of the repository (`GitCommandLog.swift`). Arguments are
logged at `.public` privacy after passing through `redactedArguments`
(see Behavioral Requirements and Privacy above), never through
`OSLogPrivacy.private`, because that would collapse the whole interpolation
for every verb rather than redacting the one argument position that needs
it (`GitCommandLog.swift`). The redaction rule today covers only
the `config` verb; the source's own comment names `commit -m <message>` and
any remote URL as expected future additions once those verbs exist
(`GitCommandLog.swift`).
