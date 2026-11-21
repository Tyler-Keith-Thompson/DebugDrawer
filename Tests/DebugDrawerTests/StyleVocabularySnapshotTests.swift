// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS) && canImport(SnapshotTesting)
    import AppKit
    @testable import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing

    // Buttons, switches and text fields are hosted in a window that is never shown and drawn into a
    // bitmap at a fixed 2x scale, in the appearance the test asks for. macOS doesn't scale text with
    // Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct StyleVocabularySnapshotTests {
        @Test("Each button kind, enabled and disabled; each issue glyph; the scope toggles off and on", arguments: [ColorScheme.light, .dark])
        func controls(colorScheme: ColorScheme) throws {
            let sut = VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Request") {}.debugDrawerButtonStyle(.primary)
                    Button("Open Settings") {}.debugDrawerButtonStyle(.secondary)
                    Button("Delete All", role: .destructive) {}.debugDrawerButtonStyle(.destructive)
                }
                HStack {
                    Button("Request") {}.debugDrawerButtonStyle(.primary).disabled(true)
                    Button("Refresh") {}.debugDrawerButtonStyle(.secondary).disabled(true)
                    Button("Copy") {}.debugDrawerButtonStyle(.borderless)
                }
                HStack {
                    ForEach(DebugDrawerIssueGlyph.Severity.allCases, id: \.self) { severity in
                        DebugDrawerIssueGlyph(severity)
                    }
                    DrawerScopeToggle(title: "Show only my code", systemImage: "person.crop.square", isOn: .constant(false))
                    DrawerScopeToggle(title: "Show only unread", systemImage: "circlebadge", isOn: .constant(true))
                }
            }
            .padding()
            .frame(width: 380, alignment: .leading)
            .background(DrawerPalette.panel)
            let host = NSHostingView(rootView: sut)
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
