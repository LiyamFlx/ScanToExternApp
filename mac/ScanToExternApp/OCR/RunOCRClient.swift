import Foundation

/// Client for the Scanmarker cloud OCR service (`RunOCR_V7` at
/// `https://cloud-google.scanmarker.com/OCRWebServiceMain.asmx`).
///
/// The Scanmarker Air pen sends a compressed RLE bitmap over BLE — NOT text. The
/// vendor's own web app and Mac desktop app both POST the raw scan bytes to this
/// SOAP endpoint, which decompresses + OCRs them server-side and returns the text.
/// This class is a direct port of the exact call the vendor's own JavaScript
/// implementation makes (see webapp.scanmarker/…/chunk-ZZUARTOR.js and the user's
/// scanmarker-app/app/api/scan-ocr/route.ts — this file is the Swift equivalent).
///
/// Auth: the service accepts anonymous calls but returns STATUS=OK with an empty
/// RESULT unless it recognizes both a registered account email AND the paired pen's
/// serial number. Both must be supplied for real OCR to run.
final class RunOCRClient {
    static let shared = RunOCRClient()

    private let endpoint = URL(string: "https://cloud-google.scanmarker.com/OCRWebServiceMain.asmx")!
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    struct Result {
        /// "OK" if OCR ran successfully. "CLICK" if the service read the payload as a tap
        /// (framing/slice off). "ERROR" or other for upstream failures.
        let status: String
        /// The recognized text (empty if STATUS != "OK").
        let text: String
    }

    /// Send a base64-encoded scan payload to Scanmarker's OCR service.
    ///
    /// - Parameters:
    ///   - bytesBase64: base64-encoded raw scan bytes (image header + compressed RLE, WITHOUT
    ///     the leading `ff ff ff 04 00` + 4-byte sub-header and WITHOUT the trailing
    ///     `ff ff ff 04 07` — see BluetoothManager.extractStrokePayload).
    ///   - email: registered Scanmarker account email (else the service returns empty text).
    ///   - serial: pen serial from BLE Device Info 0x2A25 (else the service returns empty text).
    ///   - scannerName: pen's BLE name (e.g. "PenScanBLE5968CA"). Cosmetic; used by the service
    ///     for its own analytics but doesn't gate OCR.
    ///   - languageId: Scanmarker numeric language id. 220 = English (verified from vendor).
    ///   - isRtoL: true for right-to-left languages (Hebrew, Arabic).
    func recognize(bytesBase64: String,
                   email: String,
                   serial: String,
                   scannerName: String,
                   languageId: Int = 220,
                   isRtoL: Bool = false,
                   isVertical: Bool = false) async throws -> Result {
        let envelope = buildEnvelope(
            bytesBase64: bytesBase64,
            email: email,
            serial: serial,
            scannerName: scannerName,
            languageId: languageId,
            isRtoL: isRtoL,
            isVertical: isVertical
        )

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("text/xml;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = envelope.data(using: .utf8)

        let (data, response) = try await session.data(for: req)
        let body = String(data: data, encoding: .utf8) ?? ""

        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) && !body.contains("RunOCR_V7Result") {
            throw NSError(domain: "RunOCR_V7", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "OCR upstream HTTP \(http.statusCode)"])
        }

        let status = tag("STATUS", in: body) ?? "ERROR"
        let raw = tag("RESULT", in: body) ?? ""
        // The service HTML-escapes the RESULT; decode the few entities it emits.
        let text = raw
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#xA;", with: "\n")
            .replacingOccurrences(of: "&#10;", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Result(status: status, text: status == "OK" ? text : "")
    }

    // MARK: - Private

    /// Build the SOAP envelope for RunOCR_V7. Field order + naming taken verbatim from
    /// the vendor JS (scanmarker-app/app/api/scan-ocr/route.ts::buildEnvelope).
    private func buildEnvelope(bytesBase64: String,
                               email: String,
                               serial: String,
                               scannerName: String,
                               languageId: Int,
                               isRtoL: Bool,
                               isVertical: Bool) -> String {
        let e = xmlEscape(email)
        let s = xmlEscape(serial)
        let n = xmlEscape(scannerName)
        return """
        <?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body>\
        <RunOCR_V7 xmlns="http://cloud.a.scanmarker.com/">\
        <email>\(e)</email>\
        <bmpFileBytesBase64>\(bytesBase64)</bmpFileBytesBase64>\
        <stringToReturn>1</stringToReturn>\
        <ScannerSerialNumber>\(s)</ScannerSerialNumber>\
        <ScannerName>\(n)</ScannerName>\
        <ScannerType>reader</ScannerType>\
        <donotStoreLogInKibana>false</donotStoreLogInKibana>\
        <isCompressed>true</isCompressed>\
        <languageId>\(languageId)</languageId>\
        <Token>web_app</Token>\
        <isRtoL>\(isRtoL)</isRtoL>\
        <isVertical>\(isVertical)</isVertical>\
        <isTableMode>false</isTableMode>\
        <compressionVersion>1</compressionVersion>\
        <ocrEngine>1</ocrEngine>\
        <app_id>1</app_id>\
        <scannerType_id>2</scannerType_id>\
        <os_id>1</os_id>\
        </RunOCR_V7></soap:Body></soap:Envelope>
        """
    }

    private func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func tag(_ name: String, in body: String) -> String? {
        // Match <NAME>...</NAME> non-greedy across lines.
        let pattern = "<\(name)>([\\s\\S]*?)</\(name)>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = body as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range),
              match.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
