#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    // The store tests clear the shared store and read it back without suspending, on the main
    // actor, so no other suite's line lands between the two.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsolePluginTests {
        @Test("A log line keeps the text, source and level it was made with")
        func logLineCreation() {
            let line = LogLine(timestamp: Date(), text: "hello", source: .stdout, level: .info)
            #expect(line.text == "hello")
            #expect(line.source == .stdout)
            #expect(line.level == .info)
        }

        @Test("Levels order debug, info, error, fault")
        func logLineLevelComparable() {
            #expect(LogLine.Level.debug < LogLine.Level.info)
            #expect(LogLine.Level.info < LogLine.Level.error)
            #expect(LogLine.Level.error < LogLine.Level.fault)
        }

        @Test("Error, fault and debug have the short labels ERR, FLT and DBG; info and notice have none")
        func logLineLevelLabels() {
            #expect(LogLine.Level.error.label == "ERR")
            #expect(LogLine.Level.fault.label == "FLT")
            #expect(LogLine.Level.debug.label == "DBG")
            #expect(LogLine.Level.info.label == nil)
            #expect(LogLine.Level.notice.label == nil)
        }

        @Test("Clearing the store leaves no lines")
        func consoleLogStoreCapacity() {
            let store = ConsoleLogStore.shared
            store.clear()
            #expect(store.lines.isEmpty)
        }

        @Test("A cleared store filtered to errors shows no lines")
        func consoleLogStoreFilterLevel() {
            let store = ConsoleLogStore.shared
            store.clear()
            store.filterLevel = .error
            defer { store.filterLevel = .debug }
            // filteredLines should only include error+ level
            #expect(store.filteredLines.isEmpty)
        }

        @Test("The plugin is titled Console, with the terminal icon and an id")
        func consolePluginConformsToProtocol() {
            let plugin = ConsolePlugin()
            #expect(plugin.title == "Console")
            #expect(plugin.icon == "terminal")
            #expect(!plugin.id.isEmpty)
        }

        @Test("Registering the plugin globally lists it among the drawer's global plugins")
        func consolePluginRegistration() {
            let drawer = DebugDrawer.shared
            for plugin in drawer.globalPlugins { drawer.unregisterGlobal(id: plugin.id) }

            // Register the plugin directly without installing stdout capture
            // (install() redirects stdout which breaks the test runner)
            drawer.registerGlobal(ConsolePlugin())
            #expect(drawer.globalPlugins.contains(where: { $0.title == "Console" }))
        }
    }
#endif
