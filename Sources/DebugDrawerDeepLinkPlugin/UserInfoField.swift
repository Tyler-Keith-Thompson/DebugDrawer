#if DEBUG
    import Foundation

    /// One userInfo row as the form edits it: its key, its type, and the value typed for it.
    struct UserInfoField: Identifiable, Hashable {
        /// The types a row can hold, as Xcode's property list editor names them.
        enum Kind: String, CaseIterable, Hashable {
            case string = "String"
            case number = "Number"
            case boolean = "Boolean"
        }

        let id: UUID
        var key: String
        var kind: Kind
        /// The value typed for a string or a number.
        var text: String
        /// The value of a Boolean row.
        var isOn: Bool

        init(key: String = "", kind: Kind = .string, text: String = "", isOn: Bool = false, id: UUID = UUID()) {
            self.id = id
            self.key = key
            self.kind = kind
            self.text = text
            self.isOn = isOn
        }

        /// The row that edits `entry`.
        init(_ entry: UserInfoEntry) {
            switch entry.value {
            case let .string(value): self.init(key: entry.key, kind: .string, text: value)
            case let .integer(value): self.init(key: entry.key, kind: .number, text: String(value))
            case let .double(value): self.init(key: entry.key, kind: .number, text: String(value))
            case let .bool(value): self.init(key: entry.key, kind: .boolean, isOn: value)
            }
        }

        /// The value the row holds, or `nil` for a number row whose text isn't a number. A whole
        /// number is an integer, so the app reads it back with `as? Int`.
        var value: UserInfoValue? {
            switch kind {
            case .string:
                return .string(text)
            case .boolean:
                return .bool(isOn)
            case .number:
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if let integer = Int(trimmed) {
                    return .integer(integer)
                }
                guard let double = Double(trimmed), double.isFinite else { return nil }
                return .double(double)
            }
        }
    }
#endif
