// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// A form state the open results add: each result an opened URL can have, and no presets.
    enum DeepLinkOpenState: String, CaseIterable, Sendable {
        case handled
        case notHandled
        case couldNotOpen
        case noPresets
    }

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, at the default
    // text size and an accessibility one, hosted in a window that is never shown and its layer
    // rendered at a fixed width and scale, as DeepLinkDynamicTypeSnapshotTests does.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DeepLinkResultDynamicTypeSnapshotTests {
        // The share of pixels a hosted text-field snapshot must match: a hosted text field draws a
        // few pixels differently from run to run (DD-182).
        private static let textFieldPrecision: Float = 0.99

        @Test(
            "In an iPad's drawer: after an open, the result row says handled, not handled or the system's error; with no presets, how to add them",
            arguments: DeepLinkOpenState.allCases, [DynamicTypeSize.large, .accessibility3]
        )
        func results(state: DeepLinkOpenState, size: DynamicTypeSize) throws {
            let url = "debugdrawer-example://orders/42"
            let presets = try [DeepLinkPreset("DebugDrawer Example", url: #require(URL(string: "debugdrawer-example://")))]
            let outcome: DeepLinkOutcome? = switch state {
            case .handled: .handled(url)
            case .notHandled: .notHandled(url)
            case .couldNotOpen: .couldNotOpen(url, reason: "no installed app opens debugdrawer-example: URLs")
            case .noPresets: nil
            }
            let sut = DeepLinkForm(
                urlText: .constant(state == .noPresets ? "" : url),
                outcome: outcome,
                presets: state == .noPresets ? [] : presets,
                history: state == .noPresets ? [] : [url],
                onOpen: { _ in },
                onContinue: { _ in },
                onClear: {}
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

            // A hosted text field draws a few pixels differently from run to run (DD-182).
            assertSnapshot(
                of: actual, as: .image(precision: Self.textFieldPrecision, perceptualPrecision: 0.98),
                named: "\(state.rawValue)-\(size == .large ? "large" : "accessibility3")"
            )
        }
    }
#endif
