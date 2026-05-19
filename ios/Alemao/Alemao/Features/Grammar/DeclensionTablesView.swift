import SwiftUI

/// Visualizador interativo das 9 tabelas de declinação alemãs.
/// Picker no topo para alternar entre tabelas. Tabela renderizada com 4 colunas
/// (Nom/Akk/Dat/Gen) × até 4 linhas (m/f/n/pl).
struct DeclensionTablesView: View {
    @State private var selectedID: String = DeclensionTables.all.first?.id ?? ""

    private var selected: DeclensionTable {
        DeclensionTables.all.first(where: { $0.id == selectedID }) ?? DeclensionTables.all[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tablePicker
                tableHeader
                tableGrid
                if !selected.notes.isEmpty {
                    notesSection
                }
            }
            .padding()
        }
        .navigationTitle("Tabelas de Declinação")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var tablePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DeclensionTables.all) { table in
                    Button {
                        withAnimation { selectedID = table.id }
                    } label: {
                        Text(table.title)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                table.id == selectedID
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.15)
                            )
                            .foregroundStyle(
                                table.id == selectedID
                                    ? Color.white
                                    : Color.primary
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var tableHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selected.title)
                .font(.title3.bold())
            Text(selected.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tableGrid: some View {
        let cases = DeclensionCase.allCases
        let presentGenders = DeclensionGender.allCases.filter { selected.cells[$0] != nil }

        VStack(spacing: 0) {
            // Header row: caso/Gender
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 70, alignment: .leading)
                ForEach(cases) { c in
                    VStack(spacing: 1) {
                        Text(c.shortLabel)
                            .font(.caption.bold())
                        Text(c.question)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.18))

            // Linhas de dados
            ForEach(Array(presentGenders.enumerated()), id: \.element.id) { idx, gender in
                let custom = selected.customRowLabels?[gender]
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(custom?.short ?? gender.shortLabel)
                            .font(.caption.bold())
                            .foregroundStyle(custom != nil ? Color.secondary : colorFor(gender))
                        Text(custom?.full ?? gender.label)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 70, alignment: .leading)
                    .padding(.leading, 6)

                    ForEach(cases) { c in
                        Text(selected.cells[gender]?[c] ?? "—")
                            .font(.callout.monospaced())
                            .frame(maxWidth: .infinity)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.vertical, 10)
                .background(idx % 2 == 0 ? Color.clear : Color.secondary.opacity(0.05))
                Divider()
            }
        }
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func colorFor(_ g: DeclensionGender) -> Color {
        switch g {
        case .masculine: return .blue
        case .feminine: return .red
        case .neuter: return .green
        case .plural: return .purple
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notas").font(.subheadline.bold()).foregroundStyle(.secondary)
            ForEach(Array(selected.notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(note).font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color.yellow.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    NavigationStack { DeclensionTablesView() }
}
