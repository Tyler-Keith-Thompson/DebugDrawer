#if DEBUG
    import Foundation

    /// A provisioning profile, as `embedded.mobileprovision` (iOS) or `embedded.provisionprofile`
    /// (macOS) holds it: who it was issued to, for how long, for which devices, and the
    /// entitlements it allows.
    struct ProvisioningProfile: Codable, Equatable, Sendable {
        /// The devices a profile lets the app run on.
        enum Devices: Codable, Equatable, Sendable {
            /// The devices in `ProvisionedDevices`, by count; a development or ad hoc profile.
            case listed(Int)
            /// Any device (`ProvisionsAllDevices`); an enterprise profile.
            case all
            /// No device is named; a distribution profile.
            case unlisted
        }

        /// The bytes aren't a profile: no property list, or one without a profile's fields.
        struct MalformedProfile: Error, Equatable {}

        var name: String
        var teamName: String
        var teamIdentifier: String
        var creationDate: Date
        var expirationDate: Date
        var devices: Devices
        var entitlements: Entitlements

        init(
            name: String, teamName: String, teamIdentifier: String, creationDate: Date, expirationDate: Date,
            devices: Devices, entitlements: Entitlements
        ) {
            self.name = name
            self.teamName = teamName
            self.teamIdentifier = teamIdentifier
            self.creationDate = creationDate
            self.expirationDate = expirationDate
            self.devices = devices
            self.entitlements = entitlements
        }

        /// The profile in a profile file's bytes.
        ///
        /// The file is a CMS (PKCS #7) signed message around an XML property list. The list is read
        /// from between its `<?xml` and `</plist>`, on both platforms: CMSDecoder, which would
        /// unwrap it properly, exists on the Mac alone, and the signature it would check means
        /// nothing here, where the profile is only shown. One reading also lets the tests run it on
        /// both platforms against a synthetic profile.
        ///
        /// - Throws: ``MalformedProfile`` when the bytes hold no property list, or one missing the
        ///   name, team, dates or entitlements.
        init(profileData data: Data) throws(MalformedProfile) {
            guard let start = data.range(of: Data("<?xml".utf8)),
                  let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound ..< data.endIndex),
                  let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound ..< end.upperBound], format: nil),
                  let dictionary = plist as? [String: Any],
                  let name = dictionary["Name"] as? String,
                  let teamName = dictionary["TeamName"] as? String,
                  let teamIdentifier = (dictionary["TeamIdentifier"] as? [String])?.first,
                  let creationDate = dictionary["CreationDate"] as? Date,
                  let expirationDate = dictionary["ExpirationDate"] as? Date,
                  let entitlements = dictionary["Entitlements"] as? [String: Any]
            else { throw MalformedProfile() }
            self.init(
                name: name, teamName: teamName, teamIdentifier: teamIdentifier,
                creationDate: creationDate, expirationDate: expirationDate,
                devices: Devices(dictionary),
                entitlements: Entitlements(dictionary: entitlements, source: .provisioningProfile)
            )
        }

        /// Whether the profile has expired by `date`; an app signed with it no longer launches.
        func isExpired(at date: Date) -> Bool {
            expirationDate <= date
        }

        /// A date as App Info shows it: to the minute, in UTC, the same in every locale and time
        /// zone, as an expiry compared across a team's machines needs.
        static func format(_ date: Date) -> String {
            dateFormatter.string(from: date)
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
            return formatter
        }()
    }

    extension ProvisioningProfile.Devices {
        /// The devices of a profile's dictionary.
        fileprivate init(_ dictionary: [String: Any]) {
            if let devices = dictionary["ProvisionedDevices"] as? [String] {
                self = .listed(devices.count)
            } else if dictionary["ProvisionsAllDevices"] as? Bool == true {
                self = .all
            } else {
                self = .unlisted
            }
        }

        /// The devices as App Info shows them.
        var text: String {
            switch self {
            case let .listed(count): "\(count)"
            case .all: "All"
            case .unlisted: "Not listed"
            }
        }
    }
#endif
