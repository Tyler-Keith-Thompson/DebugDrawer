// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, hosted in a
    // window that is never shown and drawn into a bitmap at a fixed 2x scale, in the appearance the
    // test asks for, as FileBrowserSnapshotTests are. Sizes and dates are drawn in en_US and GMT.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FileBrowserStateSnapshotTests {
        @Test("No root holds anything: the empty state above the roots", arguments: [ColorScheme.light, .dark])
        func emptyRoots(colorScheme: ColorScheme) throws {
            let container = "/Users/me/Library/Containers/com.example.shop/Data"
            let roots = FileRoots(available: [
                FileRoot(kind: .documents, url: URL(filePath: container + "/Documents")),
                FileRoot(kind: .library, url: URL(filePath: container + "/Library")),
                FileRoot(kind: .temporary, url: URL(filePath: container + "/tmp")),
                FileRoot(kind: .bundle, url: URL(filePath: "/Applications/Shop.app"))
            ])
            let sizes: [String: Int64] = [
                container + "/Documents": 0, container + "/Library": 0, container + "/tmp": 0, "/Applications/Shop.app": 48_200_000
            ]
            let sut = FileBrowserView(screen: .roots(roots, isEmpty: true), folderSizes: sizes, actions: FileBrowserActions())
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

        @Test("A refused delete: the folder, then what failed and why", arguments: [ColorScheme.light, .dark])
        func deleteFailure(colorScheme: ColorScheme) throws {
            let documents = URL(filePath: "/Users/me/Library/Containers/com.example.shop/Data/Documents", directoryHint: .isDirectory)
            let logs = documents.appending(path: "Logs", directoryHint: .isDirectory)
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let items = [
                FileItem(url: logs.appending(path: "2026-11-16.log"), isDirectory: false, size: 18_432, modified: date, created: date),
                FileItem(url: logs.appending(path: "2026-11-17.log"), isDirectory: false, size: 4_096, modified: date, created: date)
            ]
            let contents = DirectoryContents(
                directory: FileItem(url: logs, isDirectory: true, size: 0, modified: date, created: date), items: items
            )
            let sut = FileBrowserView(
                screen: .directory(DirectoryListing(root: FileRoot(kind: .documents, url: documents), url: logs, contents: .loaded(contents))),
                folderSizes: [logs.filePath: 22_528],
                failure: FileBrowserFailure(
                    title: "Couldn't delete Logs", reason: "“Logs” couldn’t be removed because you don’t have permission to access it."
                ),
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
