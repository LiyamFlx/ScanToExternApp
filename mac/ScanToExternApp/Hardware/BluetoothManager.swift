import Foundation
import CoreBluetooth
import Combine

/// BluetoothManager handles CoreBluetooth connection to Scanmarker devices using
/// Nordic UART Service (NUS). Discovery is always-on when Bluetooth is up so the
/// user can see nearby scanners in the Devices panel and pick one. The manager
/// only auto-connects when the user has already paired a specific device.
///
/// Reference: Scanmarker BLE Protocol in CLAUDE.md
final class BluetoothManager: NSObject, ObservableObject {
    // Scanmarker / PenScanBLE proprietary GATT profile — extracted from the vendor's own
    // JavaScript BLE code (webapp.scanmarker chunk-ZZUARTOR.js). The pen does NOT use the
    // Nordic UART Service that CLAUDE.md said it did; those UUIDs never matched.
    private let scanServiceUUID       = CBUUID(string: "7C6B5200-A002-B001-C001-0709147C6B52")
    private let scanWriteCharUUID     = CBUUID(string: "7C6B5200-A002-B001-C002-0709147C6B52") // app  → pen (commands)
    private let scanNotifyCharUUID    = CBUUID(string: "7C6B5200-A002-B001-C003-0709147C6B52") // pen  → app (scan data)
    private let scanReadCharUUID      = CBUUID(string: "7C6B5200-A002-B001-C004-0709147C6B52") // read-only info

    // Vendor activation commands, byte values from the JS chunk:
    //   0x0A → activate scanner (must be sent after connect or the pen sits idle)
    //   0x22 → request serial number
    //   0x24 → request reader flag
    private static let cmdActivate: UInt8       = 0x0A
    private static let cmdRequestSerial: UInt8  = 0x22
    private static let cmdReaderFlag: UInt8     = 0x24

    // Standard BLE Battery Service — read + notify for battery %
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelCharUUID = CBUUID(string: "2A19")

    // Standard BLE Device Information Service — used to read the pen's serial number, which
    // Scanmarker's cloud OCR (RunOCR_V7) gates real recognition on (anonymous serial → empty text).
    private let deviceInfoServiceUUID = CBUUID(string: "180A")
    private let serialNumberCharUUID  = CBUUID(string: "2A25")

    /// Frame markers used by the ScanMarker Air's BLE protocol. Extracted from the vendor JS
    /// (chunk-ZZUARTOR.js DATA_START_CODE/DATA_END_CODE) and confirmed by the user's own
    /// scanmarker-app implementation. Each scan stroke is delimited on the notify stream by:
    ///   DATA_START (ff ff ff 04 00) + 4-byte transport sub-header + image bytes + DATA_END (ff ff ff 04 07)
    /// The image bytes contain a header (dimensions) followed by an RLE-compressed bitmap.
    private static let DATA_START: [UInt8] = [0xff, 0xff, 0xff, 0x04, 0x00]
    private static let DATA_END:   [UInt8] = [0xff, 0xff, 0xff, 0x04, 0x07]
    private static let DATA_SUBHEADER = 4  // bytes after DATA_START before image payload begins

    /// The write characteristic (c002) once discovered, so activation / follow-up commands
    /// can be issued after connect.
    private var writeCharacteristic: CBCharacteristic?

    /// Pen serial number, read from BLE Device Info (0x2A25) at connect time. Passed to the
    /// OCR service alongside the account email to unlock real recognition.
    private var scannerSerial: String?

    /// Raw byte accumulator for the current in-progress stroke. Replaces the old UTF-8 string
    /// buffer — the pen sends compressed image bytes, not text, so it MUST be byte-accurate.
    private var byteBuffer = Data()
    /// Hard ceiling: a malformed stream without DATA_END could grow the buffer for the whole
    /// session. 4MB is far larger than any real stroke; past it we drop and log.
    private static let MAX_BYTE_BUFFER = 4_000_000
    /// Fallback: if bytes stop arriving mid-stroke and no DATA_END is seen, flush anyway.
    private var frameIdleTimer: Timer?
    private static let FRAME_IDLE_MS: TimeInterval = 1.2

    private var centralManager: CBCentralManager!
    /// All peripherals we've seen this session, keyed by identifier.uuidString.
    /// Kept so we can call `connect` on the exact CBPeripheral instance later —
    /// CoreBluetooth requires the same object, you can't rehydrate from just a UUID.
    private var knownPeripherals: [String: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?

    private var scanBuffer = ""
    private var silenceTimer: Timer?
    private var pruneTimer: Timer?

    // Publishers used by HardwareManager
    let scanReceived = PassthroughSubject<String, Never>()
    let connectionState = PassthroughSubject<ConnectionState, Never>()
    let deviceInfo = PassthroughSubject<(name: String, battery: Int?), Never>()

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var currentDeviceName: String = ""

    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        // Age out advertisements the user hasn't seen re-broadcast recently.
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            DeviceRegistry.shared.pruneStale()
        }
    }

    // MARK: - Public API (called from HardwareManager)

    /// Start (or continue) scanning for BLE peripherals. Idempotent.
    ///
    /// We deliberately pass `withServices: nil` — a filtered scan only returns peripherals
    /// that advertise the exact service UUID in their AD packet. BLE advertisements are
    /// only 31 bytes, and many scanner firmwares (including at least some Scanmarker
    /// revisions) don't include the NUS UUID in the ad — they only expose it after connect.
    /// Filtering by UUID at scan time therefore hides the very device we're trying to find.
    /// We show ALL nearby BLE devices and let the user pick theirs from the Devices panel.
    /// Backgrounding a Mac app with `nil` service scan does not require special entitlements
    /// on macOS (only iOS restricts this).
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            BTLog.write("[BT] Central not powered on yet")
            return
        }
        if DeviceRegistry.shared.preferredDeviceID == nil {
            DeviceRegistry.shared.setStatus(.scanning)
        }
        centralManager.scanForPeripherals(withServices: nil,
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        BTLog.write("[BT] Scanning for ALL BLE peripherals (unfiltered)")
    }

    func stopScanning() {
        centralManager.stopScan()
    }

    /// Attempt to connect to a specific peripheral by its identifier UUID string.
    /// Called from the Devices view when the user taps Connect.
    func connect(to peripheralID: String) {
        guard let target = knownPeripherals[peripheralID] else {
            BTLog.write("[BT] connect(to:) — unknown peripheral \(peripheralID)")
            return
        }
        self.peripheral = target
        target.delegate = self
        centralManager.stopScan()
        DeviceRegistry.shared.setStatus(.connecting(target.name ?? "Scanmarker"))
        currentDeviceName = target.name ?? "Scanmarker"
        centralManager.connect(target, options: nil)
        // NOTE: we intentionally do NOT publish .connected here — that was the old
        // premature-connected bug. We wait for didConnect.
    }

    /// Disconnect from the current peripheral. Keeps the pairing preference so a
    /// later Connect (or app relaunch) reconnects to the same device.
    func disconnect() {
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        peripheral = nil
        txCharacteristic = nil
        isConnected = false
        connectionState.send(.disconnected)
        DeviceRegistry.shared.setStatus(centralManager.state == .poweredOn ? .idle : .bluetoothOff)
        DeviceRegistry.shared.setBattery(nil)
    }

    // MARK: - Incoming data

    /// Bytes arrive fragmented across many small BLE notifies — a full stroke can span dozens
    /// of packets over several seconds. Accumulate raw bytes and flush whenever DATA_START AND
    /// DATA_END are both present. Keep an idle-timer fallback for strokes that never complete.
    private func handleIncomingData(_ data: Data) {
        byteBuffer.append(data)

        // Hard ceiling — protect against a never-terminated stream.
        if byteBuffer.count > Self.MAX_BYTE_BUFFER {
            BTLog.write("[BT] byte buffer exceeded \(Self.MAX_BYTE_BUFFER)B without a stroke marker — dropping")
            byteBuffer.removeAll(keepingCapacity: false)
            return
        }

        // Try to flush a complete stroke.
        if let start = indexOf(sequence: Self.DATA_START, in: byteBuffer),
           let end   = indexOf(sequence: Self.DATA_END,   in: byteBuffer, from: start + Self.DATA_START.count) {
            frameIdleTimer?.invalidate()
            frameIdleTimer = nil
            let strokeEnd = end + Self.DATA_END.count
            let stroke = byteBuffer.subdata(in: start..<strokeEnd)
            // Keep anything past DATA_END for the next stroke.
            byteBuffer = byteBuffer.suffix(from: strokeEnd)
            BTLog.write("[BT] stroke complete (\(stroke.count)B) — sending to OCR")
            recognizeStroke(stroke)
            return
        }

        // No complete stroke yet — (re)arm the idle fallback.
        frameIdleTimer?.invalidate()
        frameIdleTimer = Timer.scheduledTimer(withTimeInterval: Self.FRAME_IDLE_MS, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let buf = self.byteBuffer
            self.byteBuffer.removeAll(keepingCapacity: false)
            // A tail with no DATA_START is an inter-stroke control/status frame — discard silently.
            guard self.indexOf(sequence: Self.DATA_START, in: buf) != nil else { return }
            BTLog.write("[BT] idle-flushed \(buf.count)B partial stroke (no DATA_END seen)")
            self.recognizeStroke(buf)
        }
    }

    /// Extract the image payload from a full stroke and POST it to the Scanmarker OCR service.
    /// Payload boundary: DATA_START (5B) + 4B sub-header … DATA_END (exclusive). Matches the
    /// vendor JS `extractAirPayload` (scanmarker-app/lib/adapters/scanner-real.ts).
    private func recognizeStroke(_ stroke: Data) {
        guard let start = indexOf(sequence: Self.DATA_START, in: stroke),
              let end   = indexOf(sequence: Self.DATA_END,   in: stroke, from: start + Self.DATA_START.count) else {
            BTLog.write("[BT] recognizeStroke: no full DATA_START/DATA_END pair — skipping")
            return
        }
        let payloadStart = start + Self.DATA_START.count + Self.DATA_SUBHEADER
        guard payloadStart < end else {
            BTLog.write("[BT] recognizeStroke: payload empty — skipping")
            return
        }
        let payload = stroke.subdata(in: payloadStart..<end)
        let base64 = payload.base64EncodedString()

        let email = SettingsStore.shared.scanmarkerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let serial = scannerSerial ?? ""
        let name = currentDeviceName.isEmpty ? "ScanMarker" : currentDeviceName
        let langId = SettingsStore.shared.scanmarkerLanguageId

        if email.isEmpty || serial.isEmpty {
            BTLog.write("[BT] OCR request MISSING identity — email=\(email.isEmpty ? "EMPTY" : "set") serial=\(serial.isEmpty ? "EMPTY" : "set"). Service will return empty text. Set Settings → AI → Scanmarker email.")
        }

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let result = try await RunOCRClient.shared.recognize(
                    bytesBase64: base64,
                    email: email,
                    serial: serial,
                    scannerName: name,
                    languageId: langId
                )
                BTLog.write("[BT] OCR result status=\(result.status) chars=\(result.text.count)")
                if !result.text.isEmpty {
                    self.scanReceived.send(result.text)
                }
            } catch {
                BTLog.write("[BT] OCR request failed: \(error.localizedDescription)")
            }
        }
    }

    /// Byte-accurate needle search — Data doesn't have a built-in equivalent that returns an index.
    private func indexOf(sequence: [UInt8], in haystack: Data, from: Int = 0) -> Int? {
        guard sequence.count > 0, haystack.count >= sequence.count + from else { return nil }
        outer: for i in from...(haystack.count - sequence.count) {
            for j in 0..<sequence.count {
                if haystack[i + j] != sequence[j] { continue outer }
            }
            return i
        }
        return nil
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            BTLog.write("[BT] Max reconnect attempts reached")
            DeviceRegistry.shared.setStatus(.failed("Couldn't reach the scanner. Move it closer or re-pair from the Devices panel."))
            return
        }
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0)
        BTLog.write("[BT] Scheduling reconnect attempt #\(reconnectAttempts) in \(delay)s")
        if let name = peripheral?.name ?? knownPeripherals[DeviceRegistry.shared.preferredDeviceID ?? ""]?.name {
            DeviceRegistry.shared.setStatus(.reconnecting(name))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startScanning()
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            BTLog.write("[BT] Bluetooth powered on")
            DeviceRegistry.shared.setStatus(DeviceRegistry.shared.preferredDeviceID == nil ? .scanning : .scanning)
            startScanning()
        case .poweredOff:
            connectionState.send(.disconnected)
            DeviceRegistry.shared.setStatus(.bluetoothOff)
            BTLog.write("[BT] Bluetooth powered off")
        case .unauthorized:
            DeviceRegistry.shared.setStatus(.bluetoothUnauthorized)
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Prefer the peripheral's own name; fall back to the advertised local name;
        // fall back to a placeholder derived from the identifier so the row is at least selectable.
        let rawName = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let idString = peripheral.identifier.uuidString
        let name = rawName ?? "Unnamed BLE device • \(String(idString.prefix(8)))"

        // Diagnostic log — the user's Console will show these lines so we can figure out
        // what a specific Scanmarker actually advertises when it doesn't show up cleanly.
        let advServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map(\.uuidString).joined(separator: ",") ?? "-"
        let manuData = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?
            .prefix(8).map { String(format: "%02x", $0) }.joined() ?? "-"
        BTLog.write("[BT] discover: name=\"\(rawName ?? "<nil>")\" id=\(idString.prefix(8)) rssi=\(RSSI) services=\(advServices) manu=\(manuData)")

        // Remember the CBPeripheral so a later connect(to:) can dispatch to it.
        knownPeripherals[idString] = peripheral

        // Publish into the registry so the Devices panel updates live.
        DeviceRegistry.shared.upsert(.init(
            id: idString,
            name: name,
            kind: .bluetooth,
            rssi: RSSI.intValue,
            lastSeen: Date()
        ))

        // Auto-connect only if this is the paired device.
        if DeviceRegistry.shared.preferredDeviceID == idString, self.peripheral == nil {
            BTLog.write("[BT] Found paired device \(name); auto-connecting")
            connect(to: idString)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        BTLog.write("[BT] Link-layer connected to \(peripheral.name ?? "device"), verifying Scanmarker GATT profile...")
        reconnectAttempts = 0
        currentDeviceName = peripheral.name ?? "Scanmarker"
        // NOTE: do NOT publish .connected / isConnected here. A successful CBCentralManager
        // link-layer connect only means *some* BLE peripheral answered — it says nothing about
        // whether it's actually a Scanmarker. Publishing "Connected" at this point caused a
        // phantom-connected bug: any peripheral matching a stale persisted preferredDeviceID
        // (or any device that happened to link-connect) showed as a real, verified pen with no
        // GATT check at all. We wait for didDiscoverCharacteristicsFor to confirm the scan
        // notify characteristic (c003) is actually present and subscribed before declaring
        // .connected. See handleVerifiedConnection() below.
        peripheral.discoverServices(nil)
    }

    /// Called once didDiscoverCharacteristicsFor confirms the Scanmarker notify characteristic
    /// is present and subscribed. This is the ONLY place `.connected` should be published.
    private func handleVerifiedConnection() {
        guard let peripheral = self.peripheral, !isConnected else { return }
        isConnected = true
        connectionState.send(.connected)
        deviceInfo.send((name: currentDeviceName, battery: nil))
        DeviceRegistry.shared.setStatus(.connected(currentDeviceName, .bluetooth))
        DeviceRegistry.shared.preferredDeviceID = peripheral.identifier.uuidString
        BTLog.write("[BT] Verified Scanmarker GATT profile — declaring connected: \(currentDeviceName)")
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        BTLog.write("[BT] Failed to connect: \(error?.localizedDescription ?? "unknown")")
        DeviceRegistry.shared.setStatus(.failed(error?.localizedDescription ?? "Connection failed"))
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        BTLog.write("[BT] Disconnected: \(error?.localizedDescription ?? "no error")")
        isConnected = false
        connectionState.send(.disconnected)
        DeviceRegistry.shared.setBattery(nil)
        self.peripheral = nil
        self.txCharacteristic = nil
        // Only backoff-reconnect if the user still wants this device paired.
        if DeviceRegistry.shared.preferredDeviceID == peripheral.identifier.uuidString {
            scheduleReconnect()
        } else {
            DeviceRegistry.shared.setStatus(.idle)
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        // Discover characteristics on EVERY service — we don't know in advance which UUID this
        // specific Scanmarker firmware uses to send scan text (many pens don't use standard NUS).
        for service in services {
            BTLog.write("[BT] service found: \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            let uuid = characteristic.uuid
            let props = characteristic.properties
            let propList = [
                props.contains(.read)          ? "read"    : nil,
                props.contains(.write)         ? "write"   : nil,
                props.contains(.writeWithoutResponse) ? "writeNoRsp" : nil,
                props.contains(.notify)        ? "notify"  : nil,
                props.contains(.indicate)      ? "indicate": nil
            ].compactMap { $0 }.joined(separator: ",")
            BTLog.write("[BT]   char \(uuid.uuidString) service=\(service.uuid.uuidString) props=\(propList)")

            // Standard BLE Battery Level (0x2A19): read + subscribe, treat specially so a 1-byte
            // battery notification isn't mistaken for a scan chunk.
            if uuid == batteryLevelCharUUID {
                peripheral.readValue(for: characteristic)
                if props.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
                continue
            }

            // Standard BLE Serial Number String (0x2A25): read once, cache. The OCR service
            // gates real recognition on it — an anonymous serial means empty results.
            if uuid == serialNumberCharUUID {
                peripheral.readValue(for: characteristic)
                continue
            }

            // Scanmarker write characteristic (c002): stash it so we can send activation
            // commands (0x0A) once notifications are up.
            if uuid == scanWriteCharUUID {
                writeCharacteristic = characteristic
                BTLog.write("[BT]     → stashed write characteristic \(uuid.uuidString)")
                continue
            }

            // Everything else that supports notify or indicate: subscribe.
            if props.contains(.notify) || props.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
                if uuid == scanNotifyCharUUID {
                    txCharacteristic = characteristic
                    // This is the actual proof-of-Scanmarker: only now do we know this
                    // peripheral speaks the expected protocol. Declare connected here,
                    // not on raw link-layer connect.
                    handleVerifiedConnection()
                }
                BTLog.write("[BT]     → subscribed to notify on \(uuid.uuidString)")
            }
        }

        // If every service on this peripheral has now reported characteristics and we still
        // haven't found the scan notify characteristic, this isn't a Scanmarker — disconnect
        // and surface a clear failure instead of leaving the UI in "connecting" forever.
        if txCharacteristic == nil,
           let allServices = peripheral.services,
           allServices.allSatisfy({ $0.characteristics != nil }) {
            BTLog.write("[BT] No Scanmarker notify characteristic found on any service — not a Scanmarker device")
            DeviceRegistry.shared.setStatus(.failed("This device doesn't look like a Scanmarker pen."))
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        // If we've now found BOTH the notify subscription (c003) and the write char (c002),
        // fire the activation sequence the vendor JS uses:
        //   write(0x0A) — activate scanner (without this the pen sits idle streaming noise)
        //   write(0x22) — request serial number (side-effect: forces the pen to identify itself)
        // Ordering matches the vendor's own connect flow.
        if let writeChar = writeCharacteristic, txCharacteristic != nil {
            let writeType: CBCharacteristicWriteType =
                writeChar.properties.contains(.write) ? .withResponse : .withoutResponse
            let activate = Data([Self.cmdActivate])
            peripheral.writeValue(activate, for: writeChar, type: writeType)
            BTLog.write("[BT]     ⤴ sent activation command 0x\(String(Self.cmdActivate, radix: 16, uppercase: false)) to \(writeChar.uuid.uuidString) (\(writeType == .withResponse ? "withResponse" : "withoutResponse"))")

            let requestSerial = Data([Self.cmdRequestSerial])
            peripheral.writeValue(requestSerial, for: writeChar, type: writeType)
            BTLog.write("[BT]     ⤴ sent request-serial command 0x\(String(Self.cmdRequestSerial, radix: 16, uppercase: false))")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }

        // Battery service: 1 byte, percentage 0-100.
        if characteristic.uuid == batteryLevelCharUUID {
            if let first = data.first {
                let pct = Int(first)
                BTLog.write("[BT] Battery: \(pct)%")
                DeviceRegistry.shared.setBattery(pct)
                deviceInfo.send((name: currentDeviceName, battery: pct))
            }
            return
        }

        // Device Info: Serial Number String (0x2A25). ASCII, may be zero-padded.
        if characteristic.uuid == serialNumberCharUUID {
            let raw = String(data: data, encoding: .utf8) ?? ""
            let serial = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\0", with: "")
            if !serial.isEmpty {
                scannerSerial = serial
                BTLog.write("[BT] Read pen serial number: \(serial)")
            }
            return
        }

        // Anything else: assume it's scan text. Log the bytes so we can debug
        // any mystery source. If the data doesn't decode as UTF-8, skip it —
        // that filters out non-text streams (e.g. HID reports, binary framing).
        let hex = data.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
        if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {
            BTLog.write("[BT] rx \(data.count)B from \(characteristic.uuid.uuidString): \"\(chunk.prefix(80))\"")
            handleIncomingData(data)
        } else {
            BTLog.write("[BT] rx \(data.count)B from \(characteristic.uuid.uuidString) (not UTF-8, hex: \(hex))")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        peripheral.discoverServices(nil)
    }
}
