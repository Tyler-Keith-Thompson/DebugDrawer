#if DEBUG
    import AVFoundation
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
            let sut = AssetMovieWriter(url: url)
            let expectedLength = 1.0 + 1.0 / 30

            for frame in 0 ... 30 {
                sut.append(RecordedFrame(image: image, time: 100 + Double(frame) / 30))
            }
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
