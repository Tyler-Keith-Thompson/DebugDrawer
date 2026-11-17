#if DEBUG
    /// Why a mockup couldn't be shown or kept.
    enum MockupFailure: Error, Equatable, Sendable {
        /// The file, photo or pasteboard held no image Image I/O reads.
        case notAnImage
        /// The picked file couldn't be read.
        case unreadable
        /// The pasteboard held no image.
        case nothingToPaste
        /// The mockup couldn't be saved to Caches; it shows until the app quits.
        case notSaved

        /// What the plugin says about it.
        var message: String {
            switch self {
            case .notAnImage: "That isn't an image this device can read."
            case .unreadable: "The file couldn't be read."
            case .nothingToPaste: "The pasteboard holds no image."
            case .notSaved: "The mockup couldn't be saved to Caches, so it shows until the app quits."
            }
        }
    }
#endif
