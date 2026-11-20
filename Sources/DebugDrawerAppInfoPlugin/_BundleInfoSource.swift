#if DEBUG
    import DebugDrawerAppInfo
    import Foundation

    /// A bundle's Info.plist: the main bundle's, unless told otherwise.
    struct _BundleInfoSource: BundleInfoSource {
        let bundle: Bundle

        /// - Parameter bundle: The bundle to read; the app's own by default.
        init(bundle: Bundle = .main) {
            self.bundle = bundle
        }

        func read() -> BundleInfo {
            let info = bundle.infoDictionary
            return BundleInfo(
                identifier: bundle.bundleIdentifier,
                version: info?["CFBundleShortVersionString"] as? String,
                build: info?["CFBundleVersion"] as? String,
                buildMetadata: AppInfoBuildMetadata().filled(from: info)
            )
        }
    }
#endif
