#if DEBUG
    import Foundation

    /// Where the recorder is: one case per thing that can be true, so the drawer, the HUD and the
    /// header read the same answer.
    enum RecordingState: Equatable, Sendable {
        /// Nothing recorded since the plugin was installed.
        case idle
        /// Recording since `started`.
        case recording(started: Date)
        /// Stopped; the movie is being written out.
        case finishing
        /// The last recording, saved at this URL.
        case finished(URL)
        /// The last recording couldn't be made or saved.
        case failed(RecordingFailure)

        /// Whether frames are being recorded.
        var isRecording: Bool {
            if case .recording = self { true } else { false }
        }

        /// Whether Record can start a new recording: not while one is recording or finishing.
        var canStart: Bool {
            switch self {
            case .idle, .finished, .failed: true
            case .recording, .finishing: false
            }
        }
    }

    /// Why a recording couldn't be made or saved.
    enum RecordingFailure: Error, Equatable, Sendable, CaseIterable {
        /// The app has no window on screen to record.
        case noWindow
        /// Stopped before a single frame was drawn.
        case noFrames
        /// The movie couldn't be written: the disk is full, say, or the encoder refused the size.
        case writeFailed

        /// What the drawer says.
        var message: String {
            switch self {
            case .noWindow: "There's no window on screen to record."
            case .noFrames: "Stopped before a frame was recorded, so nothing was saved."
            case .writeFailed: "The movie couldn't be written."
            }
        }
    }
#endif
