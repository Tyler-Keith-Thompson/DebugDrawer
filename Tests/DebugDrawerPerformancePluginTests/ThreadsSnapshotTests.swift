// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerPerformancePlugin

    // ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the
    // test asks for, at the drawer's 316 pt width. macOS doesn't scale text with Dynamic Type, so
    // the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ThreadsSnapshotTests {
        @Test("The threads list shows the busiest eight, names in monospaced type and shares right-aligned, then counts the rest",
              arguments: [ColorScheme.light, .dark])
        func threads(colorScheme: ColorScheme) throws {
            let threads = [
                ThreadCPU(name: "dd54-busy", threadID: 0x1A01, cpuUsage: 0.982),
                ThreadCPU(name: "Main Thread", threadID: 0x1A00, cpuUsage: 0.214),
                ThreadCPU(name: "com.apple.NSURLSession-work", threadID: 0x1A02, cpuUsage: 0.061),
                ThreadCPU(name: "com.apple.uikit.eventfetch-thread", threadID: 0x1A03, cpuUsage: 0.024),
                ThreadCPU(name: "Thread 0x1a04", threadID: 0x1A04, cpuUsage: 0.008),
                ThreadCPU(name: "com.apple.CFNetwork.CustomProtocols", threadID: 0x1A05, cpuUsage: 0.003),
                ThreadCPU(name: "Thread 0x1a06", threadID: 0x1A06, cpuUsage: 0.001),
                ThreadCPU(name: "Thread 0x1a07", threadID: 0x1A07, cpuUsage: 0.001),
                ThreadCPU(name: "Thread 0x1a08", threadID: 0x1A08, cpuUsage: 0.001),
                ThreadCPU(name: "com.apple.CoreMotion", threadID: 0x1A09, cpuUsage: 0),
                ThreadCPU(name: "Thread 0x1a0a", threadID: 0x1A0A, cpuUsage: 0)
            ]
            let sut = ThreadsSection(threads: threads)
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
