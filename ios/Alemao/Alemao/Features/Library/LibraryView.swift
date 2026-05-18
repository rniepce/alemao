import SwiftUI

struct LibraryView: View {
    @State private var books: [LibraryDB.Book] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        RetrievalDebugView()
                    } label: {
                        Label("Testar busca (RAG)", systemImage: "magnifyingglass.circle.fill")
                    }
                }

                Section("Livros bundleados") {
                    if let loadError {
                        Text(loadError)
                            .foregroundStyle(.red)
                            .font(.caption)
                    } else if books.isEmpty {
                        Text("Nenhum livro encontrado no bundle.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(books, id: \.id) { book in
                            BookRow(book: book)
                        }
                    }
                }
            }
            .navigationTitle("Biblioteca")
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let db = LibraryDB.shared else {
            loadError = "library.sqlite não encontrado em Resources/PrebuiltContent/."
            return
        }
        do {
            books = try db.allBooks()
        } catch {
            loadError = "Erro: \(error.localizedDescription)"
        }
    }
}

private struct BookRow: View {
    let book: LibraryDB.Book

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(book.title ?? "—").font(.headline)
                Spacer()
                if let level = book.levelCEFR {
                    Text(level)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            if let author = book.author {
                Text(author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack {
                Label(book.type, systemImage: iconForType(book.type))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let pages = book.pageCount {
                    Text("· \(pages) pp")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "grammar": return "text.book.closed.fill"
        case "workbook": return "pencil.and.list.clipboard"
        case "dictionary": return "character.book.closed.fill"
        case "reader": return "book.fill"
        default: return "doc.fill"
        }
    }
}

#Preview {
    LibraryView()
}
