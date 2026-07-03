import Foundation

/// Persistent debug log for Bluetooth discovery / connection / rx events.
/// Written to ~/Library/Logs/ScanToExternApp/bluetooth.log (also mirrored to stdout).
/// We need this because `print()` from GUI apps launched via `open` doesn't reliably
/// reach `log stream`, making live BT diagnosis over CLI unreliable. A plain file the
/// user can `open` in TextEdit works from anywhere with no permissions.
enum BTLog {
    private static let queue = DispatchQueue(label: "com.topscan.ScanToExternApp.btlog")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static var url: URL {
        let dir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/ScanToExternApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bluetooth.log")
    }

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        print(message)  // keep stdout mirror for anyone reading via log stream
        queue.async {
            let url = self.url
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) { handle.write(data) }
                try? handle.close()
            } else {
                try? line.data(using: .utf8)?.write(to: url)
            }
        }
    }

    /// Truncate the log at app launch so each session starts fresh.
    static func reset() {
        queue.async {
            try? "--- ScanToExternApp Bluetooth log — session start \(Date()) ---\n".write(
                to: url, atomically: true, encoding: .utf8)
        }
    }
}
