// What turning a simulation on costs the first time. The plugin exists in debug builds only, so it
// is measured there; `--config=release` builds this target without it, and runs
// ReleaseInstallTests instead.
#if DEBUG
    @testable import DebugDrawerColorVisionPlugin
    import SwiftUI
    import Testing

    // The first simulation turned on decodes the precompiled library and has SwiftUI build its
    // pipeline with the shader stitched in, on the main actor, while the app waits for the frame.
    // Decoding the library and drawing a 13-inch iPad's screen (1032 by 1376 points at @2x) once
    // under each simulation takes about 45 ms on an Apple silicon Mac in a debug build. The
    // bound is several times that, so a loaded machine passes, and a change that rebuilds the
    // library or the pipeline on every frame fails.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ShaderFirstFrameTests {
        @Test("Decoding the library and drawing the first iPad-sized frame under each simulation takes under 300 ms")
        func firstFrame() throws {
            let clock = ContinuousClock()
            let bound = Duration.milliseconds(300)
            let content = LinearGradient(colors: [.red, .green, .blue], startPoint: .leading, endPoint: .trailing)
                .frame(width: 1032, height: 1376)

            var frames = 0
            let actual = try clock.measure {
                for simulation in ColorVision.Simulation.allCases {
                    let renderer = ImageRenderer(content: content.colorVisionSimulation(simulation))
                    renderer.scale = 2
                    _ = try #require(renderer.cgImage)
                    frames += 1
                }
            }

            #expect(frames == ColorVision.Simulation.allCases.count)
            #expect(actual < bound, "took \(actual)")
        }
    }
#endif
