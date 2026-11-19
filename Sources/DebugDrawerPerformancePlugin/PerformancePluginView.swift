#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the frame and memory readout, the threads, and on UIKit's platforms the
    /// memory warning. Showing it samples nothing by itself: the drawer that shows it starts the
    /// model through the plugin's lifecycle hooks.
    ///
    /// It draws ``PerformanceModel``'s snapshots from its transport and sends it what the user
    /// does.
    struct PerformancePluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<PerformanceSnapshot, PerformanceCommand>

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<PerformanceSnapshot, PerformanceCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            VStack(alignment: .leading, spacing: 0) {
                PerformanceReadout(
                    fps: snapshot.fps,
                    fpsHistory: snapshot.fpsHistory,
                    maximumFPS: snapshot.maximumFPS,
                    droppedFrames: snapshot.droppedFrames,
                    footprintMB: snapshot.footprintMB,
                    footprintHistory: snapshot.footprintHistory,
                    peakFootprintMB: snapshot.peakFootprintMB,
                    physicalMemoryMB: snapshot.physicalMemoryMB
                )
                ThreadsSection(threads: snapshot.threads)
                // UIKit's platforms only: the Mac has no public way to simulate memory pressure.
                #if os(iOS) || os(tvOS) || os(visionOS)
                    MemoryWarningSection(postedAt: snapshot.memoryWarningPostedAt) {
                        transport.send(PerformanceCommand(.simulateMemoryWarning))
                        // The plugin's direct transport has posted it before send returns, so the
                        // snapshot holds its time; the clock stands in for a model that hasn't.
                        return transport.snapshot.memoryWarningPostedAt ?? Date()
                    }
                #endif
            }
        }
    }
#endif
