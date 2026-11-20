#if DEBUG
    import Foundation

    /// What a bug report's `summary.txt` says about the app and the device it ran on.
    package struct ReportSummary: Equatable {
        package var appName: String
        package var bundleID: String
        package var version: String
        package var build: String
        package var operatingSystem: String
        package var deviceModel: String
        package var date: Date

        package init(appName: String, bundleID: String, version: String, build: String, operatingSystem: String, deviceModel: String, date: Date) {
            self.appName = appName
            self.bundleID = bundleID
            self.version = version
            self.build = build
            self.operatingSystem = operatingSystem
            self.deviceModel = deviceModel
            self.date = date
        }

        /// The running app, this process and this device, at `date`.
        package static func current(at date: Date, bundle: Bundle = .main, process: ProcessInfo = .processInfo) -> ReportSummary {
            ReportSummary(
                appName: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? process.processName,
                bundleID: bundle.bundleIdentifier ?? "—",
                version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
                build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—",
                operatingSystem: "\(operatingSystemName) \(process.operatingSystemVersionString)",
                deviceModel: deviceModel(process: process),
                date: date
            )
        }

        /// The report's folder name: the app's name, `-Report-` and the date in ISO 8601 with `-`
        /// for `:`, which some file systems reserve.
        var folderName: String {
            let timestamp = ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
            let app = appName.fileNameSafe
            return "\(app.isEmpty ? "App" : app)-Report-\(timestamp)"
        }

        /// The summary's text: the app, the device and the date, then every file of `report`,
        /// grouped by the plugin's folder in the order they were added.
        func text(listing report: DebugDrawerReport) -> String {
            var lines = [
                "Bug report: \(appName)",
                "",
                "Bundle ID: \(bundleID)",
                "Version: \(version) (\(build))",
                "OS: \(operatingSystem)",
                "Device: \(deviceModel)",
                "Created: \(ISO8601DateFormatter().string(from: date))",
                "",
                "Files:",
                "summary.txt"
            ]
            var folders: [String] = []
            for file in report.files {
                guard let folder = file.folder else {
                    lines.append(file.name)
                    continue
                }
                if !folders.contains(folder) {
                    folders.append(folder)
                }
            }
            for folder in folders {
                lines.append("\(folder)/")
                lines += report.files.filter { $0.folder == folder }.map { "  \($0.name)" }
            }
            if report.files.isEmpty {
                lines += ["", "No installed plugin contributed to the report."]
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }

    extension ReportSummary {
        fileprivate static var operatingSystemName: String {
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

        /// The hardware model identifier (`Mac15,3`, `iPad16,6`); in the simulator, the
        /// simulated device's.
        fileprivate static func deviceModel(process: ProcessInfo) -> String {
            // Under Mac Catalyst, uname's machine is only the CPU (`arm64`); hw.model names the Mac.
            #if os(macOS) || targetEnvironment(macCatalyst)
                var size = 0
                guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "—" }
                var model = [CChar](repeating: 0, count: size)
                guard sysctlbyname("hw.model", &model, &size, nil, 0) == 0 else { return "—" }
                return String(bytes: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? "—"
            #else
                if let simulated = process.environment["SIMULATOR_MODEL_IDENTIFIER"] {
                    return simulated
                }
                var system = utsname()
                uname(&system)
                return withUnsafeBytes(of: &system.machine) { buffer in
                    String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8) ?? "—"
                }
            #endif
        }
    }
#endif
