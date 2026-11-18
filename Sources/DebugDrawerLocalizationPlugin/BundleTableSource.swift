#if DEBUG
    import DebugDrawer
    import Foundation

    /// The app's localized bundles, read from their `.lproj` folders: the bundle at the root of
    /// ``AppBundles`` (the main bundle), the `.bundle`s in its resources and the `.framework`s in
    /// its Frameworks folder, and any other loaded bundle inside it.
    ///
    /// The folders are listed as well as the loaded bundles, since a SwiftPM resource bundle is
    /// loaded only once its module first reads `Bundle.module`, and the plugin should list its
    /// tables before that.
    struct BundleTableSource: LocalizationTableSource {
        let appBundles: AppBundles

        func bundles() -> [LocalizedBundle] {
            let root = URL(fileURLWithPath: appBundles.root, isDirectory: true)
            let rootBundle = Bundle(url: root)
            let contained = Self.children(of: rootBundle?.resourceURL ?? root, withExtension: "bundle")
                + Self.children(of: rootBundle?.privateFrameworksURL, withExtension: "framework")
            let loaded = (Bundle.allBundles + Bundle.allFrameworks).map(\.bundleURL)
            var seen: Set<String> = []
            return ([root] + contained + loaded).compactMap { url in
                let path = url.standardizedFileURL.path
                guard appBundles.contains(path), seen.insert(path).inserted, let bundle = Bundle(url: url) else { return nil }
                let localized = Self.read(bundle, isMain: path == appBundles.root)
                return localized.tables.isEmpty ? nil : localized
            }
        }

        /// The items in `folder` with the extension, sorted by name.
        private static func children(of folder: URL?, withExtension pathExtension: String) -> [URL] {
            guard let folder else { return [] }
            // The drawer's own work, which Disk I/O leaves out, as `read`'s listing is.
            let children = DebugDrawerActivity.$isDrawerWork.withValue(true) {
                (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            }
            return children
                .filter { $0.pathExtension == pathExtension }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        /// The bundle's tables, in every `.lproj` folder of its resources.
        static func read(_ bundle: Bundle, isMain: Bool) -> LocalizedBundle {
            let resources = bundle.resourceURL ?? bundle.bundleURL
            let folders = DebugDrawerActivity.$isDrawerWork.withValue(true) {
                (try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)) ?? []
            }
            var tables: [String: [LocalizationTable]] = [:]
            for folder in folders where folder.pathExtension == "lproj" {
                let localized = LocalizationTableFiles.tables(in: folder)
                if !localized.isEmpty {
                    tables[folder.deletingPathExtension().lastPathComponent] = localized
                }
            }
            return LocalizedBundle(
                name: bundle.bundleURL.lastPathComponent,
                path: bundle.bundleURL.standardizedFileURL.path,
                isMain: isMain,
                developmentLocalization: bundle.developmentLocalization ?? "en",
                preferredLocalization: bundle.preferredLocalizations.first,
                tables: tables
            )
        }
    }
#endif
