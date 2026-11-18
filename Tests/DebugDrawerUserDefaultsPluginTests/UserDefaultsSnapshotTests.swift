// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    import DebugDrawer
    @testable import DebugDrawerUserDefaultsPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (text fields, pickers, switches, disclosure
    // groups) as placeholders, so a test of a view holding one hosts it in a window that is never
    // shown and draws it into a bitmap at a fixed 2x scale, in the appearance the test asks for:
    // the snapshot doesn't depend on the Mac's own appearance or display. macOS doesn't scale text
    // with Dynamic Type, so the Mac pins light and dark only. The browser and editor are drawn at
    // 316 points, the width of the drawer on an iPad and the narrowest it gets.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct UserDefaultsSnapshotTests {
        // The share of pixels a hosted text-field snapshot must match: the AppKit field's host
        // sometimes measures it 2 pt short (DD-182), which moves only the field's text.
        private static let textFieldPrecision: Float = 0.99

        @Test("An unselected defaults row shows the key and the value's type", arguments: [ColorScheme.light, .dark])
        func unselectedRow(colorScheme: ColorScheme) throws {
            let entry = DefaultsEntry(key: "launchCount", value: .number(12))
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: false, onSelect: {}, onSet: { _ in }, onDelete: {})
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

        @Test(
            "A selected registered default names its domain, shows its value and why it is read-only, and offers Copy Value alone",
            arguments: [ColorScheme.light, .dark]
        )
        func readOnlyRow(colorScheme: ColorScheme) throws {
            let entry = DefaultsEntry(key: "maxUploadCount", value: .number(5), domain: .registration)
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})
            let host = NSHostingView(rootView: sut
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

        @Test("A selected string row shows the value, a field to edit it with Save, Copy Value and Delete Key", arguments: [ColorScheme.light, .dark])
        func selectedStringRow(colorScheme: ColorScheme) throws {
            let entry = DefaultsEntry(key: "username", value: .string("ada"))
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})
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

            // The AppKit text field's host sometimes measures it 2 pt short (DD-182), which moves its text.
            assertSnapshot(of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A selected Boolean row edits the value with a true or false picker", arguments: [ColorScheme.light, .dark])
        func selectedBoolRow(colorScheme: ColorScheme) throws {
            let entry = DefaultsEntry(key: "onboarding.completed", value: .bool(true))
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})
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

        @Test(
            "With an app group named, the suite picker shows it above Add Key, the menu and the group's keys with their types",
            arguments: [ColorScheme.light, .dark]
        )
        func suitePickerWithKeys(colorScheme: ColorScheme) throws {
            let suite = UserDefaultsSuite.named("group.com.example.shared")
            let entries = [
                DefaultsEntry(key: "launchCount", value: .number(3)),
                DefaultsEntry(key: "lastSync", value: .date(Date(timeIntervalSince1970: 1_800_000_000))),
                DefaultsEntry(key: "settings", value: .dictionary(["sync": .bool(true)])),
                DefaultsEntry(key: "token", value: .data(Data([0xDE, 0xAD, 0xBE, 0xEF])))
            ]
            let sut = UserDefaultsBrowserView(
                suites: [.standard, suite], selectedSuite: .constant(suite), entries: entries, keys: Set(entries.map(\.key)),
                searchText: .constant(""), showOtherDomains: .constant(false), redaction: .standard,
                actions: UserDefaultsBrowserActions(set: { _, _ in }, add: { _, _ in }, remove: { _ in }, reload: {})
            )
            let host = NSHostingView(rootView: sut
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

        @Test(
            "A selected dictionary lists its keys with their values in one line, each to drill into, then Add Key, Copy Value and Delete Key",
            arguments: [ColorScheme.light, .dark]
        )
        func nestedEditor(colorScheme: ColorScheme) throws {
            let value = PropertyListValue.dictionary([
                "theme": .dictionary(["accent": .string("orange"), "contrast": .number(1.5)]),
                "tabs": .array([.string("recent"), .string("favorites")]),
                "sync": .bool(true)
            ])
            let entry = DefaultsEntry(key: "settings", value: value)
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})
            let host = NSHostingView(rootView: sut
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
            "A selected data value shows its bytes in hex, a field to edit them and the Hex or Base64 toggle",
            arguments: [ColorScheme.light, .dark]
        )
        func dataEditor(colorScheme: ColorScheme) throws {
            let entry = DefaultsEntry(key: "avatarHash", value: .data(Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x0A])))
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})
            let host = NSHostingView(rootView: sut
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

        @Test(
            "A value inside a dictionary names its field by its path, with Save and Delete Item on one row",
            arguments: [ColorScheme.light, .dark]
        )
        func nestedValueEditor(colorScheme: ColorScheme) throws {
            let sut = PropertyListScalarEditor(value: .string("orange"), title: "settings › theme › accent", deleteItem: {}, save: { _ in })
            let host = NSHostingView(rootView: sut
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
