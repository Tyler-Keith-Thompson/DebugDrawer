// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // ImageRenderer draws UIKit-backed controls (the switches, pickers and text fields) as
    // placeholders, so each view is hosted in a window that is never shown and its layer is
    // rendered, at a fixed width and scale.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkConditionDynamicTypeSnapshotTests {
        @Test("The Conditions section stays readable at an accessibility text size: each switch above its summary, the lines wrapping")
        func conditionsSection() throws {
            let threeG = NetworkConditionProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                name: "3G", host: .exact("api.example.com"), latency: .milliseconds(100), bandwidth: 97500
            )
            let offline = NetworkConditionProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID(),
                name: "Payments offline", host: .wildcard("*.payments.example.com"), failureRate: 100, failure: .notConnectedToInternet
            )
            let sut = NetworkConditionsSection(
                profiles: [threeG, offline], issue: nil, selected: .constant(offline.id),
                setEnabled: { _, _ in }, add: {}, edit: { _ in }, move: { _, _ in }, delete: { _ in }
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: 320, alignment: .leading)
            // No height proposed, as the drawer's scroll view proposes none.
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility3)
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 8000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let actual = UIGraphicsImageRenderer(size: size, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("The editor stays readable at an accessibility text size: each choice a menu, each number beside its unit")
        func editor() throws {
            let profile = NetworkConditionProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                name: "Slow API", host: .exact("api.example.com"), latency: .milliseconds(2000), bandwidth: 50000, failureRate: 10,
                failure: .internalServerError
            )
            let sut = NetworkConditionEditor(draft: NetworkConditionDraft(profile, isNew: false), cancel: {}, save: { _ in })
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 320, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, .accessibility3)
            let controller = UIHostingController(rootView: sut)
            controller.safeAreaRegions = []
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 8000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let actual = UIGraphicsImageRenderer(size: size, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("A conditioned, mocked request at an accessibility text size: both badges on a line of their own")
        func conditionedRow() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET",
                url: "https://api.example.com/v1/greeting", host: "api.example.com", path: "/v1/greeting",
                requestHeaders: [:], requestBody: nil, statusCode: 200, responseHeaders: ["Content-Type": "application/json"],
                responseBody: Data(#"{"message":"Hello"}"#.utf8), duration: 2.004, isComplete: true, mockRuleName: "Greeting",
                conditionEffect: NetworkConditionEffect(profileName: "Slow API", latency: .milliseconds(2000), bandwidth: nil, failure: nil)
            )
            let sut = NetworkRequestRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {}, onMock: { _ in })
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
    }
#endif
