#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif
    import Foundation

    /// What the App Info plugin shows: labeled facts about the build, the process and the device,
    /// in titled sections, and how the app was signed.
    struct AppInfoFacts: Equatable {
        /// One labeled value.
        struct Fact: Equatable {
            var label: String
            var value: String
        }

        /// A titled group of facts.
        struct Section: Equatable {
            var title: String
            var facts: [Fact]
        }

        /// Build, runtime and environment, in that order.
        var sections: [Section]
        /// The provisioning profile and the entitlements, shown after the sections.
        var signing: AppSigning
        /// Whether the profile had expired when the facts were read.
        var isProfileExpired: Bool

        init(sections: [Section], signing: AppSigning = AppSigning(profile: .none, entitlements: nil), isProfileExpired: Bool = false) {
            self.sections = sections
            self.signing = signing
            self.isProfileExpired = isProfileExpired
        }

        /// Every section, Provisioning and Entitlements last, as Copy Info and the bug report give
        /// them: entitlements by key rather than by word label, so a key can be searched for.
        var reportSections: [Section] {
            sections + [provisioningSection, entitlementsSection]
        }

        /// The facts as plain text, for the clipboard: each section's title, then a `label: value`
        /// line per fact, with a blank line between sections.
        var report: String {
            reportSections
                .map { section in ([section.title] + section.facts.map { "\($0.label): \($0.value)" }).joined(separator: "\n") }
                .joined(separator: "\n\n")
        }

        static let launchFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            return formatter
        }()
    }

    extension AppInfoFacts {
        /// The facts now: the main bundle, this process and the device.
        ///
        /// - Parameters:
        ///   - metrics: Memory, uptime, network and the process's start.
        ///   - buildMetadata: The commit, branch and CI build the host passed; each one missing
        ///     is read from `bundle`'s Info.plist.
        ///   - signing: The profile and the entitlements.
        ///   - bundle: The app's bundle.
        ///   - process: This process.
        ///   - now: The time the profile's expiry is checked against.
        @MainActor init(
            metrics: AppMetrics,
            buildMetadata: AppInfoBuildMetadata,
            signing: AppSigning,
            bundle: Bundle = .main,
            process: ProcessInfo = .processInfo,
            now: Date = Date()
        ) {
            let info = bundle.infoDictionary
            let build = buildMetadata.filled(from: info)
            let gigabyte = 1024.0 * 1024 * 1024
            var environment = [Fact(label: Self.operatingSystemName, value: process.operatingSystemVersionString)]
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
            self.init(
                sections: [
                    Section(title: "Build", facts: [
                        Fact(label: "Bundle ID", value: bundle.bundleIdentifier ?? "—"),
                        Fact(label: "Version", value: info?["CFBundleShortVersionString"] as? String ?? "—"),
                        Fact(label: "Build", value: info?["CFBundleVersion"] as? String ?? "—"),
                        Fact(label: "Commit", value: build.gitCommit ?? "—"),
                        Fact(label: "Branch", value: build.gitBranch ?? "—"),
                        Fact(label: "CI Build", value: build.ciBuildNumber ?? "—")
                    ]),
                    Section(title: "Runtime", facts: [
                        Fact(label: "Footprint", value: String(format: "%.1f MB", metrics.footprintMB)),
                        Fact(label: "Uptime", value: metrics.uptime.map(Self.formatDuration) ?? "—"),
                        Fact(label: "PID", value: "\(process.processIdentifier)"),
                        Fact(label: "Arch", value: process.machineHardwareName),
                        Fact(label: "Arguments", value: "\(process.arguments.count)")
                    ]),
                    Section(title: "Environment", facts: environment)
                ],
                signing: signing,
                isProfileExpired: signing.profile.provisioningProfile?.isExpired(at: now) ?? false
            )
        }

        /// The OS row's label. The same names as core's bug-report summary, written out again
        /// here because core's are private to it, not part of the plugin contract.
        static var operatingSystemName: String {
            #if os(macOS)
                "macOS"
            #elseif targetEnvironment(macCatalyst)
                // ProcessInfo reports the Mac's macOS version, not an iOS one, under Catalyst.
                "macOS (Mac Catalyst)"
            #elseif os(visionOS)
                "visionOS"
            #elseif os(tvOS)
                "tvOS"
            #elseif os(watchOS)
                "watchOS"
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

    extension AppInfoFacts {
        fileprivate var provisioningSection: Section {
            let facts: [Fact] = switch signing.profile {
            case .none: [Fact(label: "Profile", value: "None")]
            case .unreadable: [Fact(label: "Profile", value: "Unreadable")]
            case let .embedded(profile): [
                    Fact(label: "Name", value: profile.name),
                    Fact(label: "Team", value: profile.teamName),
                    Fact(label: "Team ID", value: profile.teamIdentifier),
                    Fact(label: "Created", value: ProvisioningProfile.format(profile.creationDate)),
                    Fact(label: "Expires", value: ProvisioningProfile.format(profile.expirationDate) + (isProfileExpired ? " (expired)" : "")),
                    Fact(label: "Devices", value: profile.devices.text)
                ]
            }
            return Section(title: "Provisioning", facts: facts)
        }

        fileprivate var entitlementsSection: Section {
            guard let entitlements = signing.entitlements, !entitlements.entries.isEmpty else {
                return Section(title: "Entitlements", facts: [Fact(label: "Entitlements", value: "None")])
            }
            return Section(
                title: "Entitlements",
                facts: [Fact(label: "Source", value: entitlements.source.text)] + entitlements.entries.map { Fact(label: $0.key, value: $0.text) }
            )
        }
    }

    extension Entitlements.Source {
        /// Where the entitlements were read, in a few words.
        var text: String {
            switch self {
            case .codeSignature: "Code signature"
            case .executable: "Linked into the executable"
            case .provisioningProfile: "Provisioning profile"
            }
        }
    }
#endif
