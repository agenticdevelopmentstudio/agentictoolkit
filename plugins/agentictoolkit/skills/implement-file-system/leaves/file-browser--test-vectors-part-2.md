<!-- leaf: implement-file-system/file-browser--test-vectors-part-2 · source: file-system-file-browser.md -->

# File System File Browser — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| file-system-file-browser-037 | overlapping-directory-syncs-race | Call `updateIgnorePatterns(["*.a"])` immediately followed by `updateIgnorePatterns(["*.b"])`, arranging for the first call's background read to finish after the second's. | The final `rootNode` reflects the first call's `*.a` pattern rather than the more recently requested `*.b` pattern — the open question this marker records. |
