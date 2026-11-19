#if DEBUG
    import Foundation

    /// Where App Info reads the build: the app's bundle and its Info.plist.
    ///
    /// The App Info model takes it at init; `_BundleInfoSource` reads the main bundle, and a test
    /// passes one that returns what it chooses.
    protocol BundleInfoSource {
        /// The bundle's identifier, version, build number and build metadata now.
        func read() -> BundleInfo
    }
#endif
