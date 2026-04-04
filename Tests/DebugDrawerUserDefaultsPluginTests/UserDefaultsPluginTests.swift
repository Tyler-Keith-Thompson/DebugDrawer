#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerUserDefaultsPlugin
    import XCTest

    @MainActor
    final class UserDefaultsPluginTests: XCTestCase {
        private let testKey = "com.debugdrawer.test.key"

        override func tearDown() {
            UserDefaults.standard.removeObject(forKey: testKey)
        }

        func testStoreLoadsEntries() {
            UserDefaults.standard.set("test_value", forKey: testKey)
            let store = UserDefaultsStore.shared
            store.reload()
            XCTAssertTrue(store.entries.contains(where: { $0.key == testKey }))
        }

        func testStoreSetValue() {
            let store = UserDefaultsStore.shared
            store.setValue(testKey, "new_value")
            XCTAssertEqual(UserDefaults.standard.string(forKey: testKey), "new_value")
        }

        func testStoreDeleteKey() {
            UserDefaults.standard.set("to_delete", forKey: testKey)
            let store = UserDefaultsStore.shared
            store.deleteKey(testKey)
            XCTAssertNil(UserDefaults.standard.object(forKey: testKey))
        }

        func testFilterExcludesSystemKeys() {
            let store = UserDefaultsStore.shared
            store.showSystemKeys = false
            store.reload()
            let systemEntries = store.filteredEntries.filter { $0.key.hasPrefix("NS") || $0.key.hasPrefix("Apple") }
            XCTAssertEqual(systemEntries.count, 0)
        }

        func testFilterIncludesSystemKeys() {
            let store = UserDefaultsStore.shared
            store.showSystemKeys = true
            store.reload()
            // Should have some system keys
            XCTAssertTrue(store.filteredEntries.count >= store.entries.filter { !$0.key.hasPrefix("NS") && !$0.key.hasPrefix("Apple") }.count)
        }

        func testSearchFilter() {
            UserDefaults.standard.set("findme", forKey: testKey)
            let store = UserDefaultsStore.shared
            store.reload()
            store.searchText = "debugdrawer.test"
            XCTAssertTrue(store.filteredEntries.contains(where: { $0.key == testKey }))
            store.searchText = ""
        }
    }
#endif
