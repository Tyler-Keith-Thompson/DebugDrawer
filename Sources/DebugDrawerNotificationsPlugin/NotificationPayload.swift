#if DEBUG
    import Foundation

    /// An APNs payload, read as a local notification's content: the `aps` dictionary's alert,
    /// badge, sound and the rest, and the whole payload as the `userInfo` the app's handlers see.
    struct NotificationPayload: Equatable, Sendable {
        /// The `sound` an alert plays.
        enum Sound: Equatable, Sendable {
            /// `"default"`: the system's sound.
            case `default`
            /// A sound file in the app's bundle or Library/Sounds.
            case named(String)
            /// A critical alert's (`"critical": 1`), the default one when `name` is `nil`, at
            /// `volume` from 0 to 1 when given.
            case critical(name: String?, volume: Double?)
        }

        /// The `interruption-level`.
        enum InterruptionLevel: String, Equatable, Sendable, CaseIterable {
            case passive
            case active
            case timeSensitive = "time-sensitive"
            case critical
        }

        var title = ""
        var subtitle = ""
        var body = ""
        var badge: Int?
        var sound: Sound?
        var categoryIdentifier = ""
        var threadIdentifier = ""
        var targetContentIdentifier: String?
        var launchImageName = ""
        var interruptionLevel: InterruptionLevel?
        var relevanceScore: Double?
        /// What a local notification does differently from the push this payload describes, and
        /// what in it a push would be refused or shown blank for: one sentence each.
        var notes: [String] = []
        /// The whole payload as JSON with sorted keys, which `userInfo` is read from.
        let json: Data

        /// The payload's dictionary, `aps` and every key beside it, as a push delivers it to the
        /// app's handlers.
        var userInfo: [AnyHashable: Any] {
            (try? JSONSerialization.jsonObject(with: json)) as? [AnyHashable: Any] ?? [:]
        }

        /// The largest payload APNs accepts for a notification, in bytes.
        static let maximumSize = 4096

        /// Reads `text` as an APNs payload.
        ///
        /// A string `alert` is the body; a dictionary's `title-loc-key`, `subtitle-loc-key` and
        /// `loc-key` stand for the text they name, shown as the key itself with a note, where its
        /// `title`, `subtitle` or `body` is missing. Text that is JSON only once its curly double
        /// quotes are straight, as iOS's keyboard types them, is read that way.
        ///
        /// - Throws: `NotificationPayloadError` for text that isn't a JSON object with an `aps`
        ///   dictionary, or a key in `aps` whose value has the wrong type.
        init(parsing text: String) throws(NotificationPayloadError) {
            guard !text.allSatisfy(\.isWhitespace) else { throw .empty }
            var data = Data(text.utf8)
            let object: Any
            if let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                object = parsed
            } else {
                // Tried second, as a curly quote inside a string is the text's own.
                let straightened = Data(text.replacing(/[“”]/, with: "\"").utf8)
                guard let parsed = try? JSONSerialization.jsonObject(with: straightened, options: [.fragmentsAllowed]) else { throw .notJSON }
                object = parsed
                data = straightened
            }
            guard let payload = object as? [String: Any] else { throw .notAnObject }
            guard let apsValue = payload["aps"] else { throw .missingAPS }
            guard let aps = apsValue as? [String: Any] else { throw .wrongType(key: "aps", expected: "an object") }
            // Sorted keys, so two pastes of one payload compare equal however their keys were
            // ordered. The object came from JSONSerialization, so it encodes back.
            json = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? data

            try readAlert(aps["alert"])
            badge = try aps.value(of: "badge", as: Int.self, expected: "a whole number")
            sound = try Self.sound(aps["sound"])
            categoryIdentifier = try aps.value(of: "category", as: String.self, expected: "a string") ?? ""
            threadIdentifier = try aps.value(of: "thread-id", as: String.self, expected: "a string") ?? ""
            targetContentIdentifier = try aps.value(of: "target-content-id", as: String.self, expected: "a string")
            relevanceScore = try aps.value(of: "relevance-score", as: Double.self, expected: "a number")
            if let level = try aps.value(of: "interruption-level", as: String.self, expected: "a string") {
                guard let interruptionLevel = InterruptionLevel(rawValue: level) else {
                    throw .wrongType(key: "interruption-level", expected: "passive, active, time-sensitive or critical")
                }
                self.interruptionLevel = interruptionLevel
            }
            notes += Self.notes(aps: aps, isBlank: title.isEmpty && subtitle.isEmpty && body.isEmpty, size: data.count)
        }

        private mutating func readAlert(_ alert: Any?) throws(NotificationPayloadError) {
            switch alert {
            case nil:
                return
            case let text as String:
                body = text
            case let alert as [String: Any]:
                title = try alert.value(of: "title", as: String.self, expected: "a string") ?? ""
                subtitle = try alert.value(of: "subtitle", as: String.self, expected: "a string") ?? ""
                body = try alert.value(of: "body", as: String.self, expected: "a string") ?? ""
                launchImageName = try alert.value(of: "launch-image", as: String.self, expected: "a string") ?? ""
                title = try localizationKey("title-loc-key", in: alert, standingFor: title)
                subtitle = try localizationKey("subtitle-loc-key", in: alert, standingFor: subtitle)
                body = try localizationKey("loc-key", in: alert, standingFor: body)
            default:
                throw .wrongType(key: "alert", expected: "a string or an object")
            }
        }

        /// `text`, or, where it is empty, the localization key `key` names, shown as is with a note.
        private mutating func localizationKey(
            _ key: String, in alert: [String: Any], standingFor text: String
        ) throws(NotificationPayloadError) -> String {
            guard let localizationKey = try alert.value(of: key, as: String.self, expected: "a string"), text.isEmpty else { return text }
            notes.append("""
            \(key) “\(localizationKey)” is shown as the key: a push is localized on the device from the app’s strings, \
            a local notification isn’t.
            """)
            return localizationKey
        }

        private static func sound(_ value: Any?) throws(NotificationPayloadError) -> Sound? {
            switch value {
            case nil:
                return nil
            case let name as String:
                return name == "default" ? .default : .named(name)
            case let sound as [String: Any]:
                let name = try sound.value(of: "name", as: String.self, expected: "a string")
                let isCritical = try sound.value(of: "critical", as: Int.self, expected: "0 or 1") == 1
                let volume = try sound.value(of: "volume", as: Double.self, expected: "a number from 0 to 1")
                if isCritical {
                    return .critical(name: name == "default" ? nil : name, volume: volume)
                }
                return name.map { $0 == "default" ? .default : .named($0) } ?? .default
            default:
                throw .wrongType(key: "sound", expected: "a string or an object")
            }
        }

        private static func notes(aps: [String: Any], isBlank: Bool, size: Int) -> [String] {
            let isBackground = (aps["content-available"] as? Int) == 1
            let isMutable = (aps["mutable-content"] as? Int) == 1
            return [
                isBackground
                    ? """
                    content-available asks to wake the app in the background: a local notification doesn’t call \
                    application(_:didReceiveRemoteNotification:fetchCompletionHandler:).
                    """
                    : nil,
                isMutable ? "mutable-content asks for the app’s notification service extension: it doesn’t run for a local notification." : nil,
                isBlank && !isBackground ? "It has no title, subtitle or body, so the system shows nothing for it." : nil,
                size > maximumSize ? "It is \(size) bytes: APNs refuses a payload over \(maximumSize)." : nil
            ].compactMap(\.self)
        }
    }

    extension [String: Any] {
        /// The value under `key` as a `T`; `nil` when there is none.
        ///
        /// - Throws: `NotificationPayloadError.wrongType` when the value isn't a `T`.
        fileprivate func value<T>(of key: String, as _: T.Type, expected: String) throws(NotificationPayloadError) -> T? {
            guard let value = self[key] else { return nil }
            // JSONSerialization reads every number as an NSNumber, which converts to Int only when
            // it is whole, and to Double always.
            guard let typed = value as? T, !(value is NSNull) else { throw .wrongType(key: key, expected: expected) }
            return typed
        }
    }
#endif
