#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the monitor's latest reading. Showing it samples nothing by itself: the
    /// drawer that shows it starts the monitor through the plugin's lifecycle hooks.
    ///
    /// It draws ``EnergyMonitor``'s snapshots from its transport, and labels and gauges them itself.
    struct EnergyPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<EnergySnapshot, EnergyCommand>

        /// - Parameter transport: Joins the view to the monitor; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<EnergySnapshot, EnergyCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            EnergyReadout(reading: EnergyReading(snapshot), processorCount: snapshot.processorCount)
        }
    }
#endif
