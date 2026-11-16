#if DEBUG
    import Darwin
    import Foundation

    // The crash handlers, in Swift rather than a C target: Swift that touches only raw pointers
    // allocated in advance, integers and libc calls compiles to the same loads, stores and calls C
    // would, with no allocation, reference counting or locks, so it is as async-signal-safe as the
    // C it would replace, and the module graph stays Swift-only.
    //
    // What the signal handler does, and why each step is safe in a signal handler:
    // - Reads `crashHandlerState`, a global pointer set before any handler is installed. Swift
    //   initializes globals lazily through `swift_once`, whose path once initialized is a load and
    //   a compare; `install` initializes it first.
    // - `open(2)`, `write(2)`, `raise(3)`, `sigaction(2)` and `pthread_self` are on POSIX's list of
    //   async-signal-safe functions.
    // - Formats numbers into a buffer allocated at install, and writes `StaticString`s, which are
    //   pointers to constant bytes.
    // - Walks the crashed thread's frame records from the signal's context, reading only addresses
    //   inside that thread's stack (`pthread_get_stackaddr_np` and `pthread_get_stacksize_np` read
    //   the thread's own record, without a lock).
    // - Names the frames with `backtrace_symbols_fd(3)`, the one symbolication call that allocates
    //   nothing: it writes each line straight to the file. It looks symbols up with `dladdr`, which
    //   can block if the app crashed while dyld held its lock (loading a library); the frames are
    //   then lost, and the signal line before them is already written.
    // The uncaught-exception handler runs as an ordinary function before the runtime aborts, so it
    // may use Foundation.

    /// Installs the handlers that write the crash file as the app crashes: one for uncaught
    /// Objective-C exceptions and one for the fatal signals, each calling the handler that was
    /// installed before it, so a crash SDK the app also uses still sees the crash.
    enum CrashCapture {
        /// The signals that end the app on a crash. Swift's runtime failures (a force unwrap of
        /// `nil`, an index out of range, `fatalError`) arrive as `SIGTRAP` on arm64 and as `SIGILL`
        /// on x86_64.
        static let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
        /// The most frames a signal's report holds.
        static let maximumFrames = 128
        /// One more than the highest signal number.
        static let signalCount = 32
        /// The alternate stack the handler runs on, so a stack overflow can still be written.
        static let alternateStackSize = 128 * 1024

        /// Writes the crash file at `crashFile` when the app crashes, from now on.
        ///
        /// The first call installs the handlers; a later call only points them at its file, as
        /// installing again would make each handler its own previous handler.
        ///
        /// - Parameters:
        ///   - crashFile: Where the crash file is written; its directory must exist.
        ///   - appVersion: The app's version and build, written into every report.
        @MainActor static func install(crashFile: URL, appVersion: String?) {
            let path = strdup(crashFile.path(percentEncoded: false))
            let header = Array("\(CrashFile.magic)\n\(appVersion.map { "app \($0)\n" } ?? "")".utf8)
            let headerBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: header.count)
            headerBytes.initialize(from: header, count: header.count)
            if let state = crashHandlerState {
                // The old path and header are leaked rather than freed: a handler on another
                // thread may be reading them.
                state.pointee.path = path
                state.pointee.header = headerBytes
                state.pointee.headerCount = header.count
                return
            }
            let previousActions = UnsafeMutablePointer<sigaction>.allocate(capacity: signalCount)
            previousActions.initialize(repeating: sigaction(), count: signalCount)
            let state = UnsafeMutablePointer<CrashHandlerState>.allocate(capacity: 1)
            state.initialize(to: CrashHandlerState(
                path: path,
                header: headerBytes,
                headerCount: header.count,
                previousActions: previousActions,
                frames: .allocate(capacity: maximumFrames),
                digits: .allocate(capacity: CrashHandlerState.digitCapacity),
                fileDescriptor: -1,
                owner: nil
            ))
            crashHandlerState = state
            installAlternateStack()

            var action = sigaction()
            action.__sigaction_u.__sa_sigaction = handleCrashSignal
            action.sa_flags = SA_SIGINFO | SA_ONSTACK
            action.sa_mask = 0
            for signal in signals {
                sigaction(signal, &action, previousActions + Int(signal))
            }
            previousExceptionHandler = NSGetUncaughtExceptionHandler()
            NSSetUncaughtExceptionHandler(handleUncaughtException)
        }

        /// Gives the installing thread an alternate signal stack, unless it has one (a crash SDK's),
        /// so the handler can run after a stack overflow. Other threads keep running handlers on
        /// their own stacks: a stack overflow there ends the app unrecorded.
        private static func installAlternateStack() {
            var current = stack_t()
            guard sigaltstack(nil, &current) == 0, current.ss_flags & SS_DISABLE != 0,
                  let memory = malloc(alternateStackSize) else { return }
            var stack = stack_t(ss_sp: memory, ss_size: alternateStackSize, ss_flags: 0)
            sigaltstack(&stack, nil)
        }
    }

    /// Everything the handlers use, allocated by `CrashCapture.install` before a handler can run.
    struct CrashHandlerState {
        /// Room for a 64-bit number in decimal with its sign.
        static let digitCapacity = 24

        /// The crash file's path, NUL-terminated.
        var path: UnsafeMutablePointer<CChar>?
        /// The crash file's first lines: the magic and the app's version.
        var header: UnsafeMutablePointer<UInt8>
        var headerCount: Int
        /// The action each signal had before the plugin's, by signal number.
        let previousActions: UnsafeMutablePointer<sigaction>
        let frames: UnsafeMutablePointer<UnsafeMutableRawPointer?>
        let digits: UnsafeMutablePointer<UInt8>
        /// The crash file, once a handler has opened it.
        var fileDescriptor: Int32
        /// The thread that opened it, which alone writes to it.
        var owner: pthread_t?
    }

    /// Set once, before the handlers are installed; the handlers only read it.
    nonisolated(unsafe) private var crashHandlerState: UnsafeMutablePointer<CrashHandlerState>?
    /// The uncaught-exception handler installed before the plugin's, called after it.
    nonisolated(unsafe) private var previousExceptionHandler: (@convention(c) (NSException) -> Void)?

    /// Writes the exception to the crash file, then calls the handler installed before.
    private func handleUncaughtException(_ exception: NSException) {
        if let state = crashHandlerState {
            let file = openCrashFile(state)
            if file >= 0 {
                let reason = (exception.reason ?? "").split(separator: "\n", omittingEmptySubsequences: false)
                let lines = ["exception \(exception.name.rawValue)"]
                    + reason.map { "reason \($0)" }
                    + ["exception-frames"] + exception.callStackSymbols + ["end"]
                var text = lines.joined(separator: "\n") + "\n"
                text.withUTF8 { _ = write(file, $0.baseAddress, $0.count) }
            }
        }
        previousExceptionHandler?(exception)
    }

    /// Writes the signal and the crashed thread's frames to the crash file, then hands the signal
    /// to the action installed before.
    private func handleCrashSignal(_ signal: Int32, _ info: UnsafeMutablePointer<__siginfo>?, _ context: UnsafeMutableRawPointer?) {
        guard let state = crashHandlerState else { return }
        let file = openCrashFile(state)
        if file >= 0 {
            put(file, "signal ")
            put(file, decimal: Int(signal), using: state.pointee.digits)
            put(file, "\nframes\n")
            let count = captureFrames(from: context, into: state.pointee.frames)
            if count > 0 {
                backtrace_symbols_fd(state.pointee.frames, Int32(count), file)
            }
            put(file, "end\n")
        }
        chain(signal, info, context, previous: state.pointee.previousActions[Int(signal)])
    }

    /// The crash file, opened and headed by the first handler to run, or -1 when another
    /// thread's crash is already writing it (or it can't be opened).
    ///
    /// `O_EXCL` makes the open the lock: only one thread creates the file, so two threads
    /// crashing at once can't interleave their lines. The thread that created it keeps writing,
    /// as the signal that follows its own uncaught exception.
    private func openCrashFile(_ state: UnsafeMutablePointer<CrashHandlerState>) -> Int32 {
        let thread = pthread_self()
        if state.pointee.fileDescriptor >= 0 {
            guard let owner = state.pointee.owner, pthread_equal(owner, thread) != 0 else { return -1 }
            return state.pointee.fileDescriptor
        }
        guard let path = state.pointee.path else { return -1 }
        let file = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard file >= 0 else { return -1 }
        state.pointee.owner = thread
        state.pointee.fileDescriptor = file
        _ = write(file, state.pointee.header, state.pointee.headerCount)
        put(file, "time ")
        put(file, decimal: time(nil), using: state.pointee.digits)
        put(file, "\n")
        return file
    }

    /// Restores the action the app had for `signal` before the plugin and runs it: the previous
    /// handler with the signal's own information and context, or, for the default action, the
    /// signal raised again, delivered when this handler returns. An ignored signal stays ignored.
    private func chain(
        _ signal: Int32,
        _ info: UnsafeMutablePointer<__siginfo>?,
        _ context: UnsafeMutableRawPointer?,
        previous: sigaction
    ) {
        var previous = previous
        sigaction(signal, &previous, nil)
        // SIG_DFL is 0 and SIG_IGN is 1, as <sys/signal.h> defines them.
        let handlerAddress = unsafeBitCast(previous.__sigaction_u.__sa_handler, to: UInt.self)
        if handlerAddress == 0 {
            raise(signal)
        } else if handlerAddress == 1 {
            return
        } else if previous.sa_flags & SA_SIGINFO != 0, let handler = previous.__sigaction_u.__sa_sigaction {
            handler(signal, info, context)
        } else if let handler = previous.__sigaction_u.__sa_handler {
            handler(signal)
        }
    }

    /// The crashed instruction, then the return address of each frame record on the crashed
    /// thread's stack, outermost last; how many it wrote.
    ///
    /// The walk starts from the context the kernel saved, not from the handler's own frame,
    /// which runs on the alternate stack. It stops at a frame pointer outside the thread's stack,
    /// one that doesn't move outward, or a zero return address, so a corrupt stack ends the walk
    /// instead of faulting again.
    private func captureFrames(from context: UnsafeMutableRawPointer?, into frames: UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int {
        guard let machine = context?.assumingMemoryBound(to: ucontext_t.self).pointee.uc_mcontext else { return 0 }
        #if arch(arm64)
            let instruction = UInt(machine.pointee.__ss.__pc)
            var framePointer = UInt(machine.pointee.__ss.__fp)
        #elseif arch(x86_64)
            let instruction = UInt(machine.pointee.__ss.__rip)
            var framePointer = UInt(machine.pointee.__ss.__rbp)
        #else
            return 0
        #endif
        // Return addresses saved by arm64e code (the system's libraries) carry a pointer
        // authentication code in their high bits; user addresses fit in the low 47.
        let addressMask: UInt = 0x0000_7FFF_FFFF_FFFF
        let thread = pthread_self()
        let stackTop = UInt(bitPattern: pthread_get_stackaddr_np(thread))
        let stackBottom = stackTop &- UInt(pthread_get_stacksize_np(thread))
        frames[0] = UnsafeMutableRawPointer(bitPattern: instruction & addressMask)
        var count = 1
        let recordSize = UInt(2 * MemoryLayout<UInt>.size)
        while count < CrashCapture.maximumFrames,
              framePointer >= stackBottom, framePointer <= stackTop &- recordSize,
              framePointer % UInt(MemoryLayout<UInt>.alignment) == 0,
              let record = UnsafePointer<UInt>(bitPattern: framePointer) {
            let returnAddress = record[1] & addressMask
            guard returnAddress != 0 else { break }
            frames[count] = UnsafeMutableRawPointer(bitPattern: returnAddress)
            count += 1
            let next = record[0]
            guard next > framePointer else { break }
            framePointer = next
        }
        return count
    }

    /// Writes `text`'s bytes.
    private func put(_ file: Int32, _ text: StaticString) {
        _ = write(file, text.utf8Start, text.utf8CodeUnitCount)
    }

    /// Writes `value` in decimal, formatted in `digits` (`CrashHandlerState.digitCapacity` bytes).
    private func put(_ file: Int32, decimal value: Int, using digits: UnsafeMutablePointer<UInt8>) {
        var remaining = value.magnitude
        var start = CrashHandlerState.digitCapacity
        repeat {
            start -= 1
            digits[start] = UInt8(truncatingIfNeeded: 48 + remaining % 10)
            remaining /= 10
        } while remaining > 0
        if value < 0 {
            start -= 1
            digits[start] = 45
        }
        _ = write(file, digits + start, CrashHandlerState.digitCapacity - start)
    }
#endif
