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
                            // Route directly (bypass preview for re-inject)
                            // In full app this would go through InjectionRouter
                            print("Re-inject from history: \(record.id)")
                            // For demo, could call a global router if exposed
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
