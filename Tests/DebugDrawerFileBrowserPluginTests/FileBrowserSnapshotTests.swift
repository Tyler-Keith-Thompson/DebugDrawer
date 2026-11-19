// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets. The views hold
    // a share link and buttons AppKit backs, which ImageRenderer draws as placeholders, so they are
    // hosted in a window that is never shown and drawn into a bitmap at a fixed 2x scale, in the
    // appearance the test asks for. macOS doesn't scale text with Dynamic Type, so the Mac pins
    // light and dark only. Sizes and dates are drawn in en_US and GMT, so they read the same
    // anywhere.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FileBrowserSnapshotTests {
        @Test("The roots: the app's folders, the bundle and an app group with paths and totals, one still counting, and a missing group",
              arguments: [ColorScheme.light, .dark])
        func roots(colorScheme: ColorScheme) throws {
            let container = "/Users/me/Library/Containers/com.example.shop/Data"
            let roots = FileRoots(
                available: [
                    FileRoot(kind: .documents, url: URL(filePath: container + "/Documents")),
                    FileRoot(kind: .library, url: URL(filePath: container + "/Library")),
                    FileRoot(kind: .temporary, url: URL(filePath: container + "/tmp")),
                    FileRoot(kind: .bundle, url: URL(filePath: "/Applications/Shop.app")),
                    FileRoot(
                        kind: .appGroup("group.com.example.shop"),
                        url: URL(filePath: "/Users/me/Library/Group Containers/group.com.example.shop")
                    )
                ],
                missingAppGroups: ["group.com.example.widgets"]
            )
            let sizes: [String: Int64] = [
                container + "/Documents": 1_234_567, container + "/Library": 345_678, "/Applications/Shop.app": 48_200_000,
                "/Users/me/Library/Group Containers/group.com.example.shop": 8_192
            ]
            let sut = FileRootList(roots: roots, folderSizes: sizes) { _ in }
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, .gmt)
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

        @Test("A JSON file: kind, size and dates, its preview pretty-printed, and its actions", arguments: [ColorScheme.light, .dark])
        func jsonFile(colorScheme: ColorScheme) throws {
            let documents = URL(filePath: "/Users/me/Library/Containers/com.example.shop/Data/Documents", directoryHint: .isDirectory)
            let json = Data(#"{"user":{"id":42,"name":"Ada"},"features":["search","offline"],"theme":"dark","version":3}"#.utf8)
            let item = FileItem(
                url: documents.appending(path: "Settings/config.json"), isDirectory: false, size: Int64(json.count),
                modified: Date(timeIntervalSince1970: 1_800_000_000), created: Date(timeIntervalSince1970: 1_790_000_000)
            )
            let detail = FileDetailState(
                root: FileRoot(kind: .documents, url: documents), item: item,
                preview: .loaded(FilePreview(data: json, isTruncated: false))
            )
            let sut = FileDetail(detail: detail, actions: FileBrowserActions())
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, .gmt)
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

        @Test("A binary property list in the bundle: shown as XML, read-only, with no Rename or Delete", arguments: [ColorScheme.light, .dark])
        func bundlePropertyList(colorScheme: ColorScheme) throws {
            let bundle = URL(filePath: "/Applications/Shop.app", directoryHint: .isDirectory)
            let plist = try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": "com.example.shop", "CFBundleShortVersionString": "2.1", "LSRequiresIPhoneOS": true],
                format: .binary, options: 0
            )
            let item = FileItem(
                url: bundle.appending(path: "Contents/Info.plist"), isDirectory: false, size: Int64(plist.count),
                modified: Date(timeIntervalSince1970: 1_800_000_000), created: nil
            )
            let detail = FileDetailState(
                root: FileRoot(kind: .bundle, url: bundle), item: item, preview: .loaded(FilePreview(data: plist, isTruncated: false))
            )
            let sut = FileDetail(detail: detail, actions: FileBrowserActions())
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, .gmt)
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

        @Test("A folder: its total, item count and dates, its folders and files with sizes, and Refresh and More on one line",
              arguments: [ColorScheme.light, .dark])
        func folder(colorScheme: ColorScheme) throws {
            let documents = URL(filePath: "/Users/me/Library/Containers/com.example.shop/Data/Documents", directoryHint: .isDirectory)
            let exports = documents.appending(path: "Exports", directoryHint: .isDirectory)
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let items = [
                FileItem(
                    url: exports.appending(path: "2026", directoryHint: .isDirectory), isDirectory: true, size: 0, modified: date, created: date
                ),
                FileItem(url: exports.appending(path: "orders.sqlite"), isDirectory: false, size: 98_304, modified: date, created: date),
                FileItem(url: exports.appending(path: "photo.png"), isDirectory: false, size: 3_145_728, modified: date, created: date),
                FileItem(url: exports.appending(path: "report.json"), isDirectory: false, size: 2_048, modified: date, created: date)
            ]
            let contents = DirectoryContents(
                directory: FileItem(url: exports, isDirectory: true, size: 0, modified: date, created: date.addingTimeInterval(-86_400)),
                items: items
            )
            let sut = DirectoryView(
                listing: DirectoryListing(root: FileRoot(kind: .documents, url: documents), url: exports, contents: .loaded(contents)),
                folderSizes: [items[0].path: 512_000, exports.filePath: 3_758_080],
                actions: FileBrowserActions()
            )
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, .gmt)
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

            // A hosted AppKit text field (the filter) may lay out a point or two apart from run to
            // run (DD-182), so 99% of the pixels must match rather than all of them.
            assertSnapshot(of: actual, as: .image(precision: 0.99, perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
