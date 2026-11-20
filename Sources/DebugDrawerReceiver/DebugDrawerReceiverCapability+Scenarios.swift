import Foundation

extension DebugDrawerReceiverCapability {
    /// A scenario launcher: a sidecar lists the scenarios the host registered ("open order 123",
    /// "show the paywall", "onboarding step 3") with their declared parameters and, within a
    /// session, launches one, bringing the app to the foreground and running the host's handler.
    ///
    /// The risk it takes is whatever the host's handlers allow: an employee holding the sidecar can
    /// put their own device in any state a registered scenario reaches, with any value its
    /// parameters take. The receiver passes a handler only a registered scenario's ID and values
    /// for the parameters that scenario declares, each of the parameter's kind and within its
    /// bounds, and evaluates nothing it receives; a command naming any other scenario is refused
    /// (``DebugDrawerAuditEntry/Refusal/notExposed``), one passing a parameter the scenario doesn't
    /// declare or a value it doesn't take is refused
    /// (``DebugDrawerAuditEntry/Refusal/malformedCommand``), and neither runs a handler. So
    /// register only scenarios fit for production, bound their parameters tightly (an order ID's
    /// range, a closed list of plans), and keep server-side checks where the handler reaches the
    /// server. For a scenario too risky for team signing alone, add ``requiringGrant()``. It is
    /// off until the host enables it, and each launch is written to the audit log as
    /// ``DebugDrawerAuditEntry/Event/commandApplied``.
    ///
    /// A launch the sidecar leaves while the app is in the background is performed as the app
    /// comes to the foreground; the sidecar opens `launchURL` to bring it there (on the Mac it can
    /// open the app by its bundle identifier instead). What a scenario does lasts: it isn't
    /// reverted as the session ends.
    ///
    /// ```swift
    /// receiver.enable(.scenarios([openOrder, showPaywall], launchURL: URL(string: "shop-internal://")))
    /// ```
    ///
    /// - Parameters:
    ///   - scenarios: The scenarios a sidecar may launch, in the order to list them; their IDs must
    ///     differ.
    ///   - launchURL: A URL of the app's own scheme that brings it to the foreground, or `nil`.
    /// - Returns: The capability, under ``DebugDrawerScenarios/pluginID``.
    public static func scenarios(_ scenarios: [DebugDrawerScenario], launchURL: URL? = nil) -> Self {
        self.scenarios(DebugDrawerScenarios(scenarios: scenarios, launchURL: launchURL))
    }

    /// A scenario launcher over a model the host also shows elsewhere, such as in its debug build's
    /// drawer.
    ///
    /// It takes the same risk and limits as the capability made over scenarios.
    ///
    /// - Parameter model: The scenarios' model.
    /// - Returns: The capability, under ``DebugDrawerScenarios/pluginID``.
    public static func scenarios(_ model: DebugDrawerScenarios) -> Self {
        // Persistent, with no revert: a scenario's handler did whatever it does, which the library
        // can't undo. The sessions still gate every launch.
        .model(model, id: DebugDrawerScenarios.pluginID, scope: .persistent, refusal: model.refusal(of:))
    }
}
