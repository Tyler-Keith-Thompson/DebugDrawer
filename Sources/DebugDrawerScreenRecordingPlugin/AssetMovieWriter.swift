#if DEBUG
    import AVFoundation
    import CoreGraphics
    import CoreVideo
    import DebugDrawer

    /// Writes frames as H.264 in a QuickTime movie with AVAssetWriter.
    ///
    /// Main-actor isolated like the frames it is handed: each is drawn into a pixel buffer from the
    /// adaptor's pool and appended at once, lasting one frame, and the encoder works on its own
    /// queue. Rejected: ReplayKit's and ScreenCaptureKit's writers, which record the screen, drawer
    /// included.
    @MainActor
    final class AssetMovieWriter: MovieWriter {
        private let url: URL
        private let makeAssetWriter: (URL) throws -> AVAssetWriter
        private var session: Session?
        /// A frame couldn't be appended; finish throws.
        private var hasFailed = false

        /// The writer, its input and what has been written, from the first frame on.
        private struct Session {
            let writer: AVAssetWriter
            let input: AVAssetWriterInput
            let adaptor: AVAssetWriterInputPixelBufferAdaptor
            let width: Int
            let height: Int
            let firstTime: TimeInterval
            /// The last frame appended's time, `nil` until the first is.
            var lastTime: TimeInterval?
            /// The latest frame the encoder wasn't ready for, appended at finish if no later one is
            /// and the encoder is ready for it then, and left out of the movie if it isn't.
            var heldFrame: RecordedFrame?
        }

        /// A writer of a new movie at `url`, replacing any file there once the first frame arrives.
        ///
        /// - Parameters:
        ///   - url: Where the movie is written.
        ///   - makeAssetWriter: The asset writer of a QuickTime movie at a URL.
        init(
            url: URL,
            makeAssetWriter: @escaping (URL) throws -> AVAssetWriter = { try AVAssetWriter(outputURL: $0, fileType: .mov) }
        ) {
            self.url = url
            self.makeAssetWriter = makeAssetWriter
        }

        func append(_ frame: RecordedFrame) {
            guard !hasFailed else { return }
            if session == nil {
                session = startSession(with: frame)
                guard session != nil else {
                    hasFailed = true
                    return
                }
            }
            guard let session, frame.time > (session.lastTime ?? -.infinity), frame.time > (session.heldFrame?.time ?? -.infinity),
                  frame.time >= session.firstTime
            else { return }
            guard session.input.isReadyForMoreMediaData else {
                // Dropped while the encoder catches up, but kept as the latest, so the movie still
                // ends on the last frame drawn before Stop.
                self.session?.heldFrame = frame
                return
            }
            self.session?.heldFrame = nil
            write(frame)
        }

        /// Finishes without waiting for the encoder: a held frame it isn't ready for is not written,
        /// and the movie ends one frame after the frame before it instead. Rejected:
        /// waiting for `requestMediaDataWhenReady`, which a writer that fails or is cancelled
        /// meanwhile, or a real-time input on a healthy one, may never call, so finish never
        /// returned.
        func finish() async throws(RecordingFailure) -> Duration {
            if let held = session?.heldFrame, session?.input.isReadyForMoreMediaData == true {
                write(held)
            }
            return try await close()
        }

        /// Ends the movie one frame after its last frame written, and closes the file.
        private func close() async throws(RecordingFailure) -> Duration {
            guard let session else { throw hasFailed ? .writeFailed : .noFrames }
            self.session = nil
            // A writer that failed or was cancelled has no movie to close, and a cancelled one
            // raises an Objective-C exception as it is finished.
            let isWriting = session.writer.status == .writing
            guard isWriting, let lastTime = session.lastTime else {
                if session.writer.status != .cancelled { session.writer.cancelWriting() }
                // The drawer's own work, which Disk I/O leaves out, as below.
                DebugDrawerActivity.$isDrawerWork.withValue(true) { try? FileManager.default.removeItem(at: url) }
                throw hasFailed || !isWriting ? .writeFailed : .noFrames
            }
            // Each frame lasts until the next, and the last one for its own sample buffer's
            // duration, one frame, as finishWriting ends a session no endSession ended at its last
            // sample's end. So the movie runs from the first frame to one frame after the last.
            //
            // No endSession(atSourceTime:): a writer that fails on the encoder's queue after the
            // status check above, as one can on its own (disk full, media services reset), makes
            // endSession crash inside AVFoundation, which a host app can't catch. SIGSEGV, "Bad
            // pointer dereference at 0x10":
            //     0 <unknown> + 280 in MediaToolbox
            //     1 -[AVAssetWriterWritingHelper endSessionAtSourceTime:] + 328 in AVFCore
            //     2 -[AVAssetWriter endSessionAtSourceTime:] + 72 in AVFCore
            //     3 AssetMovieWriter.close()
            // The writer posts no KVO change of status as it fails this way, so there is no event
            // to wait for. markAsFinished and finishWriting don't crash there: a failure lands as
            // a failed status, which throws below. Rejected: a final duplicate frame one frame
            // after the last (the movie ends a frame late, the encoder giving the duplicate a
            // length of its own), and the adaptor's appends without endSession (the encoder then
            // guesses the last frame's length, from a frame's to half a second's).
            let length = lastTime - session.firstTime + Self.frameLength
            session.input.markAsFinished()
            let writer = UncheckedWriter(writer: session.writer)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writer.writer.finishWriting { continuation.resume() }
            }
            guard !hasFailed, session.writer.status == .completed else {
                DebugDrawerActivity.$isDrawerWork.withValue(true) { try? FileManager.default.removeItem(at: url) }
                throw .writeFailed
            }
            return .seconds(length)
        }

        /// Draws `frame` into a pixel buffer and appends it at its time from the first frame,
        /// lasting one frame.
        ///
        /// The buffer goes to the input in a sample buffer of its own rather than through the
        /// adaptor, whose append takes no duration; the adaptor still provides the pool, whose
        /// buffers suit the encoder.
        private func write(_ frame: RecordedFrame) {
            guard var session, let pool = session.adaptor.pixelBufferPool else { return }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return }
            Self.draw(frame.image, into: buffer, width: session.width, height: session.height)
            var format: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format) == noErr,
                  let format
            else { return }
            var timing = CMSampleTimingInfo(
                duration: Self.frameDuration,
                presentationTimeStamp: CMTime(seconds: frame.time - session.firstTime, preferredTimescale: Self.timescale),
                decodeTimeStamp: .invalid
            )
            var sample: CMSampleBuffer?
            guard CMSampleBufferCreateReadyWithImageBuffer(
                allocator: nil, imageBuffer: buffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample
            ) == noErr, let sample else { return }
            guard session.input.append(sample) else {
                hasFailed = true
                return
            }
            session.lastTime = frame.time
            session.heldFrame = nil
            self.session = session
        }

        /// The size movies are written at for `image`: its own, each side rounded down to an even
        /// number of pixels, as H.264 needs.
        static func movieSize(of image: CGImage) -> (width: Int, height: Int) {
            (image.width & ~1, image.height & ~1)
        }

        /// How long a frame shows at the recorder's 30 frames a second.
        static let frameLength: TimeInterval = frameDuration.seconds

        /// ``frameLength`` exactly, as each sample buffer's duration.
        private static let frameDuration = CMTime(value: 1, timescale: 30)

        private static let timescale: CMTimeScale = 600

        private func startSession(with frame: RecordedFrame) -> Session? {
            let (width, height) = Self.movieSize(of: frame.image)
            guard width >= 2, height >= 2 else { return nil }
            DebugDrawerActivity.$isDrawerWork.withValue(true) { try? FileManager.default.removeItem(at: url) }
            guard let writer = try? makeAssetWriter(url) else { return nil }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                // About two bits a pixel at 30 frames a second: text stays sharp, and a minute of
                // an iPad's screen is around 50 MB.
                // Frame reordering off: with B-frames the encoder ignores the sample buffers'
                // durations and guesses the last frame's length, so the movie's length would
                // change from one recording to the next.
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: width * height * 2,
                    AVVideoAllowFrameReorderingKey: false
                ]
            ])
            input.expectsMediaDataInRealTime = true
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ])
            guard writer.canAdd(input) else { return nil }
            writer.add(input)
            guard writer.startWriting() else { return nil }
            writer.startSession(atSourceTime: .zero)
            return Session(writer: writer, input: input, adaptor: adaptor, width: width, height: height, firstTime: frame.time, lastTime: nil)
        }

        /// Draws `image` into `buffer`, scaled to fit and centred on black.
        private static func draw(_ image: CGImage, into buffer: CVPixelBuffer, width: Int, height: Int) {
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return }
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(bounds)
            context.interpolationQuality = .high
            context.draw(image, in: bounds.fitting(width: CGFloat(image.width), height: CGFloat(image.height)))
        }
    }

    /// The asset writer, handed to its own completion handler. AVAssetWriter isn't Sendable; the
    /// writer is finished once, and touched again only after the handler resumes.
    private struct UncheckedWriter: @unchecked Sendable {
        let writer: AVAssetWriter
    }

    extension CGRect {
        /// The largest rectangle of the given proportions that fits inside this one, centred.
        fileprivate func fitting(width: CGFloat, height: CGFloat) -> CGRect {
            guard width > 0, height > 0 else { return self }
            let scale = min(self.width / width, self.height / height)
            let size = CGSize(width: width * scale, height: height * scale)
            return CGRect(x: midX - size.width / 2, y: midY - size.height / 2, width: size.width, height: size.height)
        }
    }
#endif
