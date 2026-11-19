#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the total launch time and its two phases, the uptimes they run between,
    /// and a Copy button for a report of both.
    ///
    /// It draws ``LaunchTimeModel``'s snapshots from its transport, and formats every duration and
    /// uptime itself.
    struct LaunchTimePluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<LaunchTimeSnapshot, LaunchTimeCommand>

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<LaunchTimeSnapshot, LaunchTimeCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection {
                    if let total = snapshot.totalLaunchTime {
                        DebugDrawerKeyValueRow("Total", value: total.milliseconds)
                        // Each phase as its share of the whole launch.
                        if let preMain = snapshot.preMainDuration {
                            DebugDrawerGaugeRow("Pre-main", value: preMain.milliseconds, fraction: preMain / max(total, .ulpOfOne))
                        }
                        if let toFrame = snapshot.appInitToFirstFrame {
                            DebugDrawerGaugeRow("To frame", value: toFrame.milliseconds, fraction: toFrame / max(total, .ulpOfOne))
                        }
                    } else {
                        DebugDrawerKeyValueRow("Total", value: "Measuring…")
                        if let preMain = snapshot.preMainDuration {
                            DebugDrawerKeyValueRow("Pre-main", value: preMain.milliseconds)
                        }
                    }
                } footer: {
                    Text("From process start to the first frame: pre-main is dyld and static initializers, then app init to the first frame.")
                }
                DebugDrawerSection("Uptime") {
                    if let start = snapshot.processStartUptime {
                        DebugDrawerKeyValueRow("Process start", value: start.uptime)
                    }
                    DebugDrawerKeyValueRow("App init", value: snapshot.appInitUptime.uptime)
                    if let frame = snapshot.firstFrameUptime {
                        DebugDrawerKeyValueRow("First frame", value: frame.uptime)
                    }
                }
                DebugDrawerActionRow {
                    DebugDrawerCopyButton("Copy") { snapshot.report }
                }
            }
        }
    }

    extension LaunchTimeSnapshot {
        /// The times as plain text, for the Copy button.
        fileprivate var report: String {
            var report = "Launch Time Report\n"
            report += String(repeating: "=", count: 30) + "\n"
            if let total = totalLaunchTime {
                report += "Total: \(String(format: "%.0f ms", total * 1000))\n"
            }
            if let pre = preMainDuration {
                report += "Pre-main: \(String(format: "%.0f ms", pre * 1000))\n"
            }
            if let toFrame = appInitToFirstFrame {
                report += "App init to first frame: \(String(format: "%.0f ms", toFrame * 1000))\n"
            }
            if let start = processStartUptime {
                report += "\nProcess start uptime: \(String(format: "%.4fs", start))\n"
            }
            report += "App init uptime: \(String(format: "%.4fs", appInitUptime))\n"
            if let frame = firstFrameUptime {
                report += "First frame uptime: \(String(format: "%.4fs", frame))\n"
            }
            return report
        }
    }

    extension TimeInterval {
        /// The duration in whole milliseconds ("412 ms").
        fileprivate var milliseconds: String {
            String(format: "%.0f ms", self * 1000)
        }

        /// The system uptime in seconds to a tenth of a millisecond ("100.4000s").
        fileprivate var uptime: String {
            String(format: "%.4fs", self)
        }
    }
#endif
