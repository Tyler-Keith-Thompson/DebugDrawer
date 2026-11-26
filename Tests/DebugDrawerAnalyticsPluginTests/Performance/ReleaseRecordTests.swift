// The release stand-in. `--config=release` builds and runs only the performance targets, so this
// is where a test is compiled without DEBUG, as an app's release build is; in debug the file is
// empty, and AnalyticsInstallExitTests checks the opposite.
#if !DEBUG
    import DebugDrawerAnalyticsPlugin
    import Foundation
    import Testing

    @Suite
    struct ReleaseRecordTests {
        @MainActor
        @Test("In release, install and record compile and keep nothing: record doesn't even evaluate its arguments")
        func recordKeepsNothing() throws {
            var evaluations = 0
            func name() -> String {
                evaluations += 1
                return "checkout_completed"
            }
            func properties() -> [String: AnalyticsValue] {
                evaluations += 1
                return ["plan": "pro", "seats": 3, "total": 29.99, "trial": false, "coupon": nil, "items": ["sku-1"], "shipping": ["country": "NZ"]]
            }
            func source() -> String? {
                evaluations += 1
                return "Segment"
            }

            try AnalyticsEvents.install(capacity: 10)
            for _ in 0 ..< 100 {
                AnalyticsEvents.record(name(), properties: properties(), source: source())
            }

            #expect(evaluations == 0)
        }
    }
#endif
