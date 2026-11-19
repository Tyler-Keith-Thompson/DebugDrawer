import DebugDrawer
import Foundation
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that swizzles and registers nothing.

/// The app's file calls as they happen: reads, writes, creates, deletes, listings, stats, copies
/// and moves, each with its path, size, duration, thread and error, and running totals of them.
///
/// `installDiskIO()` swizzles these, and records each call the app makes through them:
///
/// - `FileManager`: `contents(atPath:)`, `createFile(atPath:contents:attributes:)`,
///   `createDirectory` (path and URL), `removeItem`, `contentsOfDirectory`, `copyItem` and
///   `moveItem` (each by path and by URL), and `attributesOfItem(atPath:)`;
/// - `NSData`: `write(toFile:)` and `write(to:)` (with `atomically:` or `options:`), and its
///   `contentsOfFile:` and `contentsOf:` initializers;
/// - `FileHandle`: the Objective-C reads and writes (`readData(ofLength:)`, `readDataToEndOfFile()`,
///   `availableData`, `read(upToCount:)`, `readToEnd()`, `write(_:)`) on regular files.
///
/// On current OSes these never reach a swizzled method, so `installDiskIO()` doesn't record them:
/// Swift's `Data.write(to:)`, `Data(contentsOf:)` and `FileHandle.write(contentsOf:)`, `String`'s
/// file methods, POSIX calls (`open`, `read`, `write`), SQLite, Core Data and `UserDefaults`. Nor
/// is a `FileHandle` call that fails, or the drawer's own file work, which runs with
/// `DebugDrawerActivity.isDrawerWork` bound to `true`.
///
/// `unsafeInstallDiskIOWithInterposing()`, in an app that links the `DebugDrawerDiskIOInterposer`
/// dynamic library, records those too: each `read`, `write`, `pread` and `pwrite` on a regular
/// file that no swizzled method records, through dyld interposing.
public struct DiskIOPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "DiskIOPlugin"
    }

    public var title = "Disk I/O"
    public var category = "Storage"
    public var icon = "externaldrive"

    #if DEBUG
        /// The model the plugin shows, or `nil` for the shared one.
        private let model: DiskIOModel?

        /// The plugin over the calls `installDiskIO()` records.
        public init() {
            model = nil
        }

        /// - Parameter model: The model to show and install in place of the shared one.
        init(model: DiskIOModel) {
            self.model = model
        }
    #else
        /// The plugin over the calls `installDiskIO()` records.
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            DiskIOPluginView(transport: .direct(to: model ?? .shared))
        #else
            EmptyView()
        #endif
    }

    /// Starts recording (``DiskIOStore/install()``, or
    /// ``DiskIOStore/unsafeInstallWithInterposing()`` once the app asked for it) as `drawer` adds
    /// the plugin. Release builds record nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Stops recording and forgets the recorded calls (``DiskIOStore/uninstall()``) once no
    /// drawer holds the plugin: every swizzled method gets its original implementation back.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Swizzles the file methods ``DiskIOPlugin`` lists and registers the plugin.
    func installDiskIO() {
        #if DEBUG
            // Adding the plugin installs it, which swizzles.
            registerGlobal(DiskIOPlugin())
        #endif
    }

    /// Does what ``installDiskIO()`` does, and also records Swift's `Data.write(to:)`,
    /// `Data(contentsOf:)` and `FileHandle.write(contentsOf:)`, through dyld interposing.
    ///
    /// Unsafe: interposing is undocumented dyld behaviour that a new OS can change or drop, and
    /// it runs the plugin's code inside every `read`, `write`, `pread` and `pwrite` the process
    /// makes. It needs the app to link the `DebugDrawerDiskIOInterposer` dynamic library, which
    /// dyld must load at launch. Without it, and before iOS 18, where swizzling already sees those
    /// calls, this does what ``installDiskIO()`` does.
    func unsafeInstallDiskIOWithInterposing() {
        #if DEBUG
            DiskIOStore.shared.unsafeInstallWithInterposing()
            registerGlobal(DiskIOPlugin())
        #endif
    }
}
