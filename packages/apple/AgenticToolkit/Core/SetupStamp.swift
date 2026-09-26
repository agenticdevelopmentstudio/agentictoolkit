import Foundation

/// Which bundle version last completed per-user setup. An updater replaces the
/// bundle but not what setup installed around it (LaunchAgent, CLI links,
/// plugins); comparing the running bundle's version to this stamp is how an app
/// knows setup must run again. Any difference counts — a downgrade needs setup
/// as much as an upgrade does.
public enum SetupStamp {
    public static func needsSetup(bundleVersion: String, stampURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: stampURL),
              let recorded = String(data: data, encoding: .utf8) else { return true }
        return recorded.trimmingCharacters(in: .whitespacesAndNewlines) != bundleVersion
    }

    public static func record(bundleVersion: String, at stampURL: URL) throws {
        try FileManager.default.createDirectory(
            at: stampURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bundleVersion.utf8).write(to: stampURL, options: .atomic)
    }

    public static func defaultURL(supportDirectoryName: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent("last-setup-version")
    }
}
