<!-- leaf: implement-foundation/json--part-2 · source: foundation-json.md -->

# JSONCPreprocessor — continued (part 2)

## Design Decisions

**Decision**: `jsonObject(from:)` never passes `.fragmentsAllowed` to any of its `JSONSerialization.jsonObject(with:)` calls, but `jsonData(from:)`'s own initial strict-JSON check does pass it.
**Rationale**: This creates an asymmetry a reader would not expect from the two functions' names alone: `jsonData(from: Data("42".utf8))` returns `Data("42".utf8)` unchanged (the fragments-allowed check accepts a bare top-level number), but `jsonObject(from: Data("42".utf8))` throws, and a JSONC document whose root is a scalar (e.g. `42 // comment`) fails through `jsonData(from:)` too, because its fallback is `jsonObject(from:)`, which never accepts a fragment. Nothing in the source comments this choice; it follows mechanically from `jsonData(from:)`'s passthrough check being written with `.fragmentsAllowed` and every other call site in the file omitting it.
**Approved**: pending

**Decision**: Candidate encodings are tried strictly in the order `.utf8`, `.utf16`, `.utf16BigEndian`, `.utf16LittleEndian`, `.utf32BigEndian`, `.utf32LittleEndian`, and the winner is the first candidate whose decoded text also *parses*, not merely decodes.
**Rationale**: Per the source's own comment, UTF-16 bytes for ASCII text also decode as UTF-8 (the interleaved NULs are valid UTF-8), and `.utf16` accepts any even-length payload as big-endian, so a "first that decodes" rule would let an earlier candidate silently swallow a later one's file and turn a good document into a syntax error. Requiring a successful *parse*, not just a successful *decode*, is what makes the fixed try-order safe.
**Approved**: pending

**Decision**: `jsonData(from:)` returns bytes that are already strict JSON completely unchanged, rather than always round-tripping through `jsonObject(from:)` and re-serializing.
**Rationale**: Per the source's own comment, a re-serialized document is not byte-identical to the one that came in — `1e3` comes back as `1000`, and key order can change — so a decoder that never sees the rewritten form cannot be surprised by it. Only a file the strict parser actually refuses pays the transform cost.
**Approved**: pending

**Decision**: `removingTrailingCommas` blanks a disqualified comma by overwriting it with a space character rather than removing it from the string.
**Rationale**: Per the source's own comment, overwriting keeps every remaining character offset valid while the single forward scan is still running; deleting the character would shift every subsequent index and require either a second pass or index-adjustment bookkeeping the current single-pass algorithm does not do.
**Approved**: pending

**Decision**: An unterminated `/* … */` block comment consumes the rest of the document with no recovery attempt, producing a downstream parse failure rather than a repaired document.
**Rationale**: The source makes no attempt to detect or recover from this case; `JSONCPreprocessorTests.unterminatedBlockComment`'s own test comment states the intent directly: "documenting the scanner's actual behaviour rather than wishing for recovery... that is the honest outcome for a file whose author left a comment open."
**Approved**: pending
