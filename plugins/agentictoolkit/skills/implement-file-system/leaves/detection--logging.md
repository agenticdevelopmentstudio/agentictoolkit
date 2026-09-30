<!-- leaf: implement-file-system/detection--logging · source: file-system-detection.md -->

# File System Detection

## Logging

Subsystem: `Bundle.main.bundleIdentifier` | Category: `IDEDetector`
(per `Loggable`'s `subsystem`/`category` defaults, since `IDEDetector` is
the only one of the two types that conforms to `Loggable`).

| Event | Level | Message |
|-------|-------|---------|
| Detection scan completes | info | `IDE detection complete: \(results.count) IDE(s) found in \(rootURL.lastPathComponent)` |
| Each detected IDE, per scan | debug | `  Detected \(ide.type.displayName): \(ide.path)` |
| `open(project:rootURL:)` begins | info | `Opening \(project.type.displayName) project at \(targetURL.path)` |
| `NSWorkspace` open-with-application fails | error | `Failed to open \(project.type.displayName): \(error.localizedDescription)` |

`LanguageDetection.swift` contains no `Logger`/`os_log`/`print` call of any
kind.
