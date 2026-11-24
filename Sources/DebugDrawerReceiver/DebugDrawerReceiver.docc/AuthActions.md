# Expiring Tokens, Refreshing and Logging Out

Test how a release build handles its access token expiring, a forced refresh or a log out, from the
sidecar.

## Overview

The app registers actions on its own sign-in. Each is a handler of the app's that takes nothing and
says what it came to. The sidecar lists them, a button each, with the last result:

```swift
@MainActor
final class AuthService {
    private var accessToken: String? = "access-token-from-the-server"
    private(set) var state = "Signed in"

    func expireAccessToken() { state = "Expired" }
    func refresh() async -> Bool {
        guard accessToken != nil else { return false }
        accessToken = "a-new-access-token"
        state = "Signed in"
        return true
    }
    func logOut() {
        accessToken = nil
        state = "Signed out"
    }
}

@MainActor
final class ProductionAuthActions {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(auth: AuthService, container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.authActions([
            .expireAccessToken {
                auth.expireAccessToken()
                return .succeeded
            },
            .forceRefresh {
                await auth.refresh() ? .succeeded : .failed("Not signed in")
            },
            .logOut {
                auth.logOut()
                return .succeeded
            }
        ], launchURL: URL(string: "shop-internal://")))
        try receiver.start()
    }
}
```

### The risk: low

An employee holding the sidecar can expire, refresh or end the sign-in of the app on their own
device, and so log themselves out. An action of your own that reaches further
(`DebugDrawerAuthAction(_:title:summary:handler:)`, such as ending every session on the server)
deserves `.requiringGrant()` on the capability.

### Off by default

Until the app enables `.authActions(_:)`, a request is refused as
`commandRefused(.unknownCapability)`, even inside a session. An action the app didn't register is
refused as `commandRefused(.notExposed)` and runs nothing.

### No credential crosses to the sidecar

The receiver never sees a token. It runs the app's handler, which receives nothing from the sidecar,
and hands back only what the handler came to, `DebugDrawerAuthActions.Status` (`running`,
`succeeded`, `failed(message:)`). A failure's message is a `StaticString`, text written in the app's
source, so no value the app holds at run time can reach the sidecar through it; write what a tester
reads ("Not signed in"). The snapshot holds the actions' IDs, titles, summaries and last runs, and
nothing else.

### Within a session, audited, and not reverted

A request is performed only in an open session and audited as `commandApplied`. What the action did
lasts past the session. A request left while the app is in the background runs as the app comes to
the foreground; the sidecar opens `launchURL` (on the Mac, the app by its bundle identifier) to
bring it there, as it does for scenarios (<doc:LaunchScenarios>).

### In the sidecar

The kit's `DebugDrawerSidecarPlugin.authActions` lists the actions with a button each, which sends
the request and then opens the app, and shows each action's last run: running, succeeded, or failed
with the app's message.
