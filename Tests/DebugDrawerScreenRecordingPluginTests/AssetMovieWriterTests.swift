#if DEBUG
    import AVFoundation
    import Combine
    import CoreGraphics
    @testable import DebugDrawerScreenRecordingPlugin
    import Foundation
    import Testing

    // Sociable: the real AVAssetWriter writes a real H.264 movie to a temporary file, which
    // AVFoundation then reads back. A few frames of a small size take milliseconds.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AssetMovieWriterTests {
        @Test("Frames over a second make a movie that long plus one frame, at the first frame's size rounded down to even pixels")
        func movie() async throws {
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: url) }
            let context = try #require(CGContext(
                data: nil, width: 101, height: 61, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 101, height: 61))
            let image = try #require(context.makeImage())
            var assetWriter: AVAssetWriter?
            let sut = AssetMovieWriter(url: url) { url in
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                assetWriter = writer
                return writer
            }
            let expectedLength = 1.0 + 1.0 / 30

            sut.append(RecordedFrame(image: image, time: 100))
            let input = try #require(assetWriter?.inputs.first)
            // The encoder takes about eight frames handed over at once; each waits until it is
            // ready, as frames 1/30 s apart find it in a recording. Sendable: KVO tells on the
            // encoder's queue.
            var ready: AnyCancellable?
            for frame in 1 ... 30 {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    ready = input.publisher(for: \.isReadyForMoreMediaData, options: [.initial, .new])
                        .first { @Sendable isReady in isReady }
                        .sink { @Sendable _ in continuation.resume() }
                }
                sut.append(RecordedFrame(image: image, time: 100 + Double(frame) / 30))
            }
            ready?.cancel()
            let actual = try await sut.finish()

            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
            let size = try await track.load(.naturalSize)
            #expect(abs(actual / .seconds(1) - expectedLength) < 0.001)
            #expect(abs(duration.seconds - expectedLength) < 0.01)
            #expect(size == CGSize(width: 100, height: 60))
        }

        @Test("The movie shows the frames' pixels: a red frame reads back red")
        func pixels() async throws {
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: url) }
            let context = try #require(CGContext(
                data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            let image = try #require(context.makeImage())
            let sut = AssetMovieWriter(url: url)
            sut.append(RecordedFrame(image: image, time: 0))
            sut.append(RecordedFrame(image: image, time: 0.1))
            _ = try await sut.finish()

            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            let frame = try await generator.image(at: .zero).image
            let pixel = try #require(CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            pixel.draw(frame, in: CGRect(x: -32, y: -32, width: 64, height: 64))
            let bytes = try #require(pixel.data).assumingMemoryBound(to: UInt8.self)

            #expect(bytes[0] > 200)
            #expect(bytes[1] < 60)
            #expect(bytes[2] < 60)
        }

        @Test("A frame no later than the last one is dropped, so frames out of order don't end the movie early")
        func outOfOrder() async throws {
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: url) }
            let context = try #require(CGContext(
                data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let image = try #require(context.makeImage())
            let sut = AssetMovieWriter(url: url)
            let expectedLength = 1.0 + 1.0 / 30

            for time in [10, 10.5, 10.5, 10.25, 11, 9] {
                sut.append(RecordedFrame(image: image, time: time))
            }
            let actual = try await sut.finish()

            #expect(abs(actual / .seconds(1) - expectedLength) < 0.001)
        }

        @Test("Finishing with no frame throws noFrames and leaves no file")
        func noFrames() async {
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
            let sut = AssetMovieWriter(url: url)

            await #expect(throws: RecordingFailure.noFrames) {
                try await sut.finish()
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }

        @Test("A frame too small to encode (under 2 pixels a side) fails the movie with writeFailed")
        func tooSmall() async throws {
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: url) }
            let context = try #require(CGContext(
                data: nil, width: 1, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let sut = AssetMovieWriter(url: url)

            sut.append(RecordedFrame(image: try #require(context.makeImage()), time: 0))

            await #expect(throws: RecordingFailure.writeFailed) {
                try await sut.finish()
            }
        }

        @Test("Finishing after the asset writer was cancelled throws writeFailed and leaves no file")
        func cancelled() async throws {
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: url) }
            let context = try #require(CGContext(
                data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let image = try #require(context.makeImage())
            var assetWriter: AVAssetWriter?
            let sut = AssetMovieWriter(url: url) { url in
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                assetWriter = writer
                return writer
            }
            sut.append(RecordedFrame(image: image, time: 0))
            sut.append(RecordedFrame(image: image, time: 0.1))
            try #require(assetWriter).cancelWriting()

            await #expect(throws: RecordingFailure.writeFailed) {
                try await sut.finish()
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }

        @Test("A writer that failed (its folder doesn't exist) makes finish throw writeFailed rather than wait")
        func failed() async throws {
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/movie.mov")
            let context = try #require(CGContext(
                data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let image = try #require(context.makeImage())
            var assetWriter: AVAssetWriter?
            let sut = AssetMovieWriter(url: url) { url in
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                assetWriter = writer
                return writer
            }
            let expectedStatus = AVAssetWriter.Status.failed

            sut.append(RecordedFrame(image: image, time: 0))
            sut.append(RecordedFrame(image: image, time: 0.1))
            // Failed before finish, synchronously; failedOnTheEncodersQueue fails one as it finishes.
            let actual = try #require(assetWriter).status

            #expect(actual == expectedStatus)
            await #expect(throws: RecordingFailure.writeFailed) {
                try await sut.finish()
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }

        @Test("A writer that fails on the encoder's queue as the movie is finished makes finish throw writeFailed, and nothing crashes")
        func failedOnTheEncodersQueue() async throws {
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: url) }
            let context = try #require(CGContext(
                data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let image = try #require(context.makeImage())
            var assetWriter: AVAssetWriter?
            let sut = AssetMovieWriter(url: url) { url in
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                assetWriter = writer
                return writer
            }
            sut.append(RecordedFrame(image: image, time: 0))
            sut.append(RecordedFrame(image: image, time: 0.1))
            let input = try #require(assetWriter?.inputs.first)
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 32, 32, kCVPixelFormatType_32BGRA, nil, &buffer)
            var format: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: try #require(buffer), formatDescriptionOut: &format)
            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: -1, timescale: 1), decodeTimeStamp: .invalid
            )
            var sample: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: nil, imageBuffer: try #require(buffer), formatDescription: try #require(format), sampleTiming: &timing,
                sampleBufferOut: &sample
            )
            // A sample before the session's start, which the encoder fails the writer for on its
            // own queue, with no change of status a test could wait for: the failure lands
            // before, during or after finish's check of the status, as a disk filling up during
            // Stop would.
            try #require(input.isReadyForMoreMediaData)
            input.append(try #require(sample))

            await #expect(throws: RecordingFailure.writeFailed) {
                try await sut.finish()
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }

        @Test("Frames keep arriving while the writer fails on the encoder's queue: each is taken without a crash, and finish throws writeFailed")
        func framesWhileFailing() async throws {
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: url) }
            let context = try #require(CGContext(
                data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let image = try #require(context.makeImage())
            var assetWriter: AVAssetWriter?
            let sut = AssetMovieWriter(url: url) { url in
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                assetWriter = writer
                return writer
            }
            // Past the eighth frame, where a pixel buffer adaptor would replace its pool.
            for frame in 0 ..< 12 {
                sut.append(RecordedFrame(image: image, time: Double(frame) / 30))
            }
            let input = try #require(assetWriter?.inputs.first)
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
            var format: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: try #require(buffer), formatDescriptionOut: &format)
            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(value: -1, timescale: 1), decodeTimeStamp: .invalid
            )
            var sample: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: nil, imageBuffer: try #require(buffer), formatDescription: try #require(format), sampleTiming: &timing,
                sampleBufferOut: &sample
            )
            // Once the encoder is ready (Sendable: KVO tells on the encoder's queue), a sample
            // before the session's start fails the writer on that queue, as a disk filling up
            // mid-recording would; the frames after it land before, during and after the failure.
            var ready: AnyCancellable?
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                ready = input.publisher(for: \.isReadyForMoreMediaData, options: [.initial, .new])
                    .first { @Sendable isReady in isReady }
                    .sink { @Sendable _ in continuation.resume() }
            }
            ready?.cancel()
            input.append(try #require(sample))
            for frame in 12 ..< 200 {
                sut.append(RecordedFrame(image: image, time: Double(frame) / 30))
            }

            await #expect(throws: RecordingFailure.writeFailed) {
                try await sut.finish()
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }

        @Test("Frames at uneven times make a movie from the first to one frame after the last, each shown until the next")
        func unevenFrames() async throws {
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: url) }
            let context = try #require(CGContext(
                data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let image = try #require(context.makeImage())
            let sut = AssetMovieWriter(url: url)
            let expectedLength = 1.0 + 1.0 / 30

            for time in [50, 50.1, 50.2, 51] {
                sut.append(RecordedFrame(image: image, time: time))
            }
            let actual = try await sut.finish()

            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
            let segments = try await track.load(.segments)
            #expect(abs(actual / .seconds(1) - expectedLength) < 0.001)
            #expect(abs(duration.seconds - expectedLength) < 0.01)
            #expect(segments.count == 1 && segments.allSatisfy { !$0.isEmpty })
        }

        @Test("A last frame the encoder isn't ready for doesn't hold finish up: the movie ends one frame after the last frame written")
        func heldLastFrame() async throws {
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: url) }
            let context = try #require(CGContext(
                data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let image = try #require(context.makeImage())
            var assetWriter: AVAssetWriter?
            let sut = AssetMovieWriter(url: url) { url in
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                assetWriter = writer
                return writer
            }
            sut.append(RecordedFrame(image: image, time: 0))
            let input = try #require(assetWriter?.inputs.first)
            // Frames handed over faster than the encoder takes them fill its queue in about
            // eight; the next one is held.
            var frame = 1
            while input.isReadyForMoreMediaData, frame < 10000 {
                sut.append(RecordedFrame(image: image, time: Double(frame) / 30))
                frame += 1
            }
            let wasReady = input.isReadyForMoreMediaData
            let heldTime = Double(frame) / 30
            sut.append(RecordedFrame(image: image, time: heldTime))

            let actual = try await sut.finish()

            // Finish writes the held frame if the encoder has caught up by then, and leaves it out
            // if not; the movie ends one frame after whichever was written last.
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            reader.startReading()
            var lastWritten = -1.0
            while let sample = output.copyNextSampleBuffer() {
                if CMSampleBufferGetNumSamples(sample) > 0 { lastWritten = max(lastWritten, sample.presentationTimeStamp.seconds) }
            }
            let expectedLength = lastWritten + 1.0 / 30
            #expect(!wasReady)
            #expect(abs(lastWritten - heldTime) < 0.001 || abs(lastWritten - (heldTime - 1.0 / 30)) < 0.001)
            #expect(abs(actual / .seconds(1) - expectedLength) < 0.001)
            #expect(abs(duration.seconds - expectedLength) < 0.01)
        }

        @Test("Movie sizes round each side down to an even number of pixels")
        func evenSize() throws {
            let odd = try #require(CGContext(
                data: nil, width: 3, height: 5, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage())
            let even = try #require(CGContext(
                data: nil, width: 4, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage())

            let oddSize = AssetMovieWriter.movieSize(of: odd)
            let evenSize = AssetMovieWriter.movieSize(of: even)

            #expect(oddSize.width == 2 && oddSize.height == 4)
            #expect(evenSize.width == 4 && evenSize.height == 6)
        }
    }
#endif
