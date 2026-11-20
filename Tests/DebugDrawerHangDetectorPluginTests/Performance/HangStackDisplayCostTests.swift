// What the drawer pays to show a hang: its stack's lines read into frames and their Swift symbols
// demangled, as HangRow draws them. The drawer exists in debug builds only, so it is measured there;
// `--config=release` builds this target without it, and runs ReleaseInstallTests instead. The
// monitor's own costs are measured in DebugDrawerHangDetectorTests, in both builds.
#if DEBUG
    @testable import DebugDrawerHangDetectorPlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct HangStackDisplayCostTests {
        @Test("Reading and demangling a full stack of 128 frames takes under 250 ms")
        func fullStack() {
            let lines = (0 ..< 128).map { index in
                "\(index) Example 0x\(String(0x1_0000_4A1C + index * 16, radix: 16)) $s7Example5crashyyF + \(index)"
            }
            let demangler = _SymbolDemangler()
            let clock = ContinuousClock()

            let elapsed = clock.measure {
                _ = StackFrame.frames(lines).map { $0.demangled(by: demangler) }
            }

            print("Hang detector: showing a 128-frame stack costs \(elapsed)")
            #expect(elapsed < .milliseconds(250))
        }
    }
#endif
