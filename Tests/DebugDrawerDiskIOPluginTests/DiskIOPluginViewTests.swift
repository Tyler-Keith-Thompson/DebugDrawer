// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOPluginViewTests {
        @Test("The view reads the volume as it appears, and sends the filter, the switch, Refresh, Pause and Clear as commands")
        func sendsCommands() throws {
            var sent: [DiskIOCommand.Action] = []
            let sut = DiskIOPluginView(transport: DebugDrawerPluginTransport(
                initial: DiskIOSnapshot(
                    events: [IOEvent(timestamp: Date(), operation: .read, path: "/tmp/a", size: 1, duration: 0, isMainThread: false)]
                ),
                snapshots: AsyncStream { $0.finish() },
                send: { sent.append($0.action) }
            ))
            let expected: [DiskIOCommand.Action] = [
                .refreshVolume,
                .setOperation(.write),
                .setMainThreadOnly(true),
                .refreshVolume,
                .setPaused(true),
                .clear
            ]

            let view = try sut.inspect()
            try view.find(ViewType.VStack.self).callOnAppear()
            try view.find(ViewType.Picker.self).select(value: IOEvent.Operation?.some(.write))
            try view.find(ViewType.Toggle.self).tap()
            try view.find(button: "Refresh").tap()
            try view.find(button: "Pause").tap()
            try view.find(button: "Clear").tap()

            #expect(sent == expected)
        }

        @Test("While paused, the view offers Resume, which sends a resume, and says so where it lists no calls")
        func paused() throws {
            var sent: [DiskIOCommand.Action] = []
            let sut = DiskIOPluginView(transport: DebugDrawerPluginTransport(
                initial: DiskIOSnapshot(isPaused: true),
                snapshots: AsyncStream { $0.finish() },
                send: { sent.append($0.action) }
            ))

            let view = try sut.inspect()
            try view.find(button: "Resume").tap()

            #expect(sent == [.setPaused(false)])
            #expect(throws: Never.self) { try view.find(text: "Recording paused.") }
            #expect(throws: (any Error).self) { try view.find(button: "Pause") }
        }

        @Test("With calls kept but none passing the filter, the view says no calls match it")
        func noneMatch() throws {
            let sut = DiskIOPluginView(transport: DebugDrawerPluginTransport(
                initial: DiskIOSnapshot(
                    events: [IOEvent(timestamp: Date(), operation: .read, path: "/tmp/a", size: 1, duration: 0, isMainThread: false)],
                    operation: .write
                ),
                snapshots: AsyncStream { $0.finish() },
                send: { _ in }
            ))

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "No calls match the filter.") }
        }

        @Test("The view shows the snapshot's volume")
        func showsVolume() throws {
            let sut = DiskIOPluginView(transport: DebugDrawerPluginTransport(
                initial: DiskIOSnapshot(volume: DiskSpace(total: 1024 * 1024 * 1024, free: 512 * 1024 * 1024)),
                snapshots: AsyncStream { $0.finish() },
                send: { _ in }
            ))

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "50%") }
            #expect(throws: Never.self) { try view.find(text: "512.0 MB") }
        }
    }
#endif
