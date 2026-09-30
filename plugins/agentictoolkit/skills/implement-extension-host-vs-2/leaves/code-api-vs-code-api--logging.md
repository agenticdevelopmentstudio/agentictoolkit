<!-- leaf: implement-extension-host-vs-2/code-api-vs-code-api--logging · source: extension-host-vs-code-api-vs-code-api.md -->

# VSCodeAPI

## Logging

Subsystem: matches the host's `Loggable`-derived subsystem (via `makeLogger()`) | Category: `VSCodeAPI`

| Event | Level | Trigger |
| --- | --- | --- |
| oversized-array refusal | error | `arrayLength(of:)` refuses a JS array-like value whose length exceeds `maximumDecodableArrayLength` |
| error-construction failure | error | `raise(_:in:)` finds `JSValue(newErrorFromMessage:in:)` answers `nil` for the message it was given |
| malformed trampoline record | error | `outcome(of:in:)` finds the settled dispatch value is not an object, or its `ok` property is missing or not a boolean |
| trampoline install failure | error | `sharedHelper(in:)` cannot evaluate or cache `helperSource` in a context |
| sub-namespace factory install failure | error | `subNamespaceFactory(in:)` cannot evaluate or cache `subNamespaceFactorySource` in a context |
