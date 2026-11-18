import SwiftUI

/// The app the iOS test bundles run inside (TESTED_PLATFORMS in scripts/modules.py), for the
/// identity its entitlements give them. It shows nothing; XCTest loads the bundle into it.
@main
struct TestHost: App {
    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
    }
}
