#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// What the Route section's buttons do.
    struct RouteActions {
        var play: () -> Void = {}
        var pause: () -> Void = {}
        var stop: () -> Void = {}
        /// Presents the file importer.
        var importFile: () -> Void = {}
    }

    /// The Route section: the route and speed menus, how far playback has come, why an imported
    /// file couldn't be played, and Play or Pause, Stop and Import GPX….
    struct RouteSection: View {
        let routes: [Route]
        @Binding var selection: Route.ID
        @Binding var speed: PlaybackSpeed
        let playback: RoutePlayback
        let importFailure: GPXError?
        let actions: RouteActions

        var body: some View {
            DebugDrawerSection("Route") {
                DebugDrawerRow("Track", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                    MenuPicker("Track", selection: $selection, current: route?.name ?? "") {
                        ForEach(routes) { Text($0.name).tag($0.id) }
                    }
                }
                DebugDrawerRow("Speed", systemImage: "gauge.with.dots.needle.67percent") {
                    MenuPicker("Speed", selection: $speed, current: speed.title) {
                        ForEach(PlaybackSpeed.allCases) { Text($0.title).tag($0) }
                    }
                }
                DebugDrawerKeyValueRow("Progress", value: progress)
                if let importFailure {
                    DebugDrawerIssueRow("Import Failed", severity: .error) {
                        Text(importFailure.message)
                    }
                }
                DebugDrawerActionRow {
                    if case .playing = playback {
                        Button("Pause", action: actions.pause)
                    } else {
                        Button("Play", action: actions.play)
                            .debugDrawerButtonStyle(.primary)
                    }
                    Button("Stop", action: actions.stop)
                        .disabled(playback == .stopped)
                    Button("Import GPX…", action: actions.importFile)
                }
            }
        }
    }

    extension RouteSection {
        private var route: Route? { routes.first { $0.id == selection } }

        /// "Point 3 of 25, 00:20": the points delivered, and the track time of the last.
        fileprivate var progress: String {
            let fixes = route?.fixes ?? []
            let delivered = playback.delivered(of: fixes.count)
            let elapsed = delivered == 0 ? 0 : fixes[delivered - 1].offset
            let time = Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
            return "Point \(delivered) of \(fixes.count), \(time)"
        }
    }
#endif
