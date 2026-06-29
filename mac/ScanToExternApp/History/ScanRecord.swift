import Foundation
import GRDB

struct ScanRecord: Codable, FetchableRecord, PersistableRecord {
    var id: String = UUID().uuidString
    var text: String
    var processedText: String?
    var timestamp: Date
    var source: String
    var injectedTo: String?
    var aiMode: String?

    static let databaseTableName = "scan_records"

    // For GRDB
    enum Columns {
        static let id = Column("id")
        static let text = Column("text")
        static let processedText = Column("processed_text")
        static let timestamp = Column("timestamp")
        static let source = Column("source")
        static let injectedTo = Column("injected_to")
        static let aiMode = Column("ai_mode")
    }
}
