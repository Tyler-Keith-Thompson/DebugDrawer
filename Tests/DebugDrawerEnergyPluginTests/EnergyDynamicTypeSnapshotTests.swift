// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerEnergyPlugin

    // ImageRenderer draws UIKit-backed controls (text fields, pickers, switches) as placeholders,
    // so each view is hosted in a window that is never shown and its layer rendered, at a fixed
    // width (the drawer's 316 pt) and scale, so the reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct EnergyDynamicTypeSnapshotTests {
        @Test("The readout stays readable at the default and a large accessibility text size",
              arguments: [DynamicTypeSize.large, .accessibility3])
        func readout(size: DynamicTypeSize) throws {
            let reading = EnergyReading(
                cpuUsage: 23.4,
                cpuHistory: [4, 6, 12, 35, 80, 41, 18, 9, 22, 23.4],
                batteryLevel: 64,
                batteryHistory: [66, 66, 65, 65, 65, 64, 64],
                isCharging: false,
                powerSource: "Battery",
                thermalState: .fair
            )
            let sut = EnergyReadout(reading: reading, processorCount: 6)
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
    }
#endif
