// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerUserDefaultsPlugin

    // The rows, the browser and the nested editor hold menus, pickers, switches and text fields,
    // which ImageRenderer draws as placeholders, so each view is hosted in a window that is never
    // shown and its layer rendered, at a fixed scale and 316 points, the width of the drawer on an
    // iPad and the narrowest it gets, at the default text size and an accessibility one.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct UserDefaultsDynamicTypeSnapshotTests {
        @Test("An unselected defaults row stays readable at a large accessibility text size")
        func unselectedRow() throws {
            let entry = DefaultsEntry(key: "launchCount", value: .number(12))
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: false, onSelect: {}, onSet: { _ in }, onDelete: {})
            let controller = UIHostingController(rootView: sut
                .frame(width: 320, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 352, height: 8000))
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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test(
            "A selected registered default, its domain and why it is read-only stay readable at the default and an accessibility text size",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func readOnlyRow(size: DynamicTypeSize) throws {
            let entry = DefaultsEntry(key: "maxUploadCount", value: .number(5), domain: .registration)
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})
            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, size))
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let measured = controller.sizeThatFits(in: CGSize(width: 348, height: 8000))
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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(size)")
        }

        @Test("A selected string row, its field and Save stay readable at a large accessibility text size")
        func selectedStringRow() throws {
            let entry = DefaultsEntry(key: "username", value: .string("ada"))
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})
            // The edit field is a text field, which ImageRenderer draws as a placeholder, so the
            // row is hosted like the browser below.
            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, .accessibility3))
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

            // A hosted text field draws a few pixels differently from run to run (DD-182), so 99%
            // of the pixels must match rather than all of them.
            assertSnapshot(of: actual, as: .image(precision: 0.99, perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("A selected Boolean row and its true and false control stay readable at a large accessibility text size")
        func selectedBoolRow() throws {
            let entry = DefaultsEntry(key: "onboarding.completed", value: .bool(true))
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})
            // The segmented control is UIKit's, which ImageRenderer draws as a placeholder, so the
            // row is hosted like the browser below.
            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, .accessibility3))
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

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test(
            "In an iPad's drawer, the suite picker, Add Key, the menu and the keys keep whole words",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func suitePickerWithKeys(size: DynamicTypeSize) throws {
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

        @Test(
            "In an iPad's drawer, a selected dictionary's keys, values and actions keep whole words",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func nestedEditor(size: DynamicTypeSize) throws {
            let value = PropertyListValue.dictionary([
                "theme": .dictionary(["accent": .string("orange"), "contrast": .number(1.5)]),
                "tabs": .array([.string("recent"), .string("favorites")]),
                "sync": .bool(true)
            ])
            let entry = DefaultsEntry(key: "settings", value: value)
            let sut = DefaultsEntryRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onSet: { _ in }, onDelete: {})
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
