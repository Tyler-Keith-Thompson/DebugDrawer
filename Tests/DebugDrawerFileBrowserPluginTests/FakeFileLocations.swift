@testable import DebugDrawerFileBrowserPlugin
import Foundation

/// The app's folders as a test lays them out in a temporary folder, and app groups with the
/// container the system gives each, or none.
struct FakeFileLocations: FileLocations {
    var appFolders: [FileRoot] = []
    var bundle = URL(filePath: "/Applications/Example.app", directoryHint: .isDirectory)
    var appGroupContainers: [String: URL] = [:]

    func containerURL(forAppGroup identifier: String) -> URL? {
        appGroupContainers[identifier]
    }
}
