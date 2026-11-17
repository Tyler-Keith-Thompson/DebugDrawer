#if DEBUG
    import Foundation

    /// A value UserDefaults stores: a property list, as a value the editor can walk and rebuild.
    ///
    /// A number keeps the `NSNumber` UserDefaults returned, so an integer stays an integer and a
    /// real a real when it is written back.
    enum PropertyListValue: Equatable {
        case string(String)
        case number(NSNumber)
        case bool(Bool)
        case date(Date)
        case data(Data)
        case array([PropertyListValue])
        case dictionary([String: PropertyListValue])

        /// The value of a property-list object as UserDefaults returns it; `nil` for an object no
        /// property list can hold.
        init?(propertyList object: Any) {
            switch object {
            case let string as String: self = .string(string)
            case let number as NSNumber:
                self = number.isBoolean ? .bool(number.boolValue) : .number(number)
            case let date as Date: self = .date(date)
            case let data as Data: self = .data(data)
            case let array as [Any]:
                let elements = array.compactMap(PropertyListValue.init(propertyList:))
                guard elements.count == array.count else { return nil }
                self = .array(elements)
            case let dictionary as [String: Any]:
                let values = dictionary.compactMapValues(PropertyListValue.init(propertyList:))
                guard values.count == dictionary.count else { return nil }
                self = .dictionary(values)
            default: return nil
            }
        }

        /// The property-list object UserDefaults stores for the value.
        var propertyList: Any {
            switch self {
            case let .string(string): string
            case let .number(number): number
            case let .bool(bool): bool
            case let .date(date): date
            case let .data(data): data
            case let .array(elements): elements.map(\.propertyList)
            case let .dictionary(values): values.mapValues(\.propertyList)
            }
        }

        /// Which of the seven kinds the value is.
        var type: PropertyListType {
            switch self {
            case .string: .string
            case .number: .number
            case .bool: .boolean
            case .date: .date
            case .data: .data
            case .array: .array
            case .dictionary: .dictionary
            }
        }

        /// The value in one line: a string as itself, a number, `true` or `false`, a date in
        /// ISO 8601 (UTC), and the size of data, an array or a dictionary.
        var summary: String {
            switch self {
            case let .string(string): string
            case let .number(number): number.stringValue
            case let .bool(bool): bool ? "true" : "false"
            case let .date(date): date.formatted(.iso8601)
            case let .data(data): data.count == 1 ? "1 byte" : "\(data.count.formatted()) bytes"
            case let .array(elements): elements.count == 1 ? "1 item" : "\(elements.count.formatted()) items"
            case let .dictionary(values): values.count == 1 ? "1 key" : "\(values.count.formatted()) keys"
            }
        }

        /// An array's elements by index, or a dictionary's values by key, sorted; empty for any
        /// other value.
        var children: [PropertyListChild] {
            switch self {
            case let .array(elements):
                elements.enumerated().map { PropertyListChild(component: .index($0.offset), value: $0.element) }
            case let .dictionary(values):
                values.keys.sorted().map { PropertyListChild(component: .key($0), value: values[$0, default: .string("")]) }
            default: []
            }
        }

        /// The value `path` leads to, the value itself for an empty path; `nil` when the path
        /// leads nowhere, as one does after the app removed what it pointed at.
        func value(at path: [PropertyListPathComponent]) -> PropertyListValue? {
            guard let first = path.first else { return self }
            return child(first)?.value(at: Array(path.dropFirst()))
        }

        /// The value with what `path` leads to replaced by `newValue`, or removed when it is
        /// `nil`. Removing an array's element shifts the ones after it down.
        ///
        /// - Returns: The new value; the value unchanged when `path` leads nowhere, or is empty
        ///   and `newValue` is `nil`.
        func replacing(at path: [PropertyListPathComponent], with newValue: PropertyListValue?) -> PropertyListValue {
            guard let first = path.first else { return newValue ?? self }
            guard let child = child(first) else { return self }
            let rest = Array(path.dropFirst())
            let replaced = rest.isEmpty ? newValue : child.replacing(at: rest, with: newValue)
            switch (self, first) {
            case (var .array(elements), let .index(index)):
                if let replaced { elements[index] = replaced } else { elements.remove(at: index) }
                return .array(elements)
            case (var .dictionary(values), let .key(key)):
                values[key] = replaced
                return .dictionary(values)
            default:
                return self
            }
        }

        /// The array with `element` appended, or the dictionary with `element` set for `key`,
        /// replacing any value it had.
        ///
        /// - Returns: The new container and where `element` is in it; `nil` for a value that
        ///   holds no others.
        func adding(_ element: PropertyListValue, forKey key: String) -> PropertyListAddition? {
            switch self {
            case let .array(elements):
                return PropertyListAddition(container: .array(elements + [element]), component: .index(elements.count))
            case var .dictionary(values):
                values[key] = element
                return PropertyListAddition(container: .dictionary(values), component: .key(key))
            default:
                return nil
            }
        }

        /// The element at an index of an array, or the value for a key of a dictionary.
        private func child(_ component: PropertyListPathComponent) -> PropertyListValue? {
            switch (self, component) {
            case let (.array(elements), .index(index)): elements.indices.contains(index) ? elements[index] : nil
            case let (.dictionary(values), .key(key)): values[key]
            default: nil
            }
        }
    }

    /// One element of an array or value of a dictionary, and where it is.
    struct PropertyListChild: Identifiable, Equatable {
        /// Its index or key.
        let component: PropertyListPathComponent
        let value: PropertyListValue

        var id: PropertyListPathComponent {
            component
        }
    }

    /// An array or a dictionary with a value added, and where the value is.
    struct PropertyListAddition: Equatable {
        let container: PropertyListValue
        let component: PropertyListPathComponent
    }

    /// A step into an array, by index, or into a dictionary, by key.
    enum PropertyListPathComponent: Hashable {
        case index(Int)
        case key(String)

        /// The step as the editor shows it: an index in brackets, or the key.
        var title: String {
            switch self {
            case let .index(index): "[\(index)]"
            case let .key(key): key
            }
        }
    }

    extension NSNumber {
        /// Whether the number is a property list's Boolean, which bridges to `NSNumber` too.
        fileprivate var isBoolean: Bool {
            CFGetTypeID(self) == CFBooleanGetTypeID()
        }
    }
#endif
