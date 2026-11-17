// iOS scales text with Dynamic Type, so these snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerPerformancePlugin

    // ImageRenderer draws the view without a window, at a fixed scale and the drawer's 316 pt
    // width, so the reference doesn't depend on which simulator runs it.
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
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, size))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

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
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, size)
                .environment(\.timeZone, utc)
                .environment(\.locale, Locale(identifier: "en_US_POSIX")))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(size)")
        }
    }
#endif
