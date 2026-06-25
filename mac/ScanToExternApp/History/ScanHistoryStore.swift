import Foundation
import GRDB

/// GRDB wrapper for scan history. Same schema as shared/scan-record-schema.sql
final class ScanHistoryStore {
    static let shared = ScanHistoryStore()

    private let dbQueue: DatabaseQueue

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("ScanToExternApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

        let dbPath = dbDir.appendingPathComponent("history.sqlite").path
        dbQueue = try! DatabaseQueue(path: dbPath)

        try! migrateIfNeeded()
    }

    private func migrateIfNeeded() throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS scan_records (
                    id TEXT PRIMARY KEY,
                    text TEXT NOT NULL,
                    processed_text TEXT,
                    timestamp DATETIME NOT NULL,
                    source TEXT NOT NULL,
                    injected_to TEXT,
                    ai_mode TEXT
                );
                CREATE INDEX IF NOT EXISTS idx_timestamp ON scan_records(timestamp DESC);
            """)
        }
    }

    func save(_ record: ScanRecord) throws {
        try dbQueue.write { db in
            try record.save(db)
        }
    }

    func recent(limit: Int = 100) throws -> [ScanRecord] {
        try dbQueue.read { db in
            try ScanRecord
                .order(ScanRecord.Columns.timestamp.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func search(_ query: String) throws -> [ScanRecord] {
        try dbQueue.read { db in
            try ScanRecord
                .filter(ScanRecord.Columns.text.like("%\(query)%"))
                .order(ScanRecord.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }

    func deleteAll() throws {
        try dbQueue.write { db in
            try ScanRecord.deleteAll(db)
        }
    }
}
