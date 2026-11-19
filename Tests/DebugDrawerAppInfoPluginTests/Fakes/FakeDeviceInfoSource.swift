#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import Foundation

    /// A device the test chooses; counts its readings.
    @MainActor
    final class FakeDeviceInfoSource: DeviceInfoSource {
        var info: DeviceInfo
        private(set) var reads = 0

        init(_ info: DeviceInfo = DeviceInfo()) {
            self.info = info
        }

        func read() -> DeviceInfo {
            reads += 1
            return info
        }
    }
#endif
