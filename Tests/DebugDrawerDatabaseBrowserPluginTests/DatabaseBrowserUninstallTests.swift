@testable import DebugDrawer
@testable import DebugDrawerDatabaseBrowserPlugin
import DebugDrawerTestSupport
import Foundation
import Testing

@MainActor
@Suite("Databases looks for stores once installed and drops them once removed from every drawer", .timeLimit(.minutes(1)))
struct DatabaseBrowserUninstallTests {
    private static func drawer() throws -> (DebugDrawer, () -> Void) {
        let suite = temporarySuiteName("DatabaseBrowserUninstallTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
    }

    /// A folder holding one empty SQLite store, and a model over it.
    private static func model() throws -> (DatabaseBrowserModel, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #require(FileManager.default.createFile(atPath: folder.appending(path: "shop.sqlite").path(percentEncoded: false), contents: Data()))
        let discovery = StoreDiscovery(locations: FakeStoreLocations(applicationSupport: folder), additionalDirectories: [])
        return (DatabaseBrowserModel(discovery: discovery), folder)
    }

    @Test("Registering looks for stores; unregistering removes the plugin and drops the stores and their readers")
    func disappearsFromTheDrawer() async throws {
        let (drawer, cleanUp) = try Self.drawer()
        defer { cleanUp() }
        let (model, folder) = try Self.model()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sut = DatabaseBrowserPlugin(model: model)
        drawer.registerGlobal(sut)
        await model.installRefresh?.value
        let foundOnceInstalled = model.listings.map(\.store.name)
        let readersOnceInstalled = model.openStores.count

        drawer.unregisterGlobal(id: sut.id)

        #expect(foundOnceInstalled == ["shop.sqlite"])
        #expect(readersOnceInstalled == 1)
        #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
        #expect(model.stores == .loading)
        #expect(model.openStores.isEmpty)
        #expect(model.installRefresh == nil)
    }

    @Test("A look for stores still running when the plugin is removed is dropped")
    func removedWhileLooking() async throws {
        let (drawer, cleanUp) = try Self.drawer()
        defer { cleanUp() }
        let (model, folder) = try Self.model()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sut = DatabaseBrowserPlugin(model: model)
        drawer.registerGlobal(sut)
        let looking = try #require(model.installRefresh)

        drawer.unregisterGlobal(id: sut.id)
        await looking.value

        #expect(model.stores == .loading)
        #expect(model.openStores.isEmpty)
    }

    @Test("Uninstalling twice is harmless, and registering again looks for stores again")
    func uninstallTwiceThenReinstall() async throws {
        let (drawer, cleanUp) = try Self.drawer()
        defer { cleanUp() }
        let (model, folder) = try Self.model()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sut = DatabaseBrowserPlugin(model: model)
        drawer.registerGlobal(sut)
        drawer.unregisterGlobal(id: sut.id)

        sut.uninstall(from: drawer)
        drawer.registerGlobal(sut)
        await model.installRefresh?.value

        #expect(model.listings.map(\.store.name) == ["shop.sqlite"])
    }
}
