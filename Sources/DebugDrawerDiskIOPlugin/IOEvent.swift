import Foundation

/// One file call the Disk I/O plugin recorded: what it did, to which path, how many bytes, how
/// long it took, on which thread, and the error when it failed.
public struct IOEvent: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let operation: Operation
    /// The file or folder the call worked on; for a copy or a move, its source.
    public let path: String
    /// Where a copy or a move put the item; `nil` for every other operation.
    public let destination: String?
    /// The bytes read or written, the items listed, or the file's size for a stat; 0 when the
    /// call failed or has no size.
    public let size: Int64
    public let duration: TimeInterval
    public let isMainThread: Bool
    /// Why the call failed; `nil` when it succeeded.
    public let error: NSError?

    /// What a call did to the file system.
    public enum Operation: String, Sendable {
        case read = "R"
        case write = "W"
        case delete = "D"
        case create = "C"
        case list = "L"
        case stat = "S"
        case copy = "Cp"
        case move = "Mv"

        /// The operation in a word ("Read"), for the filter and VoiceOver.
        var name: String {
            switch self {
            case .read: "Read"
            case .write: "Write"
            case .delete: "Delete"
            case .create: "Create"
            case .list: "List"
            case .stat: "Stat"
            case .copy: "Copy"
            case .move: "Move"
            }
        }
    }

    init(
        timestamp: Date, operation: Operation, path: String, destination: String? = nil,
        size: Int64, duration: TimeInterval, isMainThread: Bool, error: NSError? = nil
    ) {
        self.timestamp = timestamp
        self.operation = operation
        self.path = path
        self.destination = destination
        self.size = size
        self.duration = duration
        self.isMainThread = isMainThread
        self.error = error
    }
}
