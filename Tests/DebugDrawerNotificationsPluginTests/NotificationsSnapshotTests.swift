// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerNotificationsPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (the editor, the picker, the buttons) as
    // placeholders, so the tests host the view in a window that is never shown and draw it into a
    // bitmap at a fixed 2x scale, in the appearance the test asks for: the snapshot doesn't depend
    // on the Mac's own appearance or display. macOS doesn't scale text with Dynamic Type, so the Mac
    // pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NotificationsSnapshotTests {
        @Test("The token, the authorization and settings, the editor with its note and last send, and a pending and a delivered notification",
              arguments: [ColorScheme.light, .dark])
        func notifications(colorScheme: ColorScheme) throws {
            let snapshot = NotificationCenterSnapshot(
                settings: NotificationSettings(authorization: .authorized, items: [
                    .init(name: "Alerts", value: "On"), .init(name: "Sounds", value: "On"), .init(name: "Badges", value: "Off"),
                    .init(name: "Alert Style", value: "Banners")
                ]),
                pending: [ListedNotification(
                    id: "debugdrawer-5B1E", title: "Reminder", body: "Your cart is waiting",
                    trigger: .timeInterval(seconds: 30, repeats: false, next: Date(timeIntervalSince1970: 1_800_000_030))
                )],
                delivered: [ListedNotification(
                    id: "order-7", title: "Order shipped", subtitle: "Today", body: "It's on its way", categoryIdentifier: "ORDER", badge: 1,
                    trigger: .immediate, deliveredAt: Date(timeIntervalSince1970: 1_800_000_000),
                    userInfo: UserInfoText(["aps": ["alert": ["title": "Order shipped"], "badge": 1], "orderID": 7])
                )]
            )
            let sut = NotificationsView(
                registration: .registered(deviceToken: Data((0 ..< 32).map { UInt8($0 * 7 % 256) })),
                center: .loaded(snapshot),
                authorizationRequest: .idle,
                sendState: .sent(identifier: "debugdrawer-5B1E", delay: .thirtySeconds),
                draft: .constant(#"{"aps": {"alert": {"title": "Order shipped", "loc-key": "ORDER_BODY"}, "badge": 1}, "orderID": 7}"#),
                delay: .constant(.thirtySeconds),
                redaction: .none,
                actions: NotificationsActions()
            )
            let host = NSHostingView(rootView: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("With 50 pending and 50 delivered, each list shows its newest five on one line each and Show All, below the token and composer",
              arguments: [ColorScheme.light, .dark])
        func manyNotifications(colorScheme: ColorScheme) throws {
            let snapshot = NotificationCenterSnapshot(
                settings: NotificationSettings(authorization: .authorized, items: [
                    .init(name: "Alerts", value: "On"), .init(name: "Sounds", value: "On"), .init(name: "Badges", value: "On")
                ]),
                pending: (1 ... 50).map { index in
                    ListedNotification(
                        id: "reminder-\(index)", title: "Reminder \(index)", subtitle: "Cart", body: "Your cart is waiting",
                        trigger: .timeInterval(
                            seconds: Double(index * 60), repeats: false, next: Date(timeIntervalSince1970: 1_800_000_000 + Double(index * 60))
                        ),
                        userInfo: UserInfoText(["cartID": index])
                    )
                },
                delivered: (1 ... 50).map { index in
                    ListedNotification(
                        id: "order-\(index)", title: "Order \(index) shipped with a title long enough to be cut", subtitle: "Today",
                        body: "It's on its way", categoryIdentifier: "ORDER", threadIdentifier: "orders", badge: index,
                        trigger: .push, deliveredAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index * 60)),
                        userInfo: UserInfoText(["aps": ["alert": ["title": "Order \(index) shipped"], "badge": index], "orderID": index])
                    )
                }
            )
            let sut = NotificationsView(
                registration: .registered(deviceToken: Data((0 ..< 32).map { UInt8($0 * 7 % 256) })),
                center: .loaded(snapshot),
                authorizationRequest: .idle,
                sendState: .idle,
                draft: .constant(#"{"aps": {"alert": "Hi"}}"#),
                delay: .constant(.now),
                redaction: .none,
                actions: NotificationsActions()
            )
            let host = NSHostingView(rootView: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("An opened delivered notification shows its subtitle, body, identifier, details and userInfo under its line",
              arguments: [ColorScheme.light, .dark])
        func expandedRow(colorScheme: ColorScheme) throws {
            let notification = ListedNotification(
                id: "order-7", title: "Order shipped", subtitle: "Today", body: "It's on its way", categoryIdentifier: "ORDER",
                threadIdentifier: "orders", badge: 1, trigger: .push, deliveredAt: Date(timeIntervalSince1970: 1_800_000_000),
                userInfo: UserInfoText(["aps": ["alert": ["title": "Order shipped"], "badge": 1], "orderID": 7])
            )
            let sut = VStack(alignment: .leading, spacing: 0) {
                ListedNotificationRow(notification: notification, redaction: .none, onRemove: {}, isExpanded: true)
                ListedNotificationRow(
                    notification: ListedNotification(
                        id: "order-6", title: "Order packed", trigger: .push, deliveredAt: Date(timeIntervalSince1970: 1_799_999_000)
                    ),
                    redaction: .none, onRemove: {}
                )
            }
            let host = NSHostingView(rootView: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("The plugin is as tall with 500 notifications in each list as with 6: the lists show the newest five until Show All")
        func heightIsCapped() {
            func notifications(_ count: Int) -> [ListedNotification] {
                (1 ... count).map { index in
                    ListedNotification(
                        id: "order-\(index)", title: "Order \(index) shipped", subtitle: "Today", body: "It's on its way",
                        trigger: .push, deliveredAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
                        userInfo: UserInfoText(["orderID": index])
                    )
                }
            }
            func height(each count: Int) -> CGFloat {
                let snapshot = NotificationCenterSnapshot(
                    settings: NotificationSettings(authorization: .authorized, items: []),
                    pending: notifications(count), delivered: notifications(count)
                )
                let view = NotificationsView(
                    registration: .notRegistered, center: .loaded(snapshot), authorizationRequest: .idle, sendState: .idle,
                    draft: .constant(""), delay: .constant(.now), redaction: .none, actions: NotificationsActions()
                )
                let host = NSHostingView(rootView: view
                    .frame(width: 320, alignment: .leading)
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt))
                return host.fittingSize.height
            }
            let expected = height(each: 6)

            let actual = height(each: 500)

            #expect(actual == expected)
        }
    }
#endif
