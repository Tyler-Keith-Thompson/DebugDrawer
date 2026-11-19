import Combine
import DebugDrawer
import Foundation

#if DEBUG
    // The window is drawn through `ScreenshotCapturer` and written through `ScreenshotSaver`; the
    // model holds values only. A capture waits for the drawer to hide, so it lands after `perform(_:)`
    // returns; every command sent after it waits its turn, so To Desktop's capture-then-save saves the
    // new capture. A command sent while nothing waits lands before `perform(_:)` returns, so a switch
    // bound through a direct transport reads back what it set.

    /// The Screenshot plugin's state and behavior, without its views: whether a capture hides the
    /// drawer, the last capture and where it stands, read as a ``ScreenshotSnapshot`` and changed
    /// with a ``ScreenshotCommand``.
    ///
    /// The plugin's view reaches it through a `DebugDrawerPluginTransport`:
    ///
    /// ```swift
    /// let transport = DebugDrawerPluginTransport.direct(to: ScreenshotModel.shared)
    /// ```
    ///
    /// Release builds get a stand-in whose snapshot holds nothing and which ignores every command.
    @MainActor
    public final class ScreenshotModel: DebugDrawerPluginModel {
        /// The model over the app's own windows and the user's Desktop, which the plugin shows.
        public static let shared = ScreenshotModel()

        @Published public private(set) var snapshot = ScreenshotSnapshot()

        private let capturer: any ScreenshotCapturer
        private let saver: any ScreenshotSaver
        /// The name a capture's file starts with.
        private let appName: String
        private let now: () -> Date
        /// Commands sent while a capture was under way, in the order sent.
        private var waiting: [ScreenshotCommand.Action] = []
        /// The capture under way, which every later command waits for.
        private var capturing: Task<Void, Never>?
        /// The drawers the plugin is installed in; the last to remove it drops the capture.
        private var installations: Set<ObjectIdentifier> = []

        /// - Parameters:
        ///   - capturer: Draws the app's key window.
        ///   - saver: Writes a capture where the developer finds it.
        ///   - appName: The name a capture's file starts with.
        ///   - now: The time a capture is taken.
        init(
            capturer: any ScreenshotCapturer = _ScreenshotCapturer(),
            saver: any ScreenshotSaver = _ScreenshotSaver(),
            appName: String = ScreenshotFile.appName,
            now: @escaping () -> Date = Date.init
        ) {
            self.capturer = capturer
            self.saver = saver
            self.appName = appName
            self.now = now
        }

        public func perform(_ command: ScreenshotCommand) {
            waiting.append(command.action)
            if capturing == nil {
                performWaiting()
            }
        }

        /// Counts `drawer` as one the plugin is installed in.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, drops the last capture, where it
        /// went, and a capture waiting for a place to be saved. Whether to hide the drawer stays,
        /// and a capture under way finishes. Files already saved stay.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            snapshot.capture = nil
            if snapshot.status != .capturing {
                snapshot.status = .ready
            }
        }

        /// Performs the commands waiting, in order, until one starts a capture; the rest wait for it.
        private func performWaiting() {
            while !waiting.isEmpty {
                let action = waiting.removeFirst()
                guard action == .capture else {
                    apply(action)
                    continue
                }
                snapshot.capture = nil
                snapshot.status = .capturing
                let hidingDrawer = snapshot.hidesDrawer
                capturing = Task { [capturer] in
                    let result: Result<ScreenshotImage, ScreenshotFailure>
                    do throws(ScreenshotFailure) {
                        result = try await .success(capturer.capture(hidingDrawer: hidingDrawer))
                    } catch {
                        result = .failure(error)
                    }
                    finishCapture(result)
                }
                return
            }
        }

        private func finishCapture(_ result: Result<ScreenshotImage, ScreenshotFailure>) {
            switch result {
            case let .success(image):
                let date = now()
                snapshot.capture = ScreenshotCapture(
                    image: image, date: date, filename: ScreenshotFile.filename(appName: appName, at: date)
                )
                snapshot.status = .ready
            case let .failure(failure):
                snapshot.status = .failed(failure)
            }
            capturing = nil
            performWaiting()
        }

        private func apply(_ action: ScreenshotCommand.Action) {
            switch action {
            case let .setHidesDrawer(hides):
                snapshot.hidesDrawer = hides
            case .capture:
                break
            case .save:
                save()
            case .copy:
                askToCopy()
            case .copied:
                snapshot.status = .copied
            case let .exported(path):
                snapshot.status = .saved(path: path)
            case let .exportFailed(reason):
                snapshot.status = .failed(.exportFailed(reason))
            case .cancelExport:
                cancelExport()
            case .clear:
                snapshot.capture = nil
                snapshot.status = .ready
            }
        }

        /// Writes the last capture through the saver; with no capture, does nothing.
        private func save() {
            guard let capture = snapshot.capture else { return }
            do {
                switch try saver.save(capture.image.png, as: capture.filename) {
                case let .saved(url): snapshot.status = .saved(path: url.path)
                case .needsLocation: snapshot.status = .needsLocation(filename: capture.filename)
                }
            } catch {
                snapshot.status = .failed(error)
            }
        }

        /// Asks the view to copy the last capture; with no capture, does nothing.
        private func askToCopy() {
            guard snapshot.capture != nil else { return }
            snapshot.status = .copying
        }

        /// Closes the save panel. The panel closes after it reports a save, too; only a panel still
        /// open is cancelled.
        private func cancelExport() {
            guard case .needsLocation = snapshot.status else { return }
            snapshot.status = .ready
        }
    }
#else
    // The release stand-in: the same members, and nothing behind them.

    /// Release builds capture nothing: this stand-in's snapshot holds nothing, and it ignores
    /// every command.
    @MainActor
    public final class ScreenshotModel: DebugDrawerPluginModel {
        /// The stand-in model.
        public static let shared = ScreenshotModel()

        private init() {}

        /// Always empty.
        public var snapshot: ScreenshotSnapshot {
            ScreenshotSnapshot()
        }

        /// Does nothing.
        ///
        /// - Parameter command: Ignored.
        public func perform(_ command: ScreenshotCommand) {}
    }
#endif
