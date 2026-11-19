#if DEBUG
    import Combine
    @testable import DebugDrawerDiskIOPlugin
    import Foundation
    import Testing

    // Each test records on the main actor, so the main queue can't deliver until the test awaits:
    // whatever was recorded before then is one batch.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOBatchingTests {
        @Test("Calls recorded before the main queue turns arrive in one batch, oldest first, after the recording returns")
        func oneBatch() async {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let sut = DiskIORecorder()
            var subscription: AnyCancellable?
            var deliveredCount = 0
            var deliveredWhileRecording = -1
            let paths = ["/a", "/b", "/c"]

            let first = await withCheckedContinuation { continuation in
                subscription = sut.batches.sink { batch in
                    deliveredCount += 1
                    if deliveredCount == 1 { continuation.resume(returning: batch) }
                }
                for path in paths {
                    sut.record(IOEvent(timestamp: start, operation: .read, path: path, size: 1, duration: 0, isMainThread: true))
                }
                deliveredWhileRecording = deliveredCount
            }
            subscription?.cancel()

            #expect(deliveredWhileRecording == 0)
            #expect(first.events.elements.map(\.path) == paths)
            #expect(first.totals.reads == 3)
        }

        @Test("Calls recorded on other threads while a delivery is pending reach the main actor in one batch")
        func pendingDeliveryIsOneBatch() async {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let sut = DiskIORecorder()
            var subscription: AnyCancellable?
            var batches: [DiskIOBatch] = []
            let expectedPaths: Set<String> = ["/0", "/1", "/2", "/3", "/4", "/5", "/6", "/7"]
            let expectedCalls = 8

            await withCheckedContinuation { continuation in
                subscription = sut.batches.sink { batch in
                    batches.append(batch)
                    if batches.count == 1 {
                        sut.record(IOEvent(timestamp: start, operation: .read, path: "/after", size: 0, duration: 0, isMainThread: true))
                    } else {
                        continuation.resume()
                    }
                }
                // The test holds the main actor until every record below has returned, so the
                // delivery the first record schedules is pending while the others record.
                DispatchQueue.concurrentPerform(iterations: expectedCalls) { index in
                    sut.record(IOEvent(timestamp: start, operation: .write, path: "/\(index)", size: 1, duration: 0, isMainThread: false))
                }
            }
            subscription?.cancel()

            let actual = batches.map { $0.events.elements.map(\.path) }
            #expect(actual.count == 2)
            #expect(Set(actual.first ?? []) == expectedPaths)
            #expect(batches.first?.totals.calls == expectedCalls)
            #expect(actual.last == ["/after"])
        }

        @Test("A burst past the limit keeps its newest calls, and its totals count every call")
        func burstPastLimit() async {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let sut = DiskIORecorder(limit: 2)
            var subscription: AnyCancellable?
            let paths = ["/a", "/b", "/c", "/d", "/e"]

            let batch = await withCheckedContinuation { continuation in
                subscription = sut.batches.first().sink { continuation.resume(returning: $0) }
                for path in paths {
                    sut.record(IOEvent(timestamp: start, operation: .write, path: path, size: 10, duration: 0, isMainThread: false))
                }
            }
            subscription?.cancel()

            #expect(batch.events.elements.map(\.path) == ["/d", "/e"])
            #expect(batch.events.evictedCount == 3)
            #expect(batch.totals.writes == 5)
            let expectedBytes: Int64 = 50
            #expect(batch.totals.bytesWritten == expectedBytes)
        }

        @Test("Calls recorded after a delivery arrive in the next batch")
        func nextBatch() async {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let sut = DiskIORecorder()
            var subscription: AnyCancellable?
            var batches: [[String]] = []

            await withCheckedContinuation { continuation in
                subscription = sut.batches.sink { batch in
                    batches.append(batch.events.elements.map(\.path))
                    if batches.count == 1 {
                        sut.record(IOEvent(timestamp: start, operation: .read, path: "/second", size: 0, duration: 0, isMainThread: true))
                    } else {
                        continuation.resume()
                    }
                }
                sut.record(IOEvent(timestamp: start, operation: .read, path: "/first", size: 0, duration: 0, isMainThread: true))
            }
            subscription?.cancel()

            #expect(batches == [["/first"], ["/second"]])
        }

        @Test("The store lists the newest calls first, keeps at most its capacity, and totals every call it received")
        func storeKeepsCapacity() async {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let recorder = DiskIORecorder()
            let sut = DiskIOStore(recorder: recorder)
            sut.capacity = 2
            var subscription: AnyCancellable?

            for path in ["/a", "/b", "/c", "/d", "/e"] {
                recorder.record(IOEvent(timestamp: start, operation: .read, path: path, size: 2, duration: 0, isMainThread: false))
            }
            let events = await withCheckedContinuation { continuation in
                subscription = sut.$events.first { !$0.isEmpty }.sink { continuation.resume(returning: $0) }
            }
            subscription?.cancel()

            #expect(events.map(\.path) == ["/e", "/d"])
            #expect(sut.totalReads == 5)
            let expectedBytes: Int64 = 10
            #expect(sut.totalBytesRead == expectedBytes)
        }

        @Test("Past byteCapacity the store drops the oldest calls until their paths fit, and its totals still count every call")
        func storeKeepsByteCapacity() async {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let recorder = DiskIORecorder()
            let sut = DiskIOStore(recorder: recorder)
            sut.byteCapacity = 10
            var subscription: AnyCancellable?

            for path in ["/aaaa", "/bbbb", "/cccc"] {
                recorder.record(IOEvent(timestamp: start, operation: .write, path: path, size: 1, duration: 0, isMainThread: false))
            }
            let events = await withCheckedContinuation { continuation in
                subscription = sut.$events.first { !$0.isEmpty }.sink { continuation.resume(returning: $0) }
            }
            subscription?.cancel()

            #expect(events.map(\.path) == ["/cccc", "/bbbb"])
            #expect(sut.totalWrites == 3)
        }

        @Test("The store announces a delivery, and a capacity that drops calls, through objectWillChange before its list changes")
        func storeAnnouncesChanges() async {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let recorder = DiskIORecorder()
            let sut = DiskIOStore(recorder: recorder)
            var listsWhenAnnounced: [[String]] = []
            let announcements = sut.objectWillChange.sink { listsWhenAnnounced.append(sut.events.map(\.path)) }
            var subscription: AnyCancellable?
            for path in ["/a", "/b"] {
                recorder.record(IOEvent(timestamp: start, operation: .read, path: path, size: 1, duration: 0, isMainThread: true))
            }
            _ = await withCheckedContinuation { continuation in
                subscription = sut.$events.first { !$0.isEmpty }.sink { continuation.resume(returning: $0) }
            }
            subscription?.cancel()

            sut.capacity = 1

            #expect(listsWhenAnnounced == [[], ["/b", "/a"]])
            #expect(sut.events.map(\.path) == ["/b"])
            announcements.cancel()
        }

        @Test("Clearing the store empties the list and the totals")
        func clear() async {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let recorder = DiskIORecorder()
            let sut = DiskIOStore(recorder: recorder)
            var subscription: AnyCancellable?
            recorder.record(IOEvent(timestamp: start, operation: .write, path: "/a", size: 8, duration: 0, isMainThread: true))
            _ = await withCheckedContinuation { continuation in
                subscription = sut.$events.first { !$0.isEmpty }.sink { continuation.resume(returning: $0) }
            }
            subscription?.cancel()

            sut.clear()

            #expect(sut.events.isEmpty)
            #expect(sut.totals == DiskIOTotals())
        }
    }
#endif
