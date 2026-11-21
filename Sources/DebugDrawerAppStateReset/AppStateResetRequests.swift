import Combine
import CryptoKit
import DebugDrawerReceiver
import Foundation

// The production half of the Reset App State plugin (DD-36, DD-118): the same categories, read
// and deleted by the same code (`AppState`), asked for from a sidecar instead of the drawer. The
// risk is data loss on the employee's own device, so everything leans to deleting less:
//
// - The host allows categories, and the keychain only on its own (`allowingKeychain`), never as a
//   member of `.all`.
// - Nothing is read until a sidecar asks, within a session (`refresh`): an enabled capability
//   costs a production user nothing, and no session reads the keychain or walks the container
//   unless its sidecar shows this capability. Outside a session the snapshot holds nothing of the
//   app's state.
// - The listing names what would go, never a value: defaults keys, file paths from their area,
//   sizes, cookie domains, keychain item classes and services (not accounts, often an email).
// - A reset confirms a revision per category, a digest of what the listing named (not sizes, which
//   change with every request). It is refused (`staleConfirmation`) when the listing has moved on,
//   and not applied when what is read as it runs differs from what was confirmed, so nothing the
//   employee wasn't shown is deleted. Rejected: deleting what was confirmed and leaving what came
//   since (a half-reset app, in a state no install leaves); one revision for the whole listing (a
//   key written to the defaults would refuse a reset of the caches alone).
// - It runs as the app is next in the foreground, never while it is in the background (where a
//   suspended app could be cut off half way, and the person sees nothing happen), and it is
//   dropped when its session ends first, or the app quits first.
// - DebugDrawer's own state stays: keys under `com.debugdrawer.` and `DebugDrawer.`, the files
//   under DebugDrawer's names, and the receiver's store wherever it is. The sessions and the audit
//   log live in memory, which no reset touches.
//
// Persistent scope, with no revert: deleted state can't come back.

/// The model behind the app state reset ``/DebugDrawerReceiver/DebugDrawerReceiverCapability``:
/// what each allowed category would clear, read when a sidecar asks within a session, and the
/// reset it confirms, run as the app next comes to the foreground.
///
/// ```swift
/// let reset = AppStateResetRequests(sessions: sessions, allowing: [.caches, .urlCache])
/// receiver.enable(.appStateReset(reset))
/// ```
@MainActor
public final class AppStateResetRequests: DebugDrawerPluginModel {
    /// The ID the receiver serves it under.
    public nonisolated static let pluginID = "DebugDrawer.AppStateReset"
    /// The most items a category lists, and failures a result names; the rest are counted.
    public nonisolated static let maximumListedItems = 500

    /// What is served now.
    @Published public private(set) var snapshot: Snapshot

    /// The categories a sidecar may clear.
    public let allowed: Set<AppStateReset.Category>

    private var appState: AppState
    private let foreground: any AppForeground
    private let now: () -> Date
    private var pending: [Confirmation]?
    /// The work in hand, each job after the one before, so a reset never reads or deletes beside
    /// another.
    private var work: Task<Void, Never>?
    private var observations: [AnyCancellable] = []

    /// Resets of the running app's state that a sidecar asks for within `sessions`' sessions,
    /// limited to `categories`.
    ///
    /// Traps when `categories` holds ``AppStateReset/Category/keychain``: allow the keychain with
    /// `allowingKeychain` alone.
    ///
    /// The app groups the app's entitlements name are found on their own on the Mac and in a
    /// development or ad hoc build, which embeds a provisioning profile; an App Store or
    /// TestFlight build on a device embeds none, so name its groups in `appGroups`.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions, which the snapshot follows.
    ///   - categories: The categories a sidecar may clear: ``Swift/Set/all`` for every one but the
    ///     keychain, or those you name. ``AppStateReset/Category/appCleanup`` is offered only with
    ///     a `cleanup`.
    ///   - allowingKeychain: Whether a sidecar may also delete every keychain item the app can
    ///     read, which signs the employee out. `false` unless you say otherwise.
    ///   - appGroups: App group identifiers to clear beyond those the entitlements name.
    ///   - directories: Directories beyond the app's containers whose contents count as the app's
    ///     files.
    ///   - cleanup: Cleanup of the app's own, run first, such as closing a database before its
    ///     file is deleted; `nil` for none.
    ///   - launchURL: A URL of the app's own scheme that brings it to the foreground, which a
    ///     sidecar opens after asking for a reset (on iOS the only way it can); `nil` when it has
    ///     none. The reset waits for the foreground however the app gets there.
    public convenience init(
        sessions: DebugDrawerSessions,
        allowing categories: Set<AppStateReset.Category>,
        allowingKeychain: Bool = false,
        appGroups: [String] = [],
        directories: [URL] = [],
        cleanup: AppStateReset.Cleanup? = nil,
        launchURL: URL? = nil
    ) {
        let bundleID = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        var groups = AppGroupEntitlements.identifiers()
        groups += appGroups.filter { !groups.contains($0) }
        var appState = AppState(
            domains: [bundleID] + groups,
            preferences: _PreferenceStore(appDomain: bundleID),
            keychain: _Keychain(),
            container: .current(appGroups: groups, directories: directories, appFolderName: bundleID),
            cookies: _CookieStore(),
            responseCache: URLCache.shared,
            cleanup: cleanup
        )
        appState.namesKeychainAccounts = false
        self.init(
            sessions: sessions, allowing: categories, allowingKeychain: allowingKeychain, appState: appState,
            launchURL: launchURL, foreground: _AppForeground(), now: Date.init
        )
    }

    /// Resets of `appState`, brought forward with `launchURL`, run as `foreground` says the app is in the foreground, timed with
    /// `now`.
    package init(
        sessions: DebugDrawerSessions,
        allowing categories: Set<AppStateReset.Category>,
        allowingKeychain: Bool,
        appState: AppState,
        launchURL: URL?,
        foreground: any AppForeground,
        now: @escaping () -> Date
    ) {
        precondition(!categories.contains(.keychain), "Allow the keychain with allowingKeychain: true, not as a category")
        var allowed = categories
        if allowingKeychain {
            allowed.insert(.keychain)
        }
        if appState.cleanup == nil {
            allowed.remove(.appCleanup)
        }
        self.allowed = allowed
        self.appState = appState
        self.foreground = foreground
        self.now = now
        snapshot = Snapshot(sessionID: nil, allowed: Self.ordered(allowed), activity: .idle, listing: nil, lastReset: nil, launchURL: launchURL)
        // The sessions are main-actor isolated and publish from there.
        observations.append(sessions.$snapshot.sink { [weak self] state in
            MainActor.assumeIsolated {
                self?.follow(state)
            }
        })
        observations.append(foreground.enteredForeground.sink { [weak self] in
            MainActor.assumeIsolated {
                self?.runPending()
            }
        })
    }

    isolated deinit {
        work?.cancel()
    }

    /// Why the receiver refuses `command` before the model performs it, or `nil` to perform it:
    /// a reset of no category, or of one twice, is ``DebugDrawerAuditEntry/Refusal/malformedCommand``;
    /// of a category the host didn't allow, ``DebugDrawerAuditEntry/Refusal/notExposed``; and of
    /// one whose listing isn't at the confirmed revision (or wasn't read in this session),
    /// ``DebugDrawerAuditEntry/Refusal/staleConfirmation``.
    func refusal(of command: Command) -> DebugDrawerAuditEntry.Refusal? {
        switch command {
        case .refresh, .cancel:
            return nil
        case let .reset(confirmations):
            let categories = confirmations.map(\.category)
            guard !categories.isEmpty, Set(categories).count == categories.count else { return .malformedCommand }
            guard Set(categories).isSubset(of: allowed) else { return .notExposed }
            let revisions = Dictionary(uniqueKeysWithValues: (snapshot.listing?.categories ?? []).map { ($0.category, $0.revision) })
            guard confirmations.allSatisfy({ revisions[$0.category] == $0.revision }) else { return .staleConfirmation }
            return nil
        }
    }

    /// Does what `command` asks; outside a session, nothing.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        guard snapshot.sessionID != nil else { return }
        switch command {
        case .refresh:
            if snapshot.activity == .idle {
                snapshot.activity = .reading
            }
            enqueue { model in
                await model.readListing()
            }
        case let .reset(confirmations):
            pending = confirmations
            let categories = Self.ordered(Set(confirmations.map(\.category)))
            snapshot.activity = .waitingForForeground(PendingReset(categories: categories, requested: now()))
            if foreground.isInForeground {
                runPending()
            }
        case .cancel:
            guard pending != nil else { return }
            pending = nil
            snapshot.activity = .idle
        }
    }

    /// Keeps the receiver's store, wherever it is: the store a snapshot file of the receiver's is
    /// in.
    func keepStore(ofSnapshotFile file: URL) {
        appState.container.kept.append(AppGroupStoreLayout.store(ofSnapshotFile: file))
    }

    /// Serves each new session from scratch, and drops what the one before read or asked for: a
    /// reset still waiting doesn't outlive its session.
    private func follow(_ state: DebugDrawerSessionState) {
        let sessionID = state.session?.id
        guard sessionID != snapshot.sessionID else { return }
        pending = nil
        snapshot = Snapshot(
            sessionID: sessionID, allowed: snapshot.allowed, activity: .idle, listing: nil, lastReset: nil, launchURL: snapshot.launchURL
        )
    }

    /// Runs the reset waiting, if one is.
    private func runPending() {
        guard let confirmations = pending, snapshot.sessionID != nil else { return }
        pending = nil
        snapshot.activity = .resetting
        enqueue { model in
            await model.reset(confirmations)
        }
    }

    /// Runs `job` after the work in hand.
    private func enqueue(_ job: @escaping @MainActor (AppStateResetRequests) async -> Void) {
        work = Task { [weak self, previous = work] in
            await previous?.value
            guard let self else { return }
            await job(self)
        }
    }

    /// Reads every allowed category into the listing, unless the session changed meanwhile.
    private func readListing() async {
        let sessionID = snapshot.sessionID
        let plan = await appState.plan(of: allowed, includingDebugDrawer: false)
        guard snapshot.sessionID == sessionID, sessionID != nil else { return }
        snapshot.listing = listing(of: plan)
        if snapshot.activity == .reading {
            snapshot.activity = .idle
        }
    }

    /// Reads the confirmed categories again and deletes what they hold, if it is what was
    /// confirmed; then reads the listing again. A session that ended meanwhile keeps nothing of it.
    private func reset(_ confirmations: [Confirmation]) async {
        let sessionID = snapshot.sessionID
        let plan = await appState.plan(of: allowed, includingDebugDrawer: false)
        // The session ended while the plan was read: the reset goes with it.
        guard snapshot.sessionID == sessionID, sessionID != nil else { return }
        let changed = confirmations.filter { revision(of: $0.category, in: plan) != $0.revision }.map(\.category)
        let outcome: Outcome
        if changed.isEmpty {
            let result = await appState.reset(Set(confirmations.map(\.category)), of: plan)
            outcome = .applied(AppStateReset.Category.resetOrder.compactMap { category in
                result.outcomes[category].map { CategoryResult(category, $0) }
            })
        } else {
            outcome = .notApplied(changed: Self.ordered(Set(changed)))
        }
        let after = await appState.plan(of: allowed, includingDebugDrawer: false)
        guard snapshot.sessionID == sessionID, sessionID != nil else { return }
        snapshot.lastReset = Report(finished: now(), outcome: outcome)
        snapshot.listing = listing(of: after)
        if snapshot.activity == .resetting {
            snapshot.activity = .idle
        }
    }

    private func listing(of plan: ResetPlan) -> Listing {
        Listing(read: now(), categories: Self.ordered(allowed).map { category in
            let items = plan.listedItems(of: category)
            return CategoryListing(
                category: category,
                summary: plan.summary(of: category),
                items: Array(items.prefix(Self.maximumListedItems)),
                unlistedCount: max(0, items.count - Self.maximumListedItems),
                problem: plan.problem(of: category),
                revision: revision(of: category, in: plan)
            )
        })
    }

    /// A digest of what `category` would clear in `plan`, by name.
    private func revision(of category: AppStateReset.Category, in plan: ResetPlan) -> String {
        let names = plan.identities(of: category).joined(separator: "\u{0}")
        return SHA256.hash(data: Data("\(category.rawValue)\u{0}\(names)".utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func ordered(_ categories: Set<AppStateReset.Category>) -> [AppStateReset.Category] {
        AppStateReset.Category.allCases.filter(categories.contains)
    }
}

extension AppStateResetRequests.CategoryResult {
    /// What a reset did to `category`, as a sidecar reads it.
    fileprivate init(_ category: AppStateReset.Category, _ outcome: ResetOutcome) {
        switch outcome {
        case let .cleared(count):
            self.init(category: category, cleared: count, failures: [])
        case let .failed(cleared, failures):
            self.init(category: category, cleared: cleared, failures: failures.prefix(AppStateResetRequests.maximumListedItems).map(\.message))
        }
    }
}

extension ResetPlan {
    /// What `category` would clear, as a sidecar lists it: the drawer's lines, but a keychain
    /// item by its service, never its account.
    fileprivate func listedItems(of category: AppStateReset.Category) -> [AppStateResetRequests.Item] {
        switch category {
        case .keychain:
            guard case let .items(items) = keychain else { return [] }
            return items.map { AppStateResetRequests.Item(text: $0.listedName, detail: $0.itemClass.title) }
        case .userDefaults, .files, .caches, .cookies, .urlCache, .appCleanup:
            return lines(of: category).map { AppStateResetRequests.Item(text: $0.text, detail: $0.detail) }
        }
    }

    /// What names each thing `category` would clear: sizes and counts left out, as they change
    /// with the app's every request without changing what a reset deletes.
    fileprivate func identities(of category: AppStateReset.Category) -> [String] {
        switch category {
        case .userDefaults:
            return defaults.flatMap { domain in domain.keys.map { "\(domain.name)\u{1}\($0)" } }
        case .keychain:
            switch keychain {
            case let .items(items): return items.map { "\($0.itemClass.title)\u{1}\($0.listedName)" }.sorted()
            case let .unavailable(error): return ["unavailable \(error.status)"]
            }
        case .files:
            return files.map(\.displayPath)
        case .caches:
            return caches.map(\.displayPath)
        case .cookies:
            return Array(Set(cookies.map(\.domain))).sorted()
        case .urlCache:
            return []
        case .appCleanup:
            return cleanup.map { [$0] } ?? []
        }
    }
}
