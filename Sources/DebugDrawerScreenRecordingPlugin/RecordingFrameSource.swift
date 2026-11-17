#if DEBUG
    import CoreGraphics
    import Foundation

    /// One frame of a recording: the app's windows as drawn, and when.
    struct RecordedFrame: @unchecked Sendable {
        // CGImage is immutable; the compiler can't see that it is safe to share.

        /// The frame, in pixels.
        let image: CGImage
        /// When it was drawn, in seconds on the display's clock (`CACurrentMediaTime`).
        let time: TimeInterval
    }

    /// What hands the recorder its frames: the app's windows drawn on every display frame in
    /// production (`DisplayLinkFrameSource`), frames the test sends in tests.
    @MainActor
    protocol RecordingFrameSource: AnyObject {
        /// Starts handing `frame` a frame on every display frame until ``stop()``.
        ///
        /// - Parameters:
        ///   - showsTouches: Whether to draw a circle where each finger touches, in the frames only.
        ///   - frame: Called on the main actor with each frame.
        /// - Throws: `RecordingFailure.noWindow` when there is no window to record.
        func start(showsTouches: Bool, frame: @escaping @MainActor (RecordedFrame) -> Void) throws(RecordingFailure)

        /// Stops handing out frames; none arrives after it returns.
        func stop()
    }
#endif
