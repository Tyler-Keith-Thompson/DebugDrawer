#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's face: where the recorder is, Record or Stop, Show Touches on iOS, and the saved
    /// recordings, each to share, add to the bug report or delete.
    struct ScreenRecordingView: View {
        let state: RecordingState
        /// The saved recordings, newest first.
        let recordings: [Recording]
        let includedInReport: Set<Recording.ID>
        /// How many recordings are kept.
        let capacity: Int
        @Binding var showsTouches: Bool
        let start: () -> Void
        let stop: () -> Void
        let delete: (Recording) -> Void
        let setIncludedInReport: (Bool, Recording) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                status
                #if os(iOS)
                    DebugDrawerRow("Show touches", systemImage: "hand.tap", isOn: $showsTouches)
                        .disabled(!state.canStart)
                #endif
                if case let .failed(failure) = state {
                    DebugDrawerIssueRow("Not saved", severity: .error) {
                        Text(failure.message)
                    }
                }
                if !recordings.isEmpty {
                    DebugDrawerSection("Recordings") {
                        ForEach(recordings) { recording in
                            RecordingRow(
                                recording: recording,
                                isIncludedInReport: includedInReport.contains(recording.id),
                                delete: { delete(recording) },
                                setIncludedInReport: { setIncludedInReport($0, recording) }
                            )
                        }
                    } footer: {
                        Text("The newest \(capacity.formatted()) are kept in Caches. Those marked In Bug Report go into the drawer's bug report.")
                    }
                }
                DebugDrawerActionRow {
                    if state.isRecording {
                        Button(action: stop) {
                            Label("Stop", systemImage: "stop.circle")
                        }
                        .debugDrawerButtonStyle(.primary)
                        .accessibilityLabel("Stop recording")
                    } else {
                        Button(action: start) {
                            Label("Record", systemImage: "record.circle")
                        }
                        .debugDrawerButtonStyle(.primary)
                        .disabled(!state.canStart)
                        .accessibilityLabel("Start recording the screen")
                    }
                }
            }
        }

        @ViewBuilder private var status: some View {
            switch state {
            case let .recording(started):
                DebugDrawerRow("Recording", systemImage: "record.circle") {
                    Text("The app's windows, without the drawer, its HUD or its toasts.")
                } accessory: {
                    HStack(spacing: 6) {
                        RecordingDot()
                        RecordingElapsedText(started: started)
                            .debugDrawerFont(.value)
                    }
                    .accessibilityElement(children: .combine)
                }
            case .finishing:
                DebugDrawerRow("Saving the movie…", systemImage: "record.circle") {
                    EmptyView()
                } accessory: {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Saving")
                }
            case .idle, .finished, .failed:
                DebugDrawerRow("Not recording", systemImage: "record.circle") {
                    Text(
                        "Records the app's windows without the drawer, its HUD or its toasts. Pin it to the HUD to record with the drawer closed."
                    )
                } accessory: {
                    EmptyView()
                }
            }
        }
    }
#endif
