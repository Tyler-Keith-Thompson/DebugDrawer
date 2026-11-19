// What opening a large earlier session under Previous costs the main actor. The sessions exist in
// debug builds only, so it is measured there; `--config=release` builds this target without it,
// and runs ReleaseInstallTests instead.
#if DEBUG && os(macOS)
    import AppKit
    @testable import DebugDrawerConsolePlugin
    import SwiftUI
    import Testing

    // A session at ConsoleSessionPersistence's 20 MB, about 97,000 lines, opened in the drawer's
    // view, hosted in a window that is never shown. Drawing every line's text took about a second
    // of the main actor in debug builds on an Apple silicon Mac; the page the store is handed,
    // worked out off the main actor, draws 2,000 lines in a few tens of milliseconds. The bound is
    // several times that, so a loaded machine passes and a change that draws or filters the whole
    // session on the main actor again fails.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleSessionOpenSpeedTests {
        @Test("Opening a 20 MB session under Previous blocks the main actor under 250 ms, and later updates under 50 ms")
        func openLargeSession() async throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let encoder = JSONEncoder()
            let categories = ["networking", "ui", "storage", "auth", "payments"]
            var data = try encoder.encode(ConsoleSessionHeader(started: "2027-01-15T08:00:00.000Z", app: "Shop", appVersion: "2.1 (40)"))
            var index = 0
            while data.count < 20_000_000 {
                let line = LogLine(
                    timestamp: started.addingTimeInterval(Double(index) / 100),
                    text: "Request \(index) to /api/v2/orders/\(index * 7) finished with status 200 in 42 ms",
                    source: .oslog, level: index % 50 == 0 ? .error : (index % 3 == 0 ? .debug : .info),
                    subsystem: "com.example.shop", category: categories[index % categories.count]
                )
                data.append(UInt8(ascii: "\n"))
                try data.append(encoder.encode(ConsoleSessionLine(line)))
                index += 1
            }
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started, id: UUID()), byteCount: data.count
            )))
            let log = ConsoleSessionLog(summary: summary, data: data)
            // A store of its own, whose mutes are read from a folder that doesn't exist: none.
            let mutes = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            let store = ConsoleLogStore(muteStorage: _ConsoleMuteStorage(directory: mutes))
            let model = ConsoleModel(store: store, sessions: ConsoleSessionsModel())
            let host = NSHostingView(rootView: ConsolePluginView(transport: .direct(to: model)).frame(width: 400, height: 700))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 700), styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let clock = ContinuousClock()
            let page = await ConsoleSessionPage.prepared(log: log, filter: store.filter)

            let start = clock.now
            store.showPrevious(page)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            // The text view scrolls to its end on the main queue's next turn; that is main-actor
            // time of the open too.
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            let openTime = clock.now - start
            let updateStart = clock.now
            store.objectWillChange.send()
            host.layoutSubtreeIfNeeded()
            let updateTime = clock.now - updateStart

            print("Console: opening a session of \(log.lines.count) lines (\(data.count) bytes) blocks the main actor \(openTime)")
            print("Console: a later update of the open session \(updateTime)")
            #expect(store.shownLines.count == ConsoleSessionPage.lineCount)
            #expect(store.previousPage?.earlierCount == log.lines.count - ConsoleSessionPage.lineCount)
            #expect(openTime < .milliseconds(250))
            #expect(updateTime < .milliseconds(50))
            store.hidePrevious()
        }
    }
#endif
