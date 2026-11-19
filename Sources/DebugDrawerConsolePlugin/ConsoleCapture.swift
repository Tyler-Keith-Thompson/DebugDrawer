#if DEBUG
    import Foundation
    import os
    import OSLogClient

    // The process has one stdout, one stderr and one os_log driver, so capture is one for the
    // process, and the store it fills is chosen here as installs come and go: the latest install's.
    // A drawer of a test's own, installed while the app's drawer holds the plugin too, gets the lines
    // from then on, and the app's store gets them again once that drawer removes the plugin.
    // Rejected: the first install keeping the lines (a drawer installed later would never see any),
    // and every installed store getting each line (each line kept, and written to a session, once per
    // store).

    /// Capture of stdout, stderr (on macOS) and the process's os_log entries, started by the first
    /// install and stopped by the last uninstall, into the store of the latest install: a drawer
    /// holding the Console plugin, or the app's own ``ConsoleLogStore/install()``.
    @MainActor
    enum ConsoleCapture {
        /// Who wants capture, in the order they asked, each with the store it captures into: a
        /// drawer holding the plugin, or a store the app installed itself, under its own identity.
        private static var installations: [(owner: ObjectIdentifier, store: ConsoleLogStore)] = []

        /// The store captured lines go to: the latest install's, or ``ConsoleLogStore/shared``
        /// before any, which keeps them for when it is installed.
        static var store: ConsoleLogStore {
            installations.last?.store ?? .shared
        }

        /// Whether stdout, stderr and os_log are captured: while anyone wants capture.
        private(set) static var isRunning = false
        /// Whether capture ran once and stopped since.
        private static var hasStopped = false
        /// The console's os_log driver, which OSLogClient calls from its own actor.
        nonisolated static let driver = ConsoleLogDriver()
        /// The OSLogClient calls made last, which the next ones wait for: they are asynchronous,
        /// and an uninstall must not overtake the install before it.
        private static var osLogWork: Task<Void, Never>?
        /// Original stdout fd, used to write diagnostics without triggering capture loop.
        private static var originalStdoutFd: Int32 = -1
        /// stdout and stderr, each redirected into a pipe, while capture runs.
        private static var streamCaptures: [ConsoleStreamCapture] = []

        /// Captures into `store` for `owner`, from now on, and starts capture if nothing had; an
        /// owner that wants capture already changes nothing.
        static func install(_ store: ConsoleLogStore, for owner: ObjectIdentifier) {
            guard !installations.contains(where: { $0.owner == owner }) else { return }
            installations.append((owner, store))
            store.capture = .running
            if !isRunning { start() }
        }

        /// Stops capturing for `owner`: the install before it gets the lines again. A store no
        /// install holds any more stops and drops its lines, and once nobody wants capture,
        /// stdout and stderr write to where they did before and os_log is no longer read.
        static func uninstall(for owner: ObjectIdentifier) {
            guard let index = installations.firstIndex(where: { $0.owner == owner }) else { return }
            let store = installations.remove(at: index).store
            if installations.isEmpty { stop() }
            if !installations.contains(where: { $0.store === store }) {
                store.capture = .stopped
                store.clear()
                store.hidePrevious()
            }
        }

        /// Returns once the os_log calls the installs and uninstalls so far made are done.
        static func osLogSettled() async {
            await osLogWork?.value
        }

        private static func start() {
            // Entries logged while an uninstall had stopped capture stay out: the poll that
            // follows would otherwise catch up on them.
            driver.ignoreEntries(before: hasStopped ? Date() : nil)
            isRunning = true

            // Only redirect stdout/stderr on macOS.
            // On iOS, dup2 on stdout breaks Xcode's debugger attachment.
            #if os(macOS)
                originalStdoutFd = dup(STDOUT_FILENO)
                // Swift's `print` writes through C's `stdout`, which buffers fully once it finds a
                // pipe behind it, so printed lines would reach the console in chunks. Line
                // buffering keeps each line whole and on time. Set before the redirect: setvbuf
                // flushes what was buffered to where it was headed. stderr stays unbuffered.
                setvbuf(stdout, nil, _IOLBF, 0)
                streamCaptures = [redirectStream(source: .stdout, fd: STDOUT_FILENO), redirectStream(source: .stderr, fd: STDERR_FILENO)]
            #endif

            let driver = driver
            afterOSLogWork {
                do {
                    // OSLogClient is set up once a process and refuses a second initialize.
                    if await !OSLogClient.isInitialized {
                        let store = try OSLogStore(scope: .currentProcessIdentifier)
                        try await OSLogClient.initialize(pollingInterval: .custom(2), logStore: store)
                    }
                    await OSLogClient.registerDriver(driver)
                    await OSLogClient.startPolling()
                } catch {
                    logDirect("[DebugDrawer] OSLogClient init failed: \(error)\n")
                }
            }
        }

        private static func stop() {
            isRunning = false
            hasStopped = true
            #if os(macOS)
                // What C's stdout still buffers goes to the pipe, and on to the original stream.
                fflush(stdout)
                for stream in streamCaptures {
                    stream.restore()
                }
                streamCaptures = []
                // The buffering the C library gives a stream it finds behind stdout at launch.
                setvbuf(stdout, nil, isatty(STDOUT_FILENO) == 1 ? _IOLBF : _IOFBF, 0)
                close(originalStdoutFd)
                originalStdoutFd = -1
            #endif

            // Only the console's driver goes: polling is OSLogClient's, which pauses it once no
            // driver is left, and an app may poll with drivers of its own.
            let driverID = driver.id
            afterOSLogWork {
                guard await OSLogClient.isInitialized else { return }
                await OSLogClient.deregisterDriver(withId: driverID)
            }
        }

        /// Runs `work` once the OSLogClient calls before it are done.
        private static func afterOSLogWork(_ work: @escaping @MainActor () async -> Void) {
            let previous = osLogWork
            osLogWork = Task {
                await previous?.value
                await work()
            }
        }

        /// Write directly to the original stdout fd, bypassing the pipe capture.
        private static func logDirect(_ msg: String) {
            guard originalStdoutFd >= 0 else { return }
            msg.withCString { ptr in
                _ = write(originalStdoutFd, ptr, strlen(ptr))
            }
        }

        /// Points `fd` at a new pipe whose reader forwards each read to the stream `fd` was, and
        /// ingests its lines into the store capture goes to.
        ///
        /// - Returns: What ``ConsoleStreamCapture/restore()`` undoes.
        private static func redirectStream(source: LogLine.Source, fd: Int32) -> ConsoleStreamCapture {
            let pipe = Pipe()
            let originalFd = dup(fd)
            dup2(pipe.fileHandleForWriting.fileDescriptor, fd)
            // A read ends wherever the pipe cut the stream, inside a line or a character, so the
            // stream's bytes go through one assembler that keeps what follows the last newline.
            // The handler's calls come one at a time, but it is a Sendable closure; the lock is
            // never contended. `OSAllocatedUnfairLock` rather than `Mutex`, which needs iOS 18;
            // switch once iOS 18 is the minimum.
            let assembler = OSAllocatedUnfairLock(initialState: ConsoleLineAssembler())

            // The handler holds the pipe until the end of the stream: a pipe released closes its
            // reading end, and a write still on its way would then raise SIGPIPE.
            pipe.fileHandleForReading.readabilityHandler = { [pipe] handle in
                let data = handle.availableData
                let texts: [String]
                if data.isEmpty {
                    // The end of the stream, once restore() closed the last writer: its last line
                    // shows even without a newline, and the pipe and the original stream's copy
                    // go.
                    handle.readabilityHandler = nil
                    texts = assembler.withLock { $0.flush() }.map { [$0] } ?? []
                    close(originalFd)
                    try? pipe.fileHandleForReading.close()
                } else {
                    texts = assembler.withLock { $0.lines(in: data) }
                }
                let logLines = texts
                    .filter { !$0.isEmpty }
                    .map { LogLine(timestamp: Date(), text: $0, source: source, level: source == .stderr ? .error : .info) }
                if !logLines.isEmpty {
                    Task { @MainActor in
                        let store = ConsoleCapture.store
                        for line in logLines {
                            store.ingest(line)
                        }
                    }
                }

                // Forwarded to the original destination last, so once a read comes out there the
                // reader is done with it. The Console benchmarks write a line only after the one
                // before came out, so the reader always finishes and waits between lines, and
                // their instruction counts repeat.
                if !data.isEmpty, originalFd >= 0 {
                    data.withUnsafeBytes { buf in
                        if let ptr = buf.baseAddress {
                            _ = write(originalFd, ptr, data.count)
                        }
                    }
                }
            }
            return ConsoleStreamCapture(fd: fd, originalFd: originalFd, pipe: pipe)
        }
    }
#endif
