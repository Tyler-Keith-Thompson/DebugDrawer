#if DEBUG
    import Foundation
    import os
    import OSLogClient

    // Capture of stdout, stderr and os_log into the store, started by the first install and stopped
    // by the last uninstall: the app's own install() counts as one, each drawer with the Console
    // plugin as another.
    extension ConsoleLogStore {
        /// Captures stdout and stderr (on macOS) and the process's os_log entries until
        /// ``uninstall()``, whether or not a drawer has the Console plugin. The drawer needs no
        /// call: the plugin captures while a drawer has it. Calling it again does nothing.
        public func install() {
            isInstalledByApp = true
            updateCapture()
        }

        /// Ends what ``install()`` began. Capture goes on while a drawer has the Console plugin;
        /// once nothing wants it, stdout and stderr write to where they did before, os_log entries
        /// are no longer read, and the captured lines are dropped. Calling it again does nothing.
        public func uninstall() {
            isInstalledByApp = false
            updateCapture()
        }

        /// Counts `drawer` as one the Console plugin is installed in; the first starts capture.
        func install(in drawer: ObjectIdentifier) {
            installedDrawers.insert(drawer)
            updateCapture()
        }

        /// Uncounts `drawer`; the last one stops capture unless the app installed it.
        func uninstall(from drawer: ObjectIdentifier) {
            installedDrawers.remove(drawer)
            updateCapture()
        }

        /// Returns once the os_log calls the installs and uninstalls so far made are done.
        func osLogSettled() async {
            await osLogWork?.value
        }

        private func updateCapture() {
            let isWanted = isInstalledByApp || !installedDrawers.isEmpty
            if isWanted, capture != .running { startCapture() }
            if !isWanted, capture == .running { stopCapture() }
        }

        private func startCapture() {
            // Entries logged while an uninstall had stopped capture stay out: the poll that
            // follows would otherwise catch up on them.
            driver.ignoreEntries(before: capture == .stopped ? Date() : nil)
            capture = .running

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
                    self.logDirect("[DebugDrawer] OSLogClient init failed: \(error)\n")
                }
            }
        }

        private func stopCapture() {
            capture = .stopped
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

            clear()
            hidePrevious()
        }

        /// Runs `work` once the OSLogClient calls before it are done.
        private func afterOSLogWork(_ work: @escaping @MainActor () async -> Void) {
            let previous = osLogWork
            osLogWork = Task {
                await previous?.value
                await work()
            }
        }

        /// Write directly to the original stdout fd, bypassing the pipe capture.
        private func logDirect(_ msg: String) {
            guard originalStdoutFd >= 0 else { return }
            msg.withCString { ptr in
                _ = write(originalStdoutFd, ptr, strlen(ptr))
            }
        }

        /// Points `fd` at a new pipe whose reader forwards each read to the stream `fd` was, and
        /// ingests its lines.
        ///
        /// - Returns: What ``ConsoleStreamCapture/restore()`` undoes.
        private func redirectStream(source: LogLine.Source, fd: Int32) -> ConsoleStreamCapture {
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
            pipe.fileHandleForReading.readabilityHandler = { [weak self, pipe] handle in
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
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        for line in logLines {
                            self.ingest(line)
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
