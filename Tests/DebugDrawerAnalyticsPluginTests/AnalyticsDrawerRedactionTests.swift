// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerAnalyticsPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    extension SharedDrawerTests {
        // Hosted, so the view reads the drawer it is shown in from SwiftUI's environment (offline,
        // ViewInspector can't inject a reference there) and its detail opens through its own
        // state. Here, as hosts must not run at once and one test changes DebugDrawer.shared's
        // rules, restored in a defer.
        @MainActor
        @Suite(.timeLimit(.minutes(1)))
        struct AnalyticsDrawerRedactionTests {
            @Test("In a drawer of its own, Analytics masks on screen and in Copy JSON by that drawer's rules as they change, not shared's")
            func ownDrawerRedaction() async throws {
                let suite = "AnalyticsDrawerRedactionTests.ownDrawerRedaction.\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let sharedRules = DebugDrawer.shared.redaction
                defer { DebugDrawer.shared.redaction = sharedRules }
                let drawer = DebugDrawer(defaults: defaults)
                let masksPlan = DebugDrawerRedaction.none.adding(keys: ["plan"])
                let masksCoupon = DebugDrawerRedaction.none.adding(keys: ["coupon"])
                drawer.redaction = masksPlan
                DebugDrawer.shared.redaction = masksCoupon
                let log = AnalyticsEventLog(capacity: 10)
                log.record(name: "checkout", properties: ["plan": "premium", "coupon": "SAVE10"], source: nil)
                let plugin = AnalyticsPlugin(model: AnalyticsEventsModel(log: log))
                drawer.registerGlobal(plugin)
                defer { drawer.unregisterGlobal(id: plugin.id) }
                let event = try #require(plugin.model.events.first)
                // The plugin's body, under the drawer its views are shown in, as the drawer's
                // panel sets it.
                let sut = AnalyticsPluginView(model: plugin.model)
                let expectedOwn: [String: String] = ["coupon": "SAVE10", "plan": DebugDrawerRedaction.mask]
                let expectedChanged: [String: String] = ["coupon": DebugDrawerRedaction.mask, "plan": "premium"]
                var shownDrawer: DebugDrawer?
                var shownOwn: [String: String] = [:]
                var copiedOwn: String?
                var shownChanged: [String: String] = [:]
                var copiedChanged: String?
                var shownAfterShared: [String: String] = [:]
                var copiedAfterShared: String?

                try await ViewHosting.host(sut.environment(\.showingDrawer, drawer)) {
                    try await sut.inspection.inspect { view in
                        shownDrawer = try view.actualView().showingDrawer
                        try view.find(AnalyticsEventRow.self).button().tap()
                    }
                    try await sut.inspection.inspect { view in
                        shownOwn = try Dictionary(uniqueKeysWithValues: view.findAll(DebugDrawerKeyValueRow.self).map {
                            let row = try $0.actualView()
                            return (row.label, row.redacted)
                        })
                        copiedOwn = try view.find(DebugDrawerCopyButton.self).actualView().value()
                    }
                    drawer.redaction = masksCoupon
                    try await sut.inspection.inspect { view in
                        shownChanged = try Dictionary(uniqueKeysWithValues: view.findAll(DebugDrawerKeyValueRow.self).map {
                            let row = try $0.actualView()
                            return (row.label, row.redacted)
                        })
                        copiedChanged = try view.find(DebugDrawerCopyButton.self).actualView().value()
                    }
                    DebugDrawer.shared.redaction = masksPlan
                    try await sut.inspection.inspect { view in
                        shownAfterShared = try Dictionary(uniqueKeysWithValues: view.findAll(DebugDrawerKeyValueRow.self).map {
                            let row = try $0.actualView()
                            return (row.label, row.redacted)
                        })
                        copiedAfterShared = try view.find(DebugDrawerCopyButton.self).actualView().value()
                    }
                }

                #expect(shownDrawer === drawer)
                #expect(shownOwn == expectedOwn)
                #expect(copiedOwn == event.formattedJSON(redaction: masksPlan))
                #expect(copiedOwn?.contains("SAVE10") == true)
                #expect(copiedOwn?.contains("premium") == false)
                #expect(shownChanged == expectedChanged)
                #expect(copiedChanged == event.formattedJSON(redaction: masksCoupon))
                #expect(copiedChanged?.contains("premium") == true)
                #expect(copiedChanged?.contains("SAVE10") == false)
                #expect(shownAfterShared == expectedChanged)
                #expect(copiedAfterShared == copiedChanged)
            }

            @Test("Shown outside any drawer, as in a view drawn alone, the plugin masks by DebugDrawer.shared's rules")
            func outsideDrawerFollowsShared() async throws {
                let sharedRules = DebugDrawer.shared.redaction
                defer { DebugDrawer.shared.redaction = sharedRules }
                DebugDrawer.shared.redaction = DebugDrawerRedaction.none.adding(keys: ["plan"])
                let log = AnalyticsEventLog(capacity: 10)
                log.record(name: "checkout", properties: ["plan": "premium", "coupon": "SAVE10"], source: nil)
                let sut = AnalyticsPluginView(model: AnalyticsEventsModel(log: log))
                let expected: [String: String] = ["coupon": "SAVE10", "plan": DebugDrawerRedaction.mask]
                var shownDrawer: DebugDrawer?
                var shown: [String: String] = [:]

                try await ViewHosting.host(sut) {
                    try await sut.inspection.inspect { view in
                        shownDrawer = try view.actualView().showingDrawer
                        try view.find(AnalyticsEventRow.self).button().tap()
                    }
                    try await sut.inspection.inspect { view in
                        shown = try Dictionary(uniqueKeysWithValues: view.findAll(DebugDrawerKeyValueRow.self).map {
                            let row = try $0.actualView()
                            return (row.label, row.redacted)
                        })
                    }
                }

                #expect(shownDrawer == nil)
                #expect(shown == expected)
            }
        }
    }
#endif
