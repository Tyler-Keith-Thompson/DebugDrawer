#if DEBUG
    import CoreGraphics
    import DebugDrawer
    @testable import DebugDrawerScreenRecordingPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ScreenRecordingPluginTests {
        @Test("The plugin is Screen Recording, in Interface, with a HUD readout and a header accessory, and adds to bug reports")
        func identity() throws {
            let model = ScreenRecordingModel(
                folder: RecordingFolder(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)),
                capacity: 5, frameSource: FakeFrameSource(), makeWriter: { FakeMovieWriter(url: $0) },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )
            let sut = ScreenRecordingPlugin(model: model)

            #expect(sut.id == "ScreenRecordingPlugin")
            #expect(sut.title == "Screen Recording")
            #expect(sut.category == "Interface")
            #expect(sut.icon == "record.circle")
            #expect(AnyDebugDrawerPlugin(sut).hasHUD)
            #expect(AnyDebugDrawerPlugin(sut).headerAccessory != nil)
            #expect(AnyDebugDrawerPlugin(sut).contributesToReport)
        }

        @Test("The drawer's search offers starting and stopping, found by \"video\" too")
        func action() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = FakeFrameSource()
            let model = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { FakeMovieWriter(url: $0) },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )
            let sut = ScreenRecordingPlugin(model: model)
            let action = try #require(sut.actions.first)

            action.perform()
            let started = model.state.isRecording
            source.send(at: 1)
            let states = model.$state.values
            action.perform()
            for await state in states {
                if case .finished = state { break }
            }

            #expect(sut.actions.map(\.title) == ["Start or stop screen recording"])
            #expect(action.keywords.contains("video"))
            #expect(started)
            #expect(model.recordings.count == 1)
        }

        @Test("The bug report carries each included recording as a .mov under its file's name, with its bytes")
        func report() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let first = directory.appending(path: "Screen Recording 2025-11-16T10-47-00Z.mov")
            let second = directory.appending(path: "Screen Recording 2025-11-16T10-46-40Z.mov")
            try Data("first".utf8).write(to: first)
            try Data("second".utf8).write(to: second)
            let recordings = [
                Recording(url: first, started: Date(timeIntervalSince1970: 1_763_290_020), duration: .seconds(3), byteCount: 5),
                Recording(url: second, started: Date(timeIntervalSince1970: 1_763_290_000), duration: .seconds(4), byteCount: 6)
            ]
            var actual = DebugDrawerReport()

            ScreenRecordingPlugin.contribute(recordings, to: &actual)

            #expect(actual.files.map(\.name) == [first.lastPathComponent, second.lastPathComponent])
            #expect(actual.files.map(\.kind) == [.movie, .movie])
            #expect(actual.files.map(\.data) == [Data("first".utf8), Data("second".utf8)])
        }

        @Test("No recording included adds nothing, and one whose file has gone is skipped")
        func reportEmpty() {
            let gone = Recording(
                url: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov"),
                started: .now, duration: nil, byteCount: 0
            )
            var none = DebugDrawerReport()
            var missing = DebugDrawerReport()

            ScreenRecordingPlugin.contribute([], to: &none)
            ScreenRecordingPlugin.contribute([gone], to: &missing)

            #expect(none.files.isEmpty)
            #expect(missing.files.isEmpty)
        }

        @Test("Through the plugin, the report has the newest recording once one is saved, none before, and none while one is recording")
        func reportFromModel() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = FakeFrameSource()
            let model = ScreenRecordingModel(
                folder: RecordingFolder(directory: directory), capacity: 5, frameSource: source,
                makeWriter: { FakeMovieWriter(url: $0) },
                now: { Date(timeIntervalSince1970: 1_763_290_000) },
                defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
            )
            let sut = ScreenRecordingPlugin(model: model)
            var before = DebugDrawerReport()
            var during = DebugDrawerReport()
            var after = DebugDrawerReport()

            sut.contribute(to: &before, redaction: .standard)
            model.start()
            source.send(at: 1)
            sut.contribute(to: &during, redaction: .standard)
            await model.stop()
            sut.contribute(to: &after, redaction: .standard)

            #expect(before.files.isEmpty)
            #expect(during.files.isEmpty)
            #expect(after.files.map(\.name) == ["Screen Recording 2025-11-16T10-46-40Z.mov"])
        }

        @Test("A touch indicator is drawn where the finger is, and nowhere far from it")
        func touchIndicator() throws {
            let context = try #require(CGContext(
                data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 800,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            // Row 0 of the buffer is the context's top, row 199.
            func rgb(column: Int, row: Int) -> [UInt8] {
                let offset = (199 - row) * 800 + column * 4
                return [pixels[offset], pixels[offset + 1], pixels[offset + 2]]
            }
            let background = rgb(column: 150, row: 150)

            TouchIndicator.draw(at: [CGPoint(x: 50, y: 50)], in: context)

            let centre = rgb(column: 50, row: 50)
            let far = rgb(column: 150, row: 150)
            #expect(centre[0] > 100 && centre[1] > 100)
            #expect(background[0] < 20 && background[2] > 200)
            #expect(far == background)
        }

        @Test("No touches draw nothing")
        func noTouches() throws {
            let context = try #require(CGContext(
                data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))

            TouchIndicator.draw(at: [], in: context)

            let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            #expect((0 ..< 400).allSatisfy { pixels[$0] == 0 })
        }
    }
#endif
