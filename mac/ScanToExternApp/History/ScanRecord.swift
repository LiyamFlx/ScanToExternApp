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

    /// GRDB drives column names from the Codable representation. Without this mapping the
    /// framework would try to INSERT into columns "processedText", "injectedTo", "aiMode" —
    /// which don't exist — so every save silently threw and `try?` swallowed the error.
    enum CodingKeys: String, CodingKey {
        case id
        case text
        case processedText = "processed_text"
        case timestamp
        case source
        case injectedTo    = "injected_to"
        case aiMode        = "ai_mode"
    }

    // For GRDB query building
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let text = Column(CodingKeys.text)
        static let processedText = Column(CodingKeys.processedText)
        static let timestamp = Column(CodingKeys.timestamp)
        static let source = Column(CodingKeys.source)
        static let injectedTo = Column(CodingKeys.injectedTo)
        static let aiMode = Column(CodingKeys.aiMode)
    }
}
