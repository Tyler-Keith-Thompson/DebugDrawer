#if DEBUG
    import DebugDrawer
    import DebugDrawerNetwork
    import SwiftUI

    /// The Network plugin's header accessory, drawn from the model's snapshots as the plugin's body
    /// is.
    struct NetworkHeaderAccessoryView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<NetworkSnapshot, NetworkCommand>

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<NetworkSnapshot, NetworkCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            NetworkHeaderSummary(
                entries: snapshot.log.captured, activeMocks: snapshot.enabledMockCount, conditions: snapshot.conditionProfiles
            )
        }
    }

    /// How many requests the plugin holds ("38 requests"), after an error glyph with the count of
    /// those that failed, when any did, the conditions on, when any are ("1 active"), and the
    /// number of mocks on, when any are ("2 mocks").
    struct NetworkHeaderSummary: View {
        let total: Int
        let failures: Int
        let activeMocks: Int
        /// The indicator's summary, read by VoiceOver, and its short label.
        let activeConditions: String?
        let activeConditionsLabel: String?

        /// - Parameters:
        ///   - entries: The requests captured.
        ///   - activeMocks: How many mock rules are on.
        ///   - conditions: The conditioning profiles, on or off.
        init(entries: [NetworkEntry], activeMocks: Int = 0, conditions: [NetworkConditionProfile] = []) {
            total = entries.count
            failures = entries.count(where: \.isFailure)
            self.activeMocks = activeMocks
            activeConditions = conditions.activeSummary
            activeConditionsLabel = conditions.activeCountLabel
        }

        var body: some View {
            // Where the row is too narrow for everything, the request count goes first, then the
            // mock count, then the conditions' label, leaving the tortoise: failures and conditions
            // say most about why the app misbehaves.
            ViewThatFits(in: .horizontal) {
                summary(mocks: true, requests: true)
                summary(mocks: true, requests: false)
                summary(mocks: false, requests: false)
                summary(mocks: false, requests: false, conditionsLabel: false)
            }
        }

        private func summary(mocks: Bool, requests: Bool, conditionsLabel: Bool = true) -> some View {
            HStack {
                if failures > 0 {
                    DebugDrawerIssueCount(.error, count: failures)
                }
                NetworkConditionsIndicator(summary: activeConditions, label: activeConditionsLabel, showsLabel: conditionsLabel)
                if mocks, activeMocks > 0 {
                    Text(activeMocks == 1 ? "1 mock" : "\(activeMocks.formatted()) mocks")
                }
                if requests {
                    Text(total == 1 ? "1 request" : "\(total.formatted()) requests")
                }
            }
        }
    }
#endif
