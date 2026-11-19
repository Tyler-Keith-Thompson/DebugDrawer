#if DEBUG
    /// The platform's battery-monitoring setting, which the host app can see and set too.
    ///
    /// iOS reports no battery level while it is off, so the Energy monitor turns it on while it
    /// samples and puts back what it found; the Mac has none.
    @MainActor
    protocol BatteryMonitoringSwitch: AnyObject {
        var isEnabled: Bool { get set }
    }
#endif
