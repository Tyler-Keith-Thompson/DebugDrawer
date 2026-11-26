import Combine
import DebugDrawerReceiver
import Foundation

// The app state capability's model, read-only (DD-126, charter D9: low risk). It serves the build
// always and everything else only as the host registers it: the flag and experiment overrides and
// the environments are the host's own capability models, read (never copied) as the state is read
// and followed while a session is open, so an override a sidecar sets shows here at once; the user
// ID and the host's values are closures asked as the state is read. A registered model is read from
// whether or not the host also enables it: registering it here is the host's opt-in.
//
// The state is served only while a session is open, as the push registration capability serves its
// token: a hashed user ID still names a person to whoever can match it, so the snapshot file the
// receiver writes into the shared container holds it only while someone is debugging, and is
// rewritten without it as the session ends. Nothing is read outside a session (no closure is asked,
// no hash taken) unless the host itself calls `read()`, as for a bug report's state. Under a grant
// policy a session whose grant doesn't list the capability is served nothing.
//
// The user ID is hashed as it is read (UserIDHasher), so no raw ID is held, published, encoded or
// logged; the host's values are its own choice, and the doc comments tell it never to register a
// secret there.
//
// Rejected: serving whenever enabled (a stable hashed identifier in the shared container with no
// one debugging); pulling the overrides and environments from the receiver's enabled capabilities
// without the host naming them (every new capability would join the state on its own, and the item
// makes each field opt-in); a value type of the host's for the values (its Codable form would
// decide what crosses).

/// A read-only snapshot of the app's state, which the receiver serves under ``pluginID`` while a
/// sidecar's session is open and the sidecar attaches to every report: the version, build and
/// build metadata always, and only what the host registers beside them.
///
/// ```swift
/// let appState = try DebugDrawerAppState(
///     sessions: sessions,
///     featureFlags: flagOverrides,
///     environments: environments,
///     userID: { account.userID },
///     values: [DebugDrawerAppStateField("plan") { .string(account.plan) }]
/// )
/// receiver.enable(.appState(appState))
/// ```
///
/// The user ID is hashed in the process (HMAC-SHA256 under a key of the install's own, kept in the
/// app's defaults), so the same user reads the same on every launch of the install and no raw ID
/// leaves the app.
@MainActor
public final class DebugDrawerAppState: DebugDrawerPluginModel {
    /// The ID the receiver serves it under.
    public static let pluginID = "DebugDrawer.AppState"

    /// What a sidecar sees: nothing but `nil`s while no session is open.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The open session's ID, or `nil` while none is open.
        public var sessionID: UUID?
        /// The app's state as last read; `nil` outside a session.
        public var state: State?

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - sessionID: The open session's ID, or `nil`.
        ///   - state: The app's state, or `nil`.
        public init(sessionID: UUID?, state: State?) {
            self.sessionID = sessionID
            self.state = state
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Reads the state again: the host's values and the user ID, which the model doesn't
        /// follow on its own.
        case refresh
    }

    /// Fields the state can't take.
    public enum InvalidField: Error, Equatable, Sendable {
        /// A field's key is empty.
        case emptyKey
        /// Two fields share a key.
        case duplicateKey
    }

    /// What is served now.
    @Published public private(set) var snapshot = Snapshot(sessionID: nil, state: nil)

    private let identity: AppPresence.Identity
    private let buildMetadata: AppInfoBuildMetadata
    private let featureFlags: DebugDrawerFeatureFlagOverrides?
    private let experiments: DebugDrawerExperimentOverrides?
    private let environments: DebugDrawerEnvironments?
    private let userID: (@MainActor () -> String?)?
    private let fields: [DebugDrawerAppStateField]
    private let hasher: UserIDHasher
    private let now: () -> Date
    private var observations: [AnyCancellable] = []

    /// The app's state, served during `sessions`' open session: the main bundle's version and
    /// build, `buildMetadata`, and each source the host passes.
    ///
    /// Every source is off unless passed: with none, the state holds the build alone.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions, which the snapshot follows.
    ///   - buildMetadata: The commit, branch and CI build; each one `nil` is read from the main
    ///     bundle's Info.plist, as App Info reads it.
    ///   - featureFlags: The feature flag overrides capability's model, whose overridden flags the
    ///     state lists; `nil` to leave them out.
    ///   - experiments: The experiment overrides capability's model, whose experiments the state
    ///     lists with their buckets and whether each is overridden; `nil` to leave them out.
    ///   - environments: The environment switching capability's model, whose active environment
    ///     the state names; `nil` to leave it out.
    ///   - userID: Reads the signed-in user's raw ID, which the state holds only hashed; `nil` to
    ///     leave it out. Return `nil` while no one is signed in.
    ///   - values: The host's own values, each read as the state is read. Never register a secret
    ///     or a raw identifier there: what they return leaves the process.
    ///   - defaults: Where the install's hashing key is kept; the app's own, never an app group's.
    /// - Throws: ``InvalidField/emptyKey`` when a field's key is empty, and
    ///   ``InvalidField/duplicateKey`` when two fields share a key.
    public convenience init(
        sessions: DebugDrawerSessions,
        buildMetadata: AppInfoBuildMetadata = AppInfoBuildMetadata(),
        featureFlags: DebugDrawerFeatureFlagOverrides? = nil,
        experiments: DebugDrawerExperimentOverrides? = nil,
        environments: DebugDrawerEnvironments? = nil,
        userID: (@MainActor () -> String?)? = nil,
        values: [DebugDrawerAppStateField] = [],
        defaults: UserDefaults = .standard
    ) throws(InvalidField) {
        try self.init(
            sessions: sessions, bundle: .main, buildMetadata: buildMetadata, featureFlags: featureFlags, experiments: experiments,
            environments: environments, userID: userID, values: values, defaults: defaults, now: Date.init
        )
    }

    /// The app's state, as `bundle` describes the build, read at `now`.
    ///
    /// - Throws: As ``init(sessions:buildMetadata:featureFlags:experiments:environments:userID:values:defaults:)``
    ///   does.
    package init(
        sessions: DebugDrawerSessions,
        bundle: Bundle,
        buildMetadata: AppInfoBuildMetadata,
        featureFlags: DebugDrawerFeatureFlagOverrides?,
        experiments: DebugDrawerExperimentOverrides?,
        environments: DebugDrawerEnvironments?,
        userID: (@MainActor () -> String?)?,
        values: [DebugDrawerAppStateField],
        defaults: UserDefaults,
        now: @escaping () -> Date
    ) throws(InvalidField) {
        guard !values.contains(where: \.key.isEmpty) else { throw .emptyKey }
        guard Set(values.map(\.key)).count == values.count else { throw .duplicateKey }
        identity = AppPresence.Identity.of(bundle)
        self.buildMetadata = buildMetadata.filled(from: bundle.infoDictionary)
        self.featureFlags = featureFlags
        self.experiments = experiments
        self.environments = environments
        self.userID = userID
        fields = values
        hasher = UserIDHasher(defaults: defaults)
        self.now = now
        // Each publishes from the main actor, the value about to be set; the state takes it from
        // there rather than reading the model, which still holds the old one.
        if let featureFlags {
            observations.append(featureFlags.$snapshot.dropFirst().sink { [weak self] flags in
                MainActor.assumeIsolated { self?.follow(\.featureFlagOverrides, Self.overrides(in: flags)) }
            })
        }
        if let experiments {
            observations.append(experiments.$snapshot.dropFirst().sink { [weak self] experiments in
                MainActor.assumeIsolated { self?.follow(\.experiments, Self.buckets(in: experiments)) }
            })
        }
        if let environments {
            observations.append(environments.$snapshot.dropFirst().sink { [weak self] environments in
                MainActor.assumeIsolated { self?.follow(\.environment, Self.active(in: environments)) }
            })
        }
        // The sessions are main-actor isolated and publish from there.
        observations.append(sessions.$snapshot.sink { [weak self] state in
            MainActor.assumeIsolated { self?.follow(state) }
        })
    }

    /// Reads the app's state now: the build, and each source the host registered, the user ID
    /// hashed. For the host's own use as well, such as the state of a bug report
    /// (`DebugDrawerBugReports(sessions:diagnostics:state:)`).
    ///
    /// - Returns: The state as it is now.
    public func read() -> State {
        State(
            bundleIdentifier: identity.bundleIdentifier,
            version: identity.version,
            build: identity.build,
            buildMetadata: buildMetadata,
            date: now(),
            featureFlagOverrides: featureFlags.map { Self.overrides(in: $0.snapshot) },
            experiments: experiments.map { Self.buckets(in: $0.snapshot) },
            environment: environments.flatMap { Self.active(in: $0.snapshot) },
            hashedUserID: userID?().map(hasher.hash),
            values: fields.isEmpty ? nil : Dictionary(uniqueKeysWithValues: fields.compactMap { field in field.value().map { (field.key, $0) } })
        )
    }

    /// Does what `command` asks.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case .refresh:
            if snapshot.state != nil {
                snapshot.state = read()
            }
        }
    }

    /// Serves the state as a session opens whose grant, if it has one, lists the capability, and
    /// nothing as it ends or expires.
    private func follow(_ state: DebugDrawerSessionState) {
        let session = state.session
        guard session?.id != snapshot.sessionID else { return }
        guard let session, session.allows(Self.pluginID) else {
            snapshot = Snapshot(sessionID: session?.id, state: nil)
            return
        }
        snapshot = Snapshot(sessionID: session.id, state: read())
    }

    /// Takes a registered model's change into the state served, if one is.
    private func follow<Value: Equatable>(_ field: WritableKeyPath<State, Value>, _ value: Value) {
        guard var state = snapshot.state, state[keyPath: field] != value else { return }
        state[keyPath: field] = value
        snapshot.state = state
    }

    private static func overrides(in flags: DebugDrawerFeatureFlagOverrides.Snapshot) -> [String: DebugDrawerFeatureFlagValue] {
        let overridden = Set(flags.overriddenKeys)
        return Dictionary(flags.flags.filter { overridden.contains($0.key) }.map { ($0.key, $0.value) }) { first, _ in first }
    }

    private static func buckets(in experiments: DebugDrawerExperimentOverrides.Snapshot) -> [String: ExperimentBucket] {
        let overridden = Set(experiments.overriddenKeys)
        return Dictionary(experiments.experiments.map { experiment in
            (experiment.key, ExperimentBucket(variant: experiment.assignedVariant, isOverridden: overridden.contains(experiment.key)))
        }) { first, _ in first }
    }

    private static func active(in environments: DebugDrawerEnvironments.Snapshot) -> ActiveEnvironment? {
        environments.environments.first { $0.id == environments.activeEnvironment }.map { active in
            ActiveEnvironment(id: active.id, title: active.title, isSwitched: environments.isSwitched)
        }
    }
}
