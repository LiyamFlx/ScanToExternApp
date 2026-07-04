/// Client for the Scanmarker cloud OCR service (`RunOCR_V7` at
/// `https://cloud-google.scanmarker.com/OCRWebServiceMain.asmx`).
///
/// The Scanmarker Air pen sends a compressed RLE bitmap over BLE — NOT text. The
/// vendor's own web app and the Mac desktop app (RunOCRClient.swift) both POST the
/// raw scan bytes to this SOAP endpoint, which decompresses + OCRs them server-side
/// and returns the text. This is the Rust port of RunOCRClient.swift — same
/// envelope, same field order, same auth/gating behavior.
///
/// Auth: the service accepts anonymous calls but returns STATUS=OK with an empty
/// RESULT unless it recognizes both a registered account email AND the paired pen's
/// serial number. Both must be supplied for real OCR to run.
use anyhow::{anyhow, Result};
use std::time::Duration;

const ENDPOINT: &str = "https://cloud-google.scanmarker.com/OCRWebServiceMain.asmx";

pub struct OcrResult {
    /// "OK" if OCR ran successfully. "CLICK" if the service read the payload as a tap
    /// (framing/slice off). "ERROR" or other for upstream failures.
    pub status: String,
    /// The recognized text (empty if status != "OK").
    pub text: String,
}

/// Send a base64-encoded scan payload to Scanmarker's OCR service.
///
/// - `bytes_base64`: base64-encoded raw scan bytes (image header + compressed RLE, WITHOUT
///   the leading `ff ff ff 04 00` + 4-byte sub-header and WITHOUT the trailing
///   `ff ff ff 04 07` — see hardware::bluetooth::extract_air_payload).
/// - `email`: registered Scanmarker account email (else the service returns empty text).
/// - `serial`: pen serial from BLE Device Info 0x2A25 (else the service returns empty text).
/// - `scanner_name`: pen's BLE name. Cosmetic; used by the service for analytics only.
/// - `language_id`: Scanmarker numeric language id. 220 = English (verified from vendor).
pub async fn recognize(
    bytes_base64: &str,
    email: &str,
    serial: &str,
    scanner_name: &str,
    language_id: u32,
    is_rtol: bool,
) -> Result<OcrResult> {
    let envelope = build_envelope(bytes_base64, email, serial, scanner_name, language_id, is_rtol);

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()?;

    let resp = client
        .post(ENDPOINT)
        .header("Content-Type", "text/xml;charset=UTF-8")
        .body(envelope)
        .send()
        .await?;

    let status_code = resp.status();
    let body = resp.text().await?;

    if !status_code.is_success() && !body.contains("RunOCR_V7Result") {
        return Err(anyhow!("OCR upstream HTTP {}", status_code));
    }

    let status = extract_tag("STATUS", &body).unwrap_or_else(|| "ERROR".to_string());
    let raw = extract_tag("RESULT", &body).unwrap_or_default();
    let text = raw
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
        .replace("&#xA;", "\n")
        .replace("&#10;", "\n")
        .trim()
        .to_string();

    Ok(OcrResult {
        text: if status == "OK" { text } else { String::new() },
        status,
    })
}

/// Build the SOAP envelope for RunOCR_V7. Field order + naming taken verbatim from
/// the vendor JS / RunOCRClient.swift's buildEnvelope, so the request is byte-for-byte
/// consistent with what the Mac app and the official web app send.
fn build_envelope(
    bytes_base64: &str,
    email: &str,
    serial: &str,
    scanner_name: &str,
    language_id: u32,
    is_rtol: bool,
) -> String {
    let e = xml_escape(email);
    let s = xml_escape(serial);
    let n = xml_escape(scanner_name);
    format!(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?><soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\"><soap:Body>\
<RunOCR_V7 xmlns=\"http://cloud.a.scanmarker.com/\">\
<email>{e}</email>\
<bmpFileBytesBase64>{bytes_base64}</bmpFileBytesBase64>\
<stringToReturn>1</stringToReturn>\
<ScannerSerialNumber>{s}</ScannerSerialNumber>\
<ScannerName>{n}</ScannerName>\
<ScannerType>reader</ScannerType>\
<donotStoreLogInKibana>false</donotStoreLogInKibana>\
<isCompressed>true</isCompressed>\
<languageId>{language_id}</languageId>\
<Token>web_app</Token>\
<isRtoL>{is_rtol}</isRtoL>\
<isVertical>false</isVertical>\
<isTableMode>false</isTableMode>\
<compressionVersion>1</compressionVersion>\
<ocrEngine>1</ocrEngine>\
<app_id>1</app_id>\
<scannerType_id>2</scannerType_id>\
<os_id>1</os_id>\
</RunOCR_V7></soap:Body></soap:Envelope>"
    )
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

/// Match <NAME>...</NAME> non-greedy, across lines. Simple substring scan rather than
/// pulling in a regex/XML crate for a single-field extraction from a known-shape SOAP body.
fn extract_tag(name: &str, body: &str) -> Option<String> {
    let open = format!("<{name}>");
    let close = format!("</{name}>");
    let start = body.find(&open)? + open.len();
    let end = body[start..].find(&close)? + start;
    Some(body[start..end].to_string())
}
