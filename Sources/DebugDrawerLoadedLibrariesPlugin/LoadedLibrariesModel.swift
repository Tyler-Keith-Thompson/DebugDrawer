import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // dyld's list is read through `LoadedImageList`; the model holds values only. Reading the list
    // is quick and synchronous, so every command lands before `perform(_:)` returns, in the order
    // sent, and a text field bound through a direct transport reads back what was typed.

    /// The Loaded Libraries plugin's state and behavior, without its views: the images loaded into
    /// the process, the filter and the category picked, read as a ``LoadedLibrariesSnapshot`` and
    /// changed with a ``LoadedLibrariesCommand``.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: LoadedLibrariesModel.shared)
    /// ```
    ///
    /// Release builds get a stand-in whose snapshot holds nothing and which ignores every command.
    @MainActor
    public final class LoadedLibrariesModel: DebugDrawerPluginModel {
        /// The model over this process's own images, which the plugin shows.
        public static let shared = LoadedLibrariesModel()

        @Published private var libraries: [LoadedLibrary] = []
        @Published private var filter = ""
        @Published private var category: LibraryCategory?

        private let images: any LoadedImageList
        /// The app's bundle, which decides which images are the app's own.
        private let bundlePath: String
        /// The drawers the plugin is installed in; the last to remove it drops the images read.
        private var installations: Set<ObjectIdentifier> = []

        /// - Parameters:
        ///   - images: The images loaded into the process.
        ///   - bundlePath: The app's bundle; its executable and the images in it are the app's,
        ///     the frameworks embedded in it third-party.
        init(images: any LoadedImageList = _LoadedImageList(), bundlePath: String = Bundle.main.bundlePath) {
            self.images = images
            self.bundlePath = bundlePath
        }

        public var snapshot: LoadedLibrariesSnapshot {
            LoadedLibrariesSnapshot(libraries: libraries, filter: filter, category: category)
        }

        public func perform(_ command: LoadedLibrariesCommand) {
            switch command.action {
            case .refresh:
                libraries = images.images()
                    .map { LoadedLibrary(image: $0, bundlePath: bundlePath) }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case let .setFilter(filter):
                self.filter = filter
            case let .setCategory(category):
                self.category = category
            }
        }

        /// Counts `drawer` as one the plugin is installed in; nothing is read until it is shown.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, drops the images read, so the next
        /// show reads them again. The filter and the category stay.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            libraries = []
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds read no images: this stand-in's snapshot holds nothing, and it ignores every
    /// command.
    @MainActor
    public final class LoadedLibrariesModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = LoadedLibrariesModel()

        private init() {}

        /// Always empty.
        public var snapshot: LoadedLibrariesSnapshot {
            LoadedLibrariesSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: LoadedLibrariesCommand) {}
    }
#endif
