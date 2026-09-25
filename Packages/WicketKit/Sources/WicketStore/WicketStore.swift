import Foundation
import GRDB
import WicketKit

/// WicketStore — GRDB/SQLite persistence module for Wicket Tally.
///
/// Issue #1 ships only migration scaffolding (a single marker table) so CI
/// has a real, testable GRDB target wired to the app. Issue #2's ledger
/// schema (leagues, teams, fixtures, MatchEvent rows) replaces this v1
/// migration; this scaffold version is never shipped to users, so there is
/// no frozen-fixture compatibility concern yet.
public struct WicketStore: Sendable {
    public let db: any DatabaseWriter

    public init(db: any DatabaseWriter) {
        self.db = db
    }

    /// Schema migrator. `v1-scaffold` is a placeholder marker table proving
    /// the migration pipeline works end-to-end; it is superseded (not
    /// frozen) by the real ledger schema in issue #2.
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-scaffold") { db in
            try db.create(table: "schema_meta") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("created_at", .datetime).notNull()
            }
        }
        return migrator
    }

    /// Opens (creating if needed) and migrates the on-disk store at `url`.
    public static func open(at url: URL) throws -> WicketStore {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let db = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(db)
        return WicketStore(db: db)
    }

    /// A migrated in-memory store (unit tests, previews).
    public static func inMemory() throws -> WicketStore {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let db = try DatabaseQueue(configuration: config)
        try migrator.migrate(db)
        return WicketStore(db: db)
    }
}
