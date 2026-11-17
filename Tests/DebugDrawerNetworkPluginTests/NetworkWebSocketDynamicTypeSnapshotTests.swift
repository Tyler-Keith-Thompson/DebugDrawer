// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawerNetworkPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, at the default
    // text size and an accessibility one, so a connection's row and its frames are seen to fit
    // there. The view is hosted in a window that is never shown and its layer rendered, at a fixed
    // width and scale, as the other iOS snapshots are.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkWebSocketDynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, a connection's row and detail keep the state, path, frame times, sizes and previews readable",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func connection(size: DynamicTypeSize) {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            var connection = NetworkWebSocketConnection(url: "wss://chat.example.com/v1/room?token=secret", protocols: ["chat"], opened: start)
            let frames = [
                NetworkWebSocketFrame(
                    direction: .sent, kind: .text, payload: Data(#"{"type":"join","token":"abc123"}"#.utf8),
                    timestamp: start + 0.120
                ),
                NetworkWebSocketFrame(
                    direction: .received, kind: .text, payload: Data(#"{"type":"joined","room":"general"}"#.utf8),
                    timestamp: start + 0.184
                ),
                NetworkWebSocketFrame(direction: .sent, kind: .binary, payload: Data(0 ..< 40), timestamp: start + 1.002),
                NetworkWebSocketFrame(direction: .sent, kind: .ping, timestamp: start + 2)
            ]
            for frame in frames {
                connection.record(frame, capacity: 500)
            }
            connection.end(.closed(NetworkWebSocketClose(side: .server, code: 1001, reason: "Server restarting", timestamp: start + 3)))
            let sut = NetworkWebSocketRow(connection: connection, redaction: .standard, isSelected: true, onSelect: {})
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt)

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
