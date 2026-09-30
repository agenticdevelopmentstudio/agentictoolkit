<!-- leaf: implement-extension-host-core-1/extensions-extension-identity-component--test-vectors · source: extension-host-core-extensions-extension-identity-component.md -->

# ExtensionIdentityComponent

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| extension-identity-001 | empty-value-refused | `""` | `false` |
| extension-identity-002 | leading-dot-refused | `".."` | `false` |
| extension-identity-003 | leading-dot-refused | `".hidden"` | `false` |
| extension-identity-004 | forward-slash-refused | `"../../etc"` | `false` |
| extension-identity-005 | backslash-refused | `"..\..\windows"` | `false` |
| extension-identity-006 | colon-refused | `"Macintosh HD:Users"` | `false` |
| extension-identity-007 | control-character-refused | `"a\nb"` (contains `U+000A`) | `false` |
| extension-identity-008 | control-character-refused | `"\u{7F}"` | `false` |
| extension-identity-009 | c0-boundary-accepted | `"a\u{20}b"` and `"a\u{7E}b"` | `true` |
| extension-identity-010 | c1-range-accepted | `"a\u{80}b"` | `true` |
| extension-identity-011 | interior-dot-accepted | `"ms-python.python"` | `true` |
| extension-identity-012 | non-ascii-accepted | `"日本語パック"`, `"расширение"`, `"emoji-🎉-pack"` | `true` |
| extension-identity-013 | literal-percent-sequence-accepted | `"a%2Fb"` | `true` |
| extension-identity-014 | pure-function, synchronous-non-throwing | `"1.0.0"` | `true` |

All fourteen vectors are traced to
`packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/ExtensionIdentityComponentTests.swift`
(`emptyIsRefused`, `aLeadingDotIsRefused`, `separatorsAreRefused`,
`controlCharactersAreRefused`, `theControlRangeEdgesAreRight`,
`interiorDotsAreAccepted`, `internationalisedNamesAreAccepted`,
`anEncodedSeparatorIsNotASeparator`, `ordinaryNamesAreAccepted`).
