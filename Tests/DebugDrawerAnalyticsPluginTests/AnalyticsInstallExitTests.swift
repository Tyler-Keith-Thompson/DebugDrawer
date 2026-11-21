// Installing registers the plugin with the drawer of the process that runs it, and recording
// writes to that process's one log, so these run in a child process each, in a file of their
// own, as exit tests need one. The README's example is here, verbatim, rather than in
// DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerAnalyticsPlugin
    import Foundation
    import Testing

    @Suite("Analytics install, in a child process")
    struct AnalyticsInstallExitTests {
        @Test("Install registers the plugin, keeps the events recorded before it, and badges them")
        func install() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                AnalyticsEvents.record("app_launched")
                AnalyticsEvents.record("session_started", properties: ["cold": true], source: "Segment")
                let isExpected = await MainActor.run {
                    AnalyticsEvents.install()
                    let isRegistered = DebugDrawer.shared.globalPlugins.contains { $0.title == "Analytics" }
                    let events = AnalyticsEventLog.shared.events
                    return isRegistered
                        && events.map(\.name) == ["session_started", "app_launched"]
                        && events.first?.properties == ["cold": true] && events.first?.source == "Segment"
                        && AnalyticsEventLog.shared.capacity == AnalyticsEvents.defaultCapacity
                        && DebugDrawer.shared.badges["AnalyticsPlugin"] == 2
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("An event recorded off the main actor after install reaches the plugin's model and badge")
        func recordAfterInstall() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func isExpected() async -> Bool {
                    let model = AnalyticsEventsInstallation.install(capacity: 10)
                    let updates = model.$events.values
                    await Task.detached {
                        AnalyticsEvents.record("purchase", properties: ["total": 9.99])
                    }.value
                    for await events in updates where !events.isEmpty {
                        return events.map(\.name) == ["purchase"] && DebugDrawer.shared.badges["AnalyticsPlugin"] == 1
                    }
                    return false
                }
                exit(await isExpected() ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again registers the plugin once and keeps the newest events up to the new capacity")
        func installAgain() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                for index in 0 ..< 5 {
                    AnalyticsEvents.record("event \(index)")
                }
                let isExpected = await MainActor.run {
                    AnalyticsEvents.install(capacity: 10)
                    AnalyticsEvents.install(capacity: 2)
                    let plugins = DebugDrawer.shared.globalPlugins.count { $0.title == "Analytics" }
                    return plugins == 1
                        && AnalyticsEventLog.shared.events.map(\.name) == ["event 4", "event 3"]
                        && AnalyticsEventLog.shared.capacity == 2
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Unregistering the installed plugin stops reading the shared log and clears its badge; installing again reads it")
        func uninstall() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                AnalyticsEvents.record("app_launched")
                let isExpected = await MainActor.run {
                    let model = AnalyticsEventsInstallation.install(capacity: 10)
                    let badgeWhileInstalled = DebugDrawer.shared.badges["AnalyticsPlugin"]
                    DebugDrawer.shared.unregisterGlobal(id: "AnalyticsPlugin")
                    let isUninstalled = !AnalyticsEventLog.shared.isObserved && model.events.isEmpty
                        && DebugDrawer.shared.badges["AnalyticsPlugin"] == nil
                    AnalyticsEvents.record("while_uninstalled")
                    let reinstalled = AnalyticsEventsInstallation.install(capacity: 10)
                    return badgeWhileInstalled == 1 && isUninstalled
                        && reinstalled.events.map(\.name) == ["while_uninstalled", "app_launched"]
                        && DebugDrawer.shared.badges["AnalyticsPlugin"] == 2
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Before install the newest thousand events are kept, and the plugin isn't registered")
        func recordBeforeInstall() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                for index in 0 ..< 1005 {
                    AnalyticsEvents.record("event \(index)")
                }
                let isExpected = await MainActor.run {
                    let events = AnalyticsEventLog.shared.events
                    return events.count == 1000 && events.first?.name == "event 1004" && events.last?.name == "event 5"
                        && !DebugDrawer.shared.globalPlugins.contains { $0.title == "Analytics" }
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("In debug, record evaluates each argument once")
        func recordEvaluatesOnce() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                var evaluations = 0
                func name() -> String {
                    evaluations += 1
                    return "opened"
                }
                func properties() -> [String: AnalyticsValue] {
                    evaluations += 1
                    return [:]
                }
                func source() -> String? {
                    evaluations += 1
                    return nil
                }
                AnalyticsEvents.record(name(), properties: properties(), source: source())
                exit(evaluations == 3 && AnalyticsEventLog.shared.events.count == 1 ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing with a capacity below one traps")
        func zeroCapacityTraps() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .failure) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_SUCCESS) }
                await MainActor.run {
                    AnalyticsEvents.install(capacity: 0)
                }
            }
        }

        @Test("README: Analytics")
        func readme() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isInstalled = await MainActor.run {
                    // At startup:
                    AnalyticsEvents.install()

                    // Wherever the app sends an event to its analytics service:
                    AnalyticsEvents.record("checkout_completed", properties: [
                        "plan": "pro", "seats": 3, "total": 29.99, "trial": false, "coupon": nil,
                        "items": ["sku-1", "sku-2"], "shipping": ["country": "NZ"]
                    ], source: "Segment")

                    // From an SDK's untyped properties:
                    let properties: [String: Any] = ["screen": "Settings", "dark_mode": true]
                    AnalyticsEvents.record("screen_viewed", properties: properties.mapValues(AnalyticsValue.init(converting:)))

                    return DebugDrawer.shared.globalPlugins.contains { $0.title == "Analytics" }
                        && AnalyticsEventLog.shared.events.map(\.name) == ["screen_viewed", "checkout_completed"]
                }
                exit(isInstalled ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
