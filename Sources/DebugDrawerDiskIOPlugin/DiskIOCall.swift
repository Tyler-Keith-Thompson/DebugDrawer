#if DEBUG
    import DebugDrawer
    import Foundation

    /// One file call being recorded: when it started and on which thread.
    ///
    /// A swizzled method asks ``begin()`` for one before calling the original, and ends it with
    /// the outcome. `begin()` returns `nil`, and the method calls the original unrecorded, for the
    /// drawer's own work (`DebugDrawerActivity.isDrawerWork`) and for a call made while another
    /// recorded call runs on the same thread: Foundation implements some of the swizzled methods
    /// with others (`createDirectory(at:)` calls `createDirectory(atPath:)`, `NSData(contentsOf:)`
    /// reads through `initWithContentsOfFile:`, and `readToEnd()` through `readDataOfLength:`),
    /// and the outermost call is the one the app made.
    struct DiskIOCall {
        private let start: CFAbsoluteTime
        private let isMainThread: Bool

        /// Starts recording a call, or returns `nil` when it shouldn't be recorded.
        static func begin() -> DiskIOCall? {
            guard !DebugDrawerActivity.isDrawerWork else { return nil }
            if let callInProgress {
                guard pthread_getspecific(callInProgress) == nil else { return nil }
                // Any non-nil value marks the thread; nothing reads it back.
                pthread_setspecific(callInProgress, UnsafeRawPointer(bitPattern: 1))
            }
            // Cleared so a call that fails without an error object reports its own errno.
            errno = 0
            return DiskIOCall(start: CFAbsoluteTimeGetCurrent(), isMainThread: Thread.isMainThread)
        }

        /// Whether a call the interposer saw on this thread belongs in the record: it isn't the
        /// drawer's own work, nor made inside a swizzled call being recorded, whose event covers it.
        static var isRecordable: Bool {
            guard !DebugDrawerActivity.isDrawerWork else { return false }
            guard let callInProgress else { return true }
            return pthread_getspecific(callInProgress) == nil
        }

        /// Ends the call, recording it unless `operation` is `nil`.
        ///
        /// An Objective-C exception the original raises unwinds past `end`, and the thread then
        /// records nothing more; only the legacy `FileHandle` methods raise, and an app that
        /// doesn't catch the exception stops there anyway.
        func end(
            _ operation: IOEvent.Operation?, path: @autoclosure () -> String, destination: String? = nil,
            size: Int64 = 0, error: (any Error)? = nil
        ) {
            let duration = CFAbsoluteTimeGetCurrent() - start
            if let callInProgress { pthread_setspecific(callInProgress, nil) }
            guard let operation else { return }
            DiskIORecorder.shared.record(IOEvent(
                timestamp: Date(), operation: operation, path: path(), destination: destination,
                size: error == nil ? size : 0, duration: duration, isMainThread: isMainThread, error: error.map { $0 as NSError }
            ))
        }

        /// The error a call that reports failure only by its return value left in `errno`, or a
        /// Cocoa `code` error when it left none.
        static func lastError(else code: CocoaError.Code) -> NSError {
            let number = errno
            return number == 0
                ? CocoaError(code) as NSError
                : NSError(domain: NSPOSIXErrorDomain, code: Int(number))
        }
    }

    // A thread-local flag rather than a task-local one: binding a task-local value allocates on
    // every call, and the flag only spans a synchronous call on one thread.
    // `nil` only when the process has used up its keys (512); nested calls are then recorded
    // twice, which beats recording nothing.
    private let callInProgress: pthread_key_t? = {
        var key = pthread_key_t()
        return pthread_key_create(&key, nil) == 0 ? key : nil
    }()
#endif
