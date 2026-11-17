@testable import DebugDrawerDatabaseBrowserPlugin
import Foundation

/// The app's folders as a test lays them out in a temporary folder: any of them missing, and app
/// groups the entitlements name with the container the system gives each, or none.
struct FakeStoreLocations: StoreLocations {
    var applicationSupport: URL?
    var documents: URL?
    var appGroupIdentifiers: [String] = []
    var appGroupContainers: [String: URL] = [:]

    func containerURL(forAppGroup identifier: String) -> URL? {
        appGroupContainers[identifier]
    }
}
