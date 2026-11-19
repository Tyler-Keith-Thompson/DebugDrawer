#if DEBUG
    /// The images loaded into the process.
    ///
    /// The Loaded Libraries model reads it on each refresh; `_LoadedImageList` asks dyld, and a
    /// test passes a list of its own.
    protocol LoadedImageList {
        /// Every image loaded now, in dyld's order.
        func images() -> [LoadedImage]
    }
#endif
