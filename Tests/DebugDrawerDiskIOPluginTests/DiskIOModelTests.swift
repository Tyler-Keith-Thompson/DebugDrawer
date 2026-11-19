#if DEBUG
    import Combine
    @testable import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import Foundation
    import Testing

    // The model is read and driven here as an out-of-process reader would: through its snapshot,
    // encoded and decoded, and commands, sent through a direct transport, with no view. The
    // recorded calls and the volume come from hand-written fakes; nothing is swizzled and no file
    // system is read. Every command but a volume read lands before `send(_:)` returns; a test
    // waits for a volume on the transport's stream of snapshots.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOModelTests {
        @Test("A snapshot of recorded calls, their totals, the filter, a pause and the volume encodes to JSON and decodes equal")
        func snapshotRoundTrips() async throws {
            let source = FakeDiskIOEventSource()
            let volume = DiskSpace(total: 500 * 1024 * 1024 * 1024, free: 120 * 1024 * 1024 * 1024)
            let sut = DebugDrawerPluginTransport.direct(to: DiskIOModel(source: source, volumes: FakeDiskSpaceReading([volume])))
            source.deliver([
                IOEvent(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_000), operation: .write, path: "/tmp/app/cache.json",
                    size: 2048, duration: 0.004, isMainThread: true
                ),
                IOEvent(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_001), operation: .copy, path: "/tmp/app/a.txt",
                    destination: "/tmp/app/b.txt", size: 12, duration: 0.0005, isMainThread: false
                ),
                IOEvent(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_002), operation: .read, path: "/tmp/app/missing",
                    size: 0, duration: 0.0001, isMainThread: false,
                    error: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
                )
            ])
            sut.send(DiskIOCommand(.setOperation(.read)))
            sut.send(DiskIOCommand(.setMainThreadOnly(true)))
            sut.send(DiskIOCommand(.setPaused(true)))
            sut.send(DiskIOCommand(.refreshVolume))
            for await snapshot in sut.snapshots() where snapshot.volume == volume {
                break
            }
            let expected = sut.snapshot

            let encoded = try JSONEncoder().encode(expected)
            let actual = try JSONDecoder().decode(DiskIOSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.events.map(\.path) == ["/tmp/app/missing", "/tmp/app/a.txt", "/tmp/app/cache.json"])
            #expect(actual.events[0].error?.domain == NSPOSIXErrorDomain)
            #expect(actual.events[0].error?.code == Int(ENOENT))
            #expect(actual.events[1].destination == "/tmp/app/b.txt")
            #expect(actual.totals.calls == 3)
            #expect(actual.totals.bytesWritten == 2048)
            #expect(actual.operation == .read)
            #expect(actual.mainThreadOnly)
            #expect(actual.isPaused)
            #expect(actual.volume == volume)
        }

        @Test("A snapshot before anything is recorded or read encodes to JSON and decodes equal, holding nothing")
        func emptySnapshotRoundTrips() throws {
            let volumes = FakeDiskSpaceReading([])
            let sut = DiskIOModel(source: FakeDiskIOEventSource(), volumes: volumes)
            let expected = DiskIOSnapshot()

            let encoded = try JSONEncoder().encode(sut.snapshot)
            let actual = try JSONDecoder().decode(DiskIOSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(volumes.reads == 0)
        }

        @Test("Each operation, encoded to JSON and decoded, is the same operation")
        func operationsRoundTrip() throws {
            let expected: [IOEvent.Operation] = [.read, .write, .delete, .create, .list, .stat, .copy, .move]

            let actual = try JSONDecoder().decode([IOEvent.Operation].self, from: JSONEncoder().encode(expected))

            #expect(actual == expected)
        }

        @Test("A call's error travels as its domain, code and description, and decodes to an NSError holding them")
        func errorRoundTrips() throws {
            let error = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue)
            let event = IOEvent(
                timestamp: Date(timeIntervalSince1970: 1_800_000_000), operation: .write, path: "/tmp/locked",
                size: 0, duration: 0.002, isMainThread: false, error: error
            )
            let expectedDescription = error.localizedDescription

            let actual = try JSONDecoder().decode(IOEvent.self, from: JSONEncoder().encode(event))

            #expect(actual == event)
            #expect(actual.error?.domain == NSCocoaErrorDomain)
            #expect(actual.error?.code == CocoaError.fileWriteNoPermission.rawValue)
            #expect(actual.error?.localizedDescription == expectedDescription)
        }

        @Test("Events that differ only in their error's code aren't equal")
        func errorsCompare() throws {
            func event(code: Int) -> String {
                """
                {"id": "6F1E2D3C-4B5A-4978-8695-A4B3C2D1E0F9", "timestamp": 0, "operation": "R", "path": "/tmp/x",
                 "size": 0, "duration": 0, "isMainThread": false,
                 "error": {"domain": "NSPOSIXErrorDomain", "code": \(code), "message": "Failed"}}
                """
            }
            let missing = try JSONDecoder().decode(IOEvent.self, from: Data(event(code: 2).utf8))
            let missingAgain = try JSONDecoder().decode(IOEvent.self, from: Data(event(code: 2).utf8))

            let actual = try JSONDecoder().decode(IOEvent.self, from: Data(event(code: 13).utf8))

            #expect(missing == missingAgain)
            #expect(actual != missing)
        }

        @Test("Every command, encoded to JSON and decoded, is the same command")
        func commandsRoundTrip() throws {
            let expected: [DiskIOCommand.Action] = [
                .setOperation(.write),
                .setOperation(nil),
                .setMainThreadOnly(true),
                .clear,
                .setPaused(true),
                .setPaused(false),
                .refreshVolume
            ]

            let encoded = try JSONEncoder().encode(expected.map(DiskIOCommand.init))
            let actual = try JSONDecoder().decode([DiskIOCommand].self, from: encoded).map(\.action)

            #expect(actual == expected)
        }

        @Test("Every command, encoded to JSON and decoded, drives the model through a direct transport")
        func decodedCommandsDriveTheModel() throws {
            let source = FakeDiskIOEventSource()
            let sut = DebugDrawerPluginTransport.direct(to: DiskIOModel(source: source, volumes: FakeDiskSpaceReading([])))
            let commands = [
                DiskIOCommand(.setOperation(.delete)),
                DiskIOCommand(.setMainThreadOnly(true)),
                DiskIOCommand(.setPaused(true)),
                DiskIOCommand(.clear)
            ]
            let expectedRequests: [FakeDiskIOEventSource.Request] = [.pause, .clear]

            for command in commands {
                try sut.send(JSONDecoder().decode(DiskIOCommand.self, from: JSONEncoder().encode(command)))
            }

            #expect(sut.snapshot.operation == .delete)
            #expect(sut.snapshot.mainThreadOnly)
            #expect(sut.snapshot.isPaused)
            #expect(source.requests == expectedRequests)
        }

        @Test("Calls the source delivers are announced and shown newest first, with their operation, path, size, duration, thread and time")
        func eventsArrive() {
            let source = FakeDiskIOEventSource()
            let model = DiskIOModel(source: source, volumes: FakeDiskSpaceReading([]))
            let sut = DebugDrawerPluginTransport.direct(to: model)
            var announcements = 0
            let watching = model.objectWillChange.sink { announcements += 1 }
            let first = IOEvent(
                timestamp: Date(timeIntervalSince1970: 1_800_000_000), operation: .create, path: "/tmp/app/new.db",
                size: 4096, duration: 0.02, isMainThread: true
            )
            let second = IOEvent(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), operation: .read, path: "/tmp/app/new.db",
                size: 100, duration: 0.0002, isMainThread: false
            )
            let expected = [second, first]

            source.deliver([first])
            source.deliver([second])
            let actual = sut.snapshot

            #expect(announcements > 0)
            #expect(actual.events == expected)
            #expect(actual.events[1].operation == .create)
            #expect(actual.events[1].size == 4096)
            #expect(actual.events[1].duration == 0.02)
            #expect(actual.events[1].isMainThread)
            #expect(actual.events[1].timestamp == Date(timeIntervalSince1970: 1_800_000_000))
            #expect(actual.totals.creates == 1)
            #expect(actual.totals.reads == 1)
            #expect(actual.totals.bytesRead == 100)
            #expect(actual.totals.bytesWritten == 4096)
            #expect(actual.totals.mainThreadCalls == 1)
            watching.cancel()
        }

        @Test("The operation filter and the main-thread switch narrow the calls shown, alone and together, and All shows every call again")
        func filters() {
            let source = FakeDiskIOEventSource()
            let sut = DebugDrawerPluginTransport.direct(to: DiskIOModel(source: source, volumes: FakeDiskSpaceReading([])))
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            source.deliver([
                IOEvent(timestamp: date, operation: .read, path: "/a", size: 1, duration: 0, isMainThread: true),
                IOEvent(timestamp: date, operation: .read, path: "/b", size: 1, duration: 0, isMainThread: false),
                IOEvent(timestamp: date, operation: .write, path: "/c", size: 1, duration: 0, isMainThread: true),
                IOEvent(timestamp: date, operation: .delete, path: "/d", size: 0, duration: 0, isMainThread: false)
            ])

            sut.send(DiskIOCommand(.setOperation(.read)))
            let reads = sut.snapshot.filteredEvents.map(\.path)
            sut.send(DiskIOCommand(.setMainThreadOnly(true)))
            let mainThreadReads = sut.snapshot.filteredEvents.map(\.path)
            sut.send(DiskIOCommand(.setOperation(nil)))
            let mainThread = sut.snapshot.filteredEvents.map(\.path)
            sut.send(DiskIOCommand(.setMainThreadOnly(false)))
            let all = sut.snapshot.filteredEvents.map(\.path)
            sut.send(DiskIOCommand(.setOperation(.move)))
            let none = sut.snapshot.filteredEvents

            #expect(reads == ["/b", "/a"])
            #expect(mainThreadReads == ["/a"])
            #expect(mainThread == ["/c", "/a"])
            #expect(all == ["/d", "/c", "/b", "/a"])
            #expect(none.isEmpty)
            #expect(sut.snapshot.events.count == 4)
        }

        @Test("The filter is the source's, so one set on the store is the one the view shows")
        func filterIsTheSources() {
            let source = FakeDiskIOEventSource()
            let sut = DebugDrawerPluginTransport.direct(to: DiskIOModel(source: source, volumes: FakeDiskSpaceReading([])))

            source.filterOp = .stat
            source.mainThreadOnly = true

            #expect(sut.snapshot.operation == .stat)
            #expect(sut.snapshot.mainThreadOnly)
        }

        @Test("Clear forgets the calls and starts the totals over; the filter stays")
        func clear() {
            let source = FakeDiskIOEventSource()
            let sut = DebugDrawerPluginTransport.direct(to: DiskIOModel(source: source, volumes: FakeDiskSpaceReading([])))
            source.deliver([
                IOEvent(timestamp: Date(), operation: .write, path: "/a", size: 10, duration: 0, isMainThread: false)
            ])
            sut.send(DiskIOCommand(.setOperation(.write)))

            sut.send(DiskIOCommand(.clear))

            #expect(sut.snapshot.events.isEmpty)
            #expect(sut.snapshot.totals == DiskIOTotals())
            #expect(sut.snapshot.operation == .write)
            #expect(source.requests == [.clear])
        }

        @Test("Pause and resume reach the source and read back in the snapshot; the calls already kept stay")
        func pauseAndResume() {
            let source = FakeDiskIOEventSource()
            let sut = DebugDrawerPluginTransport.direct(to: DiskIOModel(source: source, volumes: FakeDiskSpaceReading([])))
            source.deliver([
                IOEvent(timestamp: Date(), operation: .read, path: "/a", size: 10, duration: 0, isMainThread: false)
            ])

            sut.send(DiskIOCommand(.setPaused(true)))
            let paused = sut.snapshot
            sut.send(DiskIOCommand(.setPaused(false)))
            let resumed = sut.snapshot

            #expect(paused.isPaused)
            #expect(paused.events.count == 1)
            #expect(!resumed.isPaused)
            #expect(resumed.events.count == 1)
            #expect(source.requests == [.pause, .resume])
        }

        @Test("Refresh reads the volume's size and free space into the snapshot, and a later read replaces it, with nil when the system won't say")
        func volume() async {
            let full = DiskSpace(total: 1024 * 1024 * 1024, free: 1024 * 1024)
            let volumes = FakeDiskSpaceReading([full, nil])
            let sut = DebugDrawerPluginTransport.direct(to: DiskIOModel(source: FakeDiskIOEventSource(), volumes: volumes))
            let before = sut.snapshot.volume

            sut.send(DiskIOCommand(.refreshVolume))
            for await snapshot in sut.snapshots() where snapshot.volume == full {
                break
            }
            let read = sut.snapshot.volume
            sut.send(DiskIOCommand(.refreshVolume))
            for await snapshot in sut.snapshots() where snapshot.volume == nil {
                break
            }

            #expect(before == nil)
            #expect(read == full)
            #expect(sut.snapshot.volume == nil)
            #expect(volumes.reads == 2)
        }

        @Test("Commands run in the order sent: filters, pause and clear land behind a waiting volume read, and the last volume read stays")
        func commandOrder() async {
            let first = DiskSpace(total: 100, free: 90)
            let second = DiskSpace(total: 100, free: 10)
            let source = FakeDiskIOEventSource()
            let volumes = FakeDiskSpaceReading([first, second], holds: true)
            let sut = DebugDrawerPluginTransport.direct(to: DiskIOModel(source: source, volumes: volumes))
            let expectedRequests: [FakeDiskIOEventSource.Request] = [.pause, .clear, .resume]

            sut.send(DiskIOCommand(.refreshVolume))
            sut.send(DiskIOCommand(.setOperation(.write)))
            sut.send(DiskIOCommand(.setPaused(true)))
            sut.send(DiskIOCommand(.refreshVolume))
            sut.send(DiskIOCommand(.clear))
            sut.send(DiskIOCommand(.setMainThreadOnly(true)))
            sut.send(DiskIOCommand(.setPaused(false)))
            let whileWaiting = sut.snapshot
            volumes.release()
            for await snapshot in sut.snapshots() where snapshot.volume == second {
                break
            }

            #expect(whileWaiting.volume == nil)
            #expect(whileWaiting.operation == .write)
            #expect(whileWaiting.mainThreadOnly)
            #expect(!whileWaiting.isPaused)
            #expect(source.requests == expectedRequests)
            #expect(sut.snapshot.volume == second)
            #expect(volumes.reads == 2)
        }

        @Test("Recording starts with the first drawer, and stops, forgetting the calls, only when the last one counted removes the plugin")
        func installCounting() {
            let source = FakeDiskIOEventSource()
            let sut = DiskIOModel(source: source, volumes: FakeDiskSpaceReading([]))
            let first = DebugDrawer()
            let second = DebugDrawer()
            let stranger = DebugDrawer()
            source.deliver([IOEvent(timestamp: Date(), operation: .read, path: "/a", size: 1, duration: 0, isMainThread: false)])

            sut.install(in: ObjectIdentifier(first))
            sut.install(in: ObjectIdentifier(second))
            sut.uninstall(from: ObjectIdentifier(first))
            sut.uninstall(from: ObjectIdentifier(stranger))
            let afterFirstLeft = source.requests
            let keptWhileOneHolds = sut.snapshot.events.count
            sut.uninstall(from: ObjectIdentifier(second))
            sut.uninstall(from: ObjectIdentifier(second))

            #expect(afterFirstLeft == [.start, .start])
            #expect(keptWhileOneHolds == 1)
            #expect(source.requests == [.start, .start, .stop])
            #expect(sut.snapshot.events.isEmpty)
        }

        @Test("DiskIOPlugin(model:) counts the real drawers that register it, and stops recording as the last one unregisters it")
        func pluginInTwoDrawers() throws {
            let suite = "DiskIOModelTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let source = FakeDiskIOEventSource()
            let model = DiskIOModel(source: source, volumes: FakeDiskSpaceReading([]))
            let first = DebugDrawer(defaults: defaults)
            let second = DebugDrawer(defaults: defaults)

            first.registerGlobal(DiskIOPlugin(model: model))
            second.registerGlobal(DiskIOPlugin(model: model))
            first.unregisterGlobal(id: DiskIOPlugin().id)
            let afterFirst = source.requests
            second.unregisterGlobal(id: DiskIOPlugin().id)

            #expect(afterFirst == [.start, .start])
            #expect(source.requests == [.start, .start, .stop])
        }

        @Test("A model over a real store shows the calls its recorder delivers, and Clear forgets them")
        func overRealStore() async {
            let recorder = DiskIORecorder()
            let sut = DebugDrawerPluginTransport.direct(to: DiskIOModel(source: DiskIOStore(recorder: recorder), volumes: FakeDiskSpaceReading([])))
            let event = IOEvent(timestamp: Date(), operation: .write, path: "/tmp/real", size: 3, duration: 0, isMainThread: true)

            recorder.record(event)
            for await snapshot in sut.snapshots() where !snapshot.events.isEmpty {
                break
            }
            let recorded = sut.snapshot
            sut.send(DiskIOCommand(.clear))

            #expect(recorded.events == [event])
            #expect(recorded.totals.writes == 1)
            #expect(sut.snapshot.events.isEmpty)
            #expect(sut.snapshot.totals == DiskIOTotals())
        }
    }
#endif
