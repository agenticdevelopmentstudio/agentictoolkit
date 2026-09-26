import Foundation

/// Carries an app's saved settings across a bundle-identifier change. The
/// standard defaults domain IS the bundle id, so renaming the bundle silently
/// starts the app on an empty domain and every setting the user made is gone.
///
/// Copies the legacy domain into the new one exactly once: only while the new
/// domain holds nothing, so a user who has already changed a setting under the
/// new id is never overwritten. The legacy domain is left in place — it costs a
/// plist, and deleting it would make a downgrade lose everything instead.
public enum DefaultsDomainMigration {
    /// - Returns: `true` when settings were copied.
    @discardableResult
    public static func migrateIfNeeded(
        from legacyDomain: String,
        to domain: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard legacyDomain != domain,
              defaults.persistentDomain(forName: domain)?.isEmpty ?? true,
              let legacy = defaults.persistentDomain(forName: legacyDomain),
              !legacy.isEmpty else { return false }
        defaults.setPersistentDomain(legacy, forName: domain)
        return true
    }
}
