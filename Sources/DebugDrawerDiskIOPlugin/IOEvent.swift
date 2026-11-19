import Foundation

/// One file call the Disk I/O plugin recorded: what it did, to which path, how many bytes, how
/// long it took, on which thread, and the error when it failed.
///
/// It is `Codable`, so a transport can carry it: the error travels as its domain, code and
/// description, and decodes to an `NSError` holding them. Two events are equal when every field
/// is, their errors compared by domain, code and description.
public struct IOEvent: Identifiable, Sendable {
    public let id: UUID
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
    public enum Operation: String, Codable, Sendable {
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
        id = UUID()
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

extension IOEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, timestamp, operation, path, destination, size, duration, isMainThread, error
    }

    /// An error as it travels: what an `NSError` says without its user info's objects, which
    /// needn't be encodable.
    private struct Failure: Codable {
        var domain: String
        var code: Int
        var message: String

        init(_ error: NSError) {
            domain = error.domain
            code = error.code
            message = error.localizedDescription
        }

        var error: NSError {
            NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        operation = try container.decode(Operation.self, forKey: .operation)
        path = try container.decode(String.self, forKey: .path)
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
        size = try container.decode(Int64.self, forKey: .size)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        isMainThread = try container.decode(Bool.self, forKey: .isMainThread)
        error = try container.decodeIfPresent(Failure.self, forKey: .error)?.error
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(operation, forKey: .operation)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(destination, forKey: .destination)
        try container.encode(size, forKey: .size)
        try container.encode(duration, forKey: .duration)
        try container.encode(isMainThread, forKey: .isMainThread)
        try container.encodeIfPresent(error.map(Failure.init), forKey: .error)
    }
}

extension IOEvent: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.timestamp == rhs.timestamp
            && lhs.operation == rhs.operation
            && lhs.path == rhs.path
            && lhs.destination == rhs.destination
            && lhs.size == rhs.size
            && lhs.duration == rhs.duration
            && lhs.isMainThread == rhs.isMainThread
            && lhs.error?.domain == rhs.error?.domain
            && lhs.error?.code == rhs.error?.code
            && lhs.error?.localizedDescription == rhs.error?.localizedDescription
    }
}
