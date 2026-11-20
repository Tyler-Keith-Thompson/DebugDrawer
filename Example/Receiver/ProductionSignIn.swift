import Combine
import DebugDrawerReceiver
import Foundation

/// The example's sign-in: a fake access token the app holds and never shows, and whether it is
/// signed in, expired or signed out, which the screen shows. A sidecar expires, refreshes and
/// ends it through the auth actions capability; the handlers are the app's own code, and what they
/// hand back is a fixed outcome, never the token.
@MainActor
final class ProductionSignIn: ObservableObject {
    /// Where the sign-in is, as the screen says it.
    enum State: Equatable {
        case signedIn
        case expired
        case signedOut

        var title: String {
            switch self {
            case .signedIn: "Signed in"
            case .expired: "Signed in, access token expired"
            case .signedOut: "Signed out"
            }
        }
    }

    /// The URL that brings the app forward: its own scheme, declared in Info.plist's
    /// `CFBundleURLTypes`, which the iOS sidecar opens. The app needn't do anything with it.
    static let launchURL = URL(string: "debugdrawer-receiver-example://auth")

    @Published private(set) var state = State.signedIn
    /// The signed-in account's ID while signed in, which the app state capability hashes before it
    /// leaves the app; the sidecar never sees it raw.
    var userID: String? {
        accessToken == nil ? nil : "example-user-1042"
    }

    /// Stands in for the token a server issued. The screen shows only `state`, and no handler
    /// returns it.
    private var accessToken: String? = ProductionSignIn.issueToken()

    /// The actions a sidecar may ask for: the three well-known ones, each refusing with a fixed
    /// message when there is no sign-in to act on.
    var actions: [DebugDrawerAuthAction] {
        [
            .expireAccessToken { [weak self] in
                guard let self, accessToken != nil else { return .failed("Not signed in") }
                state = .expired
                return .succeeded
            },
            .forceRefresh { [weak self] in
                guard let self, accessToken != nil else { return .failed("Not signed in") }
                accessToken = Self.issueToken()
                state = .signedIn
                return .succeeded
            },
            .logOut { [weak self] in
                guard let self, accessToken != nil else { return .failed("Already signed out") }
                accessToken = nil
                state = .signedOut
                return .succeeded
            }
        ]
    }

    /// Signs in again, as the app's own sign-in screen would.
    func signIn() {
        accessToken = Self.issueToken()
        state = .signedIn
    }

    /// A new fake token, as a server would issue one.
    private static func issueToken() -> String {
        "example-access-\(UUID().uuidString)"
    }
}
