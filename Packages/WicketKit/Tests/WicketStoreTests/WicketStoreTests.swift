import Foundation
import GRDB
import Testing
import WicketKit
@testable import WicketStore

@Suite("WicketStore skeleton migration")
struct WicketStoreTests {
    @Test("in-memory store opens and migrates cleanly")
    func inMemoryStoreOpens() throws {
        let store = try WicketStore.inMemory()
        let count = try store.db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM schema_meta") ?? -1
        }
        #expect(count == 0)
    }

    @Test("migrator registers the v1-scaffold migration exactly once")
    func migratorRegistersScaffold() throws {
        let store = try WicketStore.inMemory()
        let applied = try store.db.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
        }
        #expect(applied == ["v1-scaffold"])
    }
}
