#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import Foundation

    /// A bundle the test chooses; counts its readings.
    final class FakeBundleInfoSource: BundleInfoSource {
        var info: BundleInfo
        private(set) var reads = 0

        init(_ info: BundleInfo = BundleInfo()) {
            self.info = info
        }

        func read() -> BundleInfo {
            reads += 1
            return info
        }
    }
#endif
