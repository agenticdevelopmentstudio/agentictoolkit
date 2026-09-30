<!-- leaf: implement-general-controller/single-window-controller--test-vectors-part-2 · source: single-window-controller.md -->

# SingleWindowController — Conformance Test Vectors (part 2)

| ID | Requirement | Given | When | Then |
|---|---|---|---|---|
| single-window-controller-051 | singleton-ensure-current | `current == nil` | `ensureCurrent()` is called twice | `makeShared()` runs once; the second call reuses the first instance |
| single-window-controller-052 | singleton-present | `current == nil` | `present()` is called | a shared instance is created and shown |
| single-window-controller-053 | singleton-is-open | `current == nil` | `isOpen()` is called | it returns `false` |
