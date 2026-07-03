import Foundation
import Network
import CryptoKit

/// Local-only WebSocket server on ws://127.0.0.1:52731
/// Broadcasts scan events to the browser extension (and any other localhost clients).
///
/// Implemented as a hand-rolled RFC 6455 server over raw NWConnection TCP. We do NOT use
/// NWProtocolWebSocket because its server-side handshake does not interoperate reliably with
/// Chrome's WebSocket client (the browser stays in CONNECTING forever). A manual handshake +
/// framing implementation connects cleanly from Chrome, Safari, curl and Node.
///
/// Protocol defined in shared/websocket-protocol.md
final class WebSocketBridge: NSObject {
    static let port: NWEndpoint.Port = 52731
    static let host = "127.0.0.1"

    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private let queue = DispatchQueue(label: "com.topscan.ScanToExternApp.ws", qos: .userInitiated)

    var onClientConnected: (() -> Void)?
    var onClientDisconnected: (() -> Void)?

    /// Per-connection state: tracks whether the WebSocket handshake has completed and
    /// buffers incoming bytes until full frames arrive.
    private final class Client {
        let connection: NWConnection
        var didUpgrade = false
        var inboundBuffer = Data()
        init(_ connection: NWConnection) { self.connection = connection }
    }

    // MARK: - Lifecycle

    func start() {
        // Bind a plain TCP listener on loopback. We handle the WebSocket upgrade ourselves.
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.allowLocalEndpointReuse = true
        // Bind explicitly to the IPv4 loopback address. Without this, NWListener binds
        // IPv6-only (::1), so IPv4 clients connecting to 127.0.0.1 — which is what Chrome's
        // WebSocket and the browser extension use — fail silently. Binding 127.0.0.1 makes
        // the standard ws://127.0.0.1:52731 connection work.
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback),
            port: WebSocketBridge.port
        )

        // Note: the port comes from requiredLocalEndpoint above; do NOT also pass `on:` or the
        // two conflict and the bind fails silently.
        do {
            listener = try NWListener(using: parameters)
        } catch {
            print("[WS] FATAL: could not create listener on 127.0.0.1:\(WebSocketBridge.port) — \(error). Browser extension will not receive scans.")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[WS] WebSocket server listening on \(WebSocketBridge.host):\(WebSocketBridge.port)")
            case .failed(let error):
                print("[WS] Listener failed: \(error). Restarting in 3s...")
                self?.restartAfterDelay()
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.setupConnection(connection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        for (_, client) in clients { client.connection.cancel() }
        clients.removeAll()
        listener = nil
    }

    private func restartAfterDelay() {
        listener?.cancel()
        listener = nil
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.start()
        }
    }

    // MARK: - Connection setup

    private func setupConnection(_ connection: NWConnection) {
        // Loopback-only guard: reject any connection not originating from 127.0.0.1 / ::1.
        if case let .hostPort(host, _) = connection.endpoint {
            let isLoopback: Bool
            switch host {
            case .ipv4(let addr): isLoopback = addr.isLoopback
            case .ipv6(let addr): isLoopback = addr.isLoopback
            default: isLoopback = false
            }
            if !isLoopback {
                print("[WS] Rejected non-loopback connection from \(host)")
                connection.cancel()
                return
            }
        }

        let client = Client(connection)
        let key = ObjectIdentifier(connection)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.clients[key] = client
                self.receive(on: client)
            case .failed, .cancelled:
                self.removeClient(key)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func removeClient(_ key: ObjectIdentifier) {
        guard let client = clients.removeValue(forKey: key) else { return }
        client.connection.cancel()
        if client.didUpgrade { onClientDisconnected?() }
        print("[WS] Client disconnected. Active: \(clients.count)")
    }

    // MARK: - Receiving

    private func receive(on client: Client) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                client.inboundBuffer.append(data)
                if client.didUpgrade {
                    self.parseFrames(client)
                } else {
                    self.tryCompleteHandshake(client)
                }
            }
            // Only tear down on a real error. A peer half-closing its write side (isComplete)
            // must NOT cancel the connection: we may still be completing the handshake send or
            // have pending data to broadcast. The connection's own .failed/.cancelled state
            // handler removes the client when the socket truly goes away.
            if let error = error {
                print("[WS] receive error: \(error)")
                self.removeClient(ObjectIdentifier(client.connection))
            } else if !isComplete {
                self.receive(on: client)
            }
        }
    }

    // MARK: - Handshake (RFC 6455 §4.2.2)

    private func tryCompleteHandshake(_ client: Client) {
        // Wait until we have the full HTTP request header block.
        guard let headerEnd = client.inboundBuffer.range(of: Data("\r\n\r\n".utf8)) else { return }
        let headerData = client.inboundBuffer.subdata(in: client.inboundBuffer.startIndex..<headerEnd.lowerBound)
        client.inboundBuffer.removeSubrange(client.inboundBuffer.startIndex..<headerEnd.upperBound)

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            removeClient(ObjectIdentifier(client.connection)); return
        }

        // Parse the Sec-WebSocket-Key header (case-insensitive).
        var secKey: String?
        for line in headerString.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "sec-websocket-key" {
                secKey = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }

        guard let key = secKey else {
            // Not a WebSocket upgrade — close.
            removeClient(ObjectIdentifier(client.connection)); return
        }

        // Accept = base64( SHA1( key + GUID ) )
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let acceptInput = Data((key + magic).utf8)
        let digest = Insecure.SHA1.hash(data: acceptInput)
        let accept = Data(digest).base64EncodedString()

        let response = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Accept: \(accept)",
            "", ""
        ].joined(separator: "\r\n")

        client.connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                print("[WS] Handshake send error: \(error)")
                self.removeClient(ObjectIdentifier(client.connection))
                return
            }
            client.didUpgrade = true
            print("[WS] Client connected (handshake complete). Active: \(self.clients.count)")
            self.onClientConnected?()
            // Any bytes after the header are the start of frames.
            if !client.inboundBuffer.isEmpty { self.parseFrames(client) }
        })
    }

    // MARK: - Frame parsing (incoming, client→server, always masked)

    private func parseFrames(_ client: Client) {
        while true {
            let buf = client.inboundBuffer
            guard buf.count >= 2 else { return }

            let bytes = [UInt8](buf)
            let opcode = bytes[0] & 0x0F
            let masked = (bytes[1] & 0x80) != 0
            var payloadLen = Int(bytes[1] & 0x7F)
            var offset = 2

            if payloadLen == 126 {
                guard bytes.count >= 4 else { return }
                payloadLen = (Int(bytes[2]) << 8) | Int(bytes[3])
                offset = 4
            } else if payloadLen == 127 {
                guard bytes.count >= 10 else { return }
                payloadLen = 0
                for i in 2..<10 { payloadLen = (payloadLen << 8) | Int(bytes[i]) }
                offset = 10
            }

            var maskKey: [UInt8] = [0, 0, 0, 0]
            if masked {
                guard bytes.count >= offset + 4 else { return }
                maskKey = Array(bytes[offset..<offset+4])
                offset += 4
            }

            guard bytes.count >= offset + payloadLen else { return } // wait for full payload

            var payload = Array(bytes[offset..<offset+payloadLen])
            if masked {
                for i in 0..<payload.count { payload[i] ^= maskKey[i % 4] }
            }

            // Consume this frame from the buffer.
            client.inboundBuffer.removeSubrange(buf.startIndex..<buf.index(buf.startIndex, offsetBy: offset + payloadLen))

            switch opcode {
            case 0x1: // text
                if let msg = String(bytes: payload, encoding: .utf8) {
                    handleTextMessage(msg, from: client)
                }
            case 0x8: // close
                removeClient(ObjectIdentifier(client.connection)); return
            case 0x9: // ping → pong
                sendFrame(opcode: 0xA, payload: payload, to: client)
            default:
                break // pong / continuation — ignore
            }
        }
    }

    private func handleTextMessage(_ message: String, from client: Client) {
        // Respond to application-level pings; acks are informational.
        if message.contains("\"type\":\"ping\"") {
            if let data = try? JSONSerialization.data(withJSONObject: ["type": "pong"]),
               let str = String(data: data, encoding: .utf8) {
                sendText(str, to: client)
            }
        }
    }

    // MARK: - Sending (outgoing, server→client, never masked)

    /// Broadcast a scan to ALL connected clients (primarily the browser extension).
    /// Outbound payload capped at 100,000 chars per the security invariant in CLAUDE.md.
    func broadcastScan(text: String, id: String = UUID().uuidString) {
        let safeText = text.count > 100_000 ? String(text.prefix(100_000)) : text
        let message: [String: Any] = ["type": "scan", "text": safeText, "id": id]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("[WS] Failed to serialize scan message")
            return
        }
        let upgraded = clients.values.filter { $0.didUpgrade }
        for client in upgraded { sendText(jsonString, to: client) }
        print("[WS] Broadcast scan to \(upgraded.count) client(s)")
    }

    private func sendText(_ text: String, to client: Client) {
        sendFrame(opcode: 0x1, payload: [UInt8](text.utf8), to: client)
    }

    /// Build and send a single unfragmented frame (FIN=1, no mask — server frames are never masked).
    private func sendFrame(opcode: UInt8, payload: [UInt8], to client: Client) {
        var frame: [UInt8] = []
        frame.append(0x80 | opcode) // FIN + opcode

        let len = payload.count
        if len < 126 {
            frame.append(UInt8(len))
        } else if len <= 0xFFFF {
            frame.append(126)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((len >> shift) & 0xFF))
            }
        }
        frame.append(contentsOf: payload)

        client.connection.send(content: Data(frame), completion: .contentProcessed { error in
            if let error = error { print("[WS] Send error: \(error)") }
        })
    }
}
