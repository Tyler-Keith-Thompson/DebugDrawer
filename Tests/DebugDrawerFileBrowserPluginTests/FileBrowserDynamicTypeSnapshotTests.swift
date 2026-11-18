// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, at the default
    // text size and an accessibility one. The view is hosted in a window that is never shown and
    // its layer rendered, at a fixed width and scale, as the other iOS snapshots are, since
    // ImageRenderer draws UIKit-backed controls as placeholders. Sizes and dates are drawn in en_US
    // and GMT, so they read the same anywhere.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FileBrowserDynamicTypeSnapshotTests {
        @Test("In an iPad's drawer the roots keep their titles, totals and paths readable", arguments: [DynamicTypeSize.large, .accessibility3])
        func roots(size: DynamicTypeSize) throws {
            let container = "/var/mobile/Containers/Data/Application/0A1B2C3D"
            let roots = FileRoots(
                available: [
                    FileRoot(kind: .documents, url: URL(filePath: container + "/Documents")),
                    FileRoot(kind: .library, url: URL(filePath: container + "/Library")),
                    FileRoot(kind: .temporary, url: URL(filePath: container + "/tmp")),
                    FileRoot(kind: .bundle, url: URL(filePath: "/var/containers/Bundle/Application/9F8E/Shop.app")),
                    FileRoot(kind: .appGroup("group.com.example.shop"), url: URL(filePath: "/var/mobile/Containers/Shared/AppGroup/5E6F"))
                ],
                missingAppGroups: ["group.com.example.widgets"]
            )
            let sizes: [String: Int64] = [container + "/Documents": 1_234_567, container + "/Library": 345_678, container + "/tmp": 0]
            let sut = FileRootList(roots: roots, folderSizes: sizes) { _ in }
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

        @Test("In an iPad's drawer a JSON file's facts, preview and actions stay readable", arguments: [DynamicTypeSize.large, .accessibility3])
        func jsonFile(size: DynamicTypeSize) throws {
            let documents = URL(filePath: "/var/mobile/Containers/Data/Application/0A1B2C3D/Documents", directoryHint: .isDirectory)
            let json = Data(#"{"user":{"id":42,"name":"Ada"},"features":["search","offline"],"theme":"dark"}"#.utf8)
            let item = FileItem(
                url: documents.appending(path: "Settings/config.json"), isDirectory: false, size: Int64(json.count),
                modified: Date(timeIntervalSince1970: 1_800_000_000), created: Date(timeIntervalSince1970: 1_790_000_000)
            )
            let detail = FileDetailState(
                root: FileRoot(kind: .documents, url: documents), item: item, preview: .loaded(FilePreview(data: json, isTruncated: false))
            )
            let sut = FileDetail(detail: detail, actions: FileBrowserActions())
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
