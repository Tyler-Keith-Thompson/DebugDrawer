#if DEBUG
    import Foundation

    /// Reads the file from disk, inside its security scope.
    struct _GPXFileReading: GPXFileReading {
        func track(at url: URL) throws(GPXError) -> GPXTrack {
            try GPXTrack(contentsOf: url)
        }
    }
#endif
