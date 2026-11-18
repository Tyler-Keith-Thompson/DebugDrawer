#if DEBUG
    @testable import DebugDrawerPerformancePlugin
    import Foundation
    import Testing

    @Suite("Frame statistics")
    struct FrameStatisticsTests {
        @Test("A steady 60 Hz second is 60 fps with no frame dropped")
        func steady60() {
            let frameDuration: TimeInterval = 1.0 / 60
            let timestamps = (0 ... 60).map { TimeInterval($0) * frameDuration }
            let expected = FrameStatistics(framesPerSecond: 60, droppedFrames: 0)

            let actual = FrameStatistics(timestamps: timestamps, frameDuration: frameDuration)

            #expect(actual == expected)
        }

        @Test("A steady 120 Hz second is 120 fps with no frame dropped")
        func steady120() {
            let frameDuration: TimeInterval = 1.0 / 120
            let timestamps = (0 ... 120).map { TimeInterval($0) * frameDuration }
            let expected = FrameStatistics(framesPerSecond: 120, droppedFrames: 0)

            let actual = FrameStatistics(timestamps: timestamps, frameDuration: frameDuration)

            #expect(actual == expected)
        }

        @Test("A 500 ms gap at 60 Hz drops 29 frames and leaves 31 in the second")
        func blockedMainThread() {
            // 15 frames to 0.25 s, nothing until 0.75 s (30 periods, one frame delivered), then 15
            // frames to 1 s: 31 intervals in 1 s.
            let frameDuration: TimeInterval = 1.0 / 60
            let before = (0 ... 15).map { TimeInterval($0) * frameDuration }
            let after = (0 ... 15).map { 0.75 + TimeInterval($0) * frameDuration }
            let expected = FrameStatistics(framesPerSecond: 31, droppedFrames: 29)

            let actual = FrameStatistics(timestamps: before + after, frameDuration: frameDuration)

            #expect(actual == expected)
        }

        @Test("Display jitter under half a frame drops nothing")
        func jitter() {
            let frameDuration: TimeInterval = 1.0 / 60
            let timestamps: [TimeInterval] = [0, frameDuration * 1.4, frameDuration * 2.3, frameDuration * 3.2]
            let expected = 0

            let actual = FrameStatistics(timestamps: timestamps, frameDuration: frameDuration).droppedFrames

            #expect(actual == expected)
        }

        @Test("No timestamps are 0 fps with no frame dropped")
        func empty() {
            let expected = FrameStatistics(framesPerSecond: 0, droppedFrames: 0)

            let actual = FrameStatistics(timestamps: [], frameDuration: 1.0 / 60)

            #expect(actual == expected)
        }

        @Test("A single frame has no interval: 0 fps with no frame dropped")
        func singleFrame() {
            let expected = FrameStatistics(framesPerSecond: 0, droppedFrames: 0)

            let actual = FrameStatistics(timestamps: [12.5], frameDuration: 1.0 / 60)

            #expect(actual == expected)
        }

        @Test("An unknown frame period counts the rate but no dropped frames")
        func zeroFrameDuration() {
            let timestamps: [TimeInterval] = [0, 0.5, 1]
            let expected = FrameStatistics(framesPerSecond: 2, droppedFrames: 0)

            let actual = FrameStatistics(timestamps: timestamps, frameDuration: 0)

            #expect(actual == expected)
        }
    }
#endif
