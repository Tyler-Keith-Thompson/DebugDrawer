// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // At 316 points, the width of the drawer on an iPad, at the default text size and an
    // accessibility one, hosted and rendered as FileBrowserDynamicTypeSnapshotTests are. Sizes and
    // dates are drawn in en_US and GMT.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FileBrowserStateDynamicTypeSnapshotTests {
        @Test("In an iPad's drawer a folder's facts, items and actions stay readable", arguments: [DynamicTypeSize.large, .accessibility3])
        func folder(size: DynamicTypeSize) throws {
            let documents = URL(filePath: "/var/mobile/Containers/Data/Application/0A1B2C3D/Documents", directoryHint: .isDirectory)
            let exports = documents.appending(path: "Exports", directoryHint: .isDirectory)
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let items = [
                FileItem(
                    url: exports.appending(path: "2026", directoryHint: .isDirectory), isDirectory: true, size: 0, modified: date, created: date
                ),
                FileItem(url: exports.appending(path: "orders.sqlite"), isDirectory: false, size: 98_304, modified: date, created: date),
                FileItem(url: exports.appending(path: "report.json"), isDirectory: false, size: 2_048, modified: date, created: date)
            ]
            let contents = DirectoryContents(
                directory: FileItem(url: exports, isDirectory: true, size: 0, modified: date, created: date.addingTimeInterval(-86_400)),
                items: items
            )
            let sut = DirectoryView(
                listing: DirectoryListing(root: FileRoot(kind: .documents, url: documents), url: exports, contents: .loaded(contents)),
                folderSizes: [items[0].path: 512_000, exports.filePath: 612_352],
                actions: FileBrowserActions()
            )
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, .gmt)
            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, size))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 316, height: 8000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: measured)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2

            let actual = UIGraphicsImageRenderer(size: measured, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: size == .large ? "large" : "accessibility3")
        }

        @Test("In an iPad's drawer the empty state and the roots under it stay readable", arguments: [DynamicTypeSize.large, .accessibility3])
        func emptyRoots(size: DynamicTypeSize) throws {
            let container = "/var/mobile/Containers/Data/Application/0A1B2C3D"
            let roots = FileRoots(available: [
                FileRoot(kind: .documents, url: URL(filePath: container + "/Documents")),
                FileRoot(kind: .library, url: URL(filePath: container + "/Library")),
                FileRoot(kind: .temporary, url: URL(filePath: container + "/tmp")),
                FileRoot(kind: .bundle, url: URL(filePath: "/var/containers/Bundle/Application/9F8E/Shop.app"))
            ])
            let sizes: [String: Int64] = [
                container + "/Documents": 0, container + "/Library": 0, container + "/tmp": 0,
                "/var/containers/Bundle/Application/9F8E/Shop.app": 48_200_000
            ]
            let sut = FileBrowserView(screen: .roots(roots, isEmpty: true), folderSizes: sizes, actions: FileBrowserActions())
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, .gmt)
            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, size))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 316, height: 8000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: measured)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2

            let actual = UIGraphicsImageRenderer(size: measured, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: size == .large ? "large" : "accessibility3")
        }

        @Test("In an iPad's drawer a refused delete says what failed and why, readably", arguments: [DynamicTypeSize.large, .accessibility3])
        func deleteFailure(size: DynamicTypeSize) throws {
            let documents = URL(filePath: "/var/mobile/Containers/Data/Application/0A1B2C3D/Documents", directoryHint: .isDirectory)
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
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, .gmt)
            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, size))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 316, height: 8000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: measured)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2

            let actual = UIGraphicsImageRenderer(size: measured, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: size == .large ? "large" : "accessibility3")
        }
    }
#endif
