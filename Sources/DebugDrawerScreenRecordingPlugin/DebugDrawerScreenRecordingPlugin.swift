import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// Records the app's windows without the drawer: Record and Stop in the drawer and in the HUD,
/// the elapsed time in the header while it records, and the saved movies to share, delete or
/// add to the bug report.
public struct ScreenRecordingPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer and the HUD.
    nonisolated static let pluginID = "ScreenRecordingPlugin"

    public nonisolated var id: String {
        Self.pluginID
    }

    public var title = "Screen Recording"
    public var category = "Interface"
    public var icon = "record.circle"

    #if DEBUG
        let model: ScreenRecordingModel

        init(model: ScreenRecordingModel) {
            self.model = model
        }
    #endif

    public var body: some View {
        #if DEBUG
            ScreenRecordingPluginView(model: model)
        #else
            EmptyView()
        #endif
    }

    /// Record or Stop with the elapsed time, so a recording starts and stops with the drawer
    /// closed.
    public var hud: ScreenRecordingHUD? {
        #if DEBUG
            ScreenRecordingHUD(model: model)
        #else
            nil
        #endif
    }

    /// A red dot and the elapsed time while it records; otherwise how many recordings are saved.
    public var headerAccessory: some View {
        #if DEBUG
            ScreenRecordingHeaderAccessory(model: model)
        #else
            EmptyView()
        #endif
    }

    // One action that starts or stops: the drawer reads actions off the main actor, where the
    // recorder's state can't be read to offer Start or Stop alone.

    /// Start or stop recording, found by "video", "capture" and "movie" too.
    public var actions: [DebugDrawerAction] {
        #if DEBUG
            [
                DebugDrawerAction(
                    "Start or stop screen recording", keywords: ["screen", "recording", "record", "video", "capture", "movie"]
                ) { [model] in
                    model.toggle()
                }
            ]
        #else
            []
        #endif
    }

    /// Lists the saved recordings again if an uninstall dropped them. Release builds record
    /// nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            model.install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once no drawer has the plugin, stops a recording in progress, saving its movie, and drops
    /// the list of recordings. The recordings on disk and the Show Touches setting stay.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            model.uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

/// The HUD readout: reads the model and hands its state to `ScreenRecordingHUDButton`.
public struct ScreenRecordingHUD: View {
    #if DEBUG
        @ObservedObject var model: ScreenRecordingModel
    #endif

    public var body: some View {
        #if DEBUG
            ScreenRecordingHUDButton(state: model.state, toggle: { model.toggle() })
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    /// Reads the model and hands its values to `ScreenRecordingView`.
    struct ScreenRecordingPluginView: View {
        @ObservedObject var model: ScreenRecordingModel

        var body: some View {
            ScreenRecordingView(
                state: model.state,
                recordings: model.recordings,
                includedInReport: model.includedInReport,
                capacity: model.capacity,
                showsTouches: $model.showsTouches,
                start: { model.start() },
                stop: { Task { await model.stop() } },
                delete: { model.delete($0) },
                setIncludedInReport: { model.setIncludedInReport($0, for: $1) }
            )
        }
    }

    /// One button: Record, or the elapsed time and Stop while it records.
    struct ScreenRecordingHUDButton: View {
        let state: RecordingState
        let toggle: () -> Void

        var body: some View {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    if case let .recording(started) = state {
                        RecordingDot()
                        RecordingElapsedText(started: started)
                        Image(systemName: "stop.fill")
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "record.circle")
                            .foregroundStyle(Color.red)
                            .accessibilityHidden(true)
                        Text(state == .finishing ? "Saving…" : "Record")
                    }
                }
                .debugDrawerFont(.value)
                .contentShape(Rectangle())
            }
            .debugDrawerButtonStyle(.plain)
            .disabled(state == .finishing)
            .accessibilityLabel(state.isRecording ? "Stop screen recording" : "Start screen recording")
        }
    }

    /// The header's readout: reads the model.
    struct ScreenRecordingHeaderAccessory: View {
        @ObservedObject var model: ScreenRecordingModel

        var body: some View {
            ScreenRecordingHeaderReadout(state: model.state, count: model.recordings.count)
        }
    }

    /// A red dot and the elapsed time while it records, "Saving…" while the movie is written,
    /// otherwise the number of recordings ("3 recordings"), or nothing before the first.
    struct ScreenRecordingHeaderReadout: View {
        let state: RecordingState
        let count: Int

        var body: some View {
            switch state {
            case let .recording(started):
                HStack(spacing: 4) {
                    RecordingDot()
                    RecordingElapsedText(started: started)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recording")
            case .finishing:
                Text("Saving…")
            case .idle, .finished, .failed:
                if count > 0 {
                    Text(count == 1 ? "1 recording" : "\(count.formatted()) recordings")
                }
            }
        }
    }
#endif
