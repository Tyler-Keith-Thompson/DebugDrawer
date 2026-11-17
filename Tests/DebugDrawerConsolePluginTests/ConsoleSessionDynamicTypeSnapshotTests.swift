// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, at the default
    // text size and an accessibility one, so the session menu, its rows and Delete All Sessions are
    // seen to fit. The view is hosted in a window that is never shown and its layer rendered, at a
    // fixed width and scale, as the other iOS snapshots are, since ImageRenderer draws UIKit-backed
    // controls as placeholders. The time zone is fixed, so the session's start reads the same
    // anywhere.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleSessionDynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, Previous's session menu, rows and buttons keep whole words",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func previousSession(size: DynamicTypeSize) throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let encoder = JSONEncoder()
            let header = ConsoleSessionHeader(started: "2027-01-15T08:00:00.000Z", app: "Shop", appVersion: "2.1 (40)")
            let line = LogLine(timestamp: started.addingTimeInterval(1), text: "Checkout failed", source: .oslog, level: .error)
            let rows = try [encoder.encode(header), encoder.encode(ConsoleSessionLine(line)), Data(#"{"lev"#.utf8)]
            let data = Data(rows.joined(separator: Data("\n".utf8)))
            let newest = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: "2027-01-15T080000.000Z-6E1D3C5A-2B4F-4F7E-9A51-3C1D2E4F5A6B.jsonl", byteCount: 48_000
            )))
            let older = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: "2027-01-15T070000.000Z-9A3C5E71-4B2D-4F86-A1E9-6D7B8C0F2A35.jsonl", byteCount: 2_000
            )))
            let sut = VStack(alignment: .leading, spacing: 0) {
                ConsoleLogSourcePicker(source: .constant(.previous))
                ConsolePreviousSessionPicker(
                    sessions: [newest, older], shown: ConsoleSessionLog(summary: newest, data: data), select: { _ in }, deleteAll: {}
                )
                ConsoleToolbarView(isFollowing: .constant(true), filterLevel: .constant(.debug), copyAll: {}, clear: {}, source: .previous)
            }
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
