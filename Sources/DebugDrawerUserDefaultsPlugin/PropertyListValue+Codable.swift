#if DEBUG
    import Foundation

    // Written by hand rather than synthesized: a number is an `NSNumber`, which isn't `Codable`,
    // and keeping it (rather than a Swift number per kind) keeps the exact type UserDefaults
    // returned for a value written back in the process. Each value is an object of one key naming
    // its kind; a number's key says which kind of number it is, so an integer decodes as an
    // integer and a real as a real. A real that isn't finite, which JSON can't hold, is its
    // description ("nan", "inf", "-inf").

    extension PropertyListValue: Codable {
        private enum CodingKeys: String, CodingKey {
            case string, integer, unsigned, real, bool, date, data, array, dictionary
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let key = container.allKeys.first, container.allKeys.count == 1 else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: container.codingPath, debugDescription: "A property-list value is an object of exactly one kind."
                ))
            }
            switch key {
            case .string: self = try .string(container.decode(String.self, forKey: key))
            case .integer: self = try .number(NSNumber(value: container.decode(Int64.self, forKey: key)))
            case .unsigned: self = try .number(NSNumber(value: container.decode(UInt64.self, forKey: key)))
            case .real: self = try .number(NSNumber(value: Self.decodeReal(from: container)))
            case .bool: self = try .bool(container.decode(Bool.self, forKey: key))
            case .date: self = try .date(container.decode(Date.self, forKey: key))
            case .data: self = try .data(container.decode(Data.self, forKey: key))
            case .array: self = try .array(container.decode([PropertyListValue].self, forKey: key))
            case .dictionary: self = try .dictionary(container.decode([String: PropertyListValue].self, forKey: key))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .string(string): try container.encode(string, forKey: .string)
            case let .number(number): try Self.encode(number, in: &container)
            case let .bool(bool): try container.encode(bool, forKey: .bool)
            case let .date(date): try container.encode(date, forKey: .date)
            case let .data(data): try container.encode(data, forKey: .data)
            case let .array(elements): try container.encode(elements, forKey: .array)
            case let .dictionary(values): try container.encode(values, forKey: .dictionary)
            }
        }

        private static func encode(_ number: NSNumber, in container: inout KeyedEncodingContainer<CodingKeys>) throws {
            if CFNumberIsFloatType(number as CFNumber) {
                let real = number.doubleValue
                if real.isFinite {
                    try container.encode(real, forKey: .real)
                } else {
                    try container.encode(real.description, forKey: .real)
                }
            } else if number.compare(NSNumber(value: Int64.max)) == .orderedDescending {
                try container.encode(number.uint64Value, forKey: .unsigned)
            } else {
                try container.encode(number.int64Value, forKey: .integer)
            }
        }

        private static func decodeReal(from container: KeyedDecodingContainer<CodingKeys>) throws -> Double {
            if let real = try? container.decode(Double.self, forKey: .real) { return real }
            let text = try container.decode(String.self, forKey: .real)
            guard let real = Double(text) else {
                throw DecodingError.dataCorruptedError(forKey: .real, in: container, debugDescription: "\(text) isn't a number.")
            }
            return real
        }
    }
#endif
