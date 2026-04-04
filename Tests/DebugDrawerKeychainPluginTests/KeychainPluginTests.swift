#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerKeychainPlugin
    import XCTest

    @MainActor
    final class KeychainPluginTests: XCTestCase {
        func testPluginConformance() {
            let plugin = KeychainPlugin()
            XCTAssertEqual(plugin.title, "Keychain")
            XCTAssertEqual(plugin.icon, "key")
        }

        func testKeychainStoreReload() {
            let store = KeychainStore.shared
            store.reload()
            // May have entries, may not — just ensure no crash
            _ = store.entries.count
        }

        func testKeychainStoreFilter() {
            let store = KeychainStore.shared
            store.reload()
            store.searchText = "definitely_not_a_real_keychain_entry_12345"
            XCTAssertEqual(store.filteredEntries.count, 0)
            store.searchText = ""
        }
    }
#endif
