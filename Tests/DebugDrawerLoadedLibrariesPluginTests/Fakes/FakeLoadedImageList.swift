#if DEBUG
    @testable import DebugDrawerLoadedLibrariesPlugin
    import Foundation

    /// dyld's list in memory: the images loaded, in load order, each at the next index, as dyld
    /// numbers them. It counts each read.
    final class FakeLoadedImageList: LoadedImageList {
        private(set) var loaded: [LoadedImage] = []
        /// How many times the list was read.
        private(set) var reads = 0

        /// A list holding the files at `paths`, loaded in that order.
        init(_ paths: [String] = []) {
            for path in paths {
                load(path)
            }
        }

        /// Loads the file at `path`, as `dlopen` would, after every image already loaded.
        func load(_ path: String, uuid: UUID? = nil, frameworkVersion: String? = nil) {
            let index = UInt32(loaded.count)
            loaded.append(LoadedImage(
                index: index, path: path, uuid: uuid, loadAddress: 0x1_0000_0000 + UInt(index) * 0x8000,
                frameworkVersion: frameworkVersion
            ))
        }

        func images() -> [LoadedImage] {
            reads += 1
            return loaded
        }
    }
#endif
