// The release stand-in. `--config=release` builds and runs only the performance targets, so this
// is where a test is compiled without DEBUG, as an app's release build is; in debug the file is
// empty, and LeakDetectorInstallExitTests checks the opposite.
#if !DEBUG && os(macOS)
    import AppKit
    import DebugDrawerLeakDetectorPlugin
    import ObjectiveC
    import Testing

    @Suite
    struct ReleaseInstallTests {
        @MainActor
        @Test("In release, install compiles and leaves viewDidDisappear as it was")
        func installExchangesNothing() {
            let selector = #selector(NSViewController.viewDidDisappear)
            let expected = class_getMethodImplementation(NSViewController.self, selector)

            LeakDetector.install()
            let actual = class_getMethodImplementation(NSViewController.self, selector)

            #expect(actual == expected)
        }

        @Test("In release, trackLifetime compiles, accepts any count and keeps nothing alive")
        func trackLifetimeDoesNothing() throws {
            final class Model {}
            var model: Model? = Model()
            weak let weakModel = model

            try LeakDetector.trackLifetime(of: model!, maxCount: 0)
            model = nil

            #expect(weakModel == nil)
        }
    }
#endif
