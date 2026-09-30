<!-- leaf: implement-general-2/networking--test-vectors · source: networking.md -->

# Bounded Body Loader

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| networking-001 | body-transfer | `limit: 1 << 20`, response body of 512 KiB, no misleading `Content-Length` | Returns `Data` equal to the full 512 KiB payload, byte for byte, with the paired `URLResponse` (traced to `aBodyUnderTheCapArrivesIntact`, exercised through `OpenVSXClient.data(at:)`) |
| networking-002 | running-ceiling-check | `limit: 4096`, response body of exactly 4096 bytes | Returns `Data` with `count == 4096` (traced to `aBodyOfExactlyTheCapIsAccepted`) |
| networking-003 | running-ceiling-check, overflow-error | `limit: 4096`, response body of 4097 bytes, no `Content-Length` header | Throws `Failure.tooLarge`, never returns the 4097-byte body (traced to `aBodyOneByteOverTheCapIsRefused`) |
| networking-004 | header-ceiling-check, overflow-error | `limit: 1000`, response claims `expectedContentLength: 1 << 30`, actually sends 10 bytes | Throws `Failure.tooLarge` immediately; the 10 bytes are never read into the returned `Data` (traced to `aClaimedLengthPastTheCapIsRefused`) |
| networking-005 | chunked-length-fallthrough, running-ceiling-check, overflow-error | `limit: 1000`, response claims `expectedContentLength: 1`, actually sends 4096 bytes | Throws `Failure.tooLarge` once the running total exceeds 1000, not accepted on the strength of the understated header (traced to `anUnderstatedLengthIsNotBelieved`) |
| networking-006 | status-agnosticism, overflow-error | Response status `503`, body of 64 KiB past a `limit: 1024` | Throws `Failure.tooLarge(response)` where `response` is non-nil and its `statusCode == 503`, letting the caller check status ahead of size (traced to `anErrorStatusOutranksTheCeiling`) |
| networking-007 | underlying-error-propagation | Connection drops mid-transfer before any ceiling is crossed | `body(at:limit:)` throws the underlying `URLError` unchanged, not `Failure.tooLarge` (traced to `finish`'s `else if let error` branch) |
| networking-008 | cooperative-cancellation | Calling `Task` is cancelled while `body(at:limit:)` is awaiting | The underlying `URLSessionDataTask` is cancelled (`onCancel: { task.cancel() }`) and the call throws rather than hanging |
| networking-009 | stale-callback-tolerance | A `didReceive data:` or `didReceive response:` callback arrives for a `taskIdentifier` already removed from `state.transfers` | `accept`/`append` return `false` without throwing or mutating any other transfer's record |
