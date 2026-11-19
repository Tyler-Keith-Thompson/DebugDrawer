#if DEBUG
    /// A UserDefaults suite the plugin shows: the app's standard defaults, or a suite by name, such
    /// as an app group's.
    enum UserDefaultsSuite: Codable, Hashable, Identifiable, Sendable {
        case standard
        case named(String)

        var id: Self {
            self
        }

        /// The suite as the picker lists it: "Standard", or its name.
        var title: String {
            switch self {
            case .standard: "Standard"
            case let .named(name): name
            }
        }
    }
#endif
