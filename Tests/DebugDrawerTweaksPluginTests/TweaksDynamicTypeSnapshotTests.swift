// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerTweaksPlugin

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct TweaksDynamicTypeSnapshotTests {
        @Test("The tweaks stay readable at a large accessibility text size, titles above pickers and fields")
        func changed() {
            let sections = [
                TweakSection("Features") {
                    Tweak.toggle("New checkout", key: "newCheckout", default: false)
                    Tweak.text("Greeting", key: "greeting", default: "Welcome")
                },
                TweakSection("Server") {
                    Tweak.picker("Server", key: "server", default: Server.production)
                    Tweak.stepper("Timeout (s)", key: "timeout", default: 30, in: 5 ... 120, step: 5)
                },
                TweakSection("Session") {
                    TweakAction("Expire token") {}
                }
            ]
            let stored: [String: TweakStoredValue] = ["newCheckout": .bool(true), "server": .string("staging")]
            let sut = TweaksView(
                sections: sections.map { TweakSectionState($0, stored: { stored[$0] }) },
                onChange: { _, _ in },
                onReset: { _ in },
                onResetAll: {}
            )
            .frame(width: 320, alignment: .leading)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility3)
            // ImageRenderer draws UIKit-backed controls (the switch, text field, picker and stepper)
            // as placeholders, so the view is hosted in a window that is never shown and its layer
            // is rendered, at a fixed width and scale.
            let controller = UIHostingController(rootView: sut)
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 4000))
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
    }
#endif
