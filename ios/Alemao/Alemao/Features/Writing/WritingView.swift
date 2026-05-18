import SwiftData
import SwiftUI

/// Aba Escrita: editor + timeline de entradas anteriores com correções.
struct WritingView: View {
    @Query(sort: \WritingEntry.createdAt, order: .reverse) private var entries: [WritingEntry]
    @State private var showNewEntry = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showNewEntry = true
                    } label: {
                        Label("Nova entrada", systemImage: "square.and.pencil")
                    }
                }

                if entries.isEmpty {
                    ContentUnavailableView(
                        "Diário vazio",
                        systemImage: "book.pages",
                        description: Text("Escreva sua primeira entrada para receber correção.")
                    )
                } else {
                    Section("Suas entradas") {
                        ForEach(entries, id: \.id) { entry in
                            NavigationLink {
                                WritingEntryDetailView(entry: entry)
                            } label: {
                                WritingEntryRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Escrita")
            .sheet(isPresented: $showNewEntry) {
                NewWritingEntrySheet()
            }
        }
    }
}

private struct WritingEntryRow: View {
    let entry: WritingEntry
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(entry.prompt ?? "Texto livre").font(.subheadline.bold()).lineLimit(1)
                Spacer()
                Text(entry.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.content.prefix(120))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if entry.correctionJSON != nil {
                Label("Corrigido", systemImage: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Label("Aguardando correção", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct NewWritingEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var prompt: String = ""
    @State private var content: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt (opcional)") {
                    TextField("Ex: descreva seu fim de semana", text: $prompt, axis: .vertical)
                        .lineLimit(1...2)
                }
                Section("Seu texto em alemão") {
                    TextEditor(text: $content)
                        .frame(minHeight: 180)
                        .font(.body)
                }
            }
            .navigationTitle("Nova entrada")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let entry = WritingEntry(
                            prompt: prompt.isEmpty ? nil : prompt,
                            content: content
                        )
                        modelContext.insert(entry)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    WritingView()
        .modelContainer(for: [WritingEntry.self], inMemory: true)
}
