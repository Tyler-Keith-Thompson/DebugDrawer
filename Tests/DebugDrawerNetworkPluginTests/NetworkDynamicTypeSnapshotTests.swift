// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerNetworkPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkDynamicTypeSnapshotTests {
        @Test("Request rows stay readable at a large accessibility text size")
        func rows() throws {
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
                    NetworkRequestRow(entry: entry, redaction: .standard, isSelected: false, onSelect: {})
                }
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

        @Test("A selected request stays readable at a large accessibility text size")
        func selectedRow() throws {
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
            let sut = NetworkRequestRow(entry: entry, redaction: .standard, isSelected: true, onSelect: {})
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("The timing waterfall stays readable at a large accessibility text size")
        func timing() throws {
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
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }
    }
#endif
