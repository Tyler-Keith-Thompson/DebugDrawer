import Combine

// The model half of a plugin that works apart from its view: state out as Codable snapshots,
// changes in as Codable commands, so a transport can carry both, in the process
// (`DebugDrawerPluginTransport.direct(to:)`) or, later, to a process of its own.
//
// An `ObservableObject`, as every shipped store already is: the model announces a change with
// `objectWillChange` and the transport reads `snapshot` once the change has landed. Rejected: a
// Combine publisher of snapshots on the model (not `Sendable`, so it can't cross to another
// actor or process, and each `@Published` store would need its own after-change plumbing), an
// `AsyncStream` on the model (single-consumer, and a view's first frame would wait a hop for
// it), and `async` commands (a hop before every edit, which a text field bound through it shows
// as dropped keystrokes; a model starts its own tasks for work that waits).

/// A plugin's state and behavior without its views: a ``snapshot`` of what it holds, and
/// commands that change it.
///
/// A plugin adopts it when its data should be readable, and drivable, apart from the SwiftUI view
/// that shows it in the drawer: by a test, by another tool, or by a transport that carries it to
/// another process. The model holds no SwiftUI types: colors, fonts and formatting belong to the
/// views. The services it uses (storage, a clock, the network) come in through its initializer.
///
/// The plugin's view then takes a `DebugDrawerPluginTransport`, rather than the model, and
/// draws from its snapshot and sends it commands; `DebugDrawerPluginTransport.direct(to:)`
/// joins the two in the process.
///
/// ```swift
/// @MainActor
/// final class CounterModel: DebugDrawerPluginModel {
///     struct Snapshot: Codable, Equatable, Sendable {
///         var count = 0
///     }
///
///     enum Command: Codable, Sendable {
///         case increment
///         case reset
///     }
///
///     @Published private(set) var snapshot = Snapshot()
///
///     func perform(_ command: Command) {
///         switch command {
///         case .increment: snapshot.count += 1
///         case .reset: snapshot.count = 0
///         }
///     }
/// }
/// ```
///
/// A plugin that doesn't adopt it keeps working as it does: the drawer still shows its
/// `DebugDrawerPlugin.body`. The protocol exists in every build, so a conformance compiles in
/// release too.
@MainActor
public protocol DebugDrawerPluginModel: ObservableObject {
    /// Everything the plugin's view shows, as a value: `Codable` so a transport can carry it, and
    /// `Equatable` so a reader can tell whether it changed.
    associatedtype Snapshot: Codable & Equatable & Sendable
    /// What the plugin's view asks the model to do, as a value a transport can carry.
    associatedtype Command: Codable & Sendable

    /// The model's state now. Read it after `objectWillChange` fires, once the change has landed.
    var snapshot: Snapshot { get }

    /// Does what `command` asks. Work that waits (a file read, a request) starts here and lands in
    /// a later snapshot.
    ///
    /// - Parameter command: What to do.
    func perform(_ command: Command)
}
