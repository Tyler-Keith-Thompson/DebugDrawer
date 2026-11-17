#if DEBUG
    import Foundation

    /// The seven kinds of value a property list holds, named as Xcode's property list editor names
    /// them.
    enum PropertyListType: String, CaseIterable, Identifiable {
        case string = "String"
        case number = "Number"
        case boolean = "Boolean"
        case date = "Date"
        case data = "Data"
        case array = "Array"
        case dictionary = "Dictionary"

        var id: Self {
            self
        }

        /// The type's name.
        var title: String {
            rawValue
        }

        /// What a key added with the type starts as: an empty string, zero, false, `now`, no
        /// bytes, an empty array or an empty dictionary.
        func initialValue(now: Date) -> PropertyListValue {
            switch self {
            case .string: .string("")
            case .number: .number(0)
            case .boolean: .bool(false)
            case .date: .date(now)
            case .data: .data(Data())
            case .array: .array([])
            case .dictionary: .dictionary([:])
            }
        }

        /// The value a field's `text` holds: a string as typed; a number as an integer when it is
        /// one and a real otherwise, ignoring surrounding whitespace; data in `encoding`.
        ///
        /// - Throws: ``PropertyListTextError`` saying why the text isn't a value of the type, or
        ///   that the type isn't edited as text (Boolean, Date, Array and Dictionary).
        func value(parsing text: String, encoding: DataTextEncoding) throws(PropertyListTextError) -> PropertyListValue {
            switch self {
            case .string:
                return .string(text)
            case .number:
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if let integer = Int(trimmed) { return .number(NSNumber(value: integer)) }
                guard let real = Double(trimmed), real.isFinite else { throw .notNumber }
                return .number(NSNumber(value: real))
            case .data:
                do {
                    return try .data(encoding.data(from: text))
                } catch {
                    throw .data(error)
                }
            case .boolean, .date, .array, .dictionary:
                throw .notText
            }
        }
    }

    /// Why a field's text isn't a value of its type.
    enum PropertyListTextError: Error, Equatable {
        /// Text that isn't an integer or a finite real.
        case notNumber
        /// Text that isn't bytes in the chosen encoding.
        case data(DataTextError)
        /// A type the editor doesn't take as text.
        case notText

        /// The problem as the editor shows it under the field.
        var message: String {
            switch self {
            case .notNumber: "That isn't a number: use digits, a sign and a decimal point."
            case let .data(error): error.message
            case .notText: "This type isn't edited as text."
            }
        }
    }
#endif
