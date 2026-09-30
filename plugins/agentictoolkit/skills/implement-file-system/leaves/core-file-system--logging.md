<!-- leaf: implement-file-system/core-file-system--logging · source: file-system-core-file-system.md -->

# FileSystemService

## Logging

This component performs no logging of its own — no `os_log`, `print`,
`Logger`, or diagnostic breadcrumb of any kind appears anywhere in
`FileSignature.swift`, `FileSystemService.swift`, or
`FileSystemServicing.swift` (traced to the full body of all three files).
Every failure surfaces as a thrown, typed `FileSystemServiceError` instead of
a log line; a caller that wants a trail of what this component did must log
at its own call site.
