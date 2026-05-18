import SwiftUI

/// Card visual de citação. Tocar abre o PDF na página citada (se bundleado).
struct CitationCard: View {
    let bookId: String
    let bookTitle: String
    let sectionTitle: String?
    let pageStart: Int
    let pageEnd: Int
    let excerpt: String

    /// Opcional: filePath do livro vindo do LibraryDB. Se nil, tenta resolver via LibraryDB.shared.
    var filePath: String?

    var body: some View {
        NavigationLink {
            PDFCitationView(
                bookTitle: bookTitle,
                filePath: filePath ?? resolveFilePath(),
                pageStart: pageStart,
                pageEnd: pageEnd
            )
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "book.closed")
                    Text(bookTitle).font(.subheadline.bold())
                    Spacer()
                    Text(pageLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let s = sectionTitle {
                    Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(excerpt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var pageLabel: String {
        pageEnd > pageStart ? "p. \(pageStart)-\(pageEnd)" : "p. \(pageStart)"
    }

    private func resolveFilePath() -> String? {
        guard let db = LibraryDB.shared else { return nil }
        // `try?` em método que retorna Optional colapsa para um único Optional
        guard let book = try? db.book(id: bookId) else { return nil }
        return book.filePath
    }
}

/// Helper: decodifica JSON de citações de `GeneratedLesson.citationsJSON`.
struct DecodedCitation: Codable, Hashable {
    let book_id: String
    let book_title: String
    let section_title: String?
    let page_start: Int
    let page_end: Int
    let excerpt: String
}

extension DecodedCitation {
    static func decodeList(from json: String) -> [DecodedCitation] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([DecodedCitation].self, from: data)) ?? []
    }
}
