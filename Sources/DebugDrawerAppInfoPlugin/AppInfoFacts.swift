#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif
    import Foundation

    /// What the App Info plugin shows: labeled facts about the bundle, the process and the device,
    /// in sections.
    struct AppInfoFacts: Equatable {
        /// One labeled value.
        struct Fact: Equatable {
            var label: String
            var value: String
        }

        /// Bundle, runtime and environment, in that order.
        var sections: [[Fact]]

        /// The facts as plain text, one `label: value` line each, for the clipboard.
        var report: String {
            sections.joined().map { "\($0.label): \($0.value)" }.joined(separator: "\n")
        }

        static let launchFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            return formatter
        }()
    }

    extension AppInfoFacts {
        /// The facts now: the main bundle, this process and the device, with `metrics` for
        /// memory, uptime, network and the process's start.
        @MainActor init(metrics: AppMetrics, bundle: Bundle = .main, process: ProcessInfo = .processInfo) {
            let info = bundle.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "—"
            let build = info?["CFBundleVersion"] as? String ?? "—"
            let gigabyte = 1024.0 * 1024 * 1024
            var environment: [Fact] = []
            #if os(macOS)
                // iOS, tvOS, watchOS and visionOS apps are always sandboxed, and don't get this variable.
                let isSandboxed = process.environment["APP_SANDBOX_CONTAINER_ID"] != nil
                environment.append(Fact(label: "Sandbox", value: isSandboxed ? "Yes" : "No"))
            #endif
            environment += [
                Fact(label: "Debugger", value: metrics.processStart.map { $0.isTraced ? "Attached" : "Not attached" } ?? "—"),
                Fact(label: "Active CPU", value: "\(process.activeProcessorCount)"),
                Fact(label: "Physical Mem", value: String(format: "%.0f GB", Double(process.physicalMemory) / gigabyte)),
                Fact(label: "Screen", value: Self.screenResolution),
                Fact(label: "Network", value: metrics.networkStatus),
                Fact(label: "Launched", value: metrics.processStart.map { Self.launchFormatter.string(from: $0.date) } ?? "—")
            ]
            sections = [
                [
                    Fact(label: "Bundle ID", value: bundle.bundleIdentifier ?? "—"),
                    Fact(label: "Version", value: "\(version) (\(build))"),
                    Fact(label: Self.operatingSystemName, value: process.operatingSystemVersionString)
                ],
                [
                    Fact(label: "Memory", value: String(format: "%.1f MB", metrics.memoryMB)),
                    Fact(label: "Uptime", value: metrics.uptime.map(Self.formatDuration) ?? "—"),
                    Fact(label: "PID", value: "\(process.processIdentifier)"),
                    Fact(label: "Arch", value: process.machineHardwareName),
                    Fact(label: "Arguments", value: "\(process.arguments.count)")
                ],
                environment
            ]
        }

        private static var operatingSystemName: String {
            #if os(macOS)
                "macOS"
            #else
                "iOS"
            #endif
        }

        static func formatDuration(_ seconds: TimeInterval) -> String {
            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60
            let remainder = Int(seconds) % 60
            if hours > 0 { return "\(hours)h \(minutes)m \(remainder)s" }
            if minutes > 0 { return "\(minutes)m \(remainder)s" }
            return "\(remainder)s"
        }

        @MainActor private static var screenResolution: String {
            #if os(macOS)
                guard let screen = NSScreen.main else { return "—" }
                let size = screen.frame.size
                let scale = screen.backingScaleFactor
                return "\(Int(size.width))×\(Int(size.height)) @\(Int(scale))x"
            #elseif os(iOS)
                // The screen of the foreground window scene (UIScreen.main is deprecated).
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                guard let screen = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
                else { return "—" }
                let size = screen.bounds.size
                let scale = screen.scale
                return "\(Int(size.width))×\(Int(size.height)) @\(Int(scale))x"
            #else
                return "—"
            #endif
        }
    }
#endif
