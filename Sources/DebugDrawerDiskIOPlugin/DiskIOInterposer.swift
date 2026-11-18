#if DEBUG
    import Darwin
    import Foundation
    import os

    /// Turns on the hooks of the DebugDrawerDiskIOInterposer library, when the app links it, and
    /// records what they see. Started once, by `unsafeInstallDiskIOWithInterposing()`.
    ///
    /// The plugin doesn't link the library: it looks the library's start function up with `dlsym`,
    /// so an app that doesn't link it pays nothing and the plugin behaves as `installDiskIO()` does.
    enum DiskIOInterposer {
        /// Starts the library's hooks where swizzling can't see Swift's own file calls.
        static func start() {
            _ = started
        }

        private static let logger = Logger(subsystem: "DebugDrawerDiskIOPlugin", category: "DiskIOInterposer")

        /// Interposing only where it is needed: from macOS 15 and iOS 18 (tvOS 18 and visionOS 2,
        /// where the plugin isn't built yet), Foundation's `Data.write(to:)`, `Data(contentsOf:)`
        /// and `FileHandle.write(contentsOf:)` are Swift (swift-foundation) and reach no
        /// Objective-C method, so swizzling misses them. Before that, on iOS 17 and Mac Catalyst
        /// 17, the Swift overlay forwarded them to `NSData` and `FileHandle` methods the swizzler
        /// already records, so the install leaves the library's hooks off there and behaves as
        /// `installDiskIO()` does. macOS 15 is the package's minimum, so every Mac interposes.
        private static let started: Void = {
            guard #available(macOS 15, iOS 18, tvOS 18, visionOS 2, watchOS 11, *) else { return }
            // RTLD_DEFAULT, which Swift doesn't import: search every image loaded.
            let everyImage = UnsafeMutableRawPointer(bitPattern: -2)
            guard let symbol = dlsym(everyImage, "DebugDrawerDiskIOInterposerStart") else {
                logger.notice("DebugDrawerDiskIOInterposer isn't linked; Disk I/O records only the swizzled calls")
                return
            }
            let start = unsafeBitCast(symbol, to: Start.self)
            if !start(record) {
                logger.notice("dyld didn't apply DebugDrawerDiskIOInterposer's interposing; Disk I/O records only the swizzled calls")
            }
        }()

        private typealias Handler = @convention(c) (Bool, UnsafePointer<CChar>?, Int64, UInt64, Bool, Int32) -> Void
        private typealias Start = @convention(c) (Handler) -> Bool

        // Runs on the thread that made the call, inside the library's re-entrancy guard: a file
        // call made from here goes straight to the system, unrecorded.
        private static let record: Handler = { isWrite, path, bytes, nanoseconds, isMainThread, error in
            guard let path, DiskIOCall.isRecordable else { return }
            DiskIORecorder.shared.record(IOEvent(
                timestamp: Date(), operation: isWrite ? .write : .read, path: String(cString: path), size: bytes,
                duration: TimeInterval(nanoseconds) / 1_000_000_000, isMainThread: isMainThread,
                error: error == 0 ? nil : NSError(domain: NSPOSIXErrorDomain, code: Int(error))
            ))
        }
    }
#endif
