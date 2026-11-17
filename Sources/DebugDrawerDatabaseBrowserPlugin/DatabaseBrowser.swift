import Foundation

/// The app's databases in the debug drawer: its SQLite, Core Data and SwiftData stores, opened
/// read-only, with their tables or entities and row counts, each table's rows paged and searched,
/// and read-only SELECT queries, copied as CSV.
///
/// The type exists in every build, so the call compiles unchanged in release, where it does
/// nothing and opens nothing.
public enum DatabaseBrowser {
    /// Adds the Databases plugin: in debug builds only; in release it does nothing.
    ///
    /// The plugin looks for stores in Application Support, Documents and the shared container of
    /// each app group the app's entitlements name, then in `additionalDirectories`, at any depth:
    /// files ending `.sqlite`, `.sqlite3`, `.db` or `.store` that SQLite can read. It looks when
    /// installed, each time it is shown and on Refresh, reading each store only while a read
    /// runs, never holding a transaction open, so the app's own connections keep writing and
    /// checkpointing as before.
    ///
    /// Call it once at startup. Calling it again replaces the plugin.
    ///
    /// - Parameter additionalDirectories: Other folders to search, such as a database folder in
    ///   Caches.
    @MainActor
    public static func install(additionalDirectories: [URL] = []) {
        #if DEBUG
            DatabaseBrowserInstallation.install(locations: SystemStoreLocations(), additionalDirectories: additionalDirectories)
        #endif
    }
}
