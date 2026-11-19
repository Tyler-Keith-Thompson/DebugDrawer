#if DEBUG
    import Foundation

    /// Reads the GPX file the user picked for Import GPX…. `_GPXFileReading` in production; tests
    /// pass a fake that hands back a track or an error without touching the disk.
    @MainActor
    protocol GPXFileReading {
        /// The file's points.
        ///
        /// - Parameter url: The file, which may sit outside the app's sandbox.
        /// - Throws: ``GPXError`` when the file can't be read or isn't a GPX track.
        func track(at url: URL) throws(GPXError) -> GPXTrack
    }
#endif
