/// Bluetooth LE manager — Nordic UART Service (NUS) protocol
/// Same UUIDs as Mac CoreBluetooth implementation.
///
/// Flow: scan for peripherals → connect → subscribe to TX characteristic →
/// buffer incoming 20-byte BLE chunks → emit complete string after 300ms silence.
use std::sync::{Arc, RwLock};
use std::time::Duration;
use tokio::time::Instant as TokioInstant;

use btleplug::api::{
    Central, CharPropFlags, Manager as _, Peripheral as _, ScanFilter,
};
use btleplug::platform::{Manager, Peripheral};
use futures_util::StreamExt;
use tokio::sync::broadcast;
use uuid::Uuid;

use crate::ConnectionStatus;

// Nordic UART Service UUIDs (Scanmarker Air)
const NUS_SERVICE: Uuid = uuid::uuid!("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
const NUS_TX_CHAR: Uuid = uuid::uuid!("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");

// PenScan / Scanmarker BLE5 UUIDs (discovered via characteristic sniff)
const PENSCAN_TX_CHAR: Uuid = uuid::uuid!("7c6b5200-a002-b001-c003-0709147c6b52"); // NOTIFY

pub async fn start(
    scan_tx: broadcast::Sender<(String, String)>,
    connection: Arc<RwLock<ConnectionStatus>>,
) {
    loop {
        match try_start(scan_tx.clone(), connection.clone()).await {
            Ok(_) => log::info!("[BT] Session ended, restarting in 5s"),
            Err(e) => log::warn!("[BT] Error: {} — restarting in 5s", e),
        }
        tokio::time::sleep(Duration::from_secs(5)).await;
    }
}

async fn try_start(
    scan_tx: broadcast::Sender<(String, String)>,
    connection: Arc<RwLock<ConnectionStatus>>,
) -> anyhow::Result<()> {
    let manager = Manager::new().await?;
    let adapters = manager.adapters().await?;
    let adapter = adapters.into_iter().next().ok_or_else(|| anyhow::anyhow!("No BT adapter"))?;

    log::info!("[BT] Starting scan for Scanmarker devices…");
    adapter.start_scan(ScanFilter::default()).await?;

    // Poll for Scanmarker device every 2 seconds
    loop {
        tokio::time::sleep(Duration::from_secs(2)).await;

        let peripherals = adapter.peripherals().await?;
        for p in peripherals {
            if let Ok(Some(props)) = p.properties().await {
                let name = props.local_name.as_deref().unwrap_or("");
                let is_scanmarker = name.to_lowercase().contains("scanmarker")
                    || name.to_lowercase().contains("scan")
                    || props.services.contains(&NUS_SERVICE);

                if is_scanmarker {
                    log::info!("[BT] Found device: {}", name);
                    adapter.stop_scan().await.ok();

                    if let Err(e) = connect_and_listen(
                        p,
                        scan_tx.clone(),
                        connection.clone(),
                        name.to_string(),
                    )
                    .await
                    {
                        log::warn!("[BT] Disconnected: {}", e);
                    }

                    // Mark disconnected
                    {
                        let mut conn = connection.write().unwrap();
                        conn.connected = false;
                        conn.device_name = String::new();
                        conn.source = String::new();
                    }

                    // Restart scan
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
    device_name: String,
) -> anyhow::Result<()> {
    peripheral.connect().await?;
    peripheral.discover_services().await?;

    // Log all discovered characteristics so we can identify unknown devices
    let chars = peripheral.characteristics();
    log::info!("[BT] {} characteristics on {}:", chars.len(), device_name);
    for c in &chars {
        log::info!("[BT]   UUID: {}  props: {:?}", c.uuid, c.properties);
    }

    // Priority: NUS TX → PenScan TX → any NOTIFY char
    let tx_char = chars.iter()
        .find(|c| c.uuid == NUS_TX_CHAR)
        .or_else(|| chars.iter().find(|c| c.uuid == PENSCAN_TX_CHAR))
        .or_else(|| chars.iter().find(|c| c.properties.contains(CharPropFlags::NOTIFY)))
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("No notifiable characteristic found"))?;

    log::info!("[BT] Using TX characteristic: {}", tx_char.uuid);

    peripheral.subscribe(&tx_char).await?;

    // Mark connected
    {
        let mut conn = connection.write().unwrap();
        conn.connected = true;
        conn.device_name = device_name.clone();
        conn.source = "bluetooth".to_string();
    }
    log::info!("[BT] Connected to {}, listening for scans…", device_name);

    let mut buffer = String::new();
    let mut stream = peripheral.notifications().await?;

    // Proper debounce via tokio::select!
    // Timer resets on every incoming packet; fires 300ms after the LAST packet.
    let silence = Duration::from_millis(300);
    let far_future = Duration::from_secs(86400);
    let mut deadline = TokioInstant::now() + far_future;

    loop {
        tokio::select! {
            msg = stream.next() => {
                match msg {
                    Some(data) => {
                        buffer.push_str(&String::from_utf8_lossy(&data.value));
                        // Reset the silence timer on every new chunk
                        deadline = TokioInstant::now() + silence;
                    }
                    None => break, // peripheral disconnected
                }
            }
            _ = tokio::time::sleep_until(deadline) => {
                // 300ms of silence — emit the complete buffered scan
                if !buffer.is_empty() {
                    let trimmed = buffer.trim().to_string();
                    log::info!("[BT] Emitting scan ({} chars)", trimmed.len());
                    let _ = scan_tx.send((trimmed, "bluetooth".to_string()));
                    buffer.clear();
                }
                // Push deadline far out until the next packet arrives
                deadline = TokioInstant::now() + far_future;
            }
        }
    }

    Ok(())
}
