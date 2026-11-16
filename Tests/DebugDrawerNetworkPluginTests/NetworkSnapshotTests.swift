// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerNetworkPlugin

    // ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the
    // test asks for, so a snapshot doesn't depend on the Mac's own appearance or display. macOS
    // doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkSnapshotTests {
        @Test("Request rows show the method, status or progress, path and duration", arguments: [ColorScheme.light, .dark])
        func rows(colorScheme: ColorScheme) throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let entries = [
                NetworkEntry(
                    timestamp: start, method: "GET", url: "https://api.example.com/v1/users?page=2",
                    host: "api.example.com", path: "/v1/users", requestHeaders: [:], requestBody: nil,
                    statusCode: 200, duration: 0.142, isComplete: true
                ),
                NetworkEntry(
                    timestamp: start, method: "POST", url: "https://api.example.com/v1/orders",
                    host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: nil,
                    statusCode: 422, duration: 1.25, isComplete: true
                ),
                NetworkEntry(
                    timestamp: start, method: "DELETE", url: "https://api.example.com/v1/orders/7",
                    host: "api.example.com", path: "/v1/orders/7", requestHeaders: [:], requestBody: nil,
                    duration: 0.05, error: "The network connection was lost.", isComplete: true
                )
            ]
            let sut = VStack(spacing: 0) {
                ForEach(entries) { entry in
                    NetworkRequestRow(entry: entry, isSelected: false, onSelect: {})
                }
            }
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test(
            "A selected request shows its URL, time, size and status, then its query, timing, headers and body collapsed",
            arguments: [ColorScheme.light, .dark]
        )
        func selectedRow(colorScheme: ColorScheme) throws {
            let metrics = NetworkTimingMetrics(
                phases: [
                    .init(kind: .dns, start: 0, duration: 0.012),
                    .init(kind: .connect, start: 0.012, duration: 0.03),
                    .init(kind: .tls, start: 0.02, duration: 0.022),
                    .init(kind: .request, start: 0.042, duration: 0.001),
                    .init(kind: .timeToFirstByte, start: 0.043, duration: 0.08),
                    .init(kind: .response, start: 0.123, duration: 0.019)
                ],
                protocolName: "h2", isReusedConnection: false, isCacheHit: false
            )
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET",
                url: "https://api.example.com/v1/users?page=2", host: "api.example.com", path: "/v1/users",
                requestHeaders: ["Accept": "application/json"], requestBody: nil,
                statusCode: 200, responseHeaders: ["Content-Type": "application/json"],
                responseBody: Data(#"{"users":[{"name":"Ada"}]}"#.utf8), duration: 0.142, isComplete: true,
                metrics: metrics
            )
            let sut = NetworkRequestRow(entry: entry, isSelected: true, onSelect: {})
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("The timing waterfall shows each phase's bar and duration, then the protocol", arguments: [ColorScheme.light, .dark])
        func timing(colorScheme: ColorScheme) throws {
            let metrics = NetworkTimingMetrics(
                phases: [
                    .init(kind: .dns, start: 0, duration: 0.012),
                    .init(kind: .connect, start: 0.012, duration: 0.03),
                    .init(kind: .tls, start: 0.02, duration: 0.022),
                    .init(kind: .request, start: 0.042, duration: 0.001),
                    .init(kind: .timeToFirstByte, start: 0.043, duration: 0.08),
                    .init(kind: .response, start: 0.123, duration: 0.019)
                ],
                protocolName: "h2", isReusedConnection: false, isCacheHit: false
            )
            let sut = NetworkTimingView(metrics: metrics)
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
