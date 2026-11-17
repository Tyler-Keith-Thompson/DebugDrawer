#if DEBUG
    /// Which requests the Network log shows: the ones the app made, or the ones in an imported
    /// HAR file.
    enum NetworkLogSource: Hashable, CaseIterable, Sendable {
        case captured
        case imported

        /// The segment's title.
        var title: String {
            switch self {
            case .captured: "Captured"
            case .imported: "Imported"
            }
        }
    }
#endif
