#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerScreenshotPlugin
    import Foundation
    import Testing

    // The model is read and driven here as an out-of-process reader would: through its snapshot,
    // encoded and decoded, and commands, sent through a direct transport, with no view. The window
    // and the Desktop are hand-written fakes; nothing draws a window, hides a drawer or writes a
    // file. A capture lands after `send(_:)` returns, so a test reads snapshots until it has.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ScreenshotModelTests {
        @Test("A snapshot holding a capture saved to the Desktop encodes to JSON and decodes equal, PNG bytes and all")
        func snapshotRoundTrips() async throws {
            let image = ScreenshotImage(png: Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]), pixelWidth: 2400, pixelHeight: 1600, scale: 2)
            let model = ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver(),
                appName: "Orders", now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
            let sut = DebugDrawerPluginTransport.direct(to: model)
            sut.send(ScreenshotCommand(.setHidesDrawer(false)))
            sut.send(ScreenshotCommand(.capture))
            sut.send(ScreenshotCommand(.save))
            for await snapshot in sut.snapshots() where snapshot.status != .capturing {
                break
            }
            let expected = sut.snapshot

            let encoded = try JSONEncoder().encode(expected)
            let actual = try JSONDecoder().decode(ScreenshotSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.capture?.image == image)
            #expect(actual.status == .saved(path: "/Users/dev/Desktop/Orders-Debug-2027-01-15T08-00-00Z.png"))
            #expect(!actual.hidesDrawer)
        }

        @Test("A snapshot before any capture encodes to JSON and decodes equal: the drawer hides, nothing captured")
        func emptySnapshotRoundTrips() throws {
            let capturer = FakeScreenshotCapturer([])
            let sut = ScreenshotModel(capturer: capturer, saver: FakeScreenshotSaver())
            let expected = ScreenshotSnapshot(hidesDrawer: true, capture: nil, status: .ready)

            let encoded = try JSONEncoder().encode(sut.snapshot)
            let actual = try JSONDecoder().decode(ScreenshotSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(capturer.requests.isEmpty)
        }

        @Test("Every status, failures included, encodes to JSON and decodes equal")
        func statusesRoundTrip() throws {
            let expected: [ScreenshotStatus] = [
                .ready, .capturing, .saved(path: "/Users/dev/Desktop/a.png"), .needsLocation(filename: "a.png"), .copying, .copied,
                .failed(.noWindow), .failed(.encodingFailed), .failed(.noDesktop), .failed(.writeFailed("Disk full")),
                .failed(.exportFailed("Read-only volume"))
            ]

            let actual = try expected.map { try JSONDecoder().decode(ScreenshotStatus.self, from: JSONEncoder().encode($0)) }

            #expect(actual == expected)
        }

        @Test("Every command, encoded to JSON and decoded, arrives as it was sent")
        func commandsRoundTrip() throws {
            let expected: [ScreenshotCommand.Action] = [
                .setHidesDrawer(false), .capture, .save, .copy, .copied, .exported(path: "/Users/dev/Pictures/a.png"),
                .exportFailed("Read-only volume"), .cancelExport, .clear
            ]

            let actual = try expected.map {
                try JSONDecoder().decode(ScreenshotCommand.self, from: JSONEncoder().encode(ScreenshotCommand($0))).action
            }

            #expect(actual == expected)
        }

        @Test("A capture puts the window's PNG, its size and scale, the time and the file name in the snapshot")
        func captureFillsTheSnapshot() async {
            let image = ScreenshotImage(png: Data([0x89, 0x50, 0x4E, 0x47, 9, 8, 7]), pixelWidth: 1170, pixelHeight: 2532, scale: 3)
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let capturer = FakeScreenshotCapturer([.success(image)])
            let sut = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: capturer, saver: FakeScreenshotSaver(), appName: "Orders", now: { date }
            ))
            let expected = ScreenshotCapture(image: image, date: date, filename: "Orders-Debug-2027-01-15T08-00-00Z.png")

            sut.send(ScreenshotCommand(.capture))
            let whileCapturing = sut.snapshot.status
            for await snapshot in sut.snapshots() where snapshot.status != .capturing {
                break
            }

            #expect(whileCapturing == .capturing)
            #expect(sut.snapshot.capture == expected)
            #expect(sut.snapshot.capture?.image.png == image.png)
            #expect(sut.snapshot.status == .ready)
            #expect(capturer.requests == [true])
        }

        @Test("A capture with no key window fails as such, holds no capture, and a save after it saves nothing")
        func captureFailure() async {
            let saver = FakeScreenshotSaver()
            let sut = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.failure(.noWindow)]), saver: saver
            ))

            sut.send(ScreenshotCommand(.capture))
            sut.send(ScreenshotCommand(.save))
            for await snapshot in sut.snapshots() where snapshot.status != .capturing {
                break
            }

            #expect(sut.snapshot.status == .failed(.noWindow))
            #expect(sut.snapshot.capture == nil)
            #expect(saver.requests.isEmpty)
        }

        @Test("A new capture drops the last one while it is taken, and a failed one leaves none")
        func newCaptureDropsTheLast() async {
            let image = ScreenshotImage(png: Data([1]), pixelWidth: 1, pixelHeight: 1, scale: 1)
            let sut = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image), .failure(.encodingFailed)]), saver: FakeScreenshotSaver()
            ))
            sut.send(ScreenshotCommand(.capture))
            for await snapshot in sut.snapshots() where snapshot.status != .capturing {
                break
            }

            sut.send(ScreenshotCommand(.capture))
            let whileCapturing = sut.snapshot.capture
            for await snapshot in sut.snapshots() where snapshot.status != .capturing {
                break
            }

            #expect(whileCapturing == nil)
            #expect(sut.snapshot.capture == nil)
            #expect(sut.snapshot.status == .failed(.encodingFailed))
        }

        @Test("Save writes the last capture's PNG under its file name and reports the path")
        func saveSucceeds() async {
            let image = ScreenshotImage(png: Data([0x89, 0x50, 0x4E, 0x47, 4]), pixelWidth: 4, pixelHeight: 4, scale: 2)
            let saver = FakeScreenshotSaver(folder: URL(fileURLWithPath: "/Users/dev/Desktop"))
            let sut = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: saver,
                appName: "Orders", now: { Date(timeIntervalSince1970: 1_800_000_000) }
            ))
            sut.send(ScreenshotCommand(.capture))
            for await snapshot in sut.snapshots() where snapshot.status != .capturing {
                break
            }
            let expectedName = "Orders-Debug-2027-01-15T08-00-00Z.png"

            sut.send(ScreenshotCommand(.save))

            #expect(saver.files == [expectedName: image.png])
            #expect(sut.snapshot.status == .saved(path: "/Users/dev/Desktop/\(expectedName)"))
            #expect(sut.snapshot.capture?.image == image)
        }

        @Test("A save that fails reports why and keeps the capture")
        func saveFails() async {
            let image = ScreenshotImage(png: Data([1]), pixelWidth: 1, pixelHeight: 1, scale: 1)
            let saver = FakeScreenshotSaver(outcome: .failure(.writeFailed("The disk is full.")))
            let sut = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: saver
            ))
            sut.send(ScreenshotCommand(.capture))
            for await snapshot in sut.snapshots() where snapshot.status != .capturing {
                break
            }

            sut.send(ScreenshotCommand(.save))

            #expect(sut.snapshot.status == .failed(.writeFailed("The disk is full.")))
            #expect(sut.snapshot.capture?.image == image)
            #expect(saver.files.isEmpty)
        }

        @Test("With no Desktop folder, a save fails as such")
        func saveWithNoDesktop() async {
            let image = ScreenshotImage(png: Data([1]), pixelWidth: 1, pixelHeight: 1, scale: 1)
            let sut = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver(outcome: .failure(.noDesktop))
            ))
            sut.send(ScreenshotCommand(.capture))
            for await snapshot in sut.snapshots() where snapshot.status != .capturing {
                break
            }

            sut.send(ScreenshotCommand(.save))

            #expect(sut.snapshot.status == .failed(.noDesktop))
        }

        @Test("A save the Desktop refuses asks for a location under the capture's name; the save panel's outcome is reported")
        func refusedSaveAsksForALocation() async {
            let image = ScreenshotImage(png: Data([1]), pixelWidth: 1, pixelHeight: 1, scale: 1)
            let sut = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver(outcome: .success(false)),
                appName: "Orders", now: { Date(timeIntervalSince1970: 1_800_000_000) }
            ))
            sut.send(ScreenshotCommand(.capture))
            sut.send(ScreenshotCommand(.save))
            for await snapshot in sut.snapshots() where snapshot.status != .capturing {
                break
            }
            let asked = sut.snapshot.status

            sut.send(ScreenshotCommand(.exported(path: "/Users/dev/Pictures/shot.png")))
            let exported = sut.snapshot.status
            sut.send(ScreenshotCommand(.cancelExport))

            #expect(asked == .needsLocation(filename: "Orders-Debug-2027-01-15T08-00-00Z.png"))
            #expect(exported == .saved(path: "/Users/dev/Pictures/shot.png"))
            #expect(sut.snapshot.status == .saved(path: "/Users/dev/Pictures/shot.png"))
        }

        @Test("Closing the save panel without saving leaves the capture and reports nothing; an export that fails says why")
        func cancelledAndFailedExport() async {
            let image = ScreenshotImage(png: Data([1]), pixelWidth: 1, pixelHeight: 1, scale: 1)
            let sut = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver(outcome: .success(false))
            ))
            sut.send(ScreenshotCommand(.capture))
            sut.send(ScreenshotCommand(.save))
            for await snapshot in sut.snapshots() where snapshot.status != .capturing {
                break
            }

            sut.send(ScreenshotCommand(.cancelExport))
            let cancelled = sut.snapshot
            sut.send(ScreenshotCommand(.save))
            sut.send(ScreenshotCommand(.exportFailed("Read-only volume")))

            #expect(cancelled.status == .ready)
            #expect(cancelled.capture?.image == image)
            #expect(sut.snapshot.status == .failed(.exportFailed("Read-only volume")))
        }

        @Test("Copy asks the view to copy the capture, and the view's word that it did reports it copied; with no capture, copy does nothing")
        func copy() async {
            let image = ScreenshotImage(png: Data([1]), pixelWidth: 1, pixelHeight: 1, scale: 1)
            let sut = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver()
            ))
            sut.send(ScreenshotCommand(.copy))
            let withNoCapture = sut.snapshot.status

            sut.send(ScreenshotCommand(.capture))
            sut.send(ScreenshotCommand(.copy))
            for await snapshot in sut.snapshots() where snapshot.status != .capturing {
                break
            }
            let asked = sut.snapshot.status
            sut.send(ScreenshotCommand(.copied))

            #expect(withNoCapture == .ready)
            #expect(asked == .copying)
            #expect(sut.snapshot.status == .copied)
            #expect(sut.snapshot.capture?.image == image)
        }

        @Test("Clear drops the capture and where it went, and keeps whether to hide the drawer")
        func clear() async {
            let image = ScreenshotImage(png: Data([1]), pixelWidth: 1, pixelHeight: 1, scale: 1)
            let sut = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver()
            ))
            sut.send(ScreenshotCommand(.setHidesDrawer(false)))
            sut.send(ScreenshotCommand(.capture))
            sut.send(ScreenshotCommand(.save))
            for await snapshot in sut.snapshots() where snapshot.status != .capturing {
                break
            }
            let expected = ScreenshotSnapshot(hidesDrawer: false, capture: nil, status: .ready)

            sut.send(ScreenshotCommand(.clear))

            #expect(sut.snapshot == expected)
        }

        @Test("Commands sent during a capture wait for it and land in the order sent")
        func commandOrder() async {
            let first = ScreenshotImage(png: Data([1]), pixelWidth: 1, pixelHeight: 1, scale: 1)
            let second = ScreenshotImage(png: Data([2]), pixelWidth: 2, pixelHeight: 2, scale: 1)
            let capturer = FakeScreenshotCapturer([.success(first), .success(second)], holds: true)
            let saver = FakeScreenshotSaver()
            var times = [Date(timeIntervalSince1970: 1_800_000_000), Date(timeIntervalSince1970: 1_800_000_060)]
            let sut = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: capturer, saver: saver, appName: "Orders", now: { times.removeFirst() }
            ))

            sut.send(ScreenshotCommand(.capture))
            sut.send(ScreenshotCommand(.save))
            sut.send(ScreenshotCommand(.setHidesDrawer(false)))
            sut.send(ScreenshotCommand(.capture))
            sut.send(ScreenshotCommand(.copy))
            let whileHeld = sut.snapshot
            capturer.release()
            for await snapshot in sut.snapshots() where snapshot.status != .capturing {
                break
            }

            #expect(whileHeld == ScreenshotSnapshot(hidesDrawer: true, capture: nil, status: .capturing))
            #expect(capturer.requests == [true, false])
            #expect(saver.files == ["Orders-Debug-2027-01-15T08-00-00Z.png": first.png])
            #expect(sut.snapshot.capture?.image == second)
            #expect(sut.snapshot.capture?.filename == "Orders-Debug-2027-01-15T08-01-00Z.png")
            #expect(sut.snapshot.status == .copying)
            #expect(!sut.snapshot.hidesDrawer)
        }

        @Test("A command sent while nothing is under way lands before send returns")
        func immediateCommands() {
            let sut = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([]), saver: FakeScreenshotSaver()
            ))

            sut.send(ScreenshotCommand(.setHidesDrawer(false)))

            #expect(!sut.snapshot.hidesDrawer)
        }
    }
#endif
