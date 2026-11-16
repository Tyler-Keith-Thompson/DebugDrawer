#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerAnalyticsPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct AnalyticsPluginTests {
        @Test("The plugin is Analytics, in Logs & Network, and adds to bug reports")
        func identity() {
            let sut = AnalyticsPlugin(model: AnalyticsEventsModel(log: AnalyticsEventLog(capacity: 10)))

            #expect(sut.id == "AnalyticsPlugin")
            #expect(sut.title == "Analytics")
            #expect(sut.category == "Logs & Network")
            #expect(sut.icon == "chart.line.uptrend.xyaxis")
            #expect(AnyDebugDrawerPlugin(sut).contributesToReport)
            #expect(AnyDebugDrawerPlugin(sut).headerAccessory != nil)
        }

        @Test("The drawer's search offers clearing the events, found by \"tracking\" too")
        func action() throws {
            let log = AnalyticsEventLog(capacity: 10)
            log.record(name: "opened", properties: [:], source: nil)
            let model = AnalyticsEventsModel(log: log)
            let sut = AnalyticsPlugin(model: model)

            let actual = try #require(sut.actions.first)
            actual.perform()

            #expect(sut.actions.map(\.title) == ["Clear analytics events"])
            #expect(actual.keywords.contains("tracking"))
            #expect(model.events.isEmpty)
            #expect(log.events.isEmpty)
        }

        @Test("The bug report gets analytics.json: every event, newest first, sensitive values masked")
        func report() throws {
            let events = [
                AnalyticsEvent(id: 2, timestamp: Date(timeIntervalSince1970: 1), name: "signed_in", properties: ["auth_token": "t0k3n"], source: nil),
                AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "opened", properties: [:], source: "Segment")
            ]
            let expectedJSON = """
            [
              {
                "name" : "signed_in",
                "properties" : {
                  "auth_token" : "[REDACTED]"
                },
                "timestamp" : "1970-01-01T00:00:01.000Z"
              },
              {
                "name" : "opened",
                "properties" : {

                },
                "source" : "Segment",
                "timestamp" : "1970-01-01T00:00:00.000Z"
              }
            ]
            """
            var actual = DebugDrawerReport()

            AnalyticsPlugin.contribute(events, redaction: .standard, to: &actual)

            let file = try #require(actual.files.first)
            #expect(actual.files.map(\.name) == ["analytics.json"])
            #expect(file.kind == .json)
            #expect(String(bytes: file.data, encoding: .utf8) == expectedJSON)
        }

        @Test("No events add nothing to the bug report")
        func reportEmpty() {
            var actual = DebugDrawerReport()

            AnalyticsPlugin.contribute([], redaction: .standard, to: &actual)

            #expect(actual.files.isEmpty)
        }

        @Test("The plugin's report reads the model's events")
        func reportFromModel() {
            let log = AnalyticsEventLog(capacity: 10)
            log.record(name: "opened", properties: [:], source: nil)
            let sut = AnalyticsPlugin(model: AnalyticsEventsModel(log: log))
            var actual = DebugDrawerReport()

            sut.contribute(to: &actual, redaction: .none)

            #expect(actual.files.map(\.name) == ["analytics.json"])
        }

        #if !os(tvOS) && !os(watchOS)
            @Test("Export All is a JSON array of every event, masked, named by the newest event's time")
            func export() throws {
                let events = [
                    AnalyticsEvent(
                        id: 2, timestamp: Date(timeIntervalSince1970: 1_763_290_000), name: "b", properties: ["password": "x"], source: nil
                    ),
                    AnalyticsEvent(id: 1, timestamp: Date(timeIntervalSince1970: 0), name: "a", properties: [:], source: nil)
                ]
                let sut = AnalyticsEventsFile(events: events, redaction: .standard)
                let expected = AnalyticsEvent.formattedJSON(of: events, redaction: .standard)

                let actual = try #require(String(bytes: sut.data, encoding: .utf8))

                #expect(actual == expected)
                #expect(actual.contains("[REDACTED]"))
                #expect(!actual.contains("\"x\""))
                #expect(sut.fileName == "Analytics Events 2025-11-16T10-46-40Z.json")
            }

            @Test("Export All with no events is an empty array, named without a time")
            func exportEmpty() {
                let sut = AnalyticsEventsFile(events: [], redaction: .none)

                #expect(String(bytes: sut.data, encoding: .utf8) == "[\n\n]")
                #expect(sut.fileName == "Analytics Events.json")
            }
        #endif
    }
#endif
