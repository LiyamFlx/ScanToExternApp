/// SQLite scan history store — identical schema to Mac's ScanHistoryStore (GRDB).
/// Uses rusqlite with bundled SQLite so there's no external dependency.
use rusqlite::{params, Connection, Result};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, Default)]
pub struct ScanRecord {
    pub id: String,
    pub text: String,
    pub processed_text: Option<String>,
    pub timestamp: String, // ISO 8601 / RFC 3339
    pub source: String,    // "bluetooth" | "usb" | "debug" | "history"
    pub injected_to: Option<String>,
    pub ai_mode: Option<String>,
}

pub struct ScanHistoryStore {
    conn: Connection,
}

impl ScanHistoryStore {
    pub fn new() -> Self {
        let path = dirs::data_local_dir()
            .unwrap_or_else(|| std::path::PathBuf::from("."))
            .join("ScanToExternApp")
            .join("history.sqlite");

        std::fs::create_dir_all(path.parent().unwrap()).ok();
        let conn = Connection::open(&path).expect("Failed to open SQLite DB");

        conn.execute_batch(
            "
            CREATE TABLE IF NOT EXISTS scan_records (
                id            TEXT PRIMARY KEY,
                text          TEXT NOT NULL,
                processed_text TEXT,
                timestamp     TEXT NOT NULL,
                source        TEXT NOT NULL,
                injected_to   TEXT,
                ai_mode       TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_ts ON scan_records(timestamp DESC);
            ",
        )
        .expect("Failed to migrate DB");

        log::info!("[History] SQLite store at {}", path.display());
        Self { conn }
    }

    pub fn save(&mut self, record: &ScanRecord) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO scan_records
             (id, text, processed_text, timestamp, source, injected_to, ai_mode)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                record.id,
                record.text,
                record.processed_text,
                record.timestamp,
                record.source,
                record.injected_to,
                record.ai_mode,
            ],
        )?;
        Ok(())
    }

    pub fn recent(&self, limit: usize) -> Result<Vec<ScanRecord>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, text, processed_text, timestamp, source, injected_to, ai_mode
             FROM scan_records ORDER BY timestamp DESC LIMIT ?1",
        )?;

        let rows = stmt.query_map([limit], |row| {
            Ok(ScanRecord {
                id: row.get(0)?,
                text: row.get(1)?,
                processed_text: row.get(2)?,
                timestamp: row.get(3)?,
                source: row.get(4)?,
                injected_to: row.get(5)?,
                ai_mode: row.get(6)?,
            })
        })?;

        Ok(rows.filter_map(|r| r.ok()).collect())
    }

    pub fn search(&self, query: &str) -> Result<Vec<ScanRecord>> {
        let pattern = format!("%{}%", query);
        let mut stmt = self.conn.prepare(
            "SELECT id, text, processed_text, timestamp, source, injected_to, ai_mode
             FROM scan_records WHERE text LIKE ?1 OR processed_text LIKE ?1
             ORDER BY timestamp DESC LIMIT 200",
        )?;

        let rows = stmt.query_map([&pattern], |row| {
            Ok(ScanRecord {
                id: row.get(0)?,
                text: row.get(1)?,
                processed_text: row.get(2)?,
                timestamp: row.get(3)?,
                source: row.get(4)?,
                injected_to: row.get(5)?,
                ai_mode: row.get(6)?,
            })
        })?;

        Ok(rows.filter_map(|r| r.ok()).collect())
    }

    pub fn get_by_id(&self, id: &str) -> Result<Option<ScanRecord>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, text, processed_text, timestamp, source, injected_to, ai_mode
             FROM scan_records WHERE id = ?1",
        )?;

        let mut rows = stmt.query_map([id], |row| {
            Ok(ScanRecord {
                id: row.get(0)?,
                text: row.get(1)?,
                processed_text: row.get(2)?,
                timestamp: row.get(3)?,
                source: row.get(4)?,
                injected_to: row.get(5)?,
                ai_mode: row.get(6)?,
            })
        })?;

        Ok(rows.next().and_then(|r| r.ok()))
    }

    pub fn delete_all(&mut self) -> Result<()> {
        self.conn.execute("DELETE FROM scan_records", [])?;
        Ok(())
    }
}
