/// Bluetooth LE manager — Scanmarker/PenScanBLE proprietary GATT profile.
///
/// This is the Windows port of Mac's BluetoothManager.swift. It previously assumed the
/// Nordic UART Service (NUS) and decoded every notify payload as UTF-8 text — that was
/// wrong. The real Scanmarker Air pen uses a proprietary vendor GATT and sends compressed
/// RLE image bytes, not text, framed with DATA_START/DATA_END byte markers. Turning those
/// bytes into text requires uploading the stroke to Scanmarker's cloud OCR service
/// (RunOCR_V7) — see ai::run_ocr_client. Protocol confirmed against both Mac's
/// BluetoothManager.swift (ported from the vendor's own JS) and an independent working
/// TypeScript/Web Bluetooth implementation of the same pen — both agree byte-for-byte.
///
/// Flow: scan for peripherals → connect → discover ALL services/characteristics (many
/// Scanmarker firmwares don't use a fixed service, so we log everything and match by
/// characteristic UUID) → subscribe to the notify (TX) characteristic → send the vendor
/// activation command → accumulate raw stroke bytes until DATA_START+DATA_END are both
/// seen (or an idle timeout fires) → POST the extracted payload to RunOCR_V7 → emit the
/// recognized text on scan_tx.
use std::sync::Arc;
use std::time::Duration;

use btleplug::api::{
    Central, CharPropFlags, Characteristic, Manager as _, Peripheral as _, ScanFilter, WriteType,
};
use btleplug::platform::{Manager, Peripheral};
use futures_util::StreamExt;
use parking_lot::RwLock;
use tokio::sync::broadcast;
use tokio::time::Instant as TokioInstant;
use uuid::Uuid;

use crate::{AppSettings, ConnectionStatus};

// ── Scanmarker / PenScanBLE proprietary GATT profile ──────────────────────────────────
// Extracted from the vendor's own JavaScript BLE code (webapp.scanmarker chunk-ZZUARTOR.js)
// and cross-verified against Mac's BluetoothManager.swift and a working TS/Web Bluetooth
// implementation of the same pen. The pen does NOT use the Nordic UART Service — those
// UUIDs never matched real hardware.
const SCAN_SERVICE: Uuid = uuid::uuid!("7c6b5200-a002-b001-c001-0709147c6b52");
const SCAN_WRITE_CHAR: Uuid = uuid::uuid!("7c6b5200-a002-b001-c002-0709147c6b52"); // app  → pen (commands)
const SCAN_NOTIFY_CHAR: Uuid = uuid::uuid!("7c6b5200-a002-b001-c003-0709147c6b52"); // pen  → app (scan data)
#[allow(dead_code)]
const SCAN_READ_CHAR: Uuid = uuid::uuid!("7c6b5200-a002-b001-c004-0709147c6b52"); // read-only info

// Vendor activation commands, byte values from the JS chunk:
//   0x0A → activate scanner (must be sent after connect or the pen sits idle)
//   0x22 → request serial number
const CMD_ACTIVATE: u8 = 0x0A;
const CMD_REQUEST_SERIAL: u8 = 0x22;

// Standard BLE Battery Service (0x180F / 0x2A19) — read + notify for battery %.
const BATTERY_LEVEL_CHAR: Uuid = uuid::uuid!("00002a19-0000-1000-8000-00805f9b34fb");
// Standard BLE Device Information Service — Serial Number String (0x2A25). The cloud OCR
// service gates real recognition on this; an anonymous/missing serial returns empty text.
const SERIAL_NUMBER_CHAR: Uuid = uuid::uuid!("00002a25-0000-1000-8000-00805f9b34fb");

/// Frame markers used by the ScanMarker Air's BLE protocol. Each scan stroke is delimited
/// on the notify stream by: DATA_START + 4-byte transport sub-header + image bytes + DATA_END.
/// The image bytes are a header (dimensions) followed by an RLE-compressed bitmap.
const DATA_START: [u8; 5] = [0xff, 0xff, 0xff, 0x04, 0x00];
const DATA_END: [u8; 5] = [0xff, 0xff, 0xff, 0x04, 0x07];
const DATA_SUBHEADER: usize = 4; // bytes after DATA_START before the image payload begins

// Hard ceiling: a malformed/never-terminated stream would otherwise grow the buffer for the
// whole session. 4MB is far larger than any real stroke.
const MAX_BYTE_BUFFER: usize = 4_000_000;
// Idle fallback: if bytes stop arriving mid-stroke and no DATA_END is seen, flush anyway.
const FRAME_IDLE_MS: u64 = 1200;

pub async fn start(
    scan_tx: broadcast::Sender<(String, String)>,
    connection: Arc<RwLock<ConnectionStatus>>,
    settings: Arc<RwLock<AppSettings>>,
) {
    loop {
        match try_start(scan_tx.clone(), connection.clone(), settings.clone()).await {
            Ok(_) => log::info!("[BT] Session ended, restarting in 5s"),
            Err(e) => log::warn!("[BT] Error: {} — restarting in 5s", e),
        }
        tokio::time::sleep(Duration::from_secs(5)).await;
    }
}

async fn try_start(
    scan_tx: broadcast::Sender<(String, String)>,
    connection: Arc<RwLock<ConnectionStatus>>,
    settings: Arc<RwLock<AppSettings>>,
) -> anyhow::Result<()> {
    let manager = Manager::new().await?;
    let adapters = manager.adapters().await?;
    let adapter = adapters
        .into_iter()
        .next()
        .ok_or_else(|| anyhow::anyhow!("No BT adapter"))?;

    log::info!("[BT] Starting scan for Scanmarker devices…");
    adapter.start_scan(ScanFilter::default()).await?;

    // Poll for a Scanmarker device every 2 seconds. Unfiltered — BLE advertisements are
    // only 31 bytes and many Scanmarker firmwares don't include the service UUID in the
    // ad, only after connect. Matching by name is the reliable signal at scan time.
    loop {
        tokio::time::sleep(Duration::from_secs(2)).await;

        let peripherals = adapter.peripherals().await?;
        for p in peripherals {
            if let Ok(Some(props)) = p.properties().await {
                let name = props.local_name.as_deref().unwrap_or("");
                let lower = name.to_lowercase();
                let is_scanmarker = lower.contains("scanmarker")
                    || lower.contains("scan")
                    || lower.contains("penscan")
                    || props.services.contains(&SCAN_SERVICE);

                if is_scanmarker {
                    log::info!("[BT] Found device: {}", name);
                    adapter.stop_scan().await.ok();

                    if let Err(e) = connect_and_listen(
                        p,
                        scan_tx.clone(),
                        connection.clone(),
                        settings.clone(),
                        name.to_string(),
                    )
                    .await
                    {
                        log::warn!("[BT] Disconnected: {}", e);
                    }

                    {
                        let mut conn = connection.write();
                        conn.connected = false;
                        conn.device_name = String::new();
                        conn.source = String::new();
                    }

                    adapter.start_scan(ScanFilter::default()).await.ok();
                    break;
                }
            }
        }
    }
}

async fn connect_and_listen(
    peripheral: Peripheral,
    scan_tx: broadcast::Sender<(String, String)>,
    connection: Arc<RwLock<ConnectionStatus>>,
    settings: Arc<RwLock<AppSettings>>,
    device_name: String,
) -> anyhow::Result<()> {
    peripheral.connect().await?;
    peripheral.discover_services().await?;

    let chars = peripheral.characteristics();
    log::info!("[BT] {} characteristics on {}:", chars.len(), device_name);
    for c in &chars {
        log::info!("[BT]   UUID: {}  props: {:?}", c.uuid, c.properties);
    }

    // The scan-data notify characteristic (c003) is the actual proof this is a Scanmarker —
    // fall back to "any notifiable characteristic" only if the exact UUID isn't present, so
    // firmware variants still connect, but log loudly since the framing assumptions below
    // (DATA_START/END, RunOCR_V7) are specific to the Scanmarker Air protocol.
    let tx_char = chars
        .iter()
        .find(|c| c.uuid == SCAN_NOTIFY_CHAR)
        .or_else(|| {
            chars
                .iter()
                .find(|c| c.properties.contains(CharPropFlags::NOTIFY) && c.uuid != BATTERY_LEVEL_CHAR)
        })
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("No notifiable characteristic found"))?;

    if tx_char.uuid != SCAN_NOTIFY_CHAR {
        log::warn!(
            "[BT] Using fallback notify characteristic {} — not the expected Scanmarker UUID ({}). \
             Stroke framing/OCR below assumes the Scanmarker Air protocol and may not decode this device.",
            tx_char.uuid, SCAN_NOTIFY_CHAR
        );
    }

    log::info!("[BT] Using TX characteristic: {}", tx_char.uuid);
    peripheral.subscribe(&tx_char).await?;

    // Read the pen's serial (Device Info 0x2A25) — RunOCR_V7 gates real OCR on it.
    let mut serial_number: Option<String> = None;
    if let Some(serial_char) = chars.iter().find(|c| c.uuid == SERIAL_NUMBER_CHAR) {
        match peripheral.read(serial_char).await {
            Ok(bytes) => {
                let raw = String::from_utf8_lossy(&bytes);
                let cleaned = raw.trim().trim_end_matches('\0').to_string();
                if !cleaned.is_empty() {
                    log::info!("[BT] Read pen serial number: {}", cleaned);
                    serial_number = Some(cleaned);
                }
            }
            Err(e) => log::debug!("[BT] Serial read failed: {}", e),
        }
    }

    // Send the vendor activation sequence (0x0A activate, 0x22 request-serial) once we have
    // both the write and notify characteristics — without 0x0A the pen sits idle.
    if let Some(write_char) = chars.iter().find(|c| c.uuid == SCAN_WRITE_CHAR) {
        send_activation(&peripheral, write_char).await;
    }

    // Mark connected
    {
        let mut conn = connection.write();
        conn.connected = true;
        conn.device_name = device_name.clone();
        conn.source = "bluetooth".to_string();
    }
    log::info!("[BT] Connected to {}, listening for scans…", device_name);

    let mut byte_buffer: Vec<u8> = Vec::new();
    let mut stream = peripheral.notifications().await?;

    let idle = Duration::from_millis(FRAME_IDLE_MS);
    let far_future = Duration::from_secs(86400);
    let mut deadline = TokioInstant::now() + far_future;

    loop {
        tokio::select! {
            msg = stream.next() => {
                match msg {
                    Some(data) => {
                        if data.uuid == BATTERY_LEVEL_CHAR {
                            if let Some(&pct) = data.value.first() {
                                log::info!("[BT] Battery: {}%", pct);
                            }
                            continue;
                        }

                        byte_buffer.extend_from_slice(&data.value);

                        if byte_buffer.len() > MAX_BYTE_BUFFER {
                            log::warn!(
                                "[BT] byte buffer exceeded {}B without a stroke marker — dropping",
                                MAX_BYTE_BUFFER
                            );
                            byte_buffer.clear();
                            deadline = TokioInstant::now() + far_future;
                            continue;
                        }

                        // Flush as soon as a full stroke (DATA_START..DATA_END) is buffered,
                        // rather than waiting for the idle timer — strokes fragment across many
                        // small notifies over several seconds, and the markers themselves often
                        // land in their own tiny packets.
                        if let Some((start, end)) = find_stroke(&byte_buffer) {
                            let stroke_end = end + DATA_END.len();
                            let stroke: Vec<u8> = byte_buffer[start..stroke_end].to_vec();
                            byte_buffer = byte_buffer[stroke_end..].to_vec();
                            deadline = TokioInstant::now() + far_future;
                            log::info!("[BT] stroke complete ({}B) — sending to OCR", stroke.len());
                            recognize_stroke(stroke, &scan_tx, &settings, &device_name, serial_number.clone());
                            continue;
                        }

                        // No complete stroke yet — (re)arm the idle fallback.
                        deadline = TokioInstant::now() + idle;
                    }
                    None => break, // peripheral disconnected
                }
            }
            _ = tokio::time::sleep_until(deadline) => {
                if !byte_buffer.is_empty() {
                    let stroke = std::mem::take(&mut byte_buffer);
                    // A tail with no DATA_START is an inter-stroke control/status frame —
                    // discard silently rather than reporting a failed scan.
                    if find_seq(&stroke, &DATA_START, 0).is_some() {
                        log::info!("[BT] idle-flushed {}B partial stroke (no DATA_END seen)", stroke.len());
                        recognize_stroke(stroke, &scan_tx, &settings, &device_name, serial_number.clone());
                    }
                }
                deadline = TokioInstant::now() + far_future;
            }
        }
    }

    Ok(())
}

async fn send_activation(peripheral: &Peripheral, write_char: &Characteristic) {
    let write_type = if write_char.properties.contains(CharPropFlags::WRITE) {
        WriteType::WithResponse
    } else {
        WriteType::WithoutResponse
    };

    if let Err(e) = peripheral.write(write_char, &[CMD_ACTIVATE], write_type).await {
        log::warn!("[BT] activation write failed: {}", e);
        return;
    }
    log::info!("[BT] sent activation command 0x{:02x}", CMD_ACTIVATE);

    if let Err(e) = peripheral
        .write(write_char, &[CMD_REQUEST_SERIAL], write_type)
        .await
    {
        log::debug!("[BT] request-serial write failed: {}", e);
    }
}

/// Find a complete DATA_START..DATA_END stroke in the buffer. Returns (start, end) indices
/// where `end` is the index of the first byte of DATA_END (not past it).
fn find_stroke(buf: &[u8]) -> Option<(usize, usize)> {
    let start = find_seq(buf, &DATA_START, 0)?;
    let end = find_seq(buf, &DATA_END, start + DATA_START.len())?;
    Some((start, end))
}

/// Byte-accurate needle search — equivalent to Mac's `indexOf(sequence:in:from:)`.
fn find_seq(haystack: &[u8], needle: &[u8], from: usize) -> Option<usize> {
    if needle.is_empty() || haystack.len() < needle.len() + from {
        return None;
    }
    (from..=haystack.len() - needle.len()).find(|&i| &haystack[i..i + needle.len()] == needle)
}

/// Extract the image payload from a full stroke: DATA_START (5B) + 4B sub-header … DATA_END
/// (exclusive). Matches Mac's `recognizeStroke`/the vendor JS `extractAirPayload`.
fn extract_air_payload(stroke: &[u8]) -> Option<&[u8]> {
    let start = find_seq(stroke, &DATA_START, 0)?;
    let end = find_seq(stroke, &DATA_END, start + DATA_START.len())?;
    let payload_start = start + DATA_START.len() + DATA_SUBHEADER;
    if payload_start >= end {
        return None;
    }
    Some(&stroke[payload_start..end])
}

/// POST the extracted stroke payload to Scanmarker's cloud OCR and emit the recognized text
/// on scan_tx. Fire-and-forget background task — mirrors Mac's `Task { … }` in recognizeStroke.
fn recognize_stroke(
    stroke: Vec<u8>,
    scan_tx: &broadcast::Sender<(String, String)>,
    settings: &Arc<RwLock<AppSettings>>,
    device_name: &str,
    serial_number: Option<String>,
) {
    let Some(payload) = extract_air_payload(&stroke) else {
        log::warn!("[BT] recognize_stroke: no full DATA_START/DATA_END pair — skipping");
        return;
    };
    let bytes_base64 = base64_encode(payload);

    let (email, language_id) = {
        let s = settings.read();
        (s.scanmarker_email.trim().to_string(), s.scanmarker_language_id)
    };
    let serial = serial_number.unwrap_or_default();
    let scanner_name = if device_name.is_empty() { "ScanMarker".to_string() } else { device_name.to_string() };

    if email.is_empty() || serial.is_empty() {
        log::warn!(
            "[BT] OCR request MISSING identity — email={} serial={}. Service will return empty text. \
             Set Settings → AI → Scanmarker email.",
            if email.is_empty() { "EMPTY" } else { "set" },
            if serial.is_empty() { "EMPTY" } else { "set" }
        );
    }

    let scan_tx = scan_tx.clone();
    tauri::async_runtime::spawn(async move {
        match crate::ai::run_ocr_client::recognize(
            &bytes_base64,
            &email,
            &serial,
            &scanner_name,
            language_id,
            false,
        )
        .await
        {
            Ok(result) => {
                log::info!(
                    "[BT] OCR result status={} chars={}",
                    result.status,
                    result.text.len()
                );
                if !result.text.is_empty() {
                    let _ = scan_tx.send((result.text, "bluetooth".to_string()));
                }
            }
            Err(e) => log::warn!("[BT] OCR request failed: {}", e),
        }
    });
}

/// Minimal base64 encoder (standard alphabet, with padding) — avoids pulling in the `base64`
/// crate for a single call site. Matches the output of Swift's `Data.base64EncodedString()`
/// and JS's `btoa` for the same bytes.
fn base64_encode(data: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity((data.len() + 2) / 3 * 4);
    for chunk in data.chunks(3) {
        let b0 = chunk[0];
        let b1 = *chunk.get(1).unwrap_or(&0);
        let b2 = *chunk.get(2).unwrap_or(&0);
        let n = ((b0 as u32) << 16) | ((b1 as u32) << 8) | (b2 as u32);
        out.push(ALPHABET[((n >> 18) & 0x3f) as usize] as char);
        out.push(ALPHABET[((n >> 12) & 0x3f) as usize] as char);
        out.push(if chunk.len() > 1 { ALPHABET[((n >> 6) & 0x3f) as usize] as char } else { '=' });
        out.push(if chunk.len() > 2 { ALPHABET[(n & 0x3f) as usize] as char } else { '=' });
    }
    out
}
