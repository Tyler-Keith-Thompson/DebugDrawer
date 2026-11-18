/// One button of the test bench: something the app does that a plugin records, such as a failing
/// request for Network or a write on the main thread for Disk I/O.
public struct TestBenchAction: Identifiable, Sendable {
    /// What `-RunTestBench` names it by: "network.failure".
    public let id: String
    /// The button's title.
    public let title: String
    /// The plugin that shows what it does, as the drawer titles it; the test bench groups by it.
    public let plugin: String
    /// Whether `-RunTestBench all` runs it. A crash, a hang and a keychain write run only when
    /// named: the first two end or stall the app, and the last is for the simulator.
    public let isIncludedInAll: Bool
    /// Whether it ends or stalls the app, so the button shows as destructive.
    public let isDestructive: Bool
    private let perform: @MainActor @Sendable () async -> String

    init(
        id: String,
        title: String,
        plugin: String,
        isIncludedInAll: Bool = true,
        isDestructive: Bool = false,
        perform: @escaping @MainActor @Sendable () async -> String
    ) {
        self.id = id
        self.title = title
        self.plugin = plugin
        self.isIncludedInAll = isIncludedInAll
        self.isDestructive = isDestructive
        self.perform = perform
    }

    /// Does what the action does and returns what happened, in a line: "404 in 212 ms".
    @MainActor
    public func run() async -> String {
        await perform()
    }
}

/// The actions whose data one plugin shows.
public struct TestBenchSection: Identifiable, Sendable {
    /// The plugin, as the drawer titles it.
    public let plugin: String
    /// Its actions, in the order the test bench lists them.
    public let actions: [TestBenchAction]

    public var id: String {
        plugin
    }
}
