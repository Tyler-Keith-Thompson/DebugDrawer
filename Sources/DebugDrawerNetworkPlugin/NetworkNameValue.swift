#if DEBUG
    import Foundation

    /// A header or query item as an editor holds it while it is changed: a name and a value, with
    /// an id that stays put while either is typed in. The mock and resend editors list them with
    /// `NetworkNameValueList`.
    struct NetworkNameValue: Identifiable, Equatable {
        let id: UUID
        var name: String
        var value: String

        init(id: UUID = UUID(), name: String = "", value: String = "") {
            self.id = id
            self.name = name
            self.value = value
        }
    }

    extension [NetworkNameValue] {
        /// The pairs of `dictionary`, sorted by name.
        init(sortedByName dictionary: [String: String]) {
            self = dictionary.sorted { $0.key < $1.key }.map { NetworkNameValue(name: $0.key, value: $0.value) }
        }

        /// The pairs with a name, by name; of two with one name, the later wins.
        var dictionary: [String: String] {
            reduce(into: [:]) { result, field in
                let name = field.name.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { result[name] = field.value }
            }
        }
    }
#endif
