import Combine
import Foundation
import os

// The auth actions' model (DD-117). Each action is a host closure taking nothing, so the receiver's
// part is to pick one by an ID the host registered, refusing any other as `notExposed` before the
// model sees it (`refusal(of:)`), and to report what it came to. Nothing received reaches a
// handler, and nothing a handler holds reaches the snapshot but its outcome: a fixed status, with a
// failure's message a `StaticString` from the app's source (`DebugDrawerAuthAction.Outcome`), so a
// token can't be handed back by mistake. The snapshot has no field a credential could go in.
//
// Its own capability rather than well-known scenarios (DD-116): a scenario's handler returns
// nothing, so a launch couldn't say whether the refresh worked; the actions need a capability ID of
// their own, so a grant can allow scenarios without allowing a log out, and `.requiringGrant()`
// applies to these alone; and the sidecar draws a button per action with its result, not a form.
// What they share, an ID picking one of the host's closures, is a dictionary lookup; the rest
// (parameters, their checks) the actions don't have.
//
// Running a handler can't be undone by the library (a log out is a log out), so the capability is
// persistent, with no revert; the sessions still gate every request.

/// The model behind the auth actions ``DebugDrawerReceiverCapability``: the actions the host
/// registered, each with what its last run came to.
///
/// A debug build can show the same model in its drawer, through
/// `DebugDrawerPluginTransport.direct(to:)`, while the receiver serves it.
@MainActor
public final class DebugDrawerAuthActions: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerReceiver", category: "DebugDrawerAuthActions")

    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.AuthActions"

    /// Where a run of an action is.
    public enum Status: Codable, Equatable, Sendable {
        /// The handler hasn't returned yet.
        case running
        /// The handler returned ``DebugDrawerAuthAction/Outcome/succeeded``.
        case succeeded
        /// The handler returned ``DebugDrawerAuthAction/Outcome/failed(_:)`` with `message`, text
        /// from the app's source, at most ``Run/maximumMessageLength`` characters.
        case failed(message: String)
    }

    /// A run of an action a sidecar asked for.
    public struct Run: Codable, Equatable, Sendable {
        /// The most characters of a failure's message a sidecar is shown.
        public static let maximumMessageLength = 200

        /// Counts the runs of every action since the app started, from 1.
        public let number: Int
        /// When the handler started.
        public let started: Date
        /// Where it is.
        public var status: Status

        /// A run.
        ///
        /// - Parameters:
        ///   - number: Counts the runs since the app started, from 1.
        ///   - started: When the handler started.
        ///   - status: Where it is.
        public init(number: Int, started: Date, status: Status) {
            self.number = number
            self.started = started
            self.status = status
        }
    }

    /// An action as a sidecar lists it: everything but its handler, and its last run.
    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        /// The ID a sidecar asks for it by.
        public let id: String
        /// The name a sidecar lists it under.
        public let title: String
        /// What it does; empty for none.
        public let summary: String
        /// The last run a sidecar asked for since the app started, or `nil`.
        public var lastRun: Run?

        /// An entry.
        ///
        /// - Parameters:
        ///   - id: The ID a sidecar asks for it by.
        ///   - title: The name a sidecar lists it under.
        ///   - summary: What it does.
        ///   - lastRun: The last run a sidecar asked for.
        public init(id: String, title: String, summary: String, lastRun: Run?) {
            self.id = id
            self.title = title
            self.summary = summary
            self.lastRun = lastRun
        }
    }

    /// What a sidecar sees: the actions and their last runs, and how to bring the app forward. No
    /// field holds a credential.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The actions the host registered, in its order.
        public var actions: [Entry]
        /// The URL a sidecar opens to bring the app to the foreground (its URL scheme), or `nil`
        /// when the host declares none; a Mac sidecar opens the app by its bundle identifier.
        public var launchURL: URL?

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - actions: The actions the host registered.
        ///   - launchURL: The URL a sidecar opens to bring the app to the foreground.
        public init(actions: [Entry], launchURL: URL?) {
            self.actions = actions
            self.launchURL = launchURL
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Runs the handler of the action `action`.
        case perform(action: String)
    }

    /// The actions and their last runs now.
    @Published public private(set) var snapshot: Snapshot

    private let actions: [String: DebugDrawerAuthAction]
    private let now: () -> Date
    private var runs = 0

    /// The actions `actions`, asked for from a sidecar that opens the app with `launchURL`.
    ///
    /// Traps when two actions share an ID.
    ///
    /// - Parameters:
    ///   - actions: The actions a sidecar may ask for, in the order to list them.
    ///   - launchURL: A URL of the app's own scheme that brings it to the foreground (on iOS the
    ///     only way a sidecar can); `nil` when it has none. The receiver doesn't need it: a request
    ///     the sidecar leaves is performed as the app comes to the foreground however it got there.
    public convenience init(actions: [DebugDrawerAuthAction], launchURL: URL? = nil) {
        self.init(actions: actions, launchURL: launchURL, now: Date.init)
    }

    /// The actions `actions`, timing runs with `now`.
    package init(actions: [DebugDrawerAuthAction], launchURL: URL?, now: @escaping () -> Date) {
        precondition(Set(actions.map(\.id)).count == actions.count, "Two auth actions share an ID")
        self.actions = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        self.now = now
        snapshot = Snapshot(
            actions: actions.map { Entry(id: $0.id, title: $0.title, summary: $0.summary, lastRun: nil) },
            launchURL: launchURL
        )
    }

    /// Why the receiver refuses `command` before the model performs it, or `nil` to perform it: an
    /// action the host didn't register is ``DebugDrawerAuditEntry/Refusal/notExposed``.
    func refusal(of command: Command) -> DebugDrawerAuditEntry.Refusal? {
        switch command {
        case let .perform(id):
            actions[id] == nil ? .notExposed : nil
        }
    }

    /// Starts the handler of the action `command` names, marking its run ``Status/running``
    /// until the handler returns; does nothing for an action the host didn't register.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case let .perform(id):
            guard let action = actions[id], let index = snapshot.actions.firstIndex(where: { $0.id == id }) else {
                Self.logger.notice("Ignored an auth action the host didn't register")
                return
            }
            runs += 1
            let number = runs
            snapshot.actions[index].lastRun = Run(number: number, started: now(), status: .running)
            // The handler may wait (a refresh goes to the server), and `perform(_:)` doesn't: the
            // outcome lands in a later snapshot, unless a newer run of the action started since.
            Task { [weak self, handler = action.handler] in
                let outcome = await handler()
                self?.finish(run: number, ofActionAt: index, with: outcome)
            }
        }
    }

    private func finish(run number: Int, ofActionAt index: Int, with outcome: DebugDrawerAuthAction.Outcome) {
        guard snapshot.actions[index].lastRun?.number == number else { return }
        snapshot.actions[index].lastRun?.status = Status(outcome)
    }
}

extension DebugDrawerAuthActions.Status {
    /// The status a handler's outcome reads as, a failure's message cut to the most a sidecar is
    /// shown.
    fileprivate init(_ outcome: DebugDrawerAuthAction.Outcome) {
        switch outcome {
        case .succeeded:
            self = .succeeded
        case let .failed(message):
            self = .failed(message: String(message.description.prefix(DebugDrawerAuthActions.Run.maximumMessageLength)))
        }
    }
}
