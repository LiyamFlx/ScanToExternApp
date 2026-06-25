/// Bluetooth LE manager — Nordic UART Service (NUS) protocol
/// Same UUIDs as Mac CoreBluetooth implementation.
///
/// Flow: scan for peripherals → connect → subscribe to TX characteristic →
/// buffer incoming 20-byte BLE chunks → emit complete string after 300ms silence.
use std::sync::{Arc, RwLock};
use std::time::Duration;

use btleplug::api::{
    Central, Manager as _, Peripheral as _, ScanFilter, WriteType,
};
use btleplug::platform::{Manager, Peripheral};
use futures_util::StreamExt;
use tokio::sync::broadcast;
use uuid::Uuid;

use crate::ConnectionStatus;

// Nordic UART Service UUIDs (same as Mac BluetoothManager.swift)
const NUS_SERVICE: Uuid = uuid::uuid!("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
const NUS_TX_CHAR: Uuid = uuid::uuid!("6E400003-B5A3-F393-E0A9-E50E24DCCA9E"); // scanner → app

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

    // Find TX characteristic (scanner → app data)
    let chars = peripheral.characteristics();
    let tx_char = chars
        .iter()
        .find(|c| c.uuid == NUS_TX_CHAR)
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("NUS TX characteristic not found"))?;

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
    let mut last_received = std::time::Instant::now();

    let mut stream = peripheral.notifications().await?;

    while let Some(data) = stream.next().await {
        let chunk = String::from_utf8_lossy(&data.value).to_string();
        buffer.push_str(&chunk);
        last_received = std::time::Instant::now();

        // Debounce: emit complete scan after 300ms silence
        let scan_tx_clone = scan_tx.clone();
        let text_snapshot = buffer.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(300)).await;
            if last_received.elapsed() >= Duration::from_millis(280) {
                let trimmed = text_snapshot.trim().to_string();
                if !trimmed.is_empty() {
                    let _ = scan_tx_clone.send((trimmed, "bluetooth".to_string()));
                }
            }
        });

        // Clear buffer (the spawned task already captured the snapshot)
        if last_received.elapsed() >= Duration::from_millis(280) {
            buffer.clear();
        }
    }

    Ok(())
}
