// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawerLocationPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct RouteSectionViewTests {
        @Test("Stopped, the section offers Play, Stop disabled and Import GPX…, and shows no point delivered")
        func stopped() throws {
            let start = Date(timeIntervalSince1970: 1_000_000)
            let track = GPXTrack(points: [
                GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: start),
                GPXTrackPoint(latitude: 0.001, longitude: 0, elevation: nil, time: start.addingTimeInterval(75))
            ])
            let route = Route(id: "test", name: "Test", fixes: track.fixes)
            var played = 0
            var imported = 0
            let sut = RouteSection(
                routes: [route], selection: .constant("test"), speed: .constant(.times1), playback: .stopped, importFailure: nil,
                actions: RouteActions(play: { played += 1 }, importFile: { imported += 1 })
            )
            let expectedProgress = "Point 0 of 2, 00:00"

            let view = try sut.inspect()
            try view.find(button: "Play").tap()
            try view.find(button: "Import GPX…").tap()

            #expect(played == 1)
            #expect(imported == 1)
            #expect(try view.find(button: "Stop").isDisabled())
            #expect(throws: (any Error).self) { try view.find(button: "Pause") }
            #expect(try view.find(text: expectedProgress).string() == expectedProgress)
        }

        @Test("Playing, the section offers Pause and Stop, and shows the points delivered and the track time of the last")
        func playing() throws {
            let start = Date(timeIntervalSince1970: 1_000_000)
            let track = GPXTrack(points: [
                GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: start),
                GPXTrackPoint(latitude: 0.001, longitude: 0, elevation: nil, time: start.addingTimeInterval(75)),
                GPXTrackPoint(latitude: 0.002, longitude: 0, elevation: nil, time: start.addingTimeInterval(150))
            ])
            let route = Route(id: "test", name: "Test", fixes: track.fixes)
            var paused = 0
            var stopped = 0
            let sut = RouteSection(
                routes: [route], selection: .constant("test"), speed: .constant(.times5), playback: .playing(delivered: 2),
                importFailure: nil, actions: RouteActions(pause: { paused += 1 }, stop: { stopped += 1 })
            )
            let expectedProgress = "Point 2 of 3, 01:15"

            let view = try sut.inspect()
            try view.find(button: "Pause").tap()
            try view.find(button: "Stop").tap()

            #expect(paused == 1)
            #expect(stopped == 1)
            #expect(throws: (any Error).self) { try view.find(button: "Play") }
            #expect(try view.find(text: expectedProgress).string() == expectedProgress)
        }

        @Test("Finished, the progress shows every point and the track's whole duration, and Play is offered again")
        func finished() throws {
            let start = Date(timeIntervalSince1970: 1_000_000)
            let track = GPXTrack(points: [
                GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: start),
                GPXTrackPoint(latitude: 0.001, longitude: 0, elevation: nil, time: start.addingTimeInterval(3_725))
            ])
            let route = Route(id: "test", name: "Test", fixes: track.fixes)
            let sut = RouteSection(
                routes: [route], selection: .constant("test"), speed: .constant(.times1), playback: .finished, importFailure: nil,
                actions: RouteActions()
            )
            let expectedProgress = "Point 2 of 2, 62:05"

            let view = try sut.inspect()

            #expect(try view.find(text: expectedProgress).string() == expectedProgress)
            #expect(try view.find(button: "Play").isDisabled() == false)
        }

        @Test("A file that couldn't be played shows why, inline")
        func importFailure() throws {
            let route = Route(id: "test", name: "Test", fixes: GPXTrack(points: [
                GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: nil)
            ]).fixes)
            let sut = RouteSection(
                routes: [route], selection: .constant("test"), speed: .constant(.times1), playback: .stopped, importFailure: .notGPX,
                actions: RouteActions()
            )
            let expected = GPXError.notGPX.message

            let view = try sut.inspect()

            #expect(try view.find(text: expected).string() == expected)
        }

        @Test("The speed menu offers 1x, 2x, 5x and 10x, and choosing one sets the speed")
        func speedMenu() throws {
            let route = Route(id: "test", name: "Test", fixes: GPXTrack(points: [
                GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: nil)
            ]).fixes)
            var speed = PlaybackSpeed.times1
            let binding = Binding(get: { speed }, set: { speed = $0 })
            let sut = RouteSection(
                routes: [route], selection: .constant("test"), speed: binding, playback: .stopped, importFailure: nil, actions: RouteActions()
            )
            let expectedTitles = ["1x", "2x", "5x", "10x"]

            let picker = try sut.inspect().find(ViewType.Picker.self) { try $0.accessibilityLabel().string() == "Speed" }
            let actualTitles = try picker.find(ViewType.ForEach.self).findAll(ViewType.Text.self).map { try $0.string() }
            try picker.select(value: PlaybackSpeed.times5)

            #expect(actualTitles == expectedTitles)
            #expect(speed == .times5)
        }

        @Test("The track menu lists every route by name, and choosing one selects it")
        func trackMenu() throws {
            let fixes = GPXTrack(points: [GPXTrackPoint(latitude: 0, longitude: 0, elevation: nil, time: nil)]).fixes
            let routes = [Route(id: "a", name: "Alpha", fixes: fixes), Route(id: "b", name: "Bravo", fixes: fixes)]
            var selection = "a"
            let binding = Binding(get: { selection }, set: { selection = $0 })
            let sut = RouteSection(
                routes: routes, selection: binding, speed: .constant(.times1), playback: .stopped, importFailure: nil, actions: RouteActions()
            )
            let expectedNames = ["Alpha", "Bravo"]

            let picker = try sut.inspect().find(ViewType.Picker.self) { try $0.accessibilityLabel().string() == "Track" }
            let actualNames = try picker.find(ViewType.ForEach.self).findAll(ViewType.Text.self).map { try $0.string() }
            try picker.select(value: "b")

            #expect(actualNames == expectedNames)
            #expect(selection == "b")
        }
    }
#endif
