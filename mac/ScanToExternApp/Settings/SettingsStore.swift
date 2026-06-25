import Foundation
import SwiftUI

/// User preferences persisted via @AppStorage (UserDefaults).
/// Later: move sensitive items (API key) to Keychain.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("previewEnabled")    var previewEnabled: Bool = true
    @AppStorage("previewTimeout")    var previewTimeout: Double = 2.0

    @AppStorage("aiMode")            var aiMode: String = "off"   // off | correct | translate | summarize | custom
    @AppStorage("targetLanguage")    var targetLanguage: String = "English"
    @AppStorage("claudeAPIKey")      var claudeAPIKey: String = "" // NOTE: move to keychain in prod

    @AppStorage("historyEnabled")    var historyEnabled: Bool = true
    @AppStorage("historyLimit")      var historyLimit: Int = 500

    @AppStorage("preferBluetooth")   var preferBluetooth: Bool = true
    @AppStorage("launchAtLogin")     var launchAtLogin: Bool = true
    @AppStorage("injectionMethod")   var injectionMethod: String = "ax" // ax | clipboard

    private init() {}
}
