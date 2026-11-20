import DebugDrawer
import Foundation
import SwiftUI

// The sidecar's half of the scenario launcher (DD-116): the scenarios the app registered
// (`DebugDrawerScenarios`, in the receiver), each with a field per declared parameter and Launch,
// which leaves the launch for the app and then brings the app to the foreground, where its receiver
// performs it. It ships in the kit, beside Bug Reports, rather than in each company's sidecar as
// the other capabilities' plugins do: scenarios describe themselves (their parameters' kinds and
// bounds are in the snapshot), so every sidecar would draw the same form, and opening the app is
// the kit's own (`DebugDrawerSidecarApp.open(url:)`), which the plugin reaches through the
// environment the kit's host sets.
//
// The launch is sent before the app is opened, so it is waiting in the store as the app comes
// forward. The form checks each value against its parameter before it sends anything, as the
// receiver will, so a value out of bounds is shown at the field rather than refused in the app.
// Rejected: opening the app first (it could come forward and be suspended again before the launch
// lands), and a deep link carrying the scenario (the app would parse the URL: input the receiver
// never checked).

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// The scenarios the app registered (`DebugDrawerReceiverCapability.scenarios(_:launchURL:)`),
        /// each with a field per parameter and Launch, which sends the launch and brings the app to
        /// the foreground, where its handler runs.
        @MainActor public static var scenarios: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerScenarios.pluginID, title: "Scenarios", icon: "play.rectangle",
                snapshot: DebugDrawerScenarios.Snapshot.self, command: DebugDrawerScenarios.Command.self
            ) { transport in
                ScenariosPlugin(transport: transport)
            }
        }
    }

    extension EnvironmentValues {
        /// The app whose plugin the kit hosts, for a plugin that brings it forward.
        @Entry var debugDrawerSidecarApp: DebugDrawerSidecarApp?
    }

    /// The app's scenarios, launched from the sidecar.
    struct ScenariosPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<DebugDrawerScenarios.Snapshot, DebugDrawerScenarios.Command>
        let title = "Scenarios"
        let icon = "play.rectangle"

        var body: some View {
            ScenariosView(transport: transport)
        }
    }

    /// What became of the last Launch the sidecar made.
    enum ScenarioLaunchStatus: Equatable {
        case idle
        case opening(title: String)
        case opened(title: String)
        case notOpened(title: String)

        /// The status line, or `nil` before any launch.
        var text: String? {
            switch self {
            case .idle: nil
            case let .opening(title): "Sent \(title); opening the app…"
            case let .opened(title): "Sent \(title); the app runs it in the foreground"
            case let .notOpened(title): "Sent \(title); open the app to run it"
            }
        }
    }

    /// Each scenario's form, the last launch the app ran, and what the sidecar's own launch came to.
    struct ScenariosView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerScenarios.Snapshot, DebugDrawerScenarios.Command>
        @Environment(\.debugDrawerSidecarApp) private var app
        @State private var status = ScenarioLaunchStatus.idle

        var body: some View {
            let snapshot = transport.snapshot
            if snapshot.scenarios.isEmpty {
                DebugDrawerEmptyState("No Scenarios", systemImage: "play.rectangle") {
                    Text("The app registers no scenario.")
                }
            } else {
                ForEach(snapshot.scenarios) { entry in
                    ScenarioSection(entry: entry) { arguments in
                        launch(entry, arguments: arguments, url: snapshot.launchURL)
                    }
                }
                DebugDrawerSection("Launches") {
                    DebugDrawerKeyValueRow("Last Run in the App", value: snapshot.lastRun.map { $0.summary(in: snapshot) } ?? "None yet")
                    if let text = status.text {
                        Text(text)
                            .debugDrawerFont(.label)
                            .foregroundStyle(.secondary)
                            .debugDrawerRowPadding()
                            .accessibilityIdentifier("ScenarioLaunchStatus")
                    }
                }
            }
        }

        /// Leaves the launch for the app, then brings the app forward.
        private func launch(_ entry: DebugDrawerScenarios.Entry, arguments: [String: DebugDrawerScenarioValue], url: URL?) {
            transport.send(.run(scenario: entry.id, arguments: arguments))
            status = .opening(title: entry.title)
            Task {
                let opened = await app?.open(url: url) ?? false
                status = opened ? .opened(title: entry.title) : .notOpened(title: entry.title)
            }
        }
    }

    extension DebugDrawerScenarios.Run {
        /// The launch as the sidecar lists it: the scenario's title, its number and time.
        func summary(in snapshot: DebugDrawerScenarios.Snapshot) -> String {
            let title = snapshot.scenarios.first { $0.id == scenario }?.title ?? scenario
            return "\(title) (#\(number)) at \(date.formatted(date: .omitted, time: .standard))"
        }
    }

    /// The values a scenario's form holds as the employee edits them: text for string, integer and
    /// choice parameters, a switch for boolean ones, each starting at the parameter's default.
    struct ScenarioDraft: Equatable {
        var texts: [String: String] = [:]
        var switches: [String: Bool] = [:]

        init(_ entry: DebugDrawerScenarios.Entry) {
            for parameter in entry.parameters {
                switch parameter.defaultValue {
                case let .string(text): texts[parameter.name] = text
                case let .integer(number): texts[parameter.name] = String(number)
                case let .boolean(isOn): switches[parameter.name] = isOn
                }
            }
        }

        /// The value the form holds for `parameter`, or `nil` when it isn't one the parameter takes
        /// (an integer that doesn't parse or is out of range, text too long).
        func value(for parameter: DebugDrawerScenarioParameter) -> DebugDrawerScenarioValue? {
            let value: DebugDrawerScenarioValue? = switch parameter.kind {
            case .string, .choice: texts[parameter.name].map(DebugDrawerScenarioValue.string)
            case .integer: texts[parameter.name].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.map(DebugDrawerScenarioValue.integer)
            case .boolean: switches[parameter.name].map(DebugDrawerScenarioValue.boolean)
            }
            return value.flatMap { parameter.accepts($0) ? $0 : nil }
        }

        /// The launch's arguments, a value for every parameter, or `nil` while any field holds a
        /// value its parameter doesn't take.
        func arguments(for entry: DebugDrawerScenarios.Entry) -> [String: DebugDrawerScenarioValue]? {
            var arguments: [String: DebugDrawerScenarioValue] = [:]
            for parameter in entry.parameters {
                guard let value = value(for: parameter) else { return nil }
                arguments[parameter.name] = value
            }
            return arguments
        }
    }

    /// One scenario: its summary, a field per parameter, and Launch, enabled while every field holds
    /// a value its parameter takes. A function of the entry and the launch action.
    struct ScenarioSection: View {
        let entry: DebugDrawerScenarios.Entry
        let launch: ([String: DebugDrawerScenarioValue]) -> Void
        @State private var draft: ScenarioDraft

        init(entry: DebugDrawerScenarios.Entry, launch: @escaping ([String: DebugDrawerScenarioValue]) -> Void) {
            self.entry = entry
            self.launch = launch
            _draft = State(initialValue: ScenarioDraft(entry))
        }

        var body: some View {
            let arguments = draft.arguments(for: entry)
            DebugDrawerSection(entry.title) {
                if !entry.summary.isEmpty {
                    Text(entry.summary)
                        .debugDrawerFont(.label)
                        .foregroundStyle(.secondary)
                        .debugDrawerRowPadding()
                }
                ForEach(entry.parameters, id: \.name) { parameter in
                    field(for: parameter)
                }
                DebugDrawerActionRow {
                    Button("Launch") {
                        if let arguments {
                            launch(arguments)
                        }
                    }
                    .debugDrawerButtonStyle(.primary)
                    .disabled(arguments == nil)
                    .accessibilityLabel("Launch \(entry.title)")
                }
            }
        }

        @ViewBuilder
        private func field(for parameter: DebugDrawerScenarioParameter) -> some View {
            switch parameter.kind {
            case .string:
                DebugDrawerRow(parameter.title) {
                    TextField(parameter.title, text: text(parameter.name))
                        .debugDrawerTextFieldStyle()
                        .accessibilityLabel(parameter.title)
                }
            case let .integer(range):
                DebugDrawerRow(parameter.title, details: {
                    if draft.value(for: parameter) == nil {
                        Text(range.summary)
                    }
                }, accessory: {
                    TextField(parameter.title, text: text(parameter.name))
                        .debugDrawerTextFieldStyle()
                    #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                    #endif
                        .accessibilityLabel(parameter.title)
                })
            case .boolean:
                DebugDrawerRow(parameter.title, isOn: Binding {
                    draft.switches[parameter.name] ?? false
                } set: {
                    draft.switches[parameter.name] = $0
                })
            case let .choice(options):
                DebugDrawerRow(parameter.title) {
                    Picker(parameter.title, selection: text(parameter.name)) {
                        ForEach(options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel(parameter.title)
                }
            }
        }

        private func text(_ name: String) -> Binding<String> {
            Binding { draft.texts[name] ?? "" } set: { draft.texts[name] = $0 }
        }
    }

    extension ClosedRange<Int> {
        /// The range as a field's hint says it.
        fileprivate var summary: String {
            switch (lowerBound, upperBound) {
            case (.min, .max): "A whole number"
            case (.min, _): "At most \(upperBound)"
            case (_, .max): "At least \(lowerBound)"
            default: "From \(lowerBound) to \(upperBound)"
            }
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The scenarios the app registered; release builds show nothing.
        @MainActor public static var scenarios: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerScenarios.pluginID, title: "Scenarios", icon: "play.rectangle",
                snapshot: DebugDrawerScenarios.Snapshot.self, command: DebugDrawerScenarios.Command.self
            ) { _ in
                ScenariosPlugin()
            }
        }
    }

    /// Draws nothing.
    struct ScenariosPlugin: DebugDrawerPlugin {
        let title = "Scenarios"
        let icon = "play.rectangle"

        var body: some View {
            EmptyView()
        }
    }
#endif
