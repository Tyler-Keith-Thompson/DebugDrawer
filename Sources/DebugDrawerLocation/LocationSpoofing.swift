import Combine
import CoreLocation
import DebugDrawerReceiver
import Foundation
import os

// The location spoofing capability's model (DD-122, charter D9: high risk), and what the host reads
// its locations through. A release build may not intercept anything (the charter's N1 and its
// rule on swizzling), so the Location plugin's engine, which exchanges `CLLocationManager`'s
// methods, stays in the drawer: here the host opts each reading in by passing it through
// `location(replacing:)` / `locations(replacing:)`, as `LocalizationReview` has strings read
// through it, and a spoof reaches only the code that does. What the two halves share is the
// coordinate they carry (`LocationCoordinate`, moved here).
//
// Spoofing is a fraud signal for many apps, so the host is told, not left to poll: the required
// `spoofingDidChange` closure hears every start, move and end, with the location or nil, on the
// main actor, and the snapshot (`isSpoofing`) and the nonisolated `isSpoofing` say it too. A spoof
// lasts for the session, always (no scope parameter): its revert is the session's end, expiry or
// gate-off, and the location the host reads stops being spoofed at the session's expiry date even
// before the sessions' timer fires in an app that was suspended, as network mocking's rules stop.
// A spoof outside a session (a debug build's drawer driving the model directly) is ignored.
//
// The coordinate lives in memory only, so a kill ends the spoof with the process. What survives
// it is a flag written before the host is first told, so the next launch can tell the host the
// spoof is over (it may have kept a spoofed location of its own) as the capability is made.
//
// The reads are behind a lock, not on the main actor: a location manager's delegate is called on
// the thread its run loop runs, and a fraud check may ask from any queue, so neither can wait for a
// hop. `OSAllocatedUnfairLock` rather than `Mutex`, which needs iOS 18.
//
// Rejected: the plugin's swizzles in release (interception the charter keeps out of end-user
// builds), a `CLLocationManager` subclass or delegate proxy the host installs (it would still only
// cover the managers the host routes through it, as the reads do, and adds a second way to get
// it wrong), the coordinate persisted across launches (a spoof must not outlive its session), an
// optional observer (a host that enables spoofing must decide what its fraud checks do), a
// built-in `requiringGrant()` (the item asks for a grant where a verifier is configured, which the
// grant policy already enforces for every capability; charter D6 keeps grants optional, and a
// host that wants one regardless adds `.requiringGrant()`), and the audit's `changes` for the
// coordinates (they are typed as UserDefaults values; the event, not the place, is what the log
// is for).

/// Location spoofing for a production build, set from a sidecar during its session: the locations
/// the app reads through ``location(replacing:)`` or ``locations(replacing:)`` come back as the
/// sidecar's coordinate until the session ends.
///
/// Nothing is intercepted: only the readings the app passes through it are spoofed, so route the
/// ones a tester should be able to move (a store finder, a delivery map) and leave the ones that
/// guard against fraud on Core Location's own. The app is told as spoofing starts, moves and ends
/// through `spoofingDidChange`, so its fraud checks can treat what it reads meanwhile as spoofed:
///
/// ```swift
/// let spoofing = LocationSpoofing(sessions: sessions) { location in
///     FraudSignals.shared.isLocationSpoofed = location != nil
///     storeFinder.update(location ?? locationManager.location)
/// }
/// receiver.enable(.locationSpoofing(spoofing))
///
/// // In the CLLocationManagerDelegate:
/// func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
///     storeFinder.update(spoofing.locations(replacing: locations).last)
/// }
/// ```
///
/// A sidecar connects to ``pluginID`` with ``Snapshot`` and ``Command``. Outside a session, and in an
/// app that hasn't enabled it, every command is refused and every reading is the real one.
@MainActor
public final class LocationSpoofing: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerLocation", category: "LocationSpoofing")

    /// The ID the receiver serves it under.
    public nonisolated static let pluginID = "DebugDrawer.LocationSpoofing"

    /// The defaults key of the flag the model keeps while it spoofs, so the launch after a kill
    /// tells the host the spoof is over.
    nonisolated static let spoofingDefaultsKey = "DebugDrawer.LocationSpoofing.isSpoofing"

    /// What a sidecar sees.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The coordinate the app's readings are replaced with, or `nil` while they are real.
        public var coordinate: LocationCoordinate?

        /// Whether the app's readings are spoofed: show it in the host's session indicator.
        public var isSpoofing: Bool {
            coordinate != nil
        }

        /// A snapshot.
        ///
        /// - Parameter coordinate: The coordinate readings are replaced with, or `nil`.
        public init(coordinate: LocationCoordinate?) {
            self.coordinate = coordinate
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Replaces the app's readings with `coordinate` until the session ends or another spoof
        /// moves it. A coordinate off the Earth (``LocationCoordinate/isValid``) is refused.
        case spoof(LocationCoordinate)
        /// Gives the app its real readings again: the session's revert.
        case stop
    }

    /// The coordinate spoofed now.
    @Published public private(set) var snapshot = Snapshot(coordinate: nil)

    /// The spoofed coordinate and the expiry of the session it was set in, read from any thread.
    private struct Spoof: Sendable {
        let coordinate: LocationCoordinate
        let expires: Date
    }

    private nonisolated let spoof = OSAllocatedUnfairLock<Spoof?>(initialState: nil)
    private nonisolated let now: @Sendable () -> Date
    private let defaults: UserDefaults
    private let spoofingDidChange: @MainActor (CLLocation?) -> Void
    /// The open session, as the sessions last said.
    private var session: DebugDrawerSession?
    private var sessionObservation: AnyCancellable?

    /// Spoofing that follows `sessions`' open session and tells the host of every change.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions: a spoof lasts no longer than the one it was set in.
    ///   - defaults: Where the model keeps, while it spoofs, a flag (never the coordinate) that
    ///     lets the launch after a kill tell the host the spoof is over.
    ///   - spoofingDidChange: Told on the main actor, after each change, the location the app's
    ///     readings are replaced with from now on, or `nil` once they are real again: as a spoof
    ///     starts or moves, as it stops (the session ending, expiring or a gate turning it off),
    ///     and as the capability is made after a launch the app was killed in while spoofing.
    public convenience init(
        sessions: DebugDrawerSessions,
        defaults: UserDefaults = .standard,
        spoofingDidChange: @escaping @MainActor (_ location: CLLocation?) -> Void
    ) {
        self.init(sessions: sessions, defaults: defaults, now: { Date() }, spoofingDidChange: spoofingDidChange)
    }

    /// Spoofing that dates its readings and checks the session's expiry by `now`.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions.
    ///   - defaults: Where the model keeps its flag while it spoofs.
    ///   - now: The time a spoofed reading carries and is checked against the session's expiry at.
    ///   - spoofingDidChange: Told after each change, as the public initializer's is.
    package init(
        sessions: DebugDrawerSessions,
        defaults: UserDefaults,
        now: @escaping @Sendable () -> Date,
        spoofingDidChange: @escaping @MainActor (_ location: CLLocation?) -> Void
    ) {
        self.defaults = defaults
        self.now = now
        self.spoofingDidChange = spoofingDidChange
        session = sessions.snapshot.session
        // The sessions are main-actor isolated and publish from there.
        sessionObservation = sessions.$snapshot.sink { [weak self] state in
            MainActor.assumeIsolated {
                self?.follow(state)
            }
        }
    }

    // MARK: - The host's readings

    /// Whether the app's readings are spoofed now, read from any thread: from a spoof's start until
    /// it stops or its session's expiry date passes, whichever is first.
    public nonisolated var isSpoofing: Bool {
        currentCoordinate != nil
    }

    /// The location the app's readings are replaced with now, read from any thread, dated now; `nil`
    /// while they are real.
    public nonisolated var spoofedLocation: CLLocation? {
        currentCoordinate.map { coordinate in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                altitude: 0,
                horizontalAccuracy: 0,
                verticalAccuracy: -1,
                timestamp: now()
            )
        }
    }

    /// `real`, or the spoofed location in its place while spoofing.
    ///
    /// - Parameter real: A reading of Core Location's, or `nil` when the app has none.
    /// - Returns: The location the app should use.
    public nonisolated func location(replacing real: CLLocation?) -> CLLocation? {
        spoofedLocation ?? real
    }

    /// `real`, or the spoofed location alone in its place while spoofing: for
    /// `locationManager(_:didUpdateLocations:)`.
    ///
    /// - Parameter real: The readings Core Location delivered.
    /// - Returns: The locations the app should use.
    public nonisolated func locations(replacing real: [CLLocation]) -> [CLLocation] {
        spoofedLocation.map { [$0] } ?? real
    }

    /// The coordinate spoofed now: none once the session it was set in has expired.
    private nonisolated var currentCoordinate: LocationCoordinate? {
        let spoof = spoof.withLock { $0 }
        guard let spoof, now() < spoof.expires else { return nil }
        return spoof.coordinate
    }

    // MARK: - Commands

    /// Does what `command` asks: a spoof only within an open session, and only a coordinate on the
    /// Earth.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case let .spoof(coordinate):
            guard coordinate.isValid else {
                Self.logger.notice("Ignored a coordinate off the Earth")
                return
            }
            guard let session else {
                Self.logger.notice("Ignored a spoof outside a session")
                return
            }
            guard coordinate != snapshot.coordinate else { return }
            // Recorded before the host is told, so a kill from here on leaves the flag the next
            // launch tells the host from.
            defaults.set(true, forKey: Self.spoofingDefaultsKey)
            spoof.withLock { $0 = Spoof(coordinate: coordinate, expires: session.expires) }
            snapshot = Snapshot(coordinate: coordinate)
            Self.logger.notice("Location spoofing is on")
            spoofingDidChange(spoofedLocation)
        case .stop:
            stop()
        }
    }

    /// Why the receiver refuses `command` before the model performs it, or `nil` to perform it: a
    /// coordinate off the Earth is ``DebugDrawerAuditEntry/Refusal/malformedCommand``.
    func refusal(of command: Command) -> DebugDrawerAuditEntry.Refusal? {
        switch command {
        case let .spoof(coordinate):
            coordinate.isValid ? nil : .malformedCommand
        case .stop:
            nil
        }
    }

    /// Whether a launch the app was killed in left the spoofing flag: the host is owed an end.
    var isLeftByKilledLaunch: Bool {
        snapshot.coordinate == nil && defaults.bool(forKey: Self.spoofingDefaultsKey)
    }

    /// Tells the host that the spoof a killed launch left is over, and removes its flag.
    func endSpoofLeftByKilledLaunch() {
        Self.logger.notice("Location spoofing left by an earlier launch is over")
        spoofingDidChange(nil)
        defaults.removeObject(forKey: Self.spoofingDefaultsKey)
    }

    private func stop() {
        guard snapshot.coordinate != nil else { return }
        spoof.withLock { $0 = nil }
        snapshot = Snapshot(coordinate: nil)
        Self.logger.notice("Location spoofing is off")
        spoofingDidChange(nil)
        // Removed after the host is told, so a kill between the two tells it again next launch.
        defaults.removeObject(forKey: Self.spoofingDefaultsKey)
    }

    /// Keeps the open session, and stops a spoof whose session is over: the receiver's revert has
    /// already stopped it there, so this is for a model no receiver serves.
    private func follow(_ state: DebugDrawerSessionState) {
        let previous = session
        session = state.session
        if previous?.id != state.session?.id {
            stop()
        }
    }
}
