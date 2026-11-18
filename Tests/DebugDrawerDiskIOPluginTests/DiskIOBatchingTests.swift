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
            #expect(first.events.map(\.path) == paths)
            #expect(first.totals.reads == 3)
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

            #expect(batch.events.map(\.path) == ["/d", "/e"])
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
                    batches.append(batch.events.map(\.path))
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
