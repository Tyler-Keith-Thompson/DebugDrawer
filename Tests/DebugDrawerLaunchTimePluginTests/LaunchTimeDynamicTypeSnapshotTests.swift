// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerLaunchTimePlugin

    // ImageRenderer draws UIKit-backed controls (text fields, pickers, switches) as placeholders,
    // so each view is hosted in a window that is never shown and its layer rendered, at a fixed
    // width and scale, so the reference doesn't depend on which simulator runs it.
    /// A clock that reads out the uptimes it is given, one a read.
    private final class FakeClock: UptimeClock {
        private var uptimes: [TimeInterval]
        init(_ uptimes: [TimeInterval]) { self.uptimes = uptimes }
        var uptime: TimeInterval { uptimes.removeFirst() }
    }

    /// A process that started at `uptime`.
    private struct FakeProcessStart: ProcessStartReader {
        let uptime: TimeInterval?
        func processStartUptime() -> TimeInterval? { uptime }
    }

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LaunchTimeDynamicTypeSnapshotTests {
        @Test("The measured launch time stays readable at a large accessibility text size")
        func measured() throws {
            // Process start at 100.0 s of uptime, install at 100.4 s, first frame at 100.9 s.
            let model = LaunchTimeModel(clock: FakeClock([100.4, 100.9]), processStart: FakeProcessStart(uptime: 100.0))
            model.perform(LaunchTimeCommand(.recordFirstFrame))
            let sut = LaunchTimePluginView(transport: .direct(to: model))
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

        @Test("The still-measuring message stays readable at a large accessibility text size")
        func measuring() throws {
            let model = LaunchTimeModel(clock: FakeClock([100.4]), processStart: FakeProcessStart(uptime: 100.0))
            let sut = LaunchTimePluginView(transport: .direct(to: model))
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
