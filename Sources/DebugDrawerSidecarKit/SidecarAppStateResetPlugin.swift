import DebugDrawer
import DebugDrawerAppStateReset
import Foundation
import SwiftUI

// The sidecar's half of the app state reset (DD-118): the categories the app allows
// (`AppStateResetRequests`, in DebugDrawerAppStateReset), a checkbox each with what it would
// clear, a confirmation listing exactly that, item by item, and Reset, which leaves the confirmed
// categories at the revisions shown for the app and then brings the app forward, where the reset
// runs. It ships in the kit, beside Scenarios and Auth, for the same reasons: the capability
// describes itself, so every sidecar would draw the same list, and opening the app is the kit's
// own. The kit takes the model's types from the capability itself, not from the Reset App State
// plugin, which builds on fewer platforms (watchOS among them) and whose views it doesn't use.

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// The app state reset the app allows (`DebugDrawerReceiverCapability.appStateReset(_:)`):
        /// a checkbox per category with what it would clear, a confirmation that lists exactly
        /// that, and Reset, which brings the app to the foreground, where it clears it, and what
        /// the last reset cleared.
        @MainActor public static var appStateReset: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: AppStateResetRequests.pluginID, title: "Reset App State", icon: "arrow.counterclockwise.circle",
                snapshot: AppStateResetRequests.Snapshot.self, command: AppStateResetRequests.Command.self
            ) { transport in
                AppStateResetSidecarPlugin(transport: transport)
            }
        }
    }

    /// The app's state reset, asked for from the sidecar.
    struct AppStateResetSidecarPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<AppStateResetRequests.Snapshot, AppStateResetRequests.Command>
        let title = "Reset App State"
        let icon = "arrow.counterclockwise.circle"

        var body: some View {
            AppStateResetSidecarView(transport: transport)
        }
    }

    /// What became of the last reset the sidecar sent.
    enum AppStateResetRequestStatus: Equatable {
        case idle
        case opening
        case opened
        case notOpened

        /// The status line, or `nil` before any reset.
        var text: String? {
            switch self {
            case .idle: nil
            case .opening: "Sent the reset; opening the app…"
            case .opened: "Sent the reset; the app clears it in the foreground"
            case .notOpened: "Sent the reset; open the app to clear it"
            }
        }
    }

    /// The categories, the confirmation and the last reset, over the capability's snapshot. It
    /// keeps the categories ticked and whether the confirmation is open.
    struct AppStateResetSidecarView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<AppStateResetRequests.Snapshot, AppStateResetRequests.Command>
        @Environment(\.debugDrawerSidecarApp) private var app
        @State private var selection: Set<AppStateReset.Category>
        @State private var isConfirming: Bool
        @State private var status = AppStateResetRequestStatus.idle

        /// The view over `transport`, with `selection` ticked and the confirmation open when
        /// `isConfirming`: nothing ticked and the categories shown, to begin with.
        init(
            transport: DebugDrawerPluginTransport<AppStateResetRequests.Snapshot, AppStateResetRequests.Command>,
            selection: Set<AppStateReset.Category> = [],
            isConfirming: Bool = false
        ) {
            self.transport = transport
            _selection = State(initialValue: selection)
            _isConfirming = State(initialValue: isConfirming)
        }

        var body: some View {
            let snapshot = transport.snapshot
            VStack(alignment: .leading, spacing: 0) {
                if snapshot.allowed.isEmpty {
                    DebugDrawerEmptyState("No Categories Allowed", systemImage: "arrow.counterclockwise.circle") {
                        Text("The app allows no category to be reset.")
                    }
                } else if snapshot.sessionID == nil {
                    DebugDrawerEmptyState("No Session", systemImage: "arrow.counterclockwise.circle") {
                        Text("Open a session to list what a reset would clear.")
                    }
                } else {
                    if let report = snapshot.lastReset {
                        AppStateResetReportSection(report: report)
                    }
                    AppStateResetActivityRow(activity: snapshot.activity) { transport.send(.cancel) }
                    if let listing = snapshot.listing {
                        if isConfirming {
                            AppStateResetConfirmationSection(
                                categories: listing.categories.filter { selection.contains($0.category) },
                                reset: { reset(listing, launchURL: snapshot.launchURL) },
                                cancel: { isConfirming = false }
                            )
                        } else {
                            AppStateResetChoiceSection(
                                listing: listing, selection: $selection,
                                refresh: { transport.send(.refresh) },
                                review: { isConfirming = true }
                            )
                        }
                    }
                    if let text = status.text {
                        Text(text)
                            .debugDrawerFont(.label)
                            .foregroundStyle(.secondary)
                            .debugDrawerRowPadding()
                            .accessibilityIdentifier("AppStateResetRequestStatus")
                    }
                }
            }
            .task(id: snapshot.sessionID) {
                // A new session reads nothing until asked, so the plugin asks as it shows one.
                if snapshot.sessionID != nil, snapshot.listing == nil {
                    transport.send(.refresh)
                }
            }
        }

        /// Leaves the reset of the confirmed categories, at the revisions shown, for the app, then
        /// brings the app forward.
        private func reset(_ listing: AppStateResetRequests.Listing, launchURL: URL?) {
            transport.send(.reset(listing.confirmations(of: selection)))
            isConfirming = false
            selection = []
            status = .opening
            Task {
                let opened = await app?.open(url: launchURL) ?? false
                status = opened ? .opened : .notOpened
            }
        }
    }

    extension AppStateResetRequests.Listing {
        /// The confirmations of `selection`, each at the revision this listing shows: what a
        /// reset of them sends.
        func confirmations(of selection: Set<AppStateReset.Category>) -> [AppStateResetRequests.Confirmation] {
            categories.filter { selection.contains($0.category) }.map {
                AppStateResetRequests.Confirmation(category: $0.category, revision: $0.revision)
            }
        }
    }

    /// The categories with a checkbox each and what each would clear, Refresh, and Review, which
    /// opens the confirmation. A function of the listing, the selection and the actions.
    struct AppStateResetChoiceSection: View {
        let listing: AppStateResetRequests.Listing
        @Binding var selection: Set<AppStateReset.Category>
        let refresh: () -> Void
        let review: () -> Void

        var body: some View {
            DebugDrawerSection("Clear") {
                ForEach(listing.categories) { category in
                    DebugDrawerRow(category.category.title, systemImage: category.category.systemImage) {
                        Text(category.summary)
                            .debugDrawerFont(.value)
                        if let problem = category.problem {
                            Text(problem)
                                .debugDrawerForegroundStyle(.error)
                        }
                    } accessory: {
                        Toggle(isOn: isSelected(category.category)) { Text(category.category.title) }
                            .accessibilityLabel("Clear \(category.category.title)")
                    }
                }
                DebugDrawerActionRow {
                    Button("Refresh", action: refresh)
                        .accessibilityHint("Reads what each category holds again")
                } trailing: {
                    Button("Review Reset…", action: review)
                        .debugDrawerButtonStyle(.destructive)
                        .disabled(selection.isEmpty)
                        .accessibilityHint("Lists what the reset clears before it runs")
                }
            }
        }

        private func isSelected(_ category: AppStateReset.Category) -> Binding<Bool> {
            Binding(
                get: { selection.contains(category) },
                set: { isOn in
                    if isOn {
                        selection.insert(category)
                    } else {
                        selection.remove(category)
                    }
                }
            )
        }
    }

    /// The confirmation: exactly what the reset clears, category by category and item by item,
    /// with Cancel and Reset. A function of the listings and the actions.
    struct AppStateResetConfirmationSection: View {
        let categories: [AppStateResetRequests.CategoryListing]
        let reset: () -> Void
        let cancel: () -> Void

        var body: some View {
            DebugDrawerSection("Reset App State?") {
                Text("The app deletes these as it next comes to the foreground; they can't be brought back:")
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.secondary)
                ForEach(categories) { category in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(category.category.title): \(category.summary)")
                            .debugDrawerFont(.label)
                            .accessibilityAddTraits(.isHeader)
                        if category.items.isEmpty {
                            Text("Nothing to delete.")
                                .debugDrawerFont(.secondary)
                                .debugDrawerForegroundStyle(.secondary)
                        }
                        // By position: two keychain items can share a service.
                        ForEach(Array(category.items.enumerated()), id: \.offset) { entry in
                            AppStateResetItemRow(item: entry.element)
                        }
                        if category.unlistedCount > 0 {
                            Text("and \(category.unlistedCount.formatted()) more")
                                .debugDrawerFont(.secondary)
                                .debugDrawerForegroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)
                }
                DebugDrawerActionRow {
                    Button("Cancel", action: cancel)
                        .accessibilityLabel("Cancel the reset")
                } trailing: {
                    Button("Reset", role: .destructive, action: reset)
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel("Reset the app's state")
                }
            }
        }
    }

    /// One thing a category would clear: its name, cut in the middle to fit, and its size, count,
    /// domain or class.
    struct AppStateResetItemRow: View {
        let item: AppStateResetRequests.Item

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.text)
                    .debugDrawerFont(.code)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail = item.detail {
                    Text(detail)
                        .debugDrawerFont(.value)
                        .debugDrawerForegroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// What the capability is doing, with Cancel while a reset waits for the foreground; nothing
    /// while it is idle.
    struct AppStateResetActivityRow: View {
        let activity: AppStateResetRequests.Activity
        let cancel: () -> Void

        var body: some View {
            switch activity {
            case .idle:
                EmptyView()
            case .reading:
                DebugDrawerKeyValueRow("Status", value: "Reading what each category holds…")
            case let .waitingForForeground(pending):
                DebugDrawerIssueRow(
                    "Waiting for the app", status: pending.categories.map(\.title).joined(separator: ", "), severity: .warning
                ) {
                    Text("The app clears these as it next comes to the foreground.")
                } accessory: {
                    Button("Cancel Reset", action: cancel)
                        .accessibilityHint("Drops the reset waiting for the app")
                }
            case .resetting:
                DebugDrawerKeyValueRow("Status", value: "Resetting…")
            }
        }
    }

    /// What the last reset did: each category's count and failures, or why nothing was deleted.
    struct AppStateResetReportSection: View {
        let report: AppStateResetRequests.Report

        var body: some View {
            DebugDrawerSection("Last Reset") {
                switch report.outcome {
                case let .applied(results):
                    ForEach(results, id: \.category) { result in
                        if result.failures.isEmpty {
                            DebugDrawerIssueRow(result.category.title, status: "Cleared \(result.cleared.formatted())", severity: .ok)
                        } else {
                            DebugDrawerIssueRow(
                                result.category.title, status: "\(result.failures.count.formatted()) not deleted", severity: .error
                            ) {
                                ForEach(Array(result.failures.enumerated()), id: \.offset) { Text($0.element) }
                            }
                        }
                    }
                case let .notApplied(changed):
                    DebugDrawerIssueRow("Not reset", status: changed.map(\.title).joined(separator: ", "), severity: .warning) {
                        Text("What these held changed after you confirmed, so nothing was deleted. Review the list and reset again.")
                    }
                }
            }
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The app state reset the app allows; release builds show nothing.
        @MainActor public static var appStateReset: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: AppStateResetRequests.pluginID, title: "Reset App State", icon: "arrow.counterclockwise.circle",
                snapshot: AppStateResetRequests.Snapshot.self, command: AppStateResetRequests.Command.self
            ) { _ in
                AppStateResetSidecarPlugin()
            }
        }
    }

    /// Draws nothing.
    struct AppStateResetSidecarPlugin: DebugDrawerPlugin {
        let title = "Reset App State"
        let icon = "arrow.counterclockwise.circle"

        var body: some View {
            EmptyView()
        }
    }
#endif
