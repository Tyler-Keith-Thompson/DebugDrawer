#if DEBUG
    import Foundation

    /// What turns frames into a movie file: H.264 in a QuickTime movie through AVAssetWriter in
    /// production (`AssetMovieWriter`), a fake that records what it was handed in tests.
    @MainActor
    protocol MovieWriter: AnyObject {
        /// Adds `frame` to the movie. The first frame sets the movie's size and start; a later frame
        /// of another size is scaled to fit. A frame no later than the last one, or one the encoder
        /// isn't ready for, is dropped.
        func append(_ frame: RecordedFrame)

        /// Finishes the movie and closes its file.
        ///
        /// - Returns: How long the movie runs.
        /// - Throws: `RecordingFailure.noFrames` when no frame was appended, and
        ///   `RecordingFailure.writeFailed` when the file couldn't be written.
        func finish() async throws(RecordingFailure) -> Duration
    }
#endif
