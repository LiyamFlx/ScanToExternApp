import SwiftUI

struct HistoryView: View {
    @State private var records: [ScanRecord] = []
    @State private var searchText: String = ""

    var body: some View {
        VStack {
            HStack {
                Text("Scan History")
                    .font(.title2)
                Spacer()
                Button("Clear All") {
                    try? ScanHistoryStore.shared.deleteAll()
                    load()
                }
                .foregroundColor(.red)
            }
            .padding(.horizontal)

            TextField("Search scans...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .onChange(of: searchText) { _ in load() }

            List(records) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.text)
                        .lineLimit(2)
                        .font(.body)
                    HStack {
                        Text(record.timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• \(record.source)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Re-inject") {
                            // Show the preview flow again for the historical text (user can edit/correct before injecting)
                            PreviewWindowController.shared.showPreview(
                                text: record.text,
                                onInject: { finalText in
                                    Task {
                                        let processed = await AIProcessor.shared.process(finalText)
                                        InjectionRouter.shared.route(processed)

                                        // Update or append a new history entry for the re-inject
                                        if SettingsStore.shared.historyEnabled {
                                            var newRecord = record
                                            newRecord.processedText = processed != finalText ? processed : nil
                                            newRecord.timestamp = Date()
                                            newRecord.injectedTo = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                                            try? ScanHistoryStore.shared.save(newRecord)
                                        }
                                    }
                                },
                                onDiscard: {}
                            )
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear { load() }
    }

    private func load() {
        do {
            if searchText.isEmpty {
                records = try ScanHistoryStore.shared.recent(limit: 100)
            } else {
                records = try ScanHistoryStore.shared.search(searchText)
            }
        } catch {
            records = []
            print("History load error: \(error)")
        }
    }
}

extension ScanRecord: Identifiable {}
