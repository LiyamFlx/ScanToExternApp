import Foundation
import GRDB

/// GRDB wrapper for scan history. Same schema as shared/scan-record-schema.sql
final class ScanHistoryStore {
    static let shared = ScanHistoryStore()

    private let dbQueue: DatabaseQueue

    private init() {
        // Build the on-disk path defensively; fall back to a temp/in-memory DB rather than
        // crashing the whole app if Application Support is unavailable or unwritable.
        func openOnDisk() -> DatabaseQueue? {
            guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            let dbDir = appSupport.appendingPathComponent("ScanToExternApp", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
                let dbPath = dbDir.appendingPathComponent("history.sqlite").path
                return try DatabaseQueue(path: dbPath)
            } catch {
                print("[History] Failed to open on-disk DB: \(error) — falling back to in-memory")
                return nil
            }
        }

        if let disk = openOnDisk() {
            dbQueue = disk
        } else if let mem = try? DatabaseQueue() {
            // In-memory queue keeps the app functional for the session even if disk fails.
            dbQueue = mem
        } else {
            // Last resort: a uniquely-named temp file DB. DatabaseQueue() in-memory
            // essentially never fails, so reaching here is extraordinarily unlikely.
            let tmp = NSTemporaryDirectory() + "scanhistory-\(UUID().uuidString).sqlite"
            dbQueue = (try? DatabaseQueue(path: tmp)) ?? { fatalError("Cannot open any database") }()
        }

        do {
            try migrateIfNeeded()
        } catch {
            print("[History] Migration failed: \(error)")
        }
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
