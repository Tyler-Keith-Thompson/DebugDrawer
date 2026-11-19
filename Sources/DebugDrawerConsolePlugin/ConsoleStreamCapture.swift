#if DEBUG
    import Foundation

    /// Whether the console captures.
    enum ConsoleCaptureState: Equatable, Sendable {
        /// Not installed yet: lines sent to the store are kept for when it is.
        case notStarted
        /// Installed: stdout, stderr (on macOS) and os_log are captured.
        case running
        /// Uninstalled: nothing is captured until it is installed again.
        case stopped
    }

    /// One standard stream redirected into a pipe: what ``restore()`` needs to point it back.
    @MainActor
    struct ConsoleStreamCapture {
        /// The stream's descriptor: `STDOUT_FILENO` or `STDERR_FILENO`.
        let fd: Int32
        /// A duplicate of what `fd` was before, which the pipe's reader forwards to and closes at
        /// the end of the stream.
        let originalFd: Int32
        let pipe: Pipe

        /// Points the stream back at what it was, then closes the pipe's writing end: with no
        /// writer left, its reader reads what is still in the pipe, then the end of the stream.
        /// A write after this goes to the original stream alone.
        func restore() {
            dup2(originalFd, fd)
            try? pipe.fileHandleForWriting.close()
        }
    }
#endif
