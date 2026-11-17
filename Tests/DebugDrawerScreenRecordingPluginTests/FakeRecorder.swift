#if DEBUG
    import CoreGraphics
    @testable import DebugDrawerScreenRecordingPlugin
    import Foundation

    /// A frame source the test drives: it records how it was started and stopped, and hands the
    /// recorder the frames the test sends.
    @MainActor
    final class FakeFrameSource: RecordingFrameSource {
        /// What `start` throws, or `nil` to start.
        var failure: RecordingFailure?
        private(set) var startedShowingTouches: [Bool] = []
        private(set) var stopCount = 0
        private var handler: (@MainActor (RecordedFrame) -> Void)?

        func start(showsTouches: Bool, frame: @escaping @MainActor (RecordedFrame) -> Void) throws(RecordingFailure) {
            if let failure { throw failure }
            startedShowingTouches.append(showsTouches)
            handler = frame
        }

        func stop() {
            stopCount += 1
            handler = nil
        }

        /// Hands the recorder a frame, as a display frame would, if it is started.
        func send(at time: TimeInterval) {
            let context = CGContext(
                data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            guard let image = context?.makeImage() else { return }
            handler?(RecordedFrame(image: image, time: time))
        }
    }

    /// A movie writer that keeps the times it was handed and, on finish, writes placeholder bytes
    /// to its URL or throws what the test set; it can hold finish until the test opens a gate.
    @MainActor
    final class FakeMovieWriter: MovieWriter {
        let url: URL
        var failure: RecordingFailure?
        /// Set to hold `finish` until `openGate()`.
        var holdsFinish = false
        private(set) var appendedTimes: [TimeInterval] = []
        private var gate: CheckedContinuation<Void, Never>?
        private var isGateOpen = false

        init(url: URL) {
            self.url = url
        }

        func append(_ frame: RecordedFrame) {
            appendedTimes.append(frame.time)
        }

        func finish() async throws(RecordingFailure) -> Duration {
            if holdsFinish, !isGateOpen {
                await withCheckedContinuation { gate = $0 }
            }
            if let failure { throw failure }
            try? Data("movie".utf8).write(to: url)
            return .seconds((appendedTimes.last ?? 0) - (appendedTimes.first ?? 0))
        }

        /// Lets a held `finish` go on.
        func openGate() {
            isGateOpen = true
            gate?.resume()
            gate = nil
        }
    }
#endif
