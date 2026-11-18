// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerKeychainPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, at the default
    // text size and an accessibility one, so the list, an open password, an open certificate and
    // the form are seen to fit there. Each view is hosted in a window that is never shown and its
    // layer rendered, at a fixed width and scale, as the other iOS snapshots are.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct KeychainDynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, the list filtered to one group keeps the menu, the field and each row readable",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func listWithGroupFilter(size: DynamicTypeSize) {
            var filter = KeychainFilter(accessGroup: "TEAMID.com.example.app")
            let sut = KeychainListView(
                items: [KeychainFixtures.password, KeychainFixtures.certificate, KeychainFixtures.key],
                accessGroups: ["TEAMID.com.example.app", "TEAMID.com.example.shared"],
                filter: Binding(get: { filter }, set: { filter = $0 }), selection: nil, failure: nil, issue: nil,
                redaction: .standard, actions: KeychainListActions()
            )

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.locale, Locale(identifier: "en_US"))
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

        @Test("In an iPad's drawer, an open password keeps its attributes and actions readable", arguments: [DynamicTypeSize.large, .accessibility3])
        func passwordDetail(size: DynamicTypeSize) {
            let selection = KeychainSelection(item: KeychainFixtures.password, value: .success(Data("s3cr3t-token".utf8)))
            let sut = KeychainRow(item: KeychainFixtures.password, detail: selection, redaction: .standard, onSelect: {}, onEdit: {}, onDelete: {})

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.locale, Locale(identifier: "en_US"))
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

        @Test("In an iPad's drawer, an open certificate keeps its attributes readable", arguments: [DynamicTypeSize.large, .accessibility3])
        func certificateDetail(size: DynamicTypeSize) {
            let selection = KeychainSelection(item: KeychainFixtures.certificate, value: .success(nil))
            let sut = KeychainRow(item: KeychainFixtures.certificate, detail: selection, redaction: .standard, onSelect: {}, onDelete: {})

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.locale, Locale(identifier: "en_US"))
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

        @Test("In an iPad's drawer, the add form keeps every field and its actions readable", arguments: [DynamicTypeSize.large, .accessibility3])
        func addForm(size: DynamicTypeSize) {
            let draft = GenericPassword(
                service: "com.example.App", account: "ada@example.com", value: "s3cr3t", accessGroup: "TEAMID.com.example.shared"
            )
            let sut = KeychainPasswordForm(
                editor: .adding(draft), accessGroups: ["TEAMID.com.example.app", "TEAMID.com.example.shared"], issue: nil, save: { _ in }, cancel: {}
            )

            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.locale, Locale(identifier: "en_US"))
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
