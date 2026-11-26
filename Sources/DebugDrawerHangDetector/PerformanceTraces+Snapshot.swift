import Foundation

extension PerformanceTraces {
    /// What a sidecar reads: the stalls and signpost intervals recorded in the session, empty
    /// while nothing records.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The session the recording belongs to; `nil` while nothing records.
        public var sessionID: UUID?
        /// The file name of the app's executable, which marks the app's own frames.
        public var executable: String?
        /// The shortest stall recorded, as a ``StallKind/hitch``.
        public var hitchThreshold: Duration
        /// The shortest stall recorded as a ``StallKind/hang``.
        public var hangThreshold: Duration
        /// The stalls recorded, oldest first, the newest ``Limits/stalls`` kept.
        public var stalls: [Stall]
        /// The signpost intervals that ended in the session, in the order they ended, the newest
        /// ``Limits/intervals`` kept.
        public var intervals: [SignpostInterval]
        /// How many stalls the bound dropped, oldest first.
        public var droppedStalls: Int
        /// How many intervals the bound dropped, oldest first.
        public var droppedIntervals: Int
        /// The bounds the recording keeps to.
        public var limits: Limits
        /// Each time a sidecar took a copy into its report, in the session.
        public var exports: [Export]

        /// Makes a snapshot.
        ///
        /// - Parameters:
        ///   - sessionID: The session recorded; `nil` for none.
        ///   - executable: The file name of the app's executable, if known.
        ///   - hitchThreshold: The shortest stall recorded.
        ///   - hangThreshold: The shortest stall counted as a hang.
        ///   - stalls: The stalls, oldest first.
        ///   - intervals: The intervals, in the order they ended.
        ///   - droppedStalls: How many stalls the bound dropped.
        ///   - droppedIntervals: How many intervals the bound dropped.
        ///   - limits: The bounds.
        ///   - exports: The exports in the session.
        public init(
            sessionID: UUID?,
            executable: String?,
            hitchThreshold: Duration,
            hangThreshold: Duration,
            stalls: [Stall],
            intervals: [SignpostInterval],
            droppedStalls: Int,
            droppedIntervals: Int,
            limits: Limits,
            exports: [Export]
        ) {
            self.sessionID = sessionID
            self.executable = executable
            self.hitchThreshold = hitchThreshold
            self.hangThreshold = hangThreshold
            self.stalls = stalls
            self.intervals = intervals
            self.droppedStalls = droppedStalls
            self.droppedIntervals = droppedIntervals
            self.limits = limits
            self.exports = exports
        }

        /// Whether a sidecar's recording runs.
        public var isRecording: Bool {
            sessionID != nil
        }
    }

    /// How long a stall was, by the thresholds.
    public enum StallKind: String, Codable, Equatable, Sendable {
        /// At least the hitch threshold and shorter than the hang threshold: a stutter the person
        /// sees.
        case hitch
        /// At least the hang threshold: the app stopped answering.
        case hang
    }

    /// A stretch the main thread went without turning its run loop, at least the hitch threshold
    /// long, with the stack it was stuck on.
    public struct Stall: Codable, Equatable, Identifiable, Sendable {
        /// The stall's number in its session, from 1.
        public let id: Int
        /// Whether it was a hitch or a hang.
        public let kind: StallKind
        /// When it began.
        public let began: Date
        /// How long the main thread was stuck.
        public let duration: Duration
        /// The main thread's frames, innermost first, sampled once the stall reached the hitch
        /// threshold; empty when the thread got going before the watcher looked.
        public let frames: [Frame]

        /// Makes a stall.
        ///
        /// - Parameters:
        ///   - id: Its number in its session.
        ///   - kind: Hitch or hang.
        ///   - began: When it began.
        ///   - duration: How long it lasted.
        ///   - frames: The main thread's frames, innermost first.
        public init(id: Int, kind: StallKind, began: Date, duration: Duration, frames: [Frame]) {
            self.id = id
            self.kind = kind
            self.began = began
            self.duration = duration
            self.frames = frames
        }
    }

    /// One frame of a stack: its address and what names it.
    ///
    /// In an optimized, stripped build the app's own frames have no symbol, or the nearest
    /// exported one; ``image``, ``imageUUID`` and ``imageOffset`` name the build and the place in
    /// it, which a symbolicator turns into a function and line with that build's dSYM. The
    /// system's libraries keep their symbols.
    public struct Frame: Codable, Equatable, Sendable {
        /// The instruction (the first frame) or return address, in the running process.
        public let address: UInt64
        /// The file name of the image the address is in; `nil` when it is in none.
        public let image: String?
        /// The image's UUID (its `LC_UUID`), which picks the dSYM built with it.
        public let imageUUID: UUID?
        /// The address's offset from the image's load address.
        public let imageOffset: UInt64?
        /// The nearest symbol the image exports, mangled as it is; `nil` when it exports none
        /// before the address.
        public let symbol: String?
        /// The address's offset from ``symbol``.
        public let symbolOffset: UInt64?

        /// Makes a frame.
        ///
        /// - Parameters:
        ///   - address: The address.
        ///   - image: The image's file name, if any.
        ///   - imageUUID: The image's UUID, if known.
        ///   - imageOffset: The offset into the image, if known.
        ///   - symbol: The nearest exported symbol, if any.
        ///   - symbolOffset: The offset into it, if any.
        public init(
            address: UInt64,
            image: String? = nil,
            imageUUID: UUID? = nil,
            imageOffset: UInt64? = nil,
            symbol: String? = nil,
            symbolOffset: UInt64? = nil
        ) {
            self.address = address
            self.image = image
            self.imageUUID = imageUUID
            self.imageOffset = imageOffset
            self.symbol = symbol
            self.symbolOffset = symbolOffset
        }

        /// The load address of the image, which `atos -l` takes: the address less its offset.
        public var imageLoadAddress: UInt64? {
            imageOffset.map { address &- $0 }
        }
    }

    /// An interval the host marked with ``PerformanceTraces/beginInterval(_:)`` and
    /// ``PerformanceTraces/endInterval(_:)``, as `os_signpost` marks one.
    public struct SignpostInterval: Codable, Equatable, Identifiable, Sendable {
        /// The interval's number in its session, from 1, in the order intervals ended.
        public let id: Int
        /// The name the host gave it, a string literal in its code.
        public let name: String
        /// When it began.
        public let began: Date
        /// How long it took.
        public let duration: Duration

        /// Makes an interval.
        ///
        /// - Parameters:
        ///   - id: Its number in its session.
        ///   - name: Its name.
        ///   - began: When it began.
        ///   - duration: How long it took.
        public init(id: Int, name: String, began: Date, duration: Duration) {
            self.id = id
            self.name = name
            self.began = began
            self.duration = duration
        }
    }

    /// Bounds a recording can't take, which ``Limits/init(stalls:intervals:)`` refuses.
    public enum InvalidLimits: Error, Equatable, Sendable {
        /// Fewer than 1 stall would be kept.
        case noStalls
        /// Fewer than 1 interval would be kept.
        case noIntervals
    }

    /// The bounds of one session's recording: past them the oldest go first.
    public struct Limits: Codable, Equatable, Sendable {
        /// The 50 newest stalls and 500 newest intervals.
        public static let standard = Limits(uncheckedStalls: 50, intervals: 500)

        /// The most stalls kept.
        public let stalls: Int
        /// The most intervals kept.
        public let intervals: Int

        /// Bounds of `stalls` stalls and `intervals` intervals.
        ///
        /// - Parameters:
        ///   - stalls: The most stalls kept.
        ///   - intervals: The most intervals kept.
        /// - Throws: ``PerformanceTraces/InvalidLimits/noStalls`` when `stalls` is less than 1,
        ///   and ``PerformanceTraces/InvalidLimits/noIntervals`` when `intervals` is.
        public init(stalls: Int, intervals: Int) throws(InvalidLimits) {
            guard stalls >= 1 else { throw .noStalls }
            guard intervals >= 1 else { throw .noIntervals }
            self.init(uncheckedStalls: stalls, intervals: intervals)
        }

        /// Bounds the caller knows are at least 1: ``standard``, a constant no input reaches.
        private init(uncheckedStalls stalls: Int, intervals: Int) {
            self.stalls = stalls
            self.intervals = intervals
        }
    }

    /// A copy a sidecar took into its report: when, and how much it held.
    public struct Export: Codable, Equatable, Sendable {
        /// When the sidecar took it.
        public let date: Date
        /// How many stalls it held.
        public let stalls: Int
        /// How many intervals it held.
        public let intervals: Int

        /// Makes an export.
        ///
        /// - Parameters:
        ///   - date: When the sidecar took it.
        ///   - stalls: How many stalls it held.
        ///   - intervals: How many intervals it held.
        public init(date: Date, stalls: Int, intervals: Int) {
            self.date = date
            self.stalls = stalls
            self.intervals = intervals
        }
    }
}

extension PerformanceTraces.Snapshot {
    /// The recording as text for a report: each stall with its frames, each interval, then the
    /// binary images the frames are in, with their load addresses and UUIDs, which symbolicate the
    /// frames with the build's dSYM (`atos -o <dSYM> -l <load address> <address>`).
    public var text: String {
        let stallText = stalls.map { stall in
            let header = "\(stall.kind.title) #\(stall.id): \(PerformanceTraces.milliseconds(stall.duration)) at \(stall.began.formatted(.iso8601))"
            let frameLines = stall.frames.isEmpty
                ? ["No stack was captured: the main thread got going before the watcher looked."]
                : stall.frames.enumerated().map { index, frame in frame.line(index: index) }
            return ([header] + frameLines).joined(separator: "\n")
        }
        let intervalLines = intervals.map { interval in
            "\(interval.name): \(PerformanceTraces.milliseconds(interval.duration)) at \(interval.began.formatted(.iso8601))"
        }
        var images: [String: PerformanceTraces.Frame] = [:]
        for frame in stalls.flatMap(\.frames) {
            if let image = frame.image, images[image] == nil {
                images[image] = frame
            }
        }
        let imageLines = images.keys.sorted().compactMap { name -> String? in
            guard let frame = images[name], let load = frame.imageLoadAddress else { return nil }
            return String(format: "0x%016llx ", load) + "\(name) <\(frame.imageUUID?.uuidString ?? "no UUID")>"
        }
        return [
            "Hitch threshold: \(PerformanceTraces.milliseconds(hitchThreshold)), hang threshold: \(PerformanceTraces.milliseconds(hangThreshold))",
            "Stalls (\(stalls.count), \(droppedStalls) dropped)",
            stallText.joined(separator: "\n\n"),
            "Signpost intervals (\(intervals.count), \(droppedIntervals) dropped)",
            intervalLines.joined(separator: "\n"),
            "Binary images",
            imageLines.joined(separator: "\n")
        ].filter { !$0.isEmpty }.joined(separator: "\n\n") + "\n"
    }
}

extension PerformanceTraces.StallKind {
    /// How a report names it.
    public var title: String {
        switch self {
        case .hitch: "Hitch"
        case .hang: "Hang"
        }
    }
}

extension PerformanceTraces {
    /// `duration` in whole milliseconds: `612 ms`.
    ///
    /// - Parameter duration: The duration.
    /// - Returns: Its whole milliseconds and the unit.
    public nonisolated static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return "\(seconds * 1000 + attoseconds / 1_000_000_000_000_000) ms"
    }
}

// Decoding goes through the throwing initializer, so a snapshot read from a file or a sidecar
// can't hold bounds no host could make; encoding stays synthesized, under the same keys.
extension PerformanceTraces.Limits {
    private enum CodingKeys: String, CodingKey {
        case stalls, intervals
    }

    /// Decodes bounds, refusing those ``init(stalls:intervals:)`` refuses.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError.dataCorrupted` whose `underlyingError` is the
    ///   ``PerformanceTraces/InvalidLimits`` case the initializer throws, with the container's
    ///   coding path, and the decoder's own errors for a missing or mistyped field.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stalls = try container.decode(Int.self, forKey: .stalls)
        let intervals = try container.decode(Int.self, forKey: .intervals)
        do {
            self = try Self(stalls: stalls, intervals: intervals)
        } catch {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Recording limits out of range", underlyingError: error)
            )
        }
    }
}
