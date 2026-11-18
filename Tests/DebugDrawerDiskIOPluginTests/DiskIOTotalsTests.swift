@testable import DebugDrawerDiskIOPlugin
import Foundation
import Testing

@Suite
struct DiskIOTotalsTests {
    @Test("Totals count each operation, the bytes reads returned and writes and creates wrote, failures and main-thread calls")
    func counts() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let failure = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileNoSuchFile.rawValue)
        let events = [
            IOEvent(timestamp: start, operation: .read, path: "/a", size: 100, duration: 0, isMainThread: true),
            IOEvent(timestamp: start, operation: .read, path: "/b", size: 50, duration: 0, isMainThread: false),
            IOEvent(timestamp: start, operation: .write, path: "/c", size: 30, duration: 0, isMainThread: false),
            IOEvent(timestamp: start, operation: .create, path: "/d", size: 7, duration: 0, isMainThread: true),
            IOEvent(timestamp: start, operation: .delete, path: "/e", size: 0, duration: 0, isMainThread: false, error: failure),
            IOEvent(timestamp: start, operation: .list, path: "/f", size: 12, duration: 0, isMainThread: false),
            IOEvent(timestamp: start, operation: .stat, path: "/g", size: 4096, duration: 0, isMainThread: false),
            IOEvent(timestamp: start, operation: .copy, path: "/h", destination: "/i", size: 0, duration: 0, isMainThread: false),
            IOEvent(timestamp: start, operation: .move, path: "/j", destination: "/k", size: 0, duration: 0, isMainThread: false)
        ]
        var sut = DiskIOTotals()

        for event in events {
            sut.add(event)
        }

        #expect(sut.calls == 9)
        #expect(sut.reads == 2)
        #expect(sut.writes == 1)
        #expect(sut.creates == 1)
        #expect(sut.deletes == 1)
        #expect(sut.failures == 1)
        #expect(sut.mainThreadCalls == 2)
        let expectedBytesRead: Int64 = 150
        let expectedBytesWritten: Int64 = 37
        #expect(sut.bytesRead == expectedBytesRead)
        #expect(sut.bytesWritten == expectedBytesWritten)
    }

    @Test("Adding one totals to another adds every count")
    func sum() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var actual = DiskIOTotals()
        actual.add(IOEvent(timestamp: start, operation: .read, path: "/a", size: 10, duration: 0, isMainThread: true))
        var rhs = DiskIOTotals()
        rhs.add(IOEvent(timestamp: start, operation: .write, path: "/b", size: 20, duration: 0, isMainThread: false))
        rhs.add(IOEvent(timestamp: start, operation: .read, path: "/c", size: 5, duration: 0, isMainThread: false))
        var expected = DiskIOTotals()
        expected.add(IOEvent(timestamp: start, operation: .read, path: "/a", size: 10, duration: 0, isMainThread: true))
        expected.add(IOEvent(timestamp: start, operation: .write, path: "/b", size: 20, duration: 0, isMainThread: false))
        expected.add(IOEvent(timestamp: start, operation: .read, path: "/c", size: 5, duration: 0, isMainThread: false))

        actual += rhs

        #expect(actual == expected)
    }

    @Test("Nothing added counts nothing")
    func empty() {
        let sut = DiskIOTotals()

        let actual = [sut.calls, sut.reads, sut.writes, sut.creates, sut.deletes, sut.failures, sut.mainThreadCalls]

        #expect(actual == [0, 0, 0, 0, 0, 0, 0])
        #expect(sut.bytesRead == 0)
        #expect(sut.bytesWritten == 0)
    }
}
