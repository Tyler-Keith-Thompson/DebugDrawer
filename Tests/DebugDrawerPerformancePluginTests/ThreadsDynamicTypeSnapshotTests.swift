// iOS scales text with Dynamic Type, so these snapshots run on the iOS simulator.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    @testable import DebugDrawerPerformancePlugin

    // ImageRenderer draws UIKit-backed controls (text fields, pickers, switches) as placeholders,
    // so each view is hosted in a window that is never shown and its layer rendered, at a fixed
    // width (the drawer's 316 pt) and scale, so the reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ThreadsDynamicTypeSnapshotTests {
        @Test("The threads list keeps each row on one line at the default size and stacks it at an accessibility size",
              arguments: [DynamicTypeSize.large, .accessibility3])
        func threads(size: DynamicTypeSize) throws {
            let threads = [
                ThreadCPU(name: "dd54-busy", threadID: 0x1A01, cpuUsage: 0.982),
                ThreadCPU(name: "Main Thread", threadID: 0x1A00, cpuUsage: 0.214),
                ThreadCPU(name: "com.apple.uikit.eventfetch-thread", threadID: 0x1A03, cpuUsage: 0.024),
                ThreadCPU(name: "Thread 0x1a04", threadID: 0x1A04, cpuUsage: 0.008),
                ThreadCPU(name: "com.apple.CoreMotion", threadID: 0x1A09, cpuUsage: 0),
                ThreadCPU(name: "Thread 0x1a0a", threadID: 0x1A0A, cpuUsage: 0)
            ]
            let sut = ThreadsSection(threads: threads)
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

        @Test("The memory warning shows its button, when it was last posted and what it does",
              arguments: [DynamicTypeSize.large, .accessibility3])
        func memoryWarning(size: DynamicTypeSize) throws {
            // 08:03:09 UTC.
            let posted = Date(timeIntervalSince1970: 1_800_000_189)
            // A literal identifier of the IANA database, which every Apple OS ships.
            let utc = TimeZone(identifier: "UTC")!
            let sut = MemoryWarningSection(postedAt: posted) { posted }
            let controller = UIHostingController(rootView: sut
                .frame(width: 316, alignment: .leading)
                // No height proposed, as the drawer's scroll view proposes none.
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, size)
                .environment(\.timeZone, utc)
                .environment(\.locale, Locale(identifier: "en_US_POSIX")))
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
