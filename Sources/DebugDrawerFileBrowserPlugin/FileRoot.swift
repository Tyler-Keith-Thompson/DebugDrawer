#if DEBUG
    import Foundation

    /// A folder the browser starts from: one of the app's own, its bundle or an app group's
    /// container.
    struct FileRoot: Identifiable, Hashable, Codable, Sendable {
        /// Which folder it is.
        enum Kind: Hashable, Codable, Sendable {
            case documents
            case library
            /// The app's own folder of Application Support, on a Mac app outside the sandbox.
            case applicationSupport
            /// The app's own folder of Caches, on a Mac app outside the sandbox.
            case caches
            case temporary
            case bundle
            /// The container of the app group with this identifier.
            case appGroup(String)
        }

        let kind: Kind
        let url: URL

        var id: Kind {
            kind
        }

        /// The folder's name in the list: "Documents", "tmp", "App bundle", or the group's
        /// identifier.
        var title: String {
            switch kind {
            case .documents: "Documents"
            case .library: "Library"
            case .applicationSupport: "Application Support"
            case .caches: "Caches"
            case .temporary: "tmp"
            case .bundle: "App bundle"
            case let .appGroup(identifier): identifier
            }
        }

        /// The symbol beside it.
        var systemImage: String {
            switch kind {
            case .bundle: "shippingbox"
            case .appGroup: "folder.badge.person.crop"
            default: "folder"
            }
        }

        /// Whether nothing in it may be imported, renamed or deleted: the bundle, which is signed.
        var isReadOnly: Bool {
            kind == .bundle
        }
    }

    /// The folders the browser starts from, and the app groups it was given that have no
    /// container.
    struct FileRoots: Hashable, Codable, Sendable {
        let available: [FileRoot]
        /// App groups the system gives the app no container for, as when its entitlements don't
        /// name them.
        let missingAppGroups: [String]

        /// The app's own folders, then its bundle, then the container of each of `appGroups`, in
        /// the order given, once each.
        init(locations: some FileLocations, appGroups: [String]) {
            var seen = Set<String>()
            let groups = appGroups.filter { seen.insert($0).inserted }
            let containers = groups.map { ($0, locations.containerURL(forAppGroup: $0)) }
            available = locations.appFolders + [FileRoot(kind: .bundle, url: locations.bundle)]
                + containers.compactMap { identifier, url in url.map { FileRoot(kind: .appGroup(identifier), url: $0) } }
            missingAppGroups = containers.filter { $0.1 == nil }.map(\.0)
        }

        init(available: [FileRoot], missingAppGroups: [String] = []) {
            self.available = available
            self.missingAppGroups = missingAppGroups
        }
    }
#endif
