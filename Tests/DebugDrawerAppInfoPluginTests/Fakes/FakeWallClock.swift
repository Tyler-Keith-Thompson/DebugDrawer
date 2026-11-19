#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import Foundation

    /// A wall clock the test moves by hand.
    final class FakeWallClock: WallClock {
        var now: Date

        init(_ now: Date) {
            self.now = now
        }
    }
#endif
