import Combine
import DebugDrawerAppStateReset
import DebugDrawerReceiver
import Foundation

/// The example's state a sidecar may reset: the app allows its UserDefaults and its caches, and
/// nothing else (not the keychain, not its files). Seed Data writes some of each, so a reset has
/// something to clear; the screen shows what is there, read again after each reset.
@MainActor
final class ProductionAppState: ObservableObject {
    /// The defaults keys Seed Data writes.
    static let keys = ["example.lastViewedOrder", "example.onboardingDone", "example.recentSearches"]
    /// The URL that brings the app forward, as the auth actions declare it.
    static let launchURL = URL(string: "debugdrawer-receiver-example://reset")

    /// The resets a sidecar asks for: the categories this host allows.
    let requests: AppStateResetRequests
    /// What is there now, as the screen says it.
    @Published private(set) var summary = ""
    private var resets: AnyCancellable?

    init(sessions: DebugDrawerSessions) {
        requests = AppStateResetRequests(sessions: sessions, allowing: [.userDefaults, .caches], launchURL: Self.launchURL)
        refresh()
        // Read again once a reset has run, which it does as the app comes to the foreground.
        resets = requests.$snapshot.map(\.lastReset).removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.refresh()
        }
    }

    /// Writes the defaults keys and a few cached thumbnails.
    func seed() {
        for (index, key) in Self.keys.enumerated() {
            UserDefaults.standard.set("seeded value \(index)", forKey: key)
        }
        let thumbnails = Self.thumbnails
        try? FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        for index in 1 ... 3 {
            try? Data(repeating: UInt8(index), count: 2048).write(to: thumbnails.appending(path: "\(index).png"))
        }
        refresh()
    }

    /// Reads what is there.
    func refresh() {
        let keys = Self.keys.filter { UserDefaults.standard.object(forKey: $0) != nil }.count
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.thumbnails.path(percentEncoded: false)))?.count ?? 0
        summary = "\(keys) seeded keys, \(files) cached thumbnails"
    }

    /// Where the thumbnails go: the app's Caches, which on a Mac outside the sandbox is its folder
    /// in the shared Caches, the part a reset clears there.
    private static var thumbnails: URL {
        #if os(macOS)
            let caches = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil
                ? URL.cachesDirectory.appending(path: Bundle.main.bundleIdentifier ?? "com.debugdrawer.example.receiver")
                : URL.cachesDirectory
        #else
            let caches = URL.cachesDirectory
        #endif
        return caches.appending(path: "Example Thumbnails", directoryHint: .isDirectory)
    }
}
