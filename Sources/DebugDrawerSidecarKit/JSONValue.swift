// What the device-lab relay carries without knowing a plugin's types: a snapshot or a command as the
// JSON value it is, decoded from one side's payload and encoded again for the other, so the relay
// forwards every plugin ID alike, the receiver's capabilities and any model of the host's own. The
// transports hand out typed plugin transports only (`connect(toPlugin:snapshot:command:)`), so
// this is the type the relay asks for. Numbers are kept as integers where the JSON holds one, so a
// 64-bit count or an ID survives exactly; anything else is a Double, which JSONEncoder writes back
// as the shortest text that reads as the same Double. The one value that comes back different is
// -0, which reads as the integer 0. Rejected: a raw-bytes path through the transports (a second,
// untyped connect on every transport in core, for one caller), and decoding into each capability's
// own types in the relay (it would relay only the plugins the kit knows, not a host's own models).

#if DEBUG && canImport(DebugDrawerRemote)
    import Foundation

    /// A JSON value: what the relay reads from one side and writes to the other.
    enum JSONValue: Codable, Equatable, Sendable {
        case null
        case bool(Bool)
        case integer(Int64)
        case unsignedInteger(UInt64)
        case number(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            // JSONDecoder reads a Boolean only from true or false and an integer only from a number
            // that is one, so the first type that decodes is the value's own.
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int64.self) {
                self = .integer(value)
            } else if let value = try? container.decode(UInt64.self) {
                self = .unsignedInteger(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else {
                self = try .object(container.decode([String: JSONValue].self))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .null: try container.encodeNil()
            case let .bool(value): try container.encode(value)
            case let .integer(value): try container.encode(value)
            case let .unsignedInteger(value): try container.encode(value)
            case let .number(value): try container.encode(value)
            case let .string(value): try container.encode(value)
            case let .array(value): try container.encode(value)
            case let .object(value): try container.encode(value)
            }
        }
    }
#endif
