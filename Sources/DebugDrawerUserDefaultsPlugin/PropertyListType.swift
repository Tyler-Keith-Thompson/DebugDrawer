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

    }

    /// Why a field's text isn't a value of its type.
    enum PropertyListTextError: Error, Equatable {
        /// Text that isn't a whole number, for an integer.
        case notInteger
        /// Text that isn't a finite number, for a real.
        case notNumber
        /// Text that isn't bytes in the chosen encoding.
        case data(DataTextError)
        /// A type the editor doesn't take as text.
        case notText

        /// The problem as the editor shows it under the field.
        var message: String {
            switch self {
            case .notInteger: "That isn't a whole number: the value is an integer, so use digits and a sign."
            case .notNumber: "That isn't a number: use digits, a sign and a decimal point."
            case let .data(error): error.message
            case .notText: "This type isn't edited as text."
            }
        }
    }
#endif
