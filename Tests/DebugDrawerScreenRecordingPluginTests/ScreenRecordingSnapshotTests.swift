// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerScreenRecordingPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (the buttons) as placeholders, so the tests host
    // the view in a window that is never shown and draw it into a bitmap at a fixed 2x scale, in the
    // appearance the test asks for. macOS doesn't scale text with Dynamic Type, so the Mac pins light
    // and dark only. Times are drawn in en_US and UTC. A recording in progress started in the future,
    // so its elapsed time reads 0:00 whenever the test runs.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ScreenRecordingSnapshotTests {
        @Test("Saved recordings, the newest in the bug report, below Not Recording, with Record", arguments: [ColorScheme.light, .dark])
        func saved(colorScheme: ColorScheme) throws {
            let newest = Recording(
                url: URL(filePath: "/tmp/Screen Recording 2025-11-16T10-47-00Z.mov"),
                started: Date(timeIntervalSince1970: 1_763_290_020), duration: .seconds(12), byteCount: 3_400_000
            )
            let older = Recording(
                url: URL(filePath: "/tmp/Screen Recording 2025-11-16T10-46-40Z.mov"),
                started: Date(timeIntervalSince1970: 1_763_290_000), duration: .seconds(75), byteCount: 21_800_000
            )
            let sut = ScreenRecordingView(
                state: .finished(newest.url), recordings: [newest, older], includedInReport: [newest.id], capacity: 5,
                showsTouches: .constant(false), start: {}, stop: {}, delete: { _ in }, setIncludedInReport: { _, _ in }
            )
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, try #require(TimeZone(identifier: "UTC")))
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("Recording: the red dot and elapsed time, and Stop", arguments: [ColorScheme.light, .dark])
        func recording(colorScheme: ColorScheme) throws {
            let sut = ScreenRecordingView(
                state: .recording(started: .distantFuture), recordings: [], includedInReport: [], capacity: 5,
                showsTouches: .constant(false), start: {}, stop: {}, delete: { _ in }, setIncludedInReport: { _, _ in }
            )
            let host = NSHostingView(rootView: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A recording that wasn't saved says why", arguments: [ColorScheme.light, .dark])
        func failed(colorScheme: ColorScheme) throws {
            let sut = ScreenRecordingView(
                state: .failed(.noFrames), recordings: [], includedInReport: [], capacity: 5,
                showsTouches: .constant(false), start: {}, stop: {}, delete: { _ in }, setIncludedInReport: { _, _ in }
            )
            let host = NSHostingView(rootView: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("The HUD's button: Record, and the dot, time and stop square while recording", arguments: [ColorScheme.light, .dark])
        func hud(colorScheme: ColorScheme) throws {
            let sut = VStack(alignment: .leading, spacing: 8) {
                ScreenRecordingHUDButton(state: .idle) {}
                ScreenRecordingHUDButton(state: .recording(started: .distantFuture)) {}
            }
            let host = NSHostingView(rootView: sut
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
