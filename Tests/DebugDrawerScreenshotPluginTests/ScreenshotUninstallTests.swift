#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerScreenshotPlugin
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @MainActor
    @Suite("Screenshot drops its last capture once removed from every drawer", .timeLimit(.minutes(1)))
    struct ScreenshotUninstallTests {
        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = temporarySuiteName("ScreenshotUninstallTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        @Test("Unregistering removes the plugin and drops the last capture and its result, keeping whether to hide the drawer")
        func disappearsFromTheDrawer() async throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let image = ScreenshotImage(png: Data([0x89, 0x50, 0x4E, 0x47]), pixelWidth: 1, pixelHeight: 1, scale: 1)
            let model = ScreenshotModel(capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver())
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let sut = ScreenshotPlugin(model: model)
            drawer.registerGlobal(sut)
            transport.send(ScreenshotCommand(.setHidesDrawer(false)))
            transport.send(ScreenshotCommand(.capture))
            transport.send(ScreenshotCommand(.save))
            for await snapshot in transport.snapshots() where snapshot.status != .capturing {
                break
            }
            let expected = ScreenshotSnapshot(hidesDrawer: false, capture: nil, status: .ready)

            drawer.unregisterGlobal(id: sut.id)

            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(model.snapshot == expected)
        }

        @Test("A capture the Desktop refused, waiting for a place to be saved, is dropped too")
        func dropsARefusedCapture() async throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let image = ScreenshotImage(png: Data([1]), pixelWidth: 1, pixelHeight: 1, scale: 1)
            let model = ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver(outcome: .success(false))
            )
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let sut = ScreenshotPlugin(model: model)
            drawer.registerGlobal(sut)
            transport.send(ScreenshotCommand(.capture))
            transport.send(ScreenshotCommand(.save))
            for await snapshot in transport.snapshots() where snapshot.status != .capturing {
                break
            }
            let refused = model.snapshot.status

            drawer.unregisterGlobal(id: sut.id)

            #expect(refused != .ready)
            #expect(model.snapshot.status == .ready)
            #expect(model.snapshot.capture == nil)
        }

        @Test("A second drawer still holding the plugin keeps the last capture")
        func twoDrawers() async throws {
            let (first, cleanUpFirst) = try Self.drawer()
            let (second, cleanUpSecond) = try Self.drawer()
            defer {
                cleanUpFirst()
                cleanUpSecond()
            }
            let image = ScreenshotImage(png: Data([1]), pixelWidth: 1, pixelHeight: 1, scale: 1)
            let model = ScreenshotModel(capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver())
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let sut = ScreenshotPlugin(model: model)
            first.registerGlobal(sut)
            second.registerGlobal(sut)
            transport.send(ScreenshotCommand(.capture))
            for await snapshot in transport.snapshots() where snapshot.status != .capturing {
                break
            }

            first.unregisterGlobal(id: sut.id)
            let whileTheSecondHoldsIt = model.snapshot.capture
            sut.uninstall(from: first)
            second.unregisterGlobal(id: sut.id)

            #expect(whileTheSecondHoldsIt?.image == image)
            #expect(model.snapshot.capture == nil)
        }

        @Test("Uninstalling from a drawer that never installed it keeps the capture")
        func strangerDrawer() async throws {
            let (drawer, cleanUp) = try Self.drawer()
            let (stranger, cleanUpStranger) = try Self.drawer()
            defer {
                cleanUp()
                cleanUpStranger()
            }
            let image = ScreenshotImage(png: Data([1]), pixelWidth: 1, pixelHeight: 1, scale: 1)
            let model = ScreenshotModel(capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver())
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let sut = ScreenshotPlugin(model: model)
            drawer.registerGlobal(sut)
            transport.send(ScreenshotCommand(.capture))
            for await snapshot in transport.snapshots() where snapshot.status != .capturing {
                break
            }

            sut.uninstall(from: stranger)

            #expect(model.snapshot.capture?.image == image)
        }

        @Test("A capture under way when the last drawer removes the plugin still finishes")
        func captureUnderWayFinishes() async throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let image = ScreenshotImage(png: Data([1]), pixelWidth: 1, pixelHeight: 1, scale: 1)
            let capturer = FakeScreenshotCapturer([.success(image)], holds: true)
            let model = ScreenshotModel(capturer: capturer, saver: FakeScreenshotSaver())
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let sut = ScreenshotPlugin(model: model)
            drawer.registerGlobal(sut)
            transport.send(ScreenshotCommand(.capture))

            drawer.unregisterGlobal(id: sut.id)
            let whileCapturing = model.snapshot.status
            capturer.release()
            for await snapshot in transport.snapshots() where snapshot.status != .capturing {
                break
            }

            #expect(whileCapturing == .capturing)
            #expect(model.snapshot.capture?.image == image)
        }
    }
#endif
