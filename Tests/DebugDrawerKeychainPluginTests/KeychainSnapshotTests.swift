// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    import DebugDrawer
    @testable import DebugDrawerKeychainPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets. The views hold
    // text fields, menus and pickers, which ImageRenderer draws as placeholders, so they are hosted
    // in a window that is never shown and drawn into a bitmap at a fixed 2x scale, in the
    // appearance the test asks for. macOS doesn't scale text with Dynamic Type, so the Mac pins
    // light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct KeychainSnapshotTests {
        // The share of pixels a hosted text-field snapshot must match: the AppKit field's host sometimes
        // measures it 2 pt short (DD-182), which moves only the field's text.
        private static let textFieldPrecision: Float = 0.99

        @Test(
            "The list filtered to one access group: the group menu, the filter field, a password, a certificate and a key",
            arguments: [ColorScheme.light, .dark]
        )
        func listWithGroupFilter(colorScheme: ColorScheme) throws {
            var filter = KeychainFilter(accessGroup: "TEAMID.com.example.app")
            let sut = KeychainListView(
                items: [KeychainFixtures.password, KeychainFixtures.certificate, KeychainFixtures.key],
                accessGroups: ["TEAMID.com.example.app", "TEAMID.com.example.shared"],
                filter: Binding(get: { filter }, set: { filter = $0 }), selection: nil, failure: nil, issue: nil,
                redaction: .standard, actions: KeychainListActions()
            )

            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 316, alignment: .leading)
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

            // The AppKit text field's host sometimes measures it 2 pt short (DD-182), which moves its text.
            assertSnapshot(of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("An open password: its value masked, its attributes, and Edit, Copy and Delete on one line", arguments: [ColorScheme.light, .dark])
        func passwordDetail(colorScheme: ColorScheme) throws {
            let selection = KeychainSelection(item: KeychainFixtures.password, value: .success(Data("s3cr3t-token".utf8)))
            let sut = KeychainRow(item: KeychainFixtures.password, detail: selection, redaction: .standard, onSelect: {}, onEdit: {}, onDelete: {})

            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 316, alignment: .leading)
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

        @Test("An open certificate: its attributes, Copy Attributes and Delete, and no value", arguments: [ColorScheme.light, .dark])
        func certificateDetail(colorScheme: ColorScheme) throws {
            let selection = KeychainSelection(item: KeychainFixtures.certificate, value: .success(nil))
            let sut = KeychainRow(item: KeychainFixtures.certificate, detail: selection, redaction: .standard, onSelect: {}, onDelete: {})

            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 316, alignment: .leading)
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

        @Test(
            "The add form: service, account, label, the hidden password, the group and accessibility menus, Save and Cancel",
            arguments: [ColorScheme.light, .dark]
        )
        func addForm(colorScheme: ColorScheme) throws {
            let draft = GenericPassword(
                service: "com.example.App", account: "ada@example.com", value: "s3cr3t", accessGroup: "TEAMID.com.example.shared"
            )
            let sut = KeychainPasswordForm(
                editor: .adding(draft), accessGroups: ["TEAMID.com.example.app", "TEAMID.com.example.shared"], issue: nil, save: { _ in }, cancel: {}
            )

            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 316, alignment: .leading)
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

            // The AppKit text field's host sometimes measures it 2 pt short (DD-182), which moves its text.
            assertSnapshot(of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
