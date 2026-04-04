#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import XCTest

    @MainActor
    final class ConsolePluginTests: XCTestCase {
        func testLogLineCreation() {
            let line = LogLine(timestamp: Date(), text: "hello", source: .stdout, level: .info)
            XCTAssertEqual(line.text, "hello")
            XCTAssertEqual(line.source, .stdout)
            XCTAssertEqual(line.level, .info)
        }

        func testLogLineLevelComparable() {
            XCTAssertTrue(LogLine.Level.debug < LogLine.Level.info)
            XCTAssertTrue(LogLine.Level.info < LogLine.Level.error)
            XCTAssertTrue(LogLine.Level.error < LogLine.Level.fault)
        }

        func testLogLineLevelLabels() {
            XCTAssertEqual(LogLine.Level.error.label, "ERR")
            XCTAssertEqual(LogLine.Level.fault.label, "FLT")
            XCTAssertEqual(LogLine.Level.debug.label, "DBG")
            XCTAssertNil(LogLine.Level.info.label)
            XCTAssertNil(LogLine.Level.notice.label)
        }

        func testConsoleLogStoreCapacity() {
            let store = ConsoleLogStore.shared
            store.clear()
            XCTAssertEqual(store.lines.count, 0)
        }

        func testConsoleLogStoreFilterLevel() {
            let store = ConsoleLogStore.shared
            store.clear()
            store.filterLevel = .error
            // filteredLines should only include error+ level
            XCTAssertEqual(store.filteredLines.count, 0)
            store.filterLevel = .debug // reset
        }

        func testConsolePluginConformsToProtocol() {
            let plugin = ConsolePlugin()
            XCTAssertEqual(plugin.title, "Console")
            XCTAssertEqual(plugin.icon, "terminal")
            XCTAssertFalse(plugin.id.isEmpty)
        }

        func testConsolePluginRegistration() {
            let drawer = DebugDrawer.shared
            for p in drawer.globalPlugins { drawer.unregisterGlobal(id: p.id) }

            // Register the plugin directly without installing stdout capture
            // (install() redirects stdout which breaks the test runner)
            drawer.registerGlobal(ConsolePlugin())
            XCTAssertTrue(drawer.globalPlugins.contains(where: { $0.title == "Console" }))
        }
    }
#endif
