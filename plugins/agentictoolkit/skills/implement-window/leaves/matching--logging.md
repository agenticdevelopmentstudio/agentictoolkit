<!-- leaf: implement-window/matching--logging · source: window-matching.md -->

# Window Matching

## Logging

Subsystem: the host app's bundle identifier (`Bundle.main.bundleIdentifier`, or "nil") | Category: the type name (`CustomHeuristicRule`, `SystemWindowMatcher`) via `Loggable`

| Event | Level | Message |
|-------|-------|---------|
| Rule regex fails to compile in `matchTitle` | error | `Invalid custom-rule regex '<pattern>': <reason>` |
| Fingerprint regex fails to compile in scoring | error | `Invalid title regex '<pattern>': <reason>` |

`CustomHeuristicStore` and `HeuristicRegistry` do not log; store errors are thrown to the caller.
