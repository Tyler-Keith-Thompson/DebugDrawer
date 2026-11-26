#if DEBUG
    import DebugDrawerLeakDetectorPlugin
    import Foundation
    import Testing

    // In-process: a limit below one is refused before the detector counts anything, so nothing here
    // changes the process.
    @Suite
    struct LeakDetectorTrackingValidationTests {
        @Test("A limit of zero throws InvalidMaxCount")
        func zeroLimit() {
            let maxCount = 0

            #expect(throws: LeakDetector.InvalidMaxCount.self) {
                try LeakDetector.trackLifetime(of: NSObject(), maxCount: maxCount)
            }
        }

        @Test("A negative limit throws InvalidMaxCount")
        func negativeLimit() {
            let maxCount = -1

            #expect(throws: LeakDetector.InvalidMaxCount.self) {
                try LeakDetector.trackLifetime(of: NSObject(), maxCount: maxCount)
            }
        }
    }
#endif
