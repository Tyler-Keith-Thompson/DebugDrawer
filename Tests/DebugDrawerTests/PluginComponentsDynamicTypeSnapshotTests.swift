// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it. It draws UIKit-backed controls (text
    // fields, bordered buttons) as placeholders, so a view holding one is hosted in a window that
    // is never shown and its layer is rendered, at a fixed width and scale.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PluginComponentsDynamicTypeSnapshotTests {
        @Test("Key-value rows put each label above its value at a large accessibility text size")
        func keyValueRows() throws {
            let sut = VStack(alignment: .leading, spacing: 6) {
                DebugDrawerKeyValueRow("Version", value: "1.4.2 (88)")
                DebugDrawerKeyValueRow("Bundle ID", value: "com.example.orders")
                DebugDrawerKeyValueRow("Token", value: "t0k3n", redacted: DebugDrawerRedaction.mask)
            }
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("Stat badges stay readable at a large accessibility text size")
        func statBadges() throws {
            let sut = HStack(spacing: 12) {
                DebugDrawerStatBadge("Total", value: "12")
                DebugDrawerStatBadge("Min", value: "41", color: .red)
                DebugDrawerStatBadge("Peak", value: "182", color: .blue)
            }
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("A sparkline keeps its height at a large accessibility text size")
        func sparkline() throws {
            let samples: [Double] = [60, 60, 58, 41, 59, 60, 30, 55, 60, 60, 60, 57]
            let sut = DebugDrawerSparkline("Frame rate history", data: samples, color: .green)
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("A copy button grows with the text at a large accessibility text size")
        func copyButton() {
            let sut = DebugDrawerCopyButton("Copy Value") { "value" }
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, .accessibility3)
            let controller = UIHostingController(rootView: sut)
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 2000))
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

        @Test("A searchable list's field and rows stay readable at a large accessibility text size")
        func searchableList() {
            let sut = DebugDrawerSearchableList("Filter...", text: .constant(""), accessibilityLabel: "Filter keys") {
                ForEach(["apiBaseURL", "hasOnboarded", "lastSyncDate"], id: \.self) { key in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(key)
                            .font(.system(.caption2, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                        Divider()
                    }
                }
            }
            .frame(width: 320, alignment: .leading)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility3)
            let controller = UIHostingController(rootView: sut)
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 2000))
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
