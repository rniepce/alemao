import SwiftUI

/// Mostra uma notícia da DW Nachrichten leicht com tap-to-translate no corpo.
struct DWNewsDetailView: View {
    let item: DWNewsItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "newspaper")
                    Text("Deutsche Welle — Nachrichten leicht")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let date = item.pubDate {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(item.title)
                    .font(.title3.bold())

                if !item.description.isEmpty {
                    TappableGermanText(item.description)
                }

                if let url = URL(string: item.link) {
                    Link(destination: url) {
                        Label("Abrir notícia completa no DW.com", systemImage: "arrow.up.right.square")
                            .font(.callout)
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
        }
        .navigationTitle("Notícia")
        .navigationBarTitleDisplayMode(.inline)
    }
}
