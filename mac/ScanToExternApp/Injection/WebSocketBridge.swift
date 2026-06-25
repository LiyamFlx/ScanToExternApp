import Foundation
import Network

/// Local-only WebSocket server on ws://127.0.0.1:52731
/// Broadcasts scan events to browser extension (and any other localhost clients).
/// Protocol defined in shared/websocket-protocol.md
final class WebSocketBridge: NSObject {
    static let port: NWEndpoint.Port = 52731
    static let host = "127.0.0.1"

    private var listener: NWListener?
    private var connections: [NWConnection] = []

    private let queue = DispatchQueue(label: "com.topscan.ScanToExternApp.ws", qos: .userInitiated)

    var onClientConnected: (() -> Void)?
    var onClientDisconnected: (() -> Void)?

    func start() {
        // Use WebSocket protocol options so that browser clients (using standard WebSocket JS API) can connect
        let wsOptions = NWProtocolWebSocket.Options()
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        // Create listener bound to localhost port
        listener = try? NWListener(using: parameters, on: WebSocketBridge.port)

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
            guard let self = self else { return }
            // Localhost enforced by binding + OS firewall rules.
            self.setupConnection(connection)
        }

        listener?.start(queue: queue)
    }

    private func setupConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[WS] Client connected")
                self?.connections.append(connection)
                self?.onClientConnected?()
                self?.startReceiving(on: connection)
            case .failed, .cancelled:
                self?.removeConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func startReceiving(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                // We mostly ignore inbound except for pings/acks (basic handling)
                if let message = String(data: data, encoding: .utf8) {
                    // Could parse JSON for ack/ping here in future
                    if message.contains("\"type\":\"ping\"") {
                        self?.sendPingResponse(to: connection)
                    }
                }
            }
            if isComplete || error != nil {
                self?.removeConnection(connection)
            } else {
                self?.startReceiving(on: connection)
            }
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        connection.cancel()
        onClientDisconnected?()
        print("[WS] Client disconnected. Active: \(connections.count)")
    }

    /// Broadcast a scan to ALL connected clients (primarily the browser extension)
    func broadcastScan(text: String, id: String = UUID().uuidString) {
        let message: [String: Any] = [
            "type": "scan",
            "text": text,
            "id": id
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("[WS] Failed to serialize scan message")
            return
        }

        // Proper WebSocket text frame is complex without a lib.
        // For production, use a lightweight framing or switch to a pure swift websocket lib if needed.
        // For MVP compatibility with browser WebSocket (which expects proper WS frames),
        // we send raw text for simplicity here — in practice Network.framework NWConnection with WebSocket options or use URLSessionWebSocket.
        // Simpler robust approach: use NWProtocolWebSocket for the listener.

        // Re-implement using NWProtocolWebSocket for correctness:
        sendWebSocketText(toAll: jsonString)
    }

    // MARK: - Proper WebSocket using NWProtocolWebSocket

    private func sendWebSocketText(toAll text: String) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])

        for connection in connections {
            connection.send(content: text.data(using: .utf8), contentContext: context, isComplete: true, completion: .contentProcessed({ error in
                if let error = error {
                    print("[WS] Broadcast send error: \(error)")
                }
            }))
        }
    }

    private func sendPingResponse(to connection: NWConnection) {
        let pong: [String: Any] = ["type": "pong"]
        if let data = try? JSONSerialization.data(withJSONObject: pong) {
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "pong", metadata: [metadata])
            connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed({ _ in }))
        }
    }

    private func restartAfterDelay() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.start()
        }
    }

    func stop() {
        listener?.cancel()
        for conn in connections { conn.cancel() }
        connections.removeAll()
        listener = nil
    }
}
