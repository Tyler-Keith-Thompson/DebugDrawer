// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (text fields, bordered buttons) as placeholders,
    // so a test of a view holding one hosts it in a window that is never shown and draws it into a
    // bitmap at a fixed 2x scale, in the appearance the test asks for. Views without one use
    // ImageRenderer. macOS doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PluginComponentsSnapshotTests {
        @Test("Key-value rows line their labels up, monospaced values beside them, a redacted one masked", arguments: [ColorScheme.light, .dark])
        func keyValueRows(colorScheme: ColorScheme) throws {
            let sut = VStack(alignment: .leading, spacing: 6) {
                DebugDrawerKeyValueRow("Version", value: "1.4.2 (88)")
                DebugDrawerKeyValueRow("Bundle ID", value: "com.example.orders")
                DebugDrawerKeyValueRow("Token", value: "t0k3n", redacted: DebugDrawerRedaction.mask)
            }
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A sparkline draws its samples, fitted to their lowest and highest, on a faint panel", arguments: [ColorScheme.light, .dark])
        func sparkline(colorScheme: ColorScheme) throws {
            let samples: [Double] = [60, 60, 58, 41, 59, 60, 30, 55, 60, 60, 60, 57]
            let sut = DebugDrawerSparkline("Frame rate history", data: samples)
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A sparkline with a range draws its samples against it", arguments: [ColorScheme.light, .dark])
        func sparklineInRange(colorScheme: ColorScheme) throws {
            let samples: [Double] = [12, 18, 15, 40, 72, 65, 30, 22, 25, 90, 55, 20]
            let sut = DebugDrawerSparkline("CPU history", data: samples, range: 0 ... 100)
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A copy button is small and bordered", arguments: [ColorScheme.light, .dark])
        func copyButton(colorScheme: ColorScheme) throws {
            let sut = DebugDrawerCopyButton("Copy Value") { "value" }
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

        @Test("A searchable list shows its filter field above its rows on a dark panel", arguments: [ColorScheme.light, .dark])
        func searchableList(colorScheme: ColorScheme) throws {
            let sut = DebugDrawerSearchableList("Filter...", text: .constant(""), accessibilityLabel: "Filter keys") {
                ForEach(["apiBaseURL", "hasOnboarded", "lastSyncDate"], id: \.self) { key in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(key)
                            .font(.system(.caption2, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                        Divider()
                    }
                }
            }
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
    }
#endif
