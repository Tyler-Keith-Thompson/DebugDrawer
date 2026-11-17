#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// How long the recording has run ("0:12"), advancing each second: TimelineView redraws it on
    /// the second, and nothing waits on a timer.
    struct RecordingElapsedText: View {
        let started: Date

        var body: some View {
            TimelineView(.periodic(from: started, by: 1)) { context in
                Text(Duration.seconds(context.date.timeIntervalSince(started)).recordingLength)
                    .monospacedDigit()
            }
        }
    }

    /// The red dot of a recording in progress, as the system draws it.
    struct RecordingDot: View {
        @ScaledMetric(relativeTo: .body) private var size: CGFloat = 8

        var body: some View {
            Circle()
                .fill(Color.red)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
#endif
