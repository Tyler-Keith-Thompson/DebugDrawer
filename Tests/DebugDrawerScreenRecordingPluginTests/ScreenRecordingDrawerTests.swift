#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerScreenRecordingPlugin
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    // Installing on drawers of the test's own registers nothing with DebugDrawer.shared and starts
    // nothing until Record, so these run in the test process. Each drawer has a suite of its own.
    @MainActor
    @Suite("Screen Recording installed on drawers of their own", .timeLimit(.minutes(1)))
    struct ScreenRecordingDrawerTests {
        @Test("Installed on two drawers, each keeps a model of its own: its capacity, Show Touches in its own defaults, and its install state")
        func twoDrawersKeepTheirOwnState() throws {
            let firstSuite = temporarySuiteName("ScreenRecordingDrawerTests")
            let secondSuite = temporarySuiteName("ScreenRecordingDrawerTests")
            defer {
                UserDefaults().removePersistentDomain(forName: firstSuite)
                UserDefaults().removePersistentDomain(forName: secondSuite)
            }
            let firstDefaults = try #require(UserDefaults(suiteName: firstSuite))
            let secondDefaults = try #require(UserDefaults(suiteName: secondSuite))
            let first = DebugDrawer(defaults: firstDefaults)
            let second = DebugDrawer(defaults: secondDefaults)
            let key = ScreenRecordingModel.showsTouchesKey

            let firstModel = ScreenRecordingInstallation.install(capacity: 2, in: first)
            let secondModel = ScreenRecordingInstallation.install(capacity: 3, in: second)
            let firstAgain = ScreenRecordingInstallation.install(capacity: 4, in: first)
            firstModel.showsTouches = true
            first.unregisterGlobal(id: ScreenRecordingPlugin.pluginID)

            #expect(firstAgain === firstModel)
            #expect(secondModel !== firstModel)
            #expect(firstModel.capacity == 4)
            #expect(secondModel.capacity == 3)
            #expect(firstDefaults.bool(forKey: key))
            #expect(secondDefaults.object(forKey: key) == nil)
            #expect(!secondModel.showsTouches)
            #expect(firstModel.isUninstalled)
            #expect(!secondModel.isUninstalled)
            #expect(second.globalPlugins.count { $0.id == ScreenRecordingPlugin.pluginID } == 1)
        }

        @Test("ScreenRecording.install(capacity:in:) registers the plugin with the drawer it is given, and not with DebugDrawer.shared")
        func publicInstallUsesTheDrawer() throws {
            let suite = temporarySuiteName("ScreenRecordingDrawerTests")
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let drawer = try DebugDrawer(defaults: #require(UserDefaults(suiteName: suite)))

            try ScreenRecording.install(capacity: 2, in: drawer)

            let plugin = drawer.globalPlugins.first { $0.id == ScreenRecordingPlugin.pluginID }
            #expect(plugin?.hasHUD == true)
            #expect(plugin?.contributesToReport == true)
            #expect(!DebugDrawer.shared.globalPlugins.contains { $0.id == ScreenRecordingPlugin.pluginID })
        }

        @Test("A capacity of 0 throws InvalidCapacity and adds nothing to the drawer")
        func zeroCapacity() throws {
            let suite = temporarySuiteName("ScreenRecordingDrawerTests")
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let drawer = try DebugDrawer(defaults: #require(UserDefaults(suiteName: suite)))
            let capacity = 0

            #expect(throws: ScreenRecording.InvalidCapacity.self) {
                try ScreenRecording.install(capacity: capacity, in: drawer)
            }
            #expect(!drawer.globalPlugins.contains { $0.id == ScreenRecordingPlugin.pluginID })
        }

        @Test("A negative capacity throws InvalidCapacity, on the shared drawer too, and adds nothing")
        func negativeCapacity() {
            let capacity = -1

            #expect(throws: ScreenRecording.InvalidCapacity.self) {
                try ScreenRecording.install(capacity: capacity)
            }
            #expect(!DebugDrawer.shared.globalPlugins.contains { $0.id == ScreenRecordingPlugin.pluginID })
        }

        @Test("A capacity of 1 is taken: the edge of the valid range")
        func oneCapacity() throws {
            let suite = temporarySuiteName("ScreenRecordingDrawerTests")
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            let drawer = try DebugDrawer(defaults: #require(UserDefaults(suiteName: suite)))

            try ScreenRecording.install(capacity: 1, in: drawer)

            #expect(drawer.globalPlugins.contains { $0.id == ScreenRecordingPlugin.pluginID })
        }
    }
#endif
