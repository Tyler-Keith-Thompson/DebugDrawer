#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation

    /// The recorder and its saved recordings, on the main actor, for the drawer, the HUD and the
    /// bug report: Record and Stop, the list, which recordings the report carries, and whether the
    /// frames show touches.
    ///
    /// Main-actor isolated, like the drawer and the layer tree its frames are drawn from.
    @MainActor
    final class ScreenRecordingModel: ObservableObject {
        /// Where the recorder is.
        @Published private(set) var state = RecordingState.idle
        /// The saved recordings, newest first.
        @Published private(set) var recordings: [Recording] = []
        /// The recordings the bug report carries: the newest when it is saved, and any the
        /// developer adds.
        @Published private(set) var includedInReport: Set<Recording.ID> = []
        /// Whether new recordings draw a circle where each finger touches. Off unless turned on;
        /// remembered across launches.
        @Published var showsTouches: Bool {
            didSet { defaults.set(showsTouches, forKey: Self.showsTouchesKey) }
        }

        /// How many recordings are kept; saving one past it deletes the oldest.
        var capacity: Int

        private let folder: RecordingFolder
        private let frameSource: any RecordingFrameSource
        private let makeWriter: @MainActor (URL) -> any MovieWriter
        private let now: @MainActor () -> Date
        private let defaults: UserDefaults
        /// The movie being recorded, from Record until it is written out.
        private var writer: (any MovieWriter)?
        private var recordingURL: URL?
        /// The drawers the plugin over this model is installed in.
        private var installedDrawers: Set<ObjectIdentifier> = []
        /// Whether the last drawer uninstalled the plugin, dropping the list, and none has
        /// installed it since.
        private(set) var isUninstalled = false
        /// Writing out the recording an uninstall stopped, until its movie is saved.
        private(set) var savingAfterUninstall: Task<Void, Never>?

        /// - Parameters:
        ///   - folder: Where recordings are saved.
        ///   - capacity: How many are kept.
        ///   - frameSource: What draws the frames.
        ///   - makeWriter: A writer for a new movie at a URL.
        ///   - now: The wall clock, read when a recording starts.
        ///   - defaults: Where Show Touches is remembered: the drawer's own suite, apart from the
        ///     app's defaults.
        init(
            folder: RecordingFolder,
            capacity: Int,
            frameSource: any RecordingFrameSource,
            makeWriter: @escaping @MainActor (URL) -> any MovieWriter,
            now: @escaping @MainActor () -> Date = Date.init,
            defaults: UserDefaults = .debugDrawer
        ) {
            self.folder = folder
            self.capacity = capacity
            self.frameSource = frameSource
            self.makeWriter = makeWriter
            self.now = now
            self.defaults = defaults
            showsTouches = defaults.bool(forKey: Self.showsTouchesKey)
        }

        /// Lists the recordings already saved, keeping the newest `capacity`, and includes the
        /// newest in the bug report.
        func load() async {
            let saved = folder.prune(await folder.recordings(), keeping: capacity)
            recordings = saved
            includedInReport = Set(saved.prefix(1).map(\.id))
        }

        /// Starts recording, unless a recording is already recording or being written out.
        func start() {
            guard state.canStart else { return }
            let started = now()
            do throws(RecordingFailure) {
                let url = try folder.url(forRecordingStartedAt: started)
                let writer = makeWriter(url)
                try frameSource.start(showsTouches: showsTouches) { [weak writer] frame in
                    writer?.append(frame)
                }
                self.writer = writer
                recordingURL = url
                state = .recording(started: started)
            } catch {
                state = .failed(error)
            }
        }

        /// Stops recording and writes the movie out. Once it is saved it is listed first and is
        /// the one the bug report carries; the oldest past ``capacity`` are deleted. A recording
        /// that can't be saved leaves no file and says why.
        func stop() async {
            guard case let (writer, url)? = endCapture() else { return }
            await save(writer, at: url)
        }

        /// Stops the frames of the recording in progress, if there is one.
        ///
        /// - Returns: Its writer and where it writes, for ``save(_:at:)``.
        private func endCapture() -> (any MovieWriter, URL)? {
            guard state.isRecording, let writer, let url = recordingURL else { return nil }
            frameSource.stop()
            self.writer = nil
            recordingURL = nil
            state = .finishing
            return (writer, url)
        }

        /// Writes the movie out and lists it, unless the plugin was uninstalled meanwhile: then
        /// the movie is saved (and the oldest past ``capacity`` deleted) without being listed.
        private func save(_ writer: any MovieWriter, at url: URL) async {
            do throws(RecordingFailure) {
                _ = try await writer.finish()
                let saved = folder.prune(await folder.recordings(), keeping: capacity)
                guard !isUninstalled else {
                    state = .idle
                    return
                }
                recordings = saved
                let recording = saved.first { $0.id == url.lastPathComponent }
                includedInReport = Set(recording.map { [$0.id] } ?? [])
                state = .finished(recording?.url ?? url)
            } catch {
                folder.delete(url)
                state = isUninstalled ? .idle : .failed(error)
            }
        }

        /// Counts `drawer` as one the plugin is installed in, and lists the saved recordings
        /// again if an uninstall dropped them.
        func install(in drawer: ObjectIdentifier) {
            installedDrawers.insert(drawer)
            guard isUninstalled else { return }
            isUninstalled = false
            Task { await load() }
        }

        /// Uncounts `drawer`. Once no drawer has the plugin, stops a recording in progress (its
        /// movie is still saved, in ``savingAfterUninstall``) and drops the list; the recordings
        /// on disk and Show Touches stay.
        func uninstall(from drawer: ObjectIdentifier) {
            installedDrawers.remove(drawer)
            guard installedDrawers.isEmpty, !isUninstalled else { return }
            isUninstalled = true
            if case let (writer, url)? = endCapture() {
                savingAfterUninstall = Task { await save(writer, at: url) }
            } else if state != .finishing {
                state = .idle
            }
            recordings = []
            includedInReport = []
        }

        /// Starts recording, or stops it while it records: the HUD's one button.
        func toggle() {
            if state.isRecording {
                Task { await stop() }
            } else {
                start()
            }
        }

        /// Deletes a saved recording.
        func delete(_ recording: Recording) {
            folder.delete(recording.url)
            recordings.removeAll { $0.id == recording.id }
            includedInReport.remove(recording.id)
            if case let .finished(url) = state, url.lastPathComponent == recording.id { state = .idle }
        }

        /// Adds a recording to the bug report, or takes it out.
        func setIncludedInReport(_ isIncluded: Bool, for recording: Recording) {
            if isIncluded {
                includedInReport.insert(recording.id)
            } else {
                includedInReport.remove(recording.id)
            }
        }

        /// The recordings the bug report carries, newest first.
        var reportRecordings: [Recording] {
            recordings.filter { includedInReport.contains($0.id) }
        }

        static let showsTouchesKey = "com.debugdrawer.screenRecording.showsTouches"
    }
#endif
