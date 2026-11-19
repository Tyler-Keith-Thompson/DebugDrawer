#if DEBUG
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
        /// The facts a snapshot holds, worded as the drawer shows them.
        ///
        /// - Parameter snapshot: What ``AppInfoModel`` read.
        init(snapshot: AppInfoSnapshot) {
            let build = snapshot.build
            let device = snapshot.device
            let gigabyte = 1024.0 * 1024 * 1024
            var environment = [Fact(label: device.operatingSystemName, value: device.operatingSystemVersion)]
            if let isSandboxed = device.isSandboxed {
                environment.append(Fact(label: "Sandbox", value: isSandboxed ? "Yes" : "No"))
            }
            environment += [
                Fact(label: "Debugger", value: snapshot.processStart.map { $0.isTraced ? "Attached" : "Not attached" } ?? "—"),
                Fact(label: "Active CPU", value: "\(device.activeProcessorCount)"),
                Fact(label: "Physical Mem", value: String(format: "%.0f GB", Double(device.physicalMemory) / gigabyte)),
                Fact(label: "Screen", value: device.screen.map(Self.format) ?? "—"),
                Fact(label: "Network", value: snapshot.network.text),
                Fact(label: "Launched", value: snapshot.processStart.map { Self.launchFormatter.string(from: $0.date) } ?? "—")
            ]
            self.init(
                sections: [
                    Section(title: "Build", facts: [
                        Fact(label: "Bundle ID", value: snapshot.bundle.identifier ?? "—"),
                        Fact(label: "Version", value: snapshot.bundle.version ?? "—"),
                        Fact(label: "Build", value: snapshot.bundle.build ?? "—"),
                        Fact(label: "Commit", value: build.gitCommit ?? "—"),
                        Fact(label: "Branch", value: build.gitBranch ?? "—"),
                        Fact(label: "CI Build", value: build.ciBuildNumber ?? "—")
                    ]),
                    Section(title: "Runtime", facts: [
                        Fact(label: "Footprint", value: String(format: "%.1f MB", snapshot.footprintMB)),
                        Fact(label: "Uptime", value: snapshot.uptime.map(Self.formatDuration) ?? "—"),
                        Fact(label: "PID", value: "\(snapshot.processIdentifier)"),
                        Fact(label: "Arch", value: device.architecture),
                        Fact(label: "Arguments", value: "\(snapshot.argumentCount)")
                    ]),
                    Section(title: "Environment", facts: environment)
                ],
                signing: snapshot.signing,
                isProfileExpired: snapshot.isProfileExpired
            )
        }

        static func formatDuration(_ seconds: TimeInterval) -> String {
            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60
            let remainder = Int(seconds) % 60
            if hours > 0 { return "\(hours)h \(minutes)m \(remainder)s" }
            if minutes > 0 { return "\(minutes)m \(remainder)s" }
            return "\(remainder)s"
        }

        /// A screen as its size in points and its scale: `1512×982 @2x`.
        private static func format(_ screen: DeviceInfo.Screen) -> String {
            "\(Int(screen.width))×\(Int(screen.height)) @\(Int(screen.scale))x"
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

    extension NetworkReachability {
        /// The reachability in a word.
        var text: String {
            switch self {
            case .unknown: "Unknown"
            case .offline: "Offline"
            case .wifi: "WiFi"
            case .cellular: "Cellular"
            case .wiredEthernet: "Ethernet"
            case .online: "Online"
            }
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
