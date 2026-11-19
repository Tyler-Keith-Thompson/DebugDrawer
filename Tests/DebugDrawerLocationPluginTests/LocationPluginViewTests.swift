// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import DebugDrawer
    @testable import DebugDrawerLocationPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LocationPluginViewTests {
        @Test("The view draws the snapshot, and sends the switch, typing, a preset, Play and Stop as commands")
        func sendsCommands() throws {
            let fixes = GPXTrack(points: [
                GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: nil),
                GPXTrackPoint(latitude: 0.001, longitude: 0, elevation: nil, time: nil)
            ]).fixes
            let paris = LocationSimulator.PresetLocation(name: "Paris", latitude: 48.8566, longitude: 2.3522)
            var sent: [LocationCommand.Action] = []
            let sut = LocationPluginView(transport: DebugDrawerPluginTransport(
                initial: LocationSnapshot(
                    isEnabled: true, latitudeText: "51.5", longitudeText: "-0.12",
                    coordinate: LocationCoordinate(latitude: 51.5, longitude: -0.12),
                    active: LocationCoordinate(latitude: 51.5, longitude: -0.12), presets: [paris],
                    routes: [Route(id: "test", name: "Test", fixes: fixes)], routeID: "test", playback: .paused(delivered: 1)
                ),
                snapshots: AsyncStream { $0.finish() },
                send: { sent.append($0.action) }
            ))
            let expected: [LocationCommand.Action] = [
                .setLatitudeText("48.85"),
                .choosePreset(paris),
                .play,
                .stop,
                .setEnabled(false)
            ]

            let view = try sut.inspect()
            try view.find(ViewType.TextField.self) { try $0.accessibilityLabel().string() == "Latitude" }.setInput("48.85")
            try view.find(button: "Paris").tap()
            try view.find(button: "Play").tap()
            try view.find(button: "Stop").tap()
            try view.find(ViewType.Toggle.self).tap()

            #expect(sent == expected)
            #expect(try view.find(ViewType.TextField.self) { try $0.accessibilityLabel().string() == "Longitude" }.input() == "-0.12")
            #expect(throws: Never.self) { try view.find(button: "Import GPX…") }
        }

        @Test("With spoofing off, the view shows no Route section")
        func offHidesRoutes() throws {
            let sut = LocationPluginView(transport: DebugDrawerPluginTransport(
                initial: LocationSnapshot(),
                snapshots: AsyncStream { $0.finish() },
                send: { _ in }
            ))

            let view = try sut.inspect()

            #expect(throws: (any Error).self) { try view.find(button: "Play") }
        }
    }
#endif
