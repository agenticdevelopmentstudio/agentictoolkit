//
//  ExtensionIdentityComponent.swift
//  AgenticToolkit
//

import Foundation

/// Whether a string an extension claims as its identity may be spliced into a
/// path or a URL.
///
/// **One predicate, two very different splices.** `VSIXInstaller` joins the
/// identifier and version into a directory name under the extensions folder;
/// `OpenVSXClient.detail` joins a namespace, name and version onto the registry
/// base. Both were reading the same kind of value — a field off a manifest
/// nobody here wrote — and only the first was checking it. The check lives here
/// rather than in either caller because it is one piece of knowledge, and the
/// caller that did not have it is the one that mattered *(dry)*.
///
/// **Refused, not escaped.** Percent-encoding a `/` in an extension's name
/// would install or address it under a mangled spelling that no longer matches
/// what the registry and the settings list call it — a silent identity change
/// where a refusal is a legible failure *(fail-fast)*.
///
/// **A denylist of shapes, not an allowlist of characters**, and deliberately
/// so: publisher and extension names are internationalised, so an allowlist
/// would refuse a legitimate name long before it refused a hostile one. What is
/// rejected is what changes *where the value points* — a separator, a leading
/// `.` that hides a directory or climbs out of one, the `:` that some HFS APIs
/// still map to `/`, an empty component, and the control characters that make a
/// name unprintable in the list that has to show it.
///
/// Note what is *not* rejected: an interior `.`, which every version string and
/// most extension names contain (`ms-python.python`, `2024.1.0-rc.1`). Only the
/// leading one is structural.
public enum ExtensionIdentityComponent {

    /// `true` when `value` is a single component that addresses only itself.
    public static func isSafe(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix(".") else { return false }
        guard !value.contains("/"), !value.contains("\\"), !value.contains(":") else {
            return false
        }
        return !value.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}
