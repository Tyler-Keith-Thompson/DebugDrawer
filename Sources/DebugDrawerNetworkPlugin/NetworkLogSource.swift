#if DEBUG
    /// Which requests the Network log shows: the ones the app made since it launched, the ones an
    /// earlier launch kept on disk, or the ones in an imported HAR file.
    enum NetworkLogSource: Hashable, CaseIterable, Codable, Sendable {
        case captured
        case previous
        case imported

        /// The segment's title.
        var title: String {
            switch self {
            case .captured: "Captured"
            case .previous: "Previous"
            case .imported: "Imported"
            }
        }

        /// Whether its requests are read-only: they can be copied and mocked, but not resent.
        var isReadOnly: Bool {
            self != .captured
        }
    }
#endif
