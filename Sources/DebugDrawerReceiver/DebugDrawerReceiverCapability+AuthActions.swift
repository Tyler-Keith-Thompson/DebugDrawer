import Foundation

extension DebugDrawerReceiverCapability {
    /// Auth actions: a sidecar lists the actions on the app's own sign-in that the host registered
    /// (``DebugDrawerAuthAction/expireAccessToken(summary:handler:)``,
    /// ``DebugDrawerAuthAction/forceRefresh(summary:handler:)``,
    /// ``DebugDrawerAuthAction/logOut(summary:handler:)`` and any of its own) and, within a
    /// session, asks for one, to test how the app handles an expired token, a refresh or a log out
    /// in a release build.
    ///
    /// The risk is low: an employee holding the sidecar can expire, refresh or end the sign-in of
    /// the app on their own device, and log themselves out. The receiver never sees a token: it
    /// runs the host's handler, which takes nothing from the sidecar, and reports back only what it
    /// came to (``DebugDrawerAuthActions/Status``), a failure's message being text from the
    /// app's source (``DebugDrawerAuthAction/Outcome/failed(_:)``). A request for an action the
    /// host didn't register is refused (``DebugDrawerAuditEntry/Refusal/notExposed``) and runs
    /// nothing. Add ``requiringGrant()`` for an action of the host's own that reaches further (ending
    /// sessions on the server, say). It is off until the host enables it, and each request is
    /// written to the audit log as ``DebugDrawerAuditEntry/Event/commandApplied``.
    ///
    /// A request the sidecar leaves while the app is in the background is performed as the app
    /// comes to the foreground; the sidecar opens `launchURL` to bring it there (on the Mac it can
    /// open the app by its bundle identifier instead). What an action does lasts: it isn't
    /// reverted as the session ends.
    ///
    /// ```swift
    /// try receiver.enable(.authActions([
    ///     .expireAccessToken { auth.expireAccessToken(); return .succeeded },
    ///     .logOut { await auth.logOut(); return .succeeded }
    /// ], launchURL: URL(string: "shop-internal://")))
    /// ```
    ///
    /// - Parameters:
    ///   - actions: The actions a sidecar may ask for, in the order to list them; their IDs must
    ///     differ.
    ///   - launchURL: A URL of the app's own scheme that brings it to the foreground, or `nil`.
    /// - Returns: The capability, under ``DebugDrawerAuthActions/pluginID``.
    /// - Throws: ``DebugDrawerAuthActions/DuplicateID`` when two actions share an ID.
    public static func authActions(
        _ actions: [DebugDrawerAuthAction],
        launchURL: URL? = nil
    ) throws(DebugDrawerAuthActions.DuplicateID) -> Self {
        try authActions(DebugDrawerAuthActions(actions: actions, launchURL: launchURL))
    }

    /// Auth actions over a model the host also shows elsewhere, such as in its debug build's
    /// drawer.
    ///
    /// It takes the same risk and limits as the capability made over actions.
    ///
    /// - Parameter model: The actions' model.
    /// - Returns: The capability, under ``DebugDrawerAuthActions/pluginID``.
    public static func authActions(_ model: DebugDrawerAuthActions) -> Self {
        // Persistent, with no revert: a handler did whatever it does (a log out), which the library
        // can't undo. The sessions still gate every request.
        .model(model, id: DebugDrawerAuthActions.pluginID, scope: .persistent, refusal: model.refusal(of:))
    }
}
