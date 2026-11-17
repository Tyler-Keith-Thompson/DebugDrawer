// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawerDatabaseBrowserPlugin
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DatabaseBrowserDynamicTypeSnapshotTests {
        @Test("The browser stays readable at an accessibility text size: store facts, tables, the rows grid and the query editor")
        func browser() throws {
            let shop = DatabaseStore(
                url: URL(filePath: "/var/mobile/Containers/Data/Application/0A1B/Library/Application Support/Sample Shop.sqlite"),
                location: .applicationSupport, size: 98_304, walSize: 4_152, journalMode: .wal, canWriteSharedMemory: true
            )
            let tables = [
                StoreTable(
                    name: "products", isView: false,
                    columns: [StoreColumn(name: "id", declaredType: "INTEGER"), StoreColumn(name: "name", declaredType: "TEXT")],
                    rowCount: 120, hasRowID: true
                ),
                StoreTable(name: "orders", isView: false, columns: [], rowCount: 300, hasRowID: true)
            ]
            let listing = StoreListing(store: shop, schema: .success(StoreSchema(kind: .sqlite, tables: tables)))
            let page = TablePage(
                rows: ResultSet(columns: ["id", "name"], rows: [[.integer(1), .text("Espresso cup")], [.integer(2), .null]]),
                pageIndex: 1, matchingCount: 120, searchedColumns: []
            )
            let sut = DatabaseBrowserView(
                stores: .loaded([listing]), filter: .constant(""), selectedStore: .constant(shop.id), selectedTable: .constant("products"),
                search: .constant(""), page: .loaded(page), sql: .constant("SELECT * FROM \"products\" LIMIT 50"),
                query: .failed(.writes), actions: DatabaseBrowserActions()
            )
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: 320, alignment: .leading)
            // No height proposed, as the drawer's scroll view proposes none.
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility3)
            // ImageRenderer draws UIKit-backed controls (the fields, the editor, the buttons) as
            // placeholders, so the view is hosted in a window that is never shown and its layer is
            // rendered, at a fixed width and scale.
            let controller = UIHostingController(rootView: sut)
            // No safe area: the window's status bar inset would lay the view out shorter than it
            // measured, overlapping its rows.
            controller.safeAreaRegions = []
            let size = controller.sizeThatFits(in: CGSize(width: 352, height: 8000))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .light
            window.isHidden = false
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let actual = UIGraphicsImageRenderer(size: size, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            window.isHidden = true

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }
    }
#endif
