import DebugDrawer
#if canImport(DebugDrawerHangDetectorPlugin)
    import DebugDrawerHangDetectorPlugin
#endif
import Foundation
import SwiftUI

// The sidecar's half of performance traces (DD-125): Start Recording, then the app's stalls, newest
// first, each open to its main-thread stack as the debug navigator shows one, and the signpost
// intervals the app marked, with Stop and Delete. It ships in the kit, beside Environments and Auth,
// as the capability describes itself, so every sidecar would draw the same list. Recording is
// started by a button, not as the plugin shows, because it puts an observer on the app's main run
// loop and a thread beside it. A frame the app's stripped build can't name shows as its image and
// offset, which the report's binary images (load address and UUID) symbolicate with the build's
// dSYM. It is a `DebugDrawerReportContributor`, so Create Report adds `performance.txt` and tells
// the app it was exported. The capability's types and the stack demangler come from the Hang
// Detector plugin, which doesn't build for watchOS (its monitor samples the main thread with
// thread_suspend and thread_get_state, which watchOS doesn't offer), so the kit has no
// `performanceTraces` there (PLATFORM_CONDITIONAL_DEPENDENCIES in scripts/modules.py).

#if DEBUG && canImport(DebugDrawerHangDetectorPlugin)
    extension DebugDrawerSidecarPlugin {
        /// The app's hitches, hangs and signpost intervals
        /// (`DebugDrawerReceiverCapability.performanceTraces(_:)`), recorded once Start Recording is
        /// pressed, each stall open to its main-thread stack, until Stop and Delete or the session's
        /// end; Create Report adds them as `performance.txt`.
        @MainActor public static var performanceTraces: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: PerformanceTraces.pluginID, title: "Performance", icon: "gauge.with.dots.needle.33percent",
                snapshot: PerformanceTraces.Snapshot.self, command: PerformanceTraces.Command.self
            ) { transport in
                PerformanceTracesPlugin(transport: transport)
            }
            .collectedWhileRunning()
        }
    }

    /// The app's recorded stalls and intervals, shown in the sidecar.
    struct PerformanceTracesPlugin: DebugDrawerPlugin, DebugDrawerReportContributor {
        let transport: DebugDrawerPluginTransport<PerformanceTraces.Snapshot, PerformanceTraces.Command>
        let title = "Performance"
        let icon = "gauge.with.dots.needle.33percent"

        var body: some View {
            PerformanceTracesTransportView(transport: transport)
        }

        /// Adds `performance.txt`: each stall with its frames, each interval, and the binary images
        /// that symbolicate the frames. Then tells the app, which records the export and audits it;
        /// the app's copy is still deleted as the session ends.
        func contribute(to report: inout DebugDrawerReport, redaction _: DebugDrawerRedaction) {
            let snapshot = transport.snapshot
            guard snapshot.isRecording, !snapshot.stalls.isEmpty || !snapshot.intervals.isEmpty else { return }
            report.add(text: snapshot.text, named: "performance")
            transport.send(.export)
        }
    }

    /// The recording over the capability's snapshot, sending what the view asks.
    struct PerformanceTracesTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<PerformanceTraces.Snapshot, PerformanceTraces.Command>
        @State private var expanded: PerformanceTraces.Stall.ID?

        var body: some View {
            PerformanceTracesView(snapshot: transport.snapshot, expanded: $expanded) { transport.send($0) }
        }
    }

    /// Start Recording while nothing records; then the stalls, newest first, one open to its stack,
    /// the intervals, newest first, and Stop and Delete. A function of the snapshot, the open stall
    /// and the send action.
    struct PerformanceTracesView: View {
        let snapshot: PerformanceTraces.Snapshot
        @Binding var expanded: PerformanceTraces.Stall.ID?
        var demangler: any SymbolDemangler = _SymbolDemangler()
        let send: (PerformanceTraces.Command) -> Void

        var body: some View {
            if snapshot.isRecording {
                DebugDrawerSection("Stalls") {
                    ForEach(snapshot.stalls.reversed()) { stall in
                        StallRow(
                            stall: stall, executable: snapshot.executable, isExpanded: expanded == stall.id, demangler: demangler
                        ) {
                            expanded = expanded == stall.id ? nil : stall.id
                        }
                    }
                } footer: {
                    Text(stallsFooter)
                }
                DebugDrawerSection("Signposts") {
                    ForEach(snapshot.intervals.reversed()) { interval in
                        DebugDrawerKeyValueRow(interval.name, value: PerformanceTraces.milliseconds(interval.duration))
                    }
                } footer: {
                    Text(
                        snapshot.intervals.isEmpty
                            ? "No intervals yet. The app marks them with beginInterval and endInterval."
                            : "\(snapshot.droppedIntervals) dropped by the bounds"
                    )
                }
                DebugDrawerActionRow {
                    EmptyView()
                } trailing: {
                    Button("Stop and Delete", role: .destructive) { send(.stop) }
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityHint("Stops watching the app's main thread and deletes what was recorded")
                }
            } else {
                DebugDrawerEmptyState("Not Recording", systemImage: "gauge.with.dots.needle.33percent") {
                    Text(
                        "Start records the app's hitches, hangs with their main-thread stacks, and signpost intervals "
                            + "until the session ends, when the app deletes them."
                    )
                }
                DebugDrawerActionRow {
                    Button("Start Recording") { send(.start) }
                        .accessibilityHint("Watches the app's main thread for the rest of the session")
                }
            }
        }

        private var stallsFooter: String {
            let hitch = PerformanceTraces.milliseconds(snapshot.hitchThreshold)
            let thresholds = "Hitches from \(hitch), hangs from \(PerformanceTraces.milliseconds(snapshot.hangThreshold))"
            if snapshot.stalls.isEmpty {
                return "No stalls yet. \(thresholds)."
            }
            return "\(thresholds); \(snapshot.droppedStalls) dropped by the bounds."
        }
    }

    /// One stall as an issue row: how long, hitch or hang, when; open, its main-thread stack, the
    /// app's own frames badged and the first of them selected, with a button that copies it.
    struct StallRow: View {
        let stall: PerformanceTraces.Stall
        /// The app's executable's file name, which marks its own frames.
        let executable: String?
        let isExpanded: Bool
        let demangler: any SymbolDemangler
        let onToggle: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onToggle) {
                    DebugDrawerIssueRow(PerformanceTraces.milliseconds(stall.duration), severity: stall.kind == .hang ? .error : .warning) {
                        Text("\(stall.kind.title) · \(stall.began.formatted(date: .omitted, time: .standard))")
                    } accessory: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .debugDrawerFont(.secondary)
                            .debugDrawerForegroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .debugDrawerButtonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(stall.kind.title), \(PerformanceTraces.milliseconds(stall.duration))")
                .accessibilityHint(isExpanded ? "Hides the stack" : "Shows the stack")
                .accessibilityIdentifier("Stall-\(stall.id)")
                if isExpanded {
                    stack
                }
            }
        }

        @ViewBuilder private var stack: some View {
            let selected = stall.frames.firstIndex { $0.image != nil && $0.image == executable }
            if stall.frames.isEmpty {
                Text("No stack was captured: the main thread got going before the watcher looked.")
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(stall.frames.enumerated()), id: \.offset) { index, frame in
                    DebugDrawerStackFrameRow(
                        index: index,
                        symbol: frame.displayedSymbol(demangler: demangler),
                        image: frame.image ?? "???",
                        isOwnCode: frame.image != nil && frame.image == executable,
                        isSelected: index == selected
                    )
                }
            }
            DebugDrawerActionRow {
                DebugDrawerCopyButton("Copy Stack") {
                    stall.frames.enumerated().map { $1.line(index: $0) }.joined(separator: "\n")
                }
            }
        }
    }

    extension PerformanceTraces.Frame {
        /// The frame's symbol as Xcode names it; for a frame its build doesn't name, its offset into
        /// its image, which the build's dSYM symbolicates; its address when it is in no image.
        func displayedSymbol(demangler: any SymbolDemangler) -> String {
            if let symbol {
                return demangler.demangle(symbol) ?? symbol
            }
            if let imageOffset {
                return "\(image ?? "???") + 0x\(String(imageOffset, radix: 16))"
            }
            return "0x\(String(address, radix: 16))"
        }
    }
#elseif canImport(DebugDrawerHangDetectorPlugin)
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The app's hitches, hangs and signpost intervals; release builds show nothing.
        @MainActor public static var performanceTraces: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: PerformanceTraces.pluginID, title: "Performance", icon: "gauge.with.dots.needle.33percent",
                snapshot: PerformanceTraces.Snapshot.self, command: PerformanceTraces.Command.self
            ) { _ in
                PerformanceTracesPlugin()
            }
        }
    }

    /// Draws nothing.
    struct PerformanceTracesPlugin: DebugDrawerPlugin {
        let title = "Performance"
        let icon = "gauge.with.dots.needle.33percent"

        var body: some View {
            EmptyView()
        }
    }
#endif
