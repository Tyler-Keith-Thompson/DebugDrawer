#if DEBUG
    import Foundation

    /// An image loaded into the process, as the plugin lists it: its name, path and category,
    /// with what dyld says of it.
    struct LoadedLibrary: Identifiable, Equatable, Codable, Sendable {
        /// The image's index in dyld's list.
        let id: UInt32
        let name: String
        let path: String
        let category: LibraryCategory
        /// The image's LC_UUID, which matches its dSYM.
        let uuid: UUID?
        /// Where the image's Mach-O header is mapped.
        let loadAddress: UInt
        /// CFBundleShortVersionString of the framework the image belongs to, if any.
        let version: String?

        /// The library `image` is, categorized against the app's bundle at `bundlePath`.
        init(image: LoadedImage, bundlePath: String) {
            self.init(
                id: image.index,
                name: (image.path as NSString).lastPathComponent,
                path: image.path,
                category: Self.categorize(path: image.path, bundlePath: bundlePath),
                uuid: image.uuid,
                loadAddress: image.loadAddress,
                version: image.frameworkVersion
            )
        }

        init(id: UInt32, name: String, path: String, category: LibraryCategory, uuid: UUID?, loadAddress: UInt, version: String?) {
            self.id = id
            self.name = name
            self.path = path
            self.category = category
            self.uuid = uuid
            self.loadAddress = loadAddress
            self.version = version
        }

        /// Whose image the file at `path` is, for an app whose bundle is at `bundlePath`.
        static func categorize(path: String, bundlePath: String) -> LibraryCategory {
            let systemPrefixes = [
                "/System/Library/",
                "/usr/lib/",
                "/Library/Developer/",
                "/Applications/Xcode"
            ]
            // The app's own bundle first: it decides, wherever the bundle lives.
            let bundle = bundlePath.hasSuffix("/") ? bundlePath : bundlePath + "/"
            if path.hasPrefix(bundle) {
                // Embedded frameworks (<bundle>/Frameworks/, <bundle>/Contents/Frameworks/)
                // are third-party; the executable and everything else in the bundle is the app's.
                let inBundle = path.dropFirst(bundle.count)
                return inBundle.hasPrefix("Frameworks/") || inBundle.hasPrefix("Contents/Frameworks/")
                    ? .thirdParty : .app
            }
            if systemPrefixes.contains(where: path.hasPrefix) {
                return .system
            }
            return .thirdParty
        }
    }
#endif
