#if DEBUG
    import Foundation

    /// Which of the app's folders a store was found in.
    enum StoreLocation: Hashable, Sendable {
        case applicationSupport
        case documents
        /// The shared container of the app group with this identifier.
        case appGroup(String)
        /// A folder the app passed to `DatabaseBrowser.install(additionalDirectories:)`.
        case additional

        /// The folder's name, as the store list shows it.
        var title: String {
            switch self {
            case .applicationSupport: "Application Support"
            case .documents: "Documents"
            case let .appGroup(identifier): "App group \(identifier)"
            case .additional: "Added folder"
            }
        }
    }
#endif
