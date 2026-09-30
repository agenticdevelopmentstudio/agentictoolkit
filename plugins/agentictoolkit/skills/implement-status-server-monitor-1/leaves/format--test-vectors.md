<!-- leaf: implement-status-server-monitor-1/format--test-vectors · source: status-server-monitor-format.md -->

# Status Server Monitor Format

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-format-001 | commit-full-message-null-on-falsy | `commitFullMessage(null)`; `commitFullMessage(undefined)`; `commitFullMessage('')` | All three resolve `null` — asserted by `format.test.ts` › "returns null for empty input" |
| status-server-monitor-format-002 | commit-full-message-empty-after-trim | `commitFullMessage('   \n  ')` | Resolves `null` — asserted by the same `format.test.ts` case |
| status-server-monitor-format-003 | commit-full-message-preserve-newlines | `commitFullMessage('subject')`; `commitFullMessage('subject\n\nbody line 1\nbody line 2')` | Resolves `'subject'`, then the full string unchanged, internal newlines intact — asserted by `format.test.ts` › "keeps the whole message including body newlines" |
| status-server-monitor-format-004 | commit-full-message-trailing-trim | `commitFullMessage('subject\n\nbody\n\n')` | Resolves `'subject\n\nbody'` — trailing newlines stripped, the internal blank line between subject and body preserved — asserted by `format.test.ts` › "strips trailing whitespace but not internal newlines" |
| status-server-monitor-format-005 | commit-full-message-cap, commit-full-message-default-max | `commitFullMessage('x'.repeat(50), 10)` | Resolves a 10-character string of `'x'` — asserted by `format.test.ts` › "caps at max chars" |
| status-server-monitor-format-006 | short-sha-truncation | `shortSha('abcdef1234567890')` | Resolves `'abcdef1'` — the first 7 characters, traced to `hash.slice(0, 7)`; no dedicated test exists for `shortSha` in the given source |
| status-server-monitor-format-007 | short-sha-null-on-falsy | `shortSha(null)`; `shortSha(undefined)`; `shortSha('')` | All three resolve `null`, traced to the `hash ? hash.slice(0, 7) : null` guard |
| status-server-monitor-format-008 | short-sha-no-validation | `shortSha('ab')` | Resolves `'ab'` unchanged — `slice(0, 7)` on a 2-character string returns the whole string, with no padding and no thrown error |
| status-server-monitor-format-009 | commit-first-line-extraction | `commitFirstLine('subject\n\nbody')` | Resolves `'subject'` — the substring before the first `"\n"`; no dedicated test exists for `commitFirstLine` in the given source |
| status-server-monitor-format-010 | commit-first-line-null-on-falsy | `commitFirstLine(null)`; `commitFirstLine(undefined)`; `commitFirstLine('')` | All three resolve `null` |
| status-server-monitor-format-011 | commit-first-line-cap, commit-first-line-default-max | `commitFirstLine('x'.repeat(250))` | Resolves a 200-character string of `'x'` — the default `max` of `200` applies with no explicit second argument |
| status-server-monitor-format-012 | commit-first-line-no-trim | `commitFirstLine('  leading and trailing  ')` | Resolves `'  leading and trailing  '` unchanged — no `"\n"` is present, so the whole string is the "first line," and no trim step runs |
| status-server-monitor-format-013 | pure-synchronous, no-throw | Call each of `shortSha`, `commitFirstLine`, `commitFullMessage` with global `fetch`, `console.*`, and `fs` spied, across every input vector above | Zero recorded calls on any spy; no call throws for any of the inputs exercised in vectors 001–012 |
