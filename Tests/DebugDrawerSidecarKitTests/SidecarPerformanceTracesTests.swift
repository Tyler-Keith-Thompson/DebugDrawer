#if DEBUG && os(macOS)
    import CoreFoundation
    import DebugDrawer
    import DebugDrawerHangDetectorPlugin
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    /// Names one mangled symbol, so the view's demangling is the test's to steer.
    private struct FakeDemangler: SymbolDemangler {
        func demangle(_ symbol: String) -> String? {
            symbol == "$s7Example6freezeyyF" ? "Example.freeze() -> ()" : nil
        }
    }

    // Start Recording from the sidecar's button to the production app's receiver, and the view's
    // rows: each stall's kind and duration, its stack as the frames' demangled symbols or, for a
    // frame a stripped build can't name, its image and offset. Each wait is for the snapshot that
    // step should produce, never for time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarPerformanceTracesTests {
        @Test("The kit lists the capability, and Start Recording starts the app's recording in the session")
        func startButtonStarts() async throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarPerformanceTracesTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let traces = PerformanceTraces(sessions: sessions)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.performanceTraces(traces))
            try receiver.start()
            defer { receiver.stop() }
            sessions.perform(.open(duration: 60))
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let sut = try DebugDrawerSidecarConnection(app: listed)
            defer { sut.close() }
            let hosted = try await sut.host(.performanceTraces)

            try hosted.body.inspect().find(button: "Start Recording").tap()

            for await snapshot in traces.$snapshot.values where snapshot.isRecording {
                break
            }
            #expect(listed.serves(PerformanceTraces.pluginID))
            #expect(traces.monitor != nil)
            #expect(sessions.auditLog.last?.event == .commandApplied)
            traces.perform(.stop)
        }

        @Test("While nothing records the view offers Start Recording, which sends start")
        func notRecording() throws {
            let snapshot = PerformanceTraces.Snapshot(
                sessionID: nil, executable: "Example", hitchThreshold: .milliseconds(100), hangThreshold: .milliseconds(250),
                stalls: [], intervals: [], droppedStalls: 0, droppedIntervals: 0, limits: .standard, exports: []
            )
            var sent: [PerformanceTraces.Command] = []
            let sut = PerformanceTracesView(snapshot: snapshot, expanded: .constant(nil), demangler: FakeDemangler()) { sent.append($0) }

            try sut.inspect().find(button: "Start Recording").tap()

            #expect(sent == [.start])
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Stop and Delete") }
        }

        @Test("A stall opens to its stack, symbols demangled and unnamed frames as image and offset; signposts list; Stop and Delete sends stop")
        func recording() throws {
            let uuid = try #require(UUID(uuidString: "6F1C2B0E-8C4D-4E6A-9C0B-1D2E3F405162"))
            let snapshot = PerformanceTraces.Snapshot(
                sessionID: UUID(), executable: "Example", hitchThreshold: .milliseconds(100), hangThreshold: .milliseconds(250),
                stalls: [
                    PerformanceTraces.Stall(
                        id: 1, kind: .hang, began: Date(timeIntervalSince1970: 0), duration: .milliseconds(2013),
                        frames: [
                            PerformanceTraces.Frame(
                                address: 0x1_0000_4A1C, image: "Example", imageUUID: uuid, imageOffset: 0x4A1C,
                                symbol: "$s7Example6freezeyyF", symbolOffset: 12
                            ),
                            PerformanceTraces.Frame(address: 0x1_0000_5B00, image: "Example", imageUUID: uuid, imageOffset: 0x5B00)
                        ]
                    )
                ],
                intervals: [
                    PerformanceTraces.SignpostInterval(id: 1, name: "Load feed", began: Date(timeIntervalSince1970: 1), duration: .milliseconds(340))
                ],
                droppedStalls: 0, droppedIntervals: 0, limits: .standard, exports: []
            )
            var sent: [PerformanceTraces.Command] = []
            let sut = PerformanceTracesView(snapshot: snapshot, expanded: .constant(1), demangler: FakeDemangler()) { sent.append($0) }

            try sut.inspect().find(button: "Stop and Delete").tap()

            #expect(sent == [.stop])
            #expect(throws: Never.self) { try sut.inspect().find(text: "2013 ms") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "Example.freeze() -> ()") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "Example + 0x5b00") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "Load feed") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "340 ms") }
        }

        @Test("Create Report adds performance.txt from the snapshot and tells the app it was exported")
        func reportContribution() async throws {
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let traces = PerformanceTraces(sessions: sessions)
            sessions.perform(.open(duration: 60))
            traces.perform(.start)
            traces.endInterval(traces.beginInterval("Load feed"))
            for await snapshot in traces.$snapshot.values where !snapshot.intervals.isEmpty {
                break
            }
            let sut = PerformanceTracesPlugin(transport: .direct(to: traces))
            var report = DebugDrawerReport()

            sut.contribute(to: &report, redaction: DebugDrawerRedaction())

            let file = try #require(report.files.first { $0.name == "performance.txt" })
            #expect(String(data: file.data, encoding: .utf8)?.contains("Load feed:") == true)
            #expect(traces.snapshot.exports.count == 1)
            traces.perform(.stop)
        }
    }
#endif
