#if DEBUG
    import AppTrackingTransparency
    import AVFoundation
    import Contacts
    import CoreBluetooth
    import CoreLocation
    @testable import DebugDrawerPermissionsPlugin
    import EventKit
    import Photos
    import Speech
    import Testing
    import UserNotifications
    #if os(iOS)
        import CoreMotion
        import MediaPlayer
    #endif

    @Suite
    struct PermissionStatusMappingTests {
        @Test("Camera and microphone statuses map case by case")
        func capture() {
            let statuses: [AVAuthorizationStatus] = [.notDetermined, .restricted, .denied, .authorized]
            let expected: [PermissionStatus] = [.notDetermined, .restricted, .denied, .authorized]

            let actual = statuses.map(PermissionStatus.init)

            #expect(actual == expected)
        }

        @Test("Photos' limited access is limited")
        func photos() {
            let statuses: [PHAuthorizationStatus] = [.notDetermined, .restricted, .denied, .authorized, .limited]
            let expected: [PermissionStatus] = [.notDetermined, .restricted, .denied, .authorized, .limited]

            let actual = statuses.map(PermissionStatus.init)

            #expect(actual == expected)
        }

        @Test("Location tells always from while in use, where the platform has both")
        func location() {
            #if os(iOS)
                let statuses: [CLAuthorizationStatus] = [.notDetermined, .restricted, .denied, .authorizedAlways, .authorizedWhenInUse]
                let expected: [PermissionStatus] = [.notDetermined, .restricted, .denied, .authorizedAlways, .authorizedWhenInUse]
            #else
                // macOS has no when-in-use status.
                let statuses: [CLAuthorizationStatus] = [.notDetermined, .restricted, .denied, .authorizedAlways]
                let expected: [PermissionStatus] = [.notDetermined, .restricted, .denied, .authorizedAlways]
            #endif

            let actual = statuses.map(PermissionStatus.init)

            #expect(actual == expected)
        }

        @Test("Contacts statuses map case by case")
        func contacts() {
            let statuses: [CNAuthorizationStatus] = [.notDetermined, .restricted, .denied, .authorized]
            let expected: [PermissionStatus] = [.notDetermined, .restricted, .denied, .authorized]

            let actual = statuses.map(PermissionStatus.init)

            #expect(actual == expected)
        }

        // Limited contacts access exists on iOS 18 and later alone; macOS has none.
        #if os(iOS)
            @available(iOS 18.0, *)
            @Test("Contacts' limited access is limited")
            func contactsLimited() {
                let status = CNAuthorizationStatus.limited

                let actual = PermissionStatus(status)

                #expect(actual == .limited)
            }

            @Test("Motion and media library statuses map case by case")
            func iOSOnly() {
                let expected: [PermissionStatus] = [.notDetermined, .restricted, .denied, .authorized]

                let motion = [CMAuthorizationStatus.notDetermined, .restricted, .denied, .authorized].map(PermissionStatus.init)
                let media = [MPMediaLibraryAuthorizationStatus.notDetermined, .restricted, .denied, .authorized].map(PermissionStatus.init)

                #expect(motion == expected)
                #expect(media == expected)
            }
        #endif

        @Test("Calendars' full access is allowed and write-only access is its own status")
        func calendars() {
            let statuses: [EKAuthorizationStatus] = [.notDetermined, .restricted, .denied, .fullAccess, .writeOnly]
            let expected: [PermissionStatus] = [.notDetermined, .restricted, .denied, .authorized, .writeOnly]

            let actual = statuses.map(PermissionStatus.init)

            #expect(actual == expected)
        }

        @Test("Notifications can be provisional")
        func notifications() {
            let statuses: [UNAuthorizationStatus] = [.notDetermined, .denied, .authorized, .provisional]
            let expected: [PermissionStatus] = [.notDetermined, .denied, .authorized, .provisional]

            let actual = statuses.map(PermissionStatus.init)

            #expect(actual == expected)
        }

        @Test("Tracking, speech recognition and Bluetooth statuses map case by case")
        func others() {
            let expected: [PermissionStatus] = [.notDetermined, .restricted, .denied, .authorized]

            let tracking = [ATTrackingManager.AuthorizationStatus.notDetermined, .restricted, .denied, .authorized].map(PermissionStatus.init)
            let speech = [SFSpeechRecognizerAuthorizationStatus.notDetermined, .restricted, .denied, .authorized].map(PermissionStatus.init)
            let bluetooth = [CBManagerAuthorization.notDetermined, .restricted, .denied, .allowedAlways].map(PermissionStatus.init)

            #expect(tracking == expected)
            #expect(speech == expected)
            #expect(bluetooth == expected)
        }

        @Test("A status newer than the plugin is unknown, with its raw value")
        func unknown() throws {
            let status = try #require(AVAuthorizationStatus(rawValue: 42))
            let expected = PermissionStatus.unknown(rawValue: 42)

            let actual = PermissionStatus(status)

            #expect(actual == expected)
            #expect(actual.title == "Unknown (42)")
        }

        @Test("Each grant has its own symbol, so a status reads without its color")
        func symbols() {
            let grants: [PermissionStatus.Grant] = [.granted, .partial, .refused, .undecided, .unknown]

            let actual = Set(grants.map(\.symbol))

            #expect(actual.count == grants.count)
        }

        @Test("Statuses group by how far they let the app go")
        func grants() {
            let statuses: [PermissionStatus] = [.authorizedWhenInUse, .limited, .writeOnly, .restricted, .notDetermined, .noStatusAPI, .checking]
            let expected: [PermissionStatus.Grant] = [.granted, .partial, .partial, .refused, .undecided, .unknown, .unknown]

            let actual = statuses.map(\.grant)

            #expect(actual == expected)
        }
    }
#endif
