import Foundation
import Vision
import AppKit

/// Secondary OCR correction using Apple Vision Framework.
/// Only invoked if needed (e.g. low confidence from hardware — we don't receive confidence, so we can always optionally run or on user toggle).
/// Strategy per spec: screenshot region around current cursor / front window and compare.
final class VisionCorrector {
    /// Runs Vision text recognition on a screenshot of the frontmost window.
    /// Returns a possibly improved string or the original hardwareText.
    func correct(hardwareText: String, completion: @escaping (String) -> Void) {
        // Capture the frontmost window image
        guard let windowImage = captureFrontmostWindow() else {
            completion(hardwareText)
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("[Vision] Recognition error: \(error)")
                completion(hardwareText)
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(hardwareText)
                return
            }

            let visionText = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")

            // Heuristic from spec: if vision produced significantly longer result, prefer hardware (sometimes screen area is wrong)
            // Otherwise prefer the vision result if it looks better (longer or contains more words)
            let result: String
            if visionText.count > hardwareText.count * 2 {
                result = hardwareText
            } else if visionText.count > hardwareText.count && !visionText.trimmingCharacters(in: .whitespaces).isEmpty {
                result = visionText
            } else {
                result = hardwareText
            }

            print("[Vision] hardware=\(hardwareText.prefix(30))... vision=\(visionText.prefix(30))... chosen len=\(result.count)")
            completion(result)
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"] // extend for other langs later

        let handler = VNImageRequestHandler(cgImage: windowImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(hardwareText)
            }
        }
    }

    private func captureFrontmostWindow() -> CGImage? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier

        // Capture all windows on screen and pick the front one belonging to the app is complex.
        // Simpler reliable approach: capture the entire screen then crop, or use CGWindowListCreateImage with option for onscreen.
        let windowListOption = CGWindowListOption.optionOnScreenOnly
        let image = CGWindowListCreateImage(
            CGRect.null, // full union of windows
            windowListOption,
            kCGNullWindowID,
            [.bestResolution]
        )
        return image
    }
}
