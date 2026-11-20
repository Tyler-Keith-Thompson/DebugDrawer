import DebugDrawer
import Foundation
import SwiftUI

// The sidecar's half of allowlisted UserDefaults (DD-127): the keys the app allowlists
// (`DebugDrawerUserDefaults`, in the receiver), each with its value and an editor drawn from its
// declared kind (a text field for strings, a number field for whole numbers and numbers, a switch,
// a picker for a choice), Remove for a key holding a value, and Revert All while any key is
// edited. It ships in the kit, beside Environments, as the keys describe themselves (their kinds
// and bounds are in the snapshot), so every sidecar would draw the same editors. A text or number
// field sends only once Set is pressed, and only a value the key's kind takes, as the receiver
// would refuse anything else; a switch and a picker send as they change. Like Environments it
// doesn't open the app: an edit waits in the store and lands as the app comes to the foreground.

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// The UserDefaults keys the app allowlists (`DebugDrawerReceiverCapability.userDefaults(_:defaults:scope:)`),
        /// each with its value and an editor for its kind, Remove, and Revert All while any key
        /// is edited.
        @MainActor public static var userDefaults: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerUserDefaults.pluginID, title: "UserDefaults", icon: "cylinder.split.1x2",
                snapshot: DebugDrawerUserDefaults.Snapshot.self, command: DebugDrawerUserDefaults.Command.self
            ) { transport in
                UserDefaultsSidecarPlugin(transport: transport)
            }
        }
    }

    /// The app's allowlisted UserDefaults keys, edited from the sidecar.
    struct UserDefaultsSidecarPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<DebugDrawerUserDefaults.Snapshot, DebugDrawerUserDefaults.Command>
        let title = "UserDefaults"
        let icon = "cylinder.split.1x2"

        var body: some View {
            UserDefaultsTransportView(transport: transport)
        }
    }

    /// The keys over the capability's snapshot, sending what the view asks.
    struct UserDefaultsTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerUserDefaults.Snapshot, DebugDrawerUserDefaults.Command>

        var body: some View {
            UserDefaultsEditorView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// The note on what an edit does, each allowlisted key with its editor, and Revert All while
    /// any key is edited. A function of the snapshot and the send action.
    struct UserDefaultsEditorView: View {
        let snapshot: DebugDrawerUserDefaults.Snapshot
        let send: (DebugDrawerUserDefaults.Command) -> Void

        var body: some View {
            if snapshot.entries.isEmpty {
                DebugDrawerEmptyState("No Keys", systemImage: "cylinder.split.1x2") {
                    Text("The app allowlists no UserDefaults key.")
                }
            } else {
                DebugDrawerSection("Allowlisted Keys") {
                    Text("An edit changes what the app reads for the key, and is written to the session's audit log.")
                        .debugDrawerFont(.label)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .debugDrawerRowPadding()
                        .accessibilityIdentifier("UserDefaultsNote")
                    ForEach(snapshot.entries, id: \.key) { entry in
                        UserDefaultsEntryRow(entry: entry, isEdited: snapshot.editedKeys.contains(entry.key), send: send)
                    }
                    if !snapshot.editedKeys.isEmpty {
                        DebugDrawerActionRow {
                            Button("Revert All") { send(.revertAll) }
                                .debugDrawerButtonStyle(.secondary)
                                .accessibilityLabel("Revert All")
                                .accessibilityHint("Puts every edited key back as it was before the session edited it")
                        }
                    }
                }
            }
        }
    }

    /// One allowlisted key: its title, its value and kind, and the editor its kind takes.
    struct UserDefaultsEntryRow: View {
        let entry: DebugDrawerUserDefaults.Entry
        let isEdited: Bool
        let send: (DebugDrawerUserDefaults.Command) -> Void
        @State private var draft: String

        init(entry: DebugDrawerUserDefaults.Entry, isEdited: Bool, send: @escaping (DebugDrawerUserDefaults.Command) -> Void) {
            self.entry = entry
            self.isEdited = isEdited
            self.send = send
            _draft = State(initialValue: entry.value?.draftText ?? "")
        }

        var body: some View {
            Group {
                switch entry.kind {
                case .bool:
                    DebugDrawerRow(entry.title, systemImage: nil, details: { details }, accessory: {
                        Toggle(isOn: Binding {
                            entry.value == .bool(true)
                        } set: {
                            send(.set(key: entry.key, value: .bool($0)))
                        }) {
                            Text(entry.title)
                        }
                        .labelsHidden()
                        .accessibilityLabel(entry.title)
                    })
                case let .choice(options):
                    DebugDrawerRow(entry.title, systemImage: nil, details: { details }, accessory: {
                        Picker(entry.title, selection: Binding {
                            if case let .string(option) = entry.value { option } else { "" }
                        } set: { option in
                            // The placeholder for a key holding no value is no option to send.
                            if options.contains(option) {
                                send(.set(key: entry.key, value: .string(option)))
                            }
                        }) {
                            if case let .string(stored) = entry.value, !options.contains(stored) {
                                Text(stored).tag(stored)
                            } else if entry.value == nil {
                                Text("Not Set").tag("")
                            }
                            ForEach(options, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel(entry.title)
                    })
                case .string, .integer, .double:
                    DebugDrawerRow(entry.title, systemImage: nil, details: { details }, accessory: {
                        HStack(spacing: 6) {
                            TextField(entry.title, text: $draft)
                                .debugDrawerTextFieldStyle()
                            #if os(iOS)
                                .keyboardType(entry.kind.isNumeric ? .numbersAndPunctuation : .default)
                            #endif
                                .accessibilityLabel(entry.title)
                            Button("Set") {
                                if let value = entry.kind.value(from: draft) {
                                    send(.set(key: entry.key, value: value))
                                }
                            }
                            .debugDrawerButtonStyle(.primary)
                            .disabled(entry.kind.value(from: draft) == nil || entry.kind.value(from: draft) == entry.value)
                            .accessibilityLabel("Set \(entry.title)")
                        }
                    })
                }
            }
            .onChange(of: entry.value) { _, value in
                draft = value?.draftText ?? ""
            }
            .accessibilityIdentifier("UserDefaults-\(entry.key)")
        }

        @ViewBuilder
        private var details: some View {
            Text(entry.key)
            Text(entry.value.map(\.summary) ?? "Not set")
            if let bounds = entry.kind.summary {
                Text(bounds)
            }
            if isEdited {
                Text("Edited")
                    .debugDrawerForegroundStyle(.accent)
            }
            if entry.value != nil {
                Button("Remove") { send(.remove(key: entry.key)) }
                    .debugDrawerButtonStyle(.secondary)
                    .accessibilityLabel("Remove \(entry.title)")
                    .accessibilityHint("The app reads its registered default again")
            }
        }
    }

    extension DebugDrawerUserDefaultsValue {
        /// The value as a text field starts at.
        fileprivate var draftText: String {
            switch self {
            case let .string(text): text
            case let .integer(number): String(number)
            case let .double(number): String(number)
            case let .bool(isOn): isOn ? "true" : "false"
            }
        }

        /// The value as the row says it.
        fileprivate var summary: String {
            switch self {
            case let .string(text): "\"\(text)\""
            case let .integer(number): String(number)
            case let .double(number): number.formatted()
            case let .bool(isOn): isOn ? "On" : "Off"
            }
        }
    }

    extension DebugDrawerUserDefaultsKey.Kind {
        /// Whether a text field for it takes a number.
        fileprivate var isNumeric: Bool {
            switch self {
            case .integer, .double: true
            case .string, .bool, .choice: false
            }
        }

        /// The value `text` is for a key of this kind, or `nil` when it isn't one the kind takes:
        /// the receiver would refuse it.
        func value(from text: String) -> DebugDrawerUserDefaultsValue? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let value: DebugDrawerUserDefaultsValue? = switch self {
            case .string: .string(text)
            case .integer: Int(trimmed).map(DebugDrawerUserDefaultsValue.integer)
            case .double: Double(trimmed).map(DebugDrawerUserDefaultsValue.double)
            case .bool, .choice: nil
            }
            return value.flatMap { accepts($0) ? $0 : nil }
        }

        /// The bounds as the row says them, or `nil` for a kind whose editor shows them.
        fileprivate var summary: String? {
            switch self {
            case let .string(maximumLength): "At most \(maximumLength) characters"
            case let .integer(range):
                switch (range.lowerBound, range.upperBound) {
                case (.min, .max): "A whole number"
                case (.min, _): "A whole number, at most \(range.upperBound)"
                case (_, .max): "A whole number, at least \(range.lowerBound)"
                default: "A whole number from \(range.lowerBound) to \(range.upperBound)"
                }
            case let .double(range):
                range == -Double.greatestFiniteMagnitude ... Double.greatestFiniteMagnitude
                    ? "A number"
                    : "A number from \(range.lowerBound.formatted()) to \(range.upperBound.formatted())"
            case .bool, .choice: nil
            }
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The UserDefaults keys the app allowlists; release builds show nothing.
        @MainActor public static var userDefaults: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerUserDefaults.pluginID, title: "UserDefaults", icon: "cylinder.split.1x2",
                snapshot: DebugDrawerUserDefaults.Snapshot.self, command: DebugDrawerUserDefaults.Command.self
            ) { _ in
                UserDefaultsSidecarPlugin()
            }
        }
    }

    /// Draws nothing.
    struct UserDefaultsSidecarPlugin: DebugDrawerPlugin {
        let title = "UserDefaults"
        let icon = "cylinder.split.1x2"

        var body: some View {
            EmptyView()
        }
    }
#endif
