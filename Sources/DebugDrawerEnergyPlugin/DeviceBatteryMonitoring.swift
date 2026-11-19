#if DEBUG && os(iOS)
    import UIKit

    /// `UIDevice`'s battery-monitoring setting.
    @MainActor
    final class DeviceBatteryMonitoring: BatteryMonitoringSwitch {
        var isEnabled: Bool {
            get { UIDevice.current.isBatteryMonitoringEnabled }
            set { UIDevice.current.isBatteryMonitoringEnabled = newValue }
        }
    }
#endif
