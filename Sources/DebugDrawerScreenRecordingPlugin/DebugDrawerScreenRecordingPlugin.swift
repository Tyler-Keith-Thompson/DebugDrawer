#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Records the app's windows without the drawer: Record and Stop in the drawer and in the HUD,
    /// the elapsed time in the header while it records, and the saved movies to share, delete or
    /// add to the bug report.
    public struct ScreenRecordingPlugin: DebugDrawerPlugin {
        /// The plugin's identity in the drawer and the HUD.
        static let pluginID = "ScreenRecordingPlugin"

        public var id: String {
            Self.pluginID
        }

        public var title = "Screen Recording"
        public var category = "Interface"
        public var icon = "record.circle"

        let model: ScreenRecordingModel

        init(model: ScreenRecordingModel) {
            self.model = model
        }

        public var body: some View {
            ScreenRecordingPluginView(model: model)
        }

        /// Record or Stop with the elapsed time, so a recording starts and stops with the drawer
        /// closed.
        public var hud: ScreenRecordingHUD? {
            ScreenRecordingHUD(model: model)
        }

        /// A red dot and the elapsed time while it records; otherwise how many recordings are saved.
        public var headerAccessory: some View {
            ScreenRecordingHeaderAccessory(model: model)
        }

        // One action that starts or stops: the drawer reads actions off the main actor, where the
        // recorder's state can't be read to offer Start or Stop alone.

        /// Start or stop recording, found by "video", "capture" and "movie" too.
        public var actions: [DebugDrawerAction] {
            [
                DebugDrawerAction(
                    "Start or stop screen recording", keywords: ["screen", "recording", "record", "video", "capture", "movie"]
                ) { [model] in
                    model.toggle()
                }
            ]
        }
    }

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

    /// The HUD readout: reads the model and hands its state to `ScreenRecordingHUDButton`.
    public struct ScreenRecordingHUD: View {
        @ObservedObject var model: ScreenRecordingModel

        public var body: some View {
            ScreenRecordingHUDButton(state: model.state, toggle: { model.toggle() })
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
