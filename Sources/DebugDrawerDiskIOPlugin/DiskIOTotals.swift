/// Counts of every call the Disk I/O plugin recorded since the last clear, including the calls
/// the list no longer keeps.
public struct DiskIOTotals: Equatable, Sendable {
    /// Every recorded call.
    public private(set) var calls = 0
    /// Reads: `.read` calls.
    public private(set) var reads = 0
    /// Writes: `.write` calls.
    public private(set) var writes = 0
    /// Files and folders created: `.create` calls.
    public private(set) var creates = 0
    /// Items deleted: `.delete` calls.
    public private(set) var deletes = 0
    /// Calls that failed, of any operation.
    public private(set) var failures = 0
    /// Calls made on the main thread, of any operation.
    public private(set) var mainThreadCalls = 0
    /// The bytes the reads returned.
    public private(set) var bytesRead: Int64 = 0
    /// The bytes the writes and creates wrote.
    public private(set) var bytesWritten: Int64 = 0

    /// No calls.
    public init() {}

    /// Counts `event` in.
    ///
    /// - Parameter event: A recorded call.
    /// - Complexity: O(1).
    public mutating func add(_ event: IOEvent) {
        calls += 1
        switch event.operation {
        case .read:
            reads += 1
            bytesRead += event.size
        case .write:
            writes += 1
            bytesWritten += event.size
        case .create:
            creates += 1
            bytesWritten += event.size
        case .delete:
            deletes += 1
        case .list, .stat, .copy, .move:
            break
        }
        if event.error != nil { failures += 1 }
        if event.isMainThread { mainThreadCalls += 1 }
    }

    /// Counts every call of `rhs` into `lhs`.
    ///
    /// - Complexity: O(1).
    public static func += (lhs: inout Self, rhs: Self) {
        lhs.calls += rhs.calls
        lhs.reads += rhs.reads
        lhs.writes += rhs.writes
        lhs.creates += rhs.creates
        lhs.deletes += rhs.deletes
        lhs.failures += rhs.failures
        lhs.mainThreadCalls += rhs.mainThreadCalls
        lhs.bytesRead += rhs.bytesRead
        lhs.bytesWritten += rhs.bytesWritten
    }
}
