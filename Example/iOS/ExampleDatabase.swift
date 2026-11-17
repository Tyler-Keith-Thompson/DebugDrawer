import CoreData
import DebugDrawerDatabaseBrowserPlugin
import Foundation
import SQLite3

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The example's stores, for the Databases plugin: a SQLite shop and a Core Data store of pets,
/// both in Application Support.
enum ExampleDatabase {
    /// Launched with this argument, the app writes both stores afresh at startup, so the plugin
    /// can be checked without a hand.
    static let launchArgument = "-SeedSampleDatabase"

    /// The shop's connection, kept open as an app keeps its own, so the store stays in WAL mode
    /// with its -wal and -shm files beside it while the browser reads.
    nonisolated(unsafe) private static var shop: OpaquePointer?
    /// The pets' container, kept for the same reason.
    nonisolated(unsafe) private static var pets: NSPersistentContainer?

    /// Writes the sample stores when launched with ``launchArgument``, then installs the plugin.
    @MainActor
    static func install() {
        if ProcessInfo.processInfo.arguments.contains(launchArgument) {
            seed()
        }
        DatabaseBrowser.install()
    }

    /// Writes "Sample Shop.sqlite" (customers, products with a blob thumbnail, orders and a view,
    /// with NULLs) and "Pets.sqlite" (Core Data: Owner, and Animal with Cat and Dog under it).
    static func seed() {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        seedShop(at: folder.appending(path: "Sample Shop.sqlite"))
        seedPets(at: folder.appending(path: "Pets.sqlite"))
    }

    private static func seedShop(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path(percentEncoded: false) + suffix)
        }
        guard sqlite3_open(url.path(percentEncoded: false), &shop) == SQLITE_OK else { return }
        let schema = """
            PRAGMA journal_mode = WAL;
            CREATE TABLE customers(id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT, city TEXT, joined TEXT);
            CREATE TABLE products(id INTEGER PRIMARY KEY, name TEXT NOT NULL, price REAL, stock INTEGER, notes TEXT, thumbnail BLOB);
            CREATE TABLE orders(id INTEGER PRIMARY KEY, customer_id INTEGER REFERENCES customers(id),
                product_id INTEGER REFERENCES products(id), quantity INTEGER, total REAL, placed TEXT, note TEXT);
            CREATE VIEW big_spenders AS
                SELECT c.name, sum(o.total) AS spent FROM customers c JOIN orders o ON o.customer_id = c.id
                GROUP BY c.id HAVING spent > 500;
            """
        sqlite3_exec(shop, schema, nil, nil, nil)
        sqlite3_exec(shop, "BEGIN", nil, nil, nil)
        let names = ["Ana", "Bo", "Chen", "Dita", "Emeka", "Farah", "Gus", "Hana", "Ivo", "Jun", "Kemal", "Lena"]
        let cities = ["Auckland", "Berlin", "Chicago", "Lagos", "Osaka", nil]
        for id in 1 ... 60 {
            let name = "\(names[id % names.count]) \(["Smith", "O'Brien", "Nguyen", "García", "Kowalski"][id % 5])"
            let email: String? = id % 7 == 0 ? nil : "customer\(id)@example.com"
            insert("INSERT INTO customers VALUES (?, ?, ?, ?, ?)", [.integer(id), .text(name), email.map(Value.text) ?? .null,
                cities[id % cities.count].map(Value.text) ?? .null, .text("2026-0\(id % 9 + 1)-1\(id % 10)")])
        }
        let goods = ["Espresso cup", "Plate", "Tea pot", "Bowl", "Mug, large", "Saucer", "Jug \"Classic\"", "Tray"]
        for id in 1 ... 120 {
            let thumbnail: Value = id % 4 == 0 ? .null : .blob(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(count: 24 + id))
            let notes: Value = id % 3 == 0 ? .text("Fragile\nShip in a box") : id % 5 == 0 ? .text("Gift") : .null
            insert("INSERT INTO products VALUES (?, ?, ?, ?, ?, ?)", [.integer(id), .text("\(goods[id % goods.count]) #\(id)"),
                .real(Double(id % 40) * 1.25 + 4.99), .integer((id * 7) % 50), notes, thumbnail])
        }
        for id in 1 ... 300 {
            let quantity = id % 4 + 1
            insert("INSERT INTO orders VALUES (?, ?, ?, ?, ?, ?, ?)", [.integer(id), .integer(id % 60 + 1), .integer(id % 120 + 1),
                .integer(quantity), .real(Double(quantity) * (Double(id % 40) * 1.25 + 4.99)),
                .text("2026-1\(id % 2)-\(id % 28 + 1 < 10 ? "0" : "")\(id % 28 + 1)"), id % 9 == 0 ? .text("Leave at the door") : .null])
        }
        sqlite3_exec(shop, "COMMIT", nil, nil, nil)
    }

    private enum Value {
        case integer(Int), real(Double), text(String), blob(Data), null
    }

    private static func insert(_ sql: String, _ values: [Value]) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(shop, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        // SQLITE_TRANSIENT: SQLite copies the bytes, as the Swift strings and data don't outlive the call.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let .integer(number): sqlite3_bind_int64(statement, position, Int64(number))
            case let .real(number): sqlite3_bind_double(statement, position, number)
            case let .text(text): sqlite3_bind_text(statement, position, text, -1, transient)
            case let .blob(data): _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, position, $0.baseAddress, Int32($0.count), transient) }
            case .null: sqlite3_bind_null(statement, position)
            }
        }
        sqlite3_step(statement)
    }

    // The model is built in code rather than from an .xcdatamodeld, which the example's Bazel
    // build doesn't compile; the store on disk is the same either way.
    private static func seedPets(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path(percentEncoded: false) + suffix)
        }
        let model = petsModel()
        let container = NSPersistentContainer(name: "Pets", managedObjectModel: model)
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        container.persistentStoreDescriptions[0].shouldAddStoreAsynchronously = false
        container.loadPersistentStores { _, _ in }
        let context = container.viewContext
        let owners = ["Ana", "Bo", "Chen"].map { name in
            let owner = NSManagedObject(entity: model.entitiesByName["Owner"]!, insertInto: context) // Built just above.
            owner.setValue(name, forKey: "name")
            return owner
        }
        for (index, name) in ["Miso", "Rex", "Tofu", "Biscuit", "Luna", "Pepper", "Ziggy"].enumerated() {
            let entity = model.entitiesByName[index % 2 == 0 ? "Cat" : "Dog"]! // Built just above.
            let animal = NSManagedObject(entity: entity, insertInto: context)
            animal.setValue(name, forKey: "name")
            animal.setValue(Int16(index + 1), forKey: "age")
            animal.setValue(owners[index % owners.count], forKey: "owner")
            animal.setValue(index % 2 == 0, forKey: index % 2 == 0 ? "isIndoor" : "isGoodBoy")
        }
        try? context.save()
        pets = container
    }

    private static func petsModel() -> NSManagedObjectModel {
        func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = true
            return attribute
        }
        let owner = NSEntityDescription()
        owner.name = "Owner"
        let animal = NSEntityDescription()
        animal.name = "Animal"
        animal.isAbstract = true
        let cat = NSEntityDescription()
        cat.name = "Cat"
        let dog = NSEntityDescription()
        dog.name = "Dog"
        let pets = NSRelationshipDescription()
        let animalOwner = NSRelationshipDescription()
        pets.name = "pets"
        pets.destinationEntity = animal
        pets.maxCount = 0
        pets.deleteRule = .nullifyDeleteRule
        pets.inverseRelationship = animalOwner
        animalOwner.name = "owner"
        animalOwner.destinationEntity = owner
        animalOwner.maxCount = 1
        animalOwner.deleteRule = .nullifyDeleteRule
        animalOwner.inverseRelationship = pets
        owner.properties = [attribute("name", .stringAttributeType), pets]
        animal.properties = [attribute("name", .stringAttributeType), attribute("age", .integer16AttributeType), animalOwner]
        cat.properties = [attribute("isIndoor", .booleanAttributeType)]
        dog.properties = [attribute("isGoodBoy", .booleanAttributeType)]
        animal.subentities = [cat, dog]
        let model = NSManagedObjectModel()
        model.entities = [owner, animal, cat, dog]
        model.versionIdentifiers = ["Pets 1"]
        return model
    }
}
