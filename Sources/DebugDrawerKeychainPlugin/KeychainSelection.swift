#if DEBUG
    import Foundation

    /// The item whose detail is open, with its password as read when it was opened.
    struct KeychainSelection: Hashable, Sendable {
        let item: KeychainItem
        /// The password; `nil` for an item that holds none, or a failure to read it.
        let value: Result<Data?, KeychainError>
    }

    // `Result` isn't `Codable`, so the selection writes the password under `value` or the refusal
    // under `failure`, never both.
    extension KeychainSelection: Codable {
        private enum CodingKeys: String, CodingKey {
            case item
            case value
            case failure
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let item = try container.decode(KeychainItem.self, forKey: .item)
            if let failure = try container.decodeIfPresent(KeychainError.self, forKey: .failure) {
                self.init(item: item, value: .failure(failure))
            } else {
                try self.init(item: item, value: .success(container.decodeIfPresent(Data.self, forKey: .value)))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(item, forKey: .item)
            switch value {
            case let .success(data):
                try container.encodeIfPresent(data, forKey: .value)
            case let .failure(error):
                try container.encode(error, forKey: .failure)
            }
        }
    }
#endif
