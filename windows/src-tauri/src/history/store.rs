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
        Self::init_schema(&conn).expect("Failed to migrate DB");
        log::info!("[History] SQLite store at {}", path.display());
        Self { conn }
    }

    /// Build a store from an already-open connection (used by tests with an
    /// in-memory database).
    #[cfg(test)]
    pub fn from_connection(conn: Connection) -> Self {
        Self::init_schema(&conn).expect("Failed to migrate DB");
        Self { conn }
    }

    fn init_schema(conn: &Connection) -> Result<()> {
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
        )?;
        Ok(())
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

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    fn rec(id: &str, text: &str, ts: &str, source: &str) -> ScanRecord {
        ScanRecord {
            id: id.into(),
            text: text.into(),
            processed_text: None,
            timestamp: ts.into(),
            source: source.into(),
            injected_to: None,
            ai_mode: None,
        }
    }

    fn store() -> ScanHistoryStore {
        ScanHistoryStore::from_connection(Connection::open_in_memory().unwrap())
    }

    #[test]
    fn save_and_recent_orders_by_timestamp_desc() {
        let mut s = store();
        s.save(&rec("1", "first", "2026-01-01T00:00:00Z", "usb")).unwrap();
        s.save(&rec("2", "second", "2026-02-01T00:00:00Z", "bluetooth")).unwrap();
        let recent = s.recent(10).unwrap();
        assert_eq!(recent.len(), 2);
        assert_eq!(recent[0].id, "2"); // newest first
        assert_eq!(recent[1].id, "1");
    }

    #[test]
    fn recent_respects_limit() {
        let mut s = store();
        for i in 0..5 {
            s.save(&rec(&i.to_string(), "t", &format!("2026-01-0{}T00:00:00Z", i + 1), "usb"))
                .unwrap();
        }
        assert_eq!(s.recent(3).unwrap().len(), 3);
    }

    #[test]
    fn search_matches_text_and_processed_text() {
        let mut s = store();
        s.save(&rec("1", "hello world", "2026-01-01T00:00:00Z", "usb")).unwrap();
        let mut r2 = rec("2", "raw scan", "2026-01-02T00:00:00Z", "usb");
        r2.processed_text = Some("corrected hello".into());
        s.save(&r2).unwrap();
        let hits = s.search("hello").unwrap();
        assert_eq!(hits.len(), 2); // matched in text and in processed_text
        assert!(s.search("nonexistent").unwrap().is_empty());
    }

    #[test]
    fn get_by_id_and_save_replaces() {
        let mut s = store();
        s.save(&rec("abc", "v1", "2026-01-01T00:00:00Z", "usb")).unwrap();
        s.save(&rec("abc", "v2", "2026-01-01T00:00:00Z", "usb")).unwrap(); // same id replaces
        let got = s.get_by_id("abc").unwrap().unwrap();
        assert_eq!(got.text, "v2");
        assert_eq!(s.recent(10).unwrap().len(), 1);
        assert!(s.get_by_id("missing").unwrap().is_none());
    }

    #[test]
    fn delete_all_clears() {
        let mut s = store();
        s.save(&rec("1", "x", "2026-01-01T00:00:00Z", "usb")).unwrap();
        s.delete_all().unwrap();
        assert!(s.recent(10).unwrap().is_empty());
    }
}
