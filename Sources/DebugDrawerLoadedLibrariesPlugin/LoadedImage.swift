#if DEBUG
    import Foundation

    /// One entry in dyld's list of the images loaded into the process, as ``LoadedImageList``
    /// reads it.
    struct LoadedImage: Equatable, Sendable {
        /// The image's index in dyld's list.
        let index: UInt32
        /// The file the image was loaded from.
        let path: String
        /// The image's LC_UUID, or `nil` when its header has none.
        let uuid: UUID?
        /// Where the image's Mach-O header is mapped.
        let loadAddress: UInt
        /// CFBundleShortVersionString of the `.framework` that holds the image, if any.
        let frameworkVersion: String?
    }
#endif
