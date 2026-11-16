// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerPermissionsPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (the buttons) as placeholders, so the tests host
    // the view in a window that is never shown and draw it into a bitmap at a fixed 2x scale, in
    // the appearance the test asks for: the snapshot doesn't depend on the Mac's own appearance or
    // display. macOS doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PermissionsSnapshotTests {
        @Test("Each permission shows its status by symbol, word and color, its usage description and key, and its buttons",
              arguments: [ColorScheme.light, .dark])
        func permissions(colorScheme: ColorScheme) throws {
            let rows = [
                PermissionRowState(
                    permission: DeclaredPermission(
                        kind: .camera, usageDescriptions: [UsageDescription(key: "NSCameraUsageDescription", text: "Scans receipts")]
                    ),
                    status: .authorized, request: .unavailable
                ),
                PermissionRowState(
                    permission: DeclaredPermission(
                        kind: .microphone, usageDescriptions: [UsageDescription(key: "NSMicrophoneUsageDescription", text: "Records memos")]
                    ),
                    status: .denied, request: .unavailable
                ),
                PermissionRowState(
                    permission: DeclaredPermission(
                        kind: .photoLibrary, usageDescriptions: [UsageDescription(key: "NSPhotoLibraryUsageDescription", text: "Picks a photo")]
                    ),
                    status: .limited, request: .unavailable
                ),
                PermissionRowState(
                    permission: DeclaredPermission(
                        kind: .location,
                        usageDescriptions: [UsageDescription(key: "NSLocationWhenInUseUsageDescription", text: "Shows nearby stores")]
                    ),
                    status: .notDetermined, request: .available
                ),
                PermissionRowState(
                    permission: DeclaredPermission(
                        kind: .calendars, usageDescriptions: [UsageDescription(key: "NSCalendarsUsageDescription", text: "Plans trips")]
                    ),
                    status: .notDetermined, request: .needsKey("NSCalendarsFullAccessUsageDescription")
                ),
                PermissionRowState(
                    permission: DeclaredPermission(kind: .notifications, usageDescriptions: []), status: .provisional, request: .unavailable
                ),
                PermissionRowState(
                    permission: DeclaredPermission(
                        kind: .localNetwork, usageDescriptions: [UsageDescription(key: "NSLocalNetworkUsageDescription", text: "Finds printers")]
                    ),
                    status: .noStatusAPI, request: .unavailable
                )
            ]
            let sut = PermissionsView(rows: rows, onRequest: { _ in }, onOpenSettings: { _ in })
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
