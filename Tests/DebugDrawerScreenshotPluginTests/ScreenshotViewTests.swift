// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import AppKit
    import DebugDrawer
    @testable import DebugDrawerScreenshotPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    // The model is driven into each state through its commands, over a hand-written window and
    // Desktop, and the view is read over a direct transport to it. The view's failure wording is
    // private to it, so the expected texts are the literals it shows. Nothing sends `copy` through
    // a hosted view: the view would write the Mac's real clipboard. A test of the copied state sends
    // `copied` itself, as the view does once it has written the clipboard. Hosted views must not run
    // side by side, hence `.serialized`.
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct ScreenshotViewTests {
        @Test("A capture saved to the Desktop shows Saved and the file's path")
        func savedShowsThePath() async throws {
            let image = ScreenshotImage(png: Data([0x89, 0x50, 0x4E, 0x47]), pixelWidth: 2, pixelHeight: 2, scale: 2)
            let transport = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver(),
                appName: "Orders", now: { Date(timeIntervalSince1970: 1_800_000_000) }
            ))
            transport.send(ScreenshotCommand(.capture))
            transport.send(ScreenshotCommand(.save))
            for await snapshot in transport.snapshots() where snapshot.status != .capturing {
                break
            }
            let sut = ScreenshotPluginView(transport: transport)
            let expectedTitle = "Saved"
            let expectedPath = "/Users/dev/Desktop/Orders-Debug-2027-01-15T08-00-00Z.png"

            let view = try sut.inspect()
            let title = try view.find(text: expectedTitle).string()
            let path = try view.find(text: expectedPath).string()

            #expect(title == expectedTitle)
            #expect(path == expectedPath)
        }

        @Test("A capture put on the clipboard shows Saved and Copied to clipboard")
        func copiedSaysSo() async throws {
            let image = ScreenshotImage(png: Data([0x89, 0x50, 0x4E, 0x47]), pixelWidth: 2, pixelHeight: 2, scale: 2)
            let transport = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver()
            ))
            transport.send(ScreenshotCommand(.capture))
            transport.send(ScreenshotCommand(.copy))
            for await snapshot in transport.snapshots() where snapshot.status == .copying {
                break
            }
            transport.send(ScreenshotCommand(.copied))
            let sut = ScreenshotPluginView(transport: transport)
            let expectedTitle = "Saved"
            let expectedSubline = "Copied to clipboard"

            let view = try sut.inspect()
            let title = try view.find(text: expectedTitle).string()
            let subline = try view.find(text: expectedSubline).string()

            #expect(transport.snapshot.status == .copied)
            #expect(title == expectedTitle)
            #expect(subline == expectedSubline)
        }

        @Test("A capture that fails shows Error and what went wrong", arguments: [
            (ScreenshotFailure.noWindow, "Error: No key window to capture"),
            (.encodingFailed, "Error: Failed to encode screenshot as PNG")
        ])
        func captureFailureSaysWhy(failure: ScreenshotFailure, expected: String) async throws {
            let transport = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.failure(failure)]), saver: FakeScreenshotSaver()
            ))
            transport.send(ScreenshotCommand(.capture))
            for await snapshot in transport.snapshots() where snapshot.status != .capturing {
                break
            }
            let sut = ScreenshotPluginView(transport: transport)

            let actual = try sut.inspect().find(text: expected).string()

            #expect(transport.snapshot.status == .failed(failure))
            #expect(actual == expected)
        }

        @Test("A save that fails shows Error and what went wrong", arguments: [
            (ScreenshotFailure.noDesktop, "Error: Could not locate Desktop directory"),
            (.writeFailed("Disk full"), "Error: Disk full")
        ])
        func saveFailureSaysWhy(failure: ScreenshotFailure, expected: String) async throws {
            let image = ScreenshotImage(png: Data([0x89, 0x50, 0x4E, 0x47]), pixelWidth: 2, pixelHeight: 2, scale: 2)
            let transport = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver(outcome: .failure(failure))
            ))
            transport.send(ScreenshotCommand(.capture))
            transport.send(ScreenshotCommand(.save))
            for await snapshot in transport.snapshots() where snapshot.status != .capturing {
                break
            }
            let sut = ScreenshotPluginView(transport: transport)

            let actual = try sut.inspect().find(text: expected).string()

            #expect(transport.snapshot.status == .failed(failure))
            #expect(actual == expected)
        }

        @Test("A save at the location picked that fails shows Error and the reason")
        func exportFailureSaysWhy() async throws {
            let image = ScreenshotImage(png: Data([0x89, 0x50, 0x4E, 0x47]), pixelWidth: 2, pixelHeight: 2, scale: 2)
            let transport = DebugDrawerPluginTransport.direct(to: ScreenshotModel(
                capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver(outcome: .success(false))
            ))
            transport.send(ScreenshotCommand(.capture))
            transport.send(ScreenshotCommand(.save))
            for await snapshot in transport.snapshots() where snapshot.status != .capturing {
                break
            }
            transport.send(ScreenshotCommand(.exportFailed("Read-only volume")))
            let sut = ScreenshotPluginView(transport: transport)
            let expected = "Error: Read-only volume"

            let actual = try sut.inspect().find(text: expected).string()

            #expect(transport.snapshot.status == .failed(.exportFailed("Read-only volume")))
            #expect(actual == expected)
        }

        @Test("Clear shows only while a capture is held, and pressing it returns the view to how it was before the capture")
        func clearShowsOnlyWhileHeld() async throws {
            // A PNG that decodes, so the view shows its preview.
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let image = ScreenshotImage(png: png, pixelWidth: 4, pixelHeight: 4, scale: 2)
            let model = ScreenshotModel(capturer: FakeScreenshotCapturer([.success(image)]), saver: FakeScreenshotSaver())
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = transport.snapshots()
            let sut = ScreenshotPluginView(transport: transport)
            var clearBefore = true
            var clearWhileHeld = false
            var previewWhileHeld = false
            var clearAfter = true
            var previewAfter = true
            var statusAfter = true

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    clearBefore = (try? view.find(button: "Clear")) != nil
                    // To Desktop captures and saves, through the fakes: nothing is drawn or written.
                    try view.find(button: "To Desktop").tap()
                }
                for await snapshot in snapshots where snapshot.capture != nil && snapshot.status != .capturing {
                    break
                }
                try await sut.inspection.inspect { view in
                    clearWhileHeld = (try? view.find(button: "Clear")) != nil
                    previewWhileHeld = (try? view.find(ViewType.Image.self, where: {
                        try $0.accessibilityLabel().string() == "Last capture"
                    })) != nil
                    try view.find(button: "Clear").tap()
                }
                for await snapshot in snapshots where snapshot.capture == nil {
                    break
                }
                try await sut.inspection.inspect { view in
                    clearAfter = (try? view.find(button: "Clear")) != nil
                    previewAfter = (try? view.find(ViewType.Image.self, where: {
                        try $0.accessibilityLabel().string() == "Last capture"
                    })) != nil
                    statusAfter = (try? view.find(text: "Saved")) != nil
                }
            }

            #expect(!clearBefore)
            #expect(clearWhileHeld)
            #expect(previewWhileHeld)
            #expect(!clearAfter)
            #expect(!previewAfter)
            #expect(!statusAfter)
            #expect(model.snapshot == ScreenshotSnapshot())
        }
    }
#endif
