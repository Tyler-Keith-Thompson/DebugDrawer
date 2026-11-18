import SwiftUI

/// The test bench as a list: a section per plugin, a button per action, and what the action did
/// under its button.
public struct TestBenchList: View {
    @State private var outcomes: [TestBenchAction.ID: String] = [:]

    public init() {}

    public var body: some View {
        List {
            ForEach(TestBench.sections) { section in
                Section(section.plugin) {
                    ForEach(section.actions) { action in
                        row(action)
                    }
                }
            }
        }
        .navigationTitle("Test Bench")
    }

    private func row(_ action: TestBenchAction) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action.title, role: action.isDestructive ? .destructive : nil) {
                outcomes[action.id] = "Running…"
                Task { outcomes[action.id] = await action.run() }
            }
            if let outcome = outcomes[action.id] {
                Text(outcome)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
