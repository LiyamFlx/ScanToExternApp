/// USB serial manager — Silicon Labs VCP (COM port)
/// Baud: 115200, 8N1. Same text protocol as Bluetooth.
/// Scans Windows COM ports for a Silicon Labs device (VID 0x10C4).
use std::io::Read;
use std::sync::Arc;
use parking_lot::RwLock;
use std::time::Duration;

use tokio::sync::broadcast;

use crate::ConnectionStatus;

// Silicon Labs USB-to-UART vendor ID
const SLAB_VID: u16 = 0x10C4;

pub async fn start(
    scan_tx: broadcast::Sender<(String, String)>,
    connection: Arc<RwLock<ConnectionStatus>>,
) {
    loop {
        if let Err(e) = try_start(scan_tx.clone(), connection.clone()).await {
            log::debug!("[USB] {e} — retrying in 5s");
        }
        tokio::time::sleep(Duration::from_secs(5)).await;
    }
}

async fn try_start(
    scan_tx: broadcast::Sender<(String, String)>,
    connection: Arc<RwLock<ConnectionStatus>>,
) -> anyhow::Result<()> {
    // Find Silicon Labs VCP port
    let ports = serialport::available_ports()?;
    let target = ports.into_iter().find(|p| {
        if let serialport::SerialPortType::UsbPort(info) = &p.port_type {
            info.vid == SLAB_VID
        } else {
            false
        }
    });

    let port_info = target.ok_or_else(|| anyhow::anyhow!("No Silicon Labs VCP found"))?;
    log::info!("[USB] Opening {}", port_info.port_name);

    // Open port (sync; run in blocking thread to avoid blocking async executor)
    let port_name = port_info.port_name.clone();
    let scan_tx_clone = scan_tx.clone();
    let connection_clone = connection.clone();

    tokio::task::spawn_blocking(move || {
        let mut port = serialport::new(&port_name, 115_200)
            .data_bits(serialport::DataBits::Eight)
            .parity(serialport::Parity::None)
            .stop_bits(serialport::StopBits::One)
            .timeout(Duration::from_millis(10))
            .open()?;

        // Mark connected
        {
            let mut conn = connection_clone.write();
            // Only mark USB connected if BT is not already connected
            if !conn.connected {
                conn.connected = true;
                conn.device_name = format!("Scanmarker USB ({})", port_name);
                conn.source = "usb".to_string();
            }
        }
        log::info!("[USB] Listening on {}", port_name);

        let mut buffer = String::new();
        let mut last_byte = std::time::Instant::now();
        let mut read_buf = [0u8; 64];

        loop {
            match port.read(&mut read_buf) {
                Ok(n) if n > 0 => {
                    let chunk = String::from_utf8_lossy(&read_buf[..n]).to_string();
                    buffer.push_str(&chunk);
                    last_byte = std::time::Instant::now();
                }
                Ok(_) => {}
                Err(ref e) if e.kind() == std::io::ErrorKind::TimedOut => {
                    // Emit after 300ms silence
                    if !buffer.is_empty() && last_byte.elapsed() >= Duration::from_millis(300) {
                        let text = buffer.trim().to_string();
                        if !text.is_empty() {
                            let _ = scan_tx_clone.send((text, "usb".to_string()));
                        }
                        buffer.clear();
                    }
                }
                Err(e) => {
                    log::warn!("[USB] Read error: {}", e);
                    // Mark disconnected
                    {
                        let mut conn = connection_clone.write();
                        if conn.source == "usb" {
                            conn.connected = false;
                            conn.device_name = String::new();
                            conn.source = String::new();
                        }
                    }
                    return Err(anyhow::anyhow!("Serial read error: {}", e));
                }
            }
        }
    })
    .await??;

    Ok(())
}
