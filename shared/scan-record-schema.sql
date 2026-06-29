-- ScanToExternApp SQLite schema (identical for macOS GRDB + Windows rusqlite)
-- Used by ScanHistoryStore on both platforms

CREATE TABLE IF NOT EXISTS scan_records (
    id TEXT PRIMARY KEY,
    text TEXT NOT NULL,
    processed_text TEXT,
    timestamp DATETIME NOT NULL,
    source TEXT NOT NULL,           -- "bluetooth" | "usb"
    injected_to TEXT,               -- bundle ID or "browser" or "unknown"
    ai_mode TEXT                    -- "off" | "correct" | "translate" | "summarize" | "custom"
);

CREATE INDEX IF NOT EXISTS idx_timestamp ON scan_records(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_source ON scan_records(source);
