// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac. The
// views take their values and hold no state of their own, so they are inspected offline.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerScreenRecordingPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ScreenRecordingViewTests {
        @Test("Before recording: Not Recording, and Record starts; there is no Stop")
        func idle() throws {
            var starts = 0
            let sut = ScreenRecordingView(
                state: .idle, recordings: [], includedInReport: [], capacity: 5, showsTouches: .constant(false),
                start: { starts += 1 }, stop: {}, delete: { _ in }, setIncludedInReport: { _, _ in }
            )

            _ = try sut.inspect().find(text: "Not recording")
            try sut.inspect().find(button: "Record").tap()

            #expect(starts == 1)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Stop") }
            #expect(throws: (any Error).self) { try sut.inspect().find(text: "Recordings") }
        }

        @Test("While recording: Recording, and Stop stops; there is no Record")
        func recording() throws {
            var stops = 0
            let sut = ScreenRecordingView(
                state: .recording(started: Date()), recordings: [], includedInReport: [], capacity: 5, showsTouches: .constant(false),
                start: {}, stop: { stops += 1 }, delete: { _ in }, setIncludedInReport: { _, _ in }
            )

            _ = try sut.inspect().find(text: "Recording")
            try sut.inspect().find(button: "Stop").tap()

            #expect(stops == 1)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Record") }
        }

        @Test("While the movie is written, Record is unavailable")
        func finishing() throws {
            let sut = ScreenRecordingView(
                state: .finishing, recordings: [], includedInReport: [], capacity: 5, showsTouches: .constant(false),
                start: {}, stop: {}, delete: { _ in }, setIncludedInReport: { _, _ in }
            )

            let record = try sut.inspect().find(button: "Record")

            _ = try sut.inspect().find(text: "Saving the movie…")
            #expect(record.isDisabled())
        }

        @Test("A failure says why, and Record can start again")
        func failed() throws {
            let sut = ScreenRecordingView(
                state: .failed(.noFrames), recordings: [], includedInReport: [], capacity: 5, showsTouches: .constant(false),
                start: {}, stop: {}, delete: { _ in }, setIncludedInReport: { _, _ in }
            )

            let message = try sut.inspect().find(text: RecordingFailure.noFrames.message).string()

            #expect(message == "Stopped before a frame was recorded, so nothing was saved.")
            #expect(try !sut.inspect().find(button: "Record").isDisabled())
        }

        @Test("Each recording shows its start, length and size, and offers Share, its report state and Delete")
        func recordings() throws {
            let newest = Recording(
                url: URL(filePath: "/tmp/Screen Recording 2025-11-16T10-47-00Z.mov"),
                started: Date(timeIntervalSince1970: 1_763_290_020), duration: .seconds(12), byteCount: 3_400_000
            )
            let older = Recording(
                url: URL(filePath: "/tmp/Screen Recording 2025-11-16T10-46-40Z.mov"),
                started: Date(timeIntervalSince1970: 1_763_290_000), duration: nil, byteCount: 1000
            )
            var deleted: [Recording] = []
            var included: [(Bool, Recording)] = []
            let sut = ScreenRecordingView(
                state: .finished(newest.url), recordings: [newest, older], includedInReport: [newest.id], capacity: 5,
                showsTouches: .constant(false), start: {}, stop: {},
                delete: { deleted.append($0) }, setIncludedInReport: { included.append(($0, $1)) }
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, try #require(TimeZone(identifier: "UTC")))

            let rows = try sut.inspect().findAll(RecordingRow.self)
            try rows[0].find(button: "Delete").tap()
            try rows[0].find(button: "In Bug Report").tap()
            try rows[1].find(button: "Add to Bug Report").tap()

            #expect(rows.count == 2)
            #expect(try rows[0].find(text: "Nov 16 at 10:47:00\u{202F}AM").string() == "Nov 16 at 10:47:00\u{202F}AM")
            #expect(try rows[0].find(text: "0:12 · 3.4 MB").string() == "0:12 · 3.4 MB")
            #expect(try rows[1].find(text: "1 kB").string() == "1 kB")
            _ = try rows[0].find(ViewType.ShareLink.self)
            #expect(deleted == [newest])
            #expect(included.map(\.0) == [false, true])
            #expect(included.map(\.1) == [newest, older])
            _ = try sut.inspect().find(text: "Recordings")
        }

        @Test("The HUD shows Record before a recording and Stop with the time while it records; each tap toggles")
        func hud() throws {
            var toggles = 0
            let idle = ScreenRecordingHUDButton(state: .idle) { toggles += 1 }
            let recording = ScreenRecordingHUDButton(state: .recording(started: Date())) { toggles += 1 }

            _ = try idle.inspect().find(text: "Record")
            try idle.inspect().button().tap()
            try recording.inspect().button().tap()

            #expect(try idle.inspect().button().accessibilityLabel().string() == "Start screen recording")
            #expect(try recording.inspect().button().accessibilityLabel().string() == "Stop screen recording")
            #expect(toggles == 2)
        }

        @Test("While the movie is written the HUD says Saving and can't be pressed")
        func hudFinishing() throws {
            let sut = ScreenRecordingHUDButton(state: .finishing) {}

            _ = try sut.inspect().find(text: "Saving…")
            #expect(try sut.inspect().button().isDisabled())
        }

        @Test("The header counts the recordings, says Saving while one is written, and shows nothing before the first")
        func header() throws {
            let none = ScreenRecordingHeaderReadout(state: .idle, count: 0)
            let one = ScreenRecordingHeaderReadout(state: .finished(URL(filePath: "/tmp/a.mov")), count: 1)
            let three = ScreenRecordingHeaderReadout(state: .idle, count: 3)
            let saving = ScreenRecordingHeaderReadout(state: .finishing, count: 3)

            #expect(throws: (any Error).self) { try none.inspect().find(ViewType.Text.self) }
            #expect(try one.inspect().find(ViewType.Text.self).string() == "1 recording")
            #expect(try three.inspect().find(ViewType.Text.self).string() == "3 recordings")
            #expect(try saving.inspect().find(ViewType.Text.self).string() == "Saving…")
        }
    }
#endif
