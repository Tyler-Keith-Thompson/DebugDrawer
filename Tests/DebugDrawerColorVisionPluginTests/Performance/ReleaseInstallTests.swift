// The release stand-in. `--config=release` builds and runs only the performance targets, so this
// is where a test is compiled without DEBUG, as an app's release build is; in debug the file is
// empty, and ColorVisionInstallExitTests checks the opposite.
#if !DEBUG
    import DebugDrawerColorVisionPlugin
    import SwiftUI
    import Testing

    @Suite
    struct ReleaseInstallTests {
        @MainActor
        @Test("In release, install takes any simulation and does nothing")
        func installDoesNothing() {
            ColorVision.install()
            for simulation in ColorVision.Simulation.allCases {
                ColorVision.install(simulating: simulation)
            }
        }

        @MainActor
        @Test("In release, debugColorVision returns the view as it is")
        func modifierIsTheView() {
            let content = Text("Checkout")

            let actual = content.debugColorVision()

            #expect(type(of: actual) == Text.self)
        }
    }
#endif
