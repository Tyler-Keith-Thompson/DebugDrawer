// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    extension DebugDrawerConsolePlugin.Inspection: InspectionEmissary {}

    // Hosted, so the view reads the drawer it is shown in from SwiftUI's environment (offline,
    // ViewInspector can't inject a reference there). Serialized, as hosts must not run at once and
    // both tests change DebugDrawer.shared's rules, restored in a defer.
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct ConsoleCopyRedactionTests {
        @Test("In a drawer of its own, Copy All and Copy Line mask by that drawer's rules as each copy happens, not shared's")
        func ownDrawerRules() async throws {
            final class Copied {
                var texts: [String] = []
            }
            let suite = "ConsoleCopyRedactionTests.ownDrawerRules.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sharedRules = DebugDrawer.shared.redaction
            defer { DebugDrawer.shared.redaction = sharedRules }
            let drawer = DebugDrawer(defaults: defaults)
            drawer.redaction = DebugDrawerRedaction.none.adding(keys: ["token"])
            DebugDrawer.shared.redaction = DebugDrawerRedaction.none.adding(keys: ["order"])
            let time = Date(timeIntervalSince1970: 1_800_000_000)
            let line = LogLine(
                timestamp: time, text: "Paid token=abc order=1042", source: .sink, level: .info, metadata: ["token": "t1", "order": "7"]
            )
            var snapshot = ConsoleSnapshot()
            snapshot.log.lines = [line]
            let copied = Copied()
            let sut = ConsolePluginContent(
                transport: DebugDrawerPluginTransport(initial: snapshot, snapshots: AsyncStream { $0.finish() }, send: { _ in }),
                copyToClipboard: { copied.texts.append($0) }
            )
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let shown = formatter.string(from: time)
            let expectedOwn = "\(shown) Paid token=[REDACTED] order=1042 order=7 token=[REDACTED]"
            let expectedChanged = "\(shown) Paid token=abc order=[REDACTED] order=[REDACTED] token=t1"
            let expected = [expectedOwn, expectedOwn, expectedChanged, expectedChanged]

            try await ViewHosting.host(sut.environment(\.showingDrawer, drawer)) {
                try await sut.inspection.inspect { view in
                    try view.find(ConsoleMoreMenu.self).actualView().copyAll()
                    try view.find(ConsoleLinesWell.self).actualView().perform(.copy(line))
                    drawer.redaction = DebugDrawerRedaction.none.adding(keys: ["order"])
                    DebugDrawer.shared.redaction = DebugDrawerRedaction.none.adding(keys: ["token"])
                    try view.find(ConsoleMoreMenu.self).actualView().copyAll()
                    try view.find(ConsoleLinesWell.self).actualView().perform(.copy(line))
                }
            }

            #expect(copied.texts == expected)
        }

        @Test("Shown outside any drawer, as in a view drawn alone, Copy All and Copy Line mask by DebugDrawer.shared's rules")
        func outsideDrawerFollowsShared() async throws {
            final class Copied {
                var texts: [String] = []
            }
            let sharedRules = DebugDrawer.shared.redaction
            defer { DebugDrawer.shared.redaction = sharedRules }
            DebugDrawer.shared.redaction = DebugDrawerRedaction.none.adding(keys: ["order"])
            let time = Date(timeIntervalSince1970: 1_800_000_000)
            let line = LogLine(timestamp: time, text: "Paid token=abc order=1042", source: .stdout, level: .info)
            var snapshot = ConsoleSnapshot()
            snapshot.log.lines = [line]
            let copied = Copied()
            let sut = ConsolePluginContent(
                transport: DebugDrawerPluginTransport(initial: snapshot, snapshots: AsyncStream { $0.finish() }, send: { _ in }),
                copyToClipboard: { copied.texts.append($0) }
            )
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let expectedLine = "\(formatter.string(from: time)) Paid token=abc order=[REDACTED]"
            let expected = [expectedLine, expectedLine]

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ConsoleMoreMenu.self).actualView().copyAll()
                    try view.find(ConsoleLinesWell.self).actualView().perform(.copy(line))
                }
            }

            #expect(copied.texts == expected)
        }
    }
#endif
