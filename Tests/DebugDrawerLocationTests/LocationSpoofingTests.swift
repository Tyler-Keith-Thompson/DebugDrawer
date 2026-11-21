#if DEBUG
    import CoreLocation
    @testable import DebugDrawerLocation
    @testable import DebugDrawerReceiver
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    // The model alone, over sessions on a clock the test moves and a timer it fires, with no
    // receiver: what the host is told and what its readings become as a spoof starts, moves and
    // stops, within a session only, and up to the session's expiry date. Each test keeps the
    // model's flag in a defaults suite of its own.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct LocationSpoofingTests {
        private nonisolated static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        private let paris = LocationCoordinate(latitude: 48.8566, longitude: 2.3522)
        private let tokyo = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        private let real = CLLocation(latitude: 37.3349, longitude: -122.009)

        @Test("A spoof in an open session tells the host its location, and the host's readings become it, dated now")
        func spoofTellsHostAndReplacesReadings() throws {
            let suite = temporarySuiteName("LocationSpoofingTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let clock = MovableClock(Self.now)
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let observer = SpoofingObserver()
            let sut = LocationSpoofing(sessions: sessions, defaults: defaults, now: { clock.now }, spoofingDidChange: observer.spoofingDidChange)
            sessions.perform(.open(duration: 60))
            let readingsBefore = sut.locations(replacing: [real]).map { LocationCoordinate($0.coordinate) }

            sut.perform(.spoof(paris))

            let replaced = try #require(sut.locations(replacing: [real]).last)
            #expect(readingsBefore == [LocationCoordinate(real.coordinate)])
            #expect(observer.told == [paris])
            #expect(sut.snapshot == LocationSpoofing.Snapshot(coordinate: paris))
            #expect(sut.snapshot.isSpoofing)
            #expect(sut.isSpoofing)
            #expect(sut.locations(replacing: [real]).count == 1)
            #expect(LocationCoordinate(replaced.coordinate) == paris)
            #expect(replaced.timestamp == Self.now)
            #expect(sut.location(replacing: real).map { LocationCoordinate($0.coordinate) } == paris)
            #expect(sut.location(replacing: nil).map { LocationCoordinate($0.coordinate) } == paris)
        }

        @Test("Moving the spoof tells the host the new location; the same coordinate again tells it nothing; stop tells it nil")
        func moveRepeatAndStop() throws {
            let suite = temporarySuiteName("LocationSpoofingTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let observer = SpoofingObserver()
            let sut = LocationSpoofing(sessions: sessions, defaults: defaults, now: { Self.now }, spoofingDidChange: observer.spoofingDidChange)
            sessions.perform(.open(duration: 60))
            let expected: [LocationCoordinate?] = [paris, tokyo, nil]

            sut.perform(.spoof(paris))
            sut.perform(.spoof(tokyo))
            sut.perform(.spoof(tokyo))
            sut.perform(.stop)
            sut.perform(.stop)

            #expect(observer.told == expected)
            #expect(!sut.isSpoofing)
            #expect(sut.snapshot == LocationSpoofing.Snapshot(coordinate: nil))
            #expect(sut.locations(replacing: [real]) == [real])
            #expect(sut.location(replacing: nil) == nil)
        }

        @Test("A spoof outside a session is ignored: the host hears nothing and its readings stay real")
        func spoofOutsideSessionIgnored() throws {
            let suite = temporarySuiteName("LocationSpoofingTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let observer = SpoofingObserver()
            let sut = LocationSpoofing(sessions: sessions, defaults: defaults, now: { Self.now }, spoofingDidChange: observer.spoofingDidChange)

            sut.perform(.spoof(paris))

            #expect(observer.told.isEmpty)
            #expect(!sut.isSpoofing)
            #expect(sut.spoofedLocation == nil)
            #expect(defaults.object(forKey: LocationSpoofing.spoofingDefaultsKey) == nil)
        }

        @Test("A coordinate off the Earth is refused malformedCommand and, performed anyway, ignored")
        func coordinateOffTheEarth() throws {
            let suite = temporarySuiteName("LocationSpoofingTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let observer = SpoofingObserver()
            let sut = LocationSpoofing(sessions: sessions, defaults: defaults, now: { Self.now }, spoofingDidChange: observer.spoofingDidChange)
            sessions.perform(.open(duration: 60))
            let offTheEarth = [
                LocationCoordinate(latitude: 90.000_1, longitude: 0),
                LocationCoordinate(latitude: 0, longitude: -180.000_1),
                LocationCoordinate(latitude: .nan, longitude: 0),
                LocationCoordinate(latitude: 0, longitude: .infinity)
            ]
            let refusals = offTheEarth.map { sut.refusal(of: .spoof($0)) }

            for coordinate in offTheEarth {
                sut.perform(.spoof(coordinate))
            }

            #expect(refusals == Array(repeating: .malformedCommand, count: offTheEarth.count))
            #expect(sut.refusal(of: .spoof(paris)) == nil)
            #expect(sut.refusal(of: .stop) == nil)
            #expect(observer.told.isEmpty)
            #expect(!sut.isSpoofing)
        }

        @Test("A coordinate is valid on the bounds of latitude and longitude, and not past them")
        func validityBounds() {
            let onTheBounds = [
                LocationCoordinate(latitude: 90, longitude: 180),
                LocationCoordinate(latitude: -90, longitude: -180),
                LocationCoordinate(latitude: 0, longitude: 0)
            ]
            let pastThem = [
                LocationCoordinate(latitude: 90.000_001, longitude: 0),
                LocationCoordinate(latitude: -90.000_001, longitude: 0),
                LocationCoordinate(latitude: 0, longitude: 180.000_001),
                LocationCoordinate(latitude: 0, longitude: -180.000_001),
                LocationCoordinate(latitude: 0, longitude: .nan)
            ]

            let actualOnTheBounds = onTheBounds.map(\.isValid)
            let actualPastThem = pastThem.map(\.isValid)

            #expect(actualOnTheBounds == [true, true, true])
            #expect(actualPastThem == [false, false, false, false, false])
        }

        @Test("The host's readings stop being spoofed at the session's expiry date, before the timer fires; the end then tells it nil")
        func readingsStopAtExpiryDate() throws {
            let suite = temporarySuiteName("LocationSpoofingTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let clock = MovableClock(Self.now)
            let timer = ManualTimer()
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: timer)
            let observer = SpoofingObserver()
            let sut = LocationSpoofing(sessions: sessions, defaults: defaults, now: { clock.now }, spoofingDidChange: observer.spoofingDidChange)
            sessions.perform(.open(duration: 60))
            sut.perform(.spoof(paris))
            clock.set(Self.now.addingTimeInterval(59))
            let justBefore = sut.isSpoofing

            clock.set(Self.now.addingTimeInterval(60))

            let atExpiry = (sut.isSpoofing, sut.locations(replacing: [real]), observer.told)
            timer.fireNow()
            #expect(justBefore)
            #expect(atExpiry.0 == false)
            #expect(atExpiry.1 == [real])
            #expect(atExpiry.2 == [paris])
            #expect(observer.told == [paris, nil])
            #expect(!sut.snapshot.isSpoofing)
        }

        @Test("A session that ends with no receiver to revert it still ends the spoof, and the host is told once")
        func sessionEndWithoutReceiver() throws {
            let suite = temporarySuiteName("LocationSpoofingTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let observer = SpoofingObserver()
            let sut = LocationSpoofing(sessions: sessions, defaults: defaults, now: { Self.now }, spoofingDidChange: observer.spoofingDidChange)
            sessions.perform(.open(duration: 60))
            sut.perform(.spoof(paris))
            let expected: [LocationCoordinate?] = [paris, nil]

            sessions.end()

            #expect(observer.told == expected)
            #expect(!sut.isSpoofing)
        }

        @Test("The flag is in the defaults from the spoof's start to its stop, and never the coordinate")
        func flagKeptWhileSpoofing() throws {
            let suite = temporarySuiteName("LocationSpoofingTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let sut = LocationSpoofing(sessions: sessions, defaults: defaults, now: { Self.now }, spoofingDidChange: { _ in })
            sessions.perform(.open(duration: 60))
            sut.perform(.spoof(paris))
            let whileSpoofing = defaults.persistentDomain(forName: suite) ?? [:]

            sut.perform(.stop)

            #expect(whileSpoofing.keys.sorted() == [LocationSpoofing.spoofingDefaultsKey])
            #expect(whileSpoofing[LocationSpoofing.spoofingDefaultsKey] as? Bool == true)
            #expect(defaults.object(forKey: LocationSpoofing.spoofingDefaultsKey) == nil)
        }

        @Test("The host's readings are spoofed when read off the main actor")
        func readsFromAnyThread() async throws {
            let suite = temporarySuiteName("LocationSpoofingTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
            let sut = LocationSpoofing(sessions: sessions, defaults: defaults, now: { Self.now }, spoofingDidChange: { _ in })
            sessions.perform(.open(duration: 60))
            sut.perform(.spoof(tokyo))

            let actual = await Task.detached { [sut] in
                (sut.isSpoofing, sut.spoofedLocation.map { LocationCoordinate($0.coordinate) })
            }.value

            #expect(actual.0)
            #expect(actual.1 == tokyo)
        }
    }
#endif
