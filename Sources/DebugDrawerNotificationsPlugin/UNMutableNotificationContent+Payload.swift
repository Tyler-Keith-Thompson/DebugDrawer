#if DEBUG
    import Foundation
    import UserNotifications

    extension UNMutableNotificationContent {
        /// The content a push of `payload` would show: its alert, badge, sound, category, thread,
        /// interruption level and relevance score, with the whole payload as `userInfo`.
        ///
        /// macOS has no critical sounds, so a critical one plays the default sound there.
        convenience init(_ payload: NotificationPayload) {
            self.init()
            title = payload.title
            subtitle = payload.subtitle
            body = payload.body
            badge = payload.badge.map { NSNumber(value: $0) }
            sound = payload.sound.map(UNNotificationSound.make)
            categoryIdentifier = payload.categoryIdentifier
            threadIdentifier = payload.threadIdentifier
            targetContentIdentifier = payload.targetContentIdentifier
            #if os(iOS)
                launchImageName = payload.launchImageName
            #endif
            if let level = payload.interruptionLevel {
                interruptionLevel = UNNotificationInterruptionLevel(level)
            }
            if let score = payload.relevanceScore {
                relevanceScore = score
            }
            userInfo = payload.userInfo
        }
    }

    extension UNNotificationSound {
        fileprivate static func make(_ sound: NotificationPayload.Sound) -> UNNotificationSound {
            switch sound {
            case .default:
                return .default
            case let .named(name):
                return UNNotificationSound(named: UNNotificationSoundName(name))
            case let .critical(name, volume):
                #if os(iOS)
                    switch (name, volume) {
                    case let (name?, volume?): return .criticalSoundNamed(UNNotificationSoundName(name), withAudioVolume: Float(volume))
                    case let (name?, nil): return .criticalSoundNamed(UNNotificationSoundName(name))
                    case let (nil, volume?): return .defaultCriticalSound(withAudioVolume: Float(volume))
                    case (nil, nil): return .defaultCritical
                    }
                #else
                    return .default
                #endif
            }
        }
    }

    extension UNNotificationInterruptionLevel {
        fileprivate init(_ level: NotificationPayload.InterruptionLevel) {
            switch level {
            case .passive: self = .passive
            case .active: self = .active
            case .timeSensitive: self = .timeSensitive
            case .critical: self = .critical
            }
        }
    }
#endif
