#if DEBUG
    import Foundation

    /// Which bundles are the app's own: the main bundle and every bundle inside it (its
    /// frameworks, plug-ins and SwiftPM resource bundles), but none of the drawer's.
    ///
    /// The modes rewrite only these bundles' strings. A bundle outside the app is the system's
    /// (UIKit's "Cancel", the share sheet), which the app doesn't translate and a tester can't
    /// fix; and the drawer's own bundles stay readable, so the drawer can turn a mode off.
    /// Chosen by path rather than by a list of bundle identifiers, which an app would have to keep
    /// up to date as it adds frameworks, or the main bundle alone, which would miss the strings of
    /// the app's own frameworks and packages.
    struct AppBundles: Sendable {
        /// The folder the app's bundles are in: the main bundle's.
        let root: String

        /// The bundles inside `root`, with its symbolic links resolved, as a bundle reports its
        /// path.
        init(root: String) {
            self.root = URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL.path
        }

        /// The running app's: the main bundle and the bundles inside it.
        static var main: AppBundles {
            AppBundles(root: Bundle.main.bundleURL.path)
        }

        /// The prefix of the drawer's own bundles' names: its SwiftPM resource bundles
        /// (`DebugDrawer_DebugDrawerConsolePlugin.bundle`) and frameworks.
        static let drawerPrefix = "DebugDrawer"

        /// Whether the bundle at `path`, standardized, is the app's.
        func contains(_ path: String) -> Bool {
            guard path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/") else { return false }
            return path == root || !(path as NSString).lastPathComponent.hasPrefix(Self.drawerPrefix)
        }
    }
#endif
