import SwiftUI

/// Mostra tabela de conjugação de um verbo: 3 tempos × 6 pessoas + Perfekt + Imperativ.
struct ConjugationTableView: View {
    let conjugation: VerbConjugation
    @State private var highlighted: VerbConjugation.Person? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            tableSection(tense: .praesens)
            tableSection(tense: .praeteritum)
            tableSection(tense: .konjunktivII)

            perfektSection
            imperativSection

            if !conjugation.examples.isEmpty {
                examplesSection
            }

            if let notes = conjugation.notes_pt, !notes.isEmpty {
                notesSection(notes)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conjugation.infinitive)
                    .font(.title.bold())
                Spacer()
                if conjugation.is_irregular {
                    Text("irregular")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(Capsule())
                }
                if conjugation.is_separable {
                    Text("separável")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2))
                        .clipShape(Capsule())
                }
                if conjugation.is_reflexive {
                    Text("reflexivo")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.pink.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            Text(conjugation.translation_pt)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func tableSection(tense: VerbConjugation.Tense) -> some View {
        let forms = conjugation.forms(for: tense)
        VStack(alignment: .leading, spacing: 6) {
            Text(tense.label)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(VerbConjugation.Person.allCases) { p in
                    HStack {
                        Text(p.label)
                            .frame(width: 80, alignment: .leading)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                        Text(forms.form(for: p))
                            .font(.callout)
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(highlighted == p ? Color.accentColor.opacity(0.12) : Color.clear)
                    Divider()
                }
            }
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var perfektSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Perfekt")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text("aux:")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                Text(conjugation.perfekt_aux)
                    .font(.callout.bold())
                    .foregroundStyle(conjugation.perfekt_aux == "sein" ? .red : .blue)
                Text("+")
                    .foregroundStyle(.tertiary)
                Text(conjugation.partizip_ii)
                    .font(.callout.italic())
                Spacer()
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Exemplo: \(perfektExample)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var perfektExample: String {
        let aux = conjugation.perfekt_aux
        let auxIch = aux == "haben" ? "habe" : "bin"
        return "Ich \(auxIch) \(conjugation.partizip_ii)."
    }

    @ViewBuilder
    private var imperativSection: some View {
        if conjugation.imperativ_du != nil
            || conjugation.imperativ_ihr != nil
            || conjugation.imperativ_sie != nil
        {
            VStack(alignment: .leading, spacing: 6) {
                Text("Imperativ")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    if let du = conjugation.imperativ_du {
                        Text("du → \(du)").font(.callout)
                    }
                    if let ihr = conjugation.imperativ_ihr {
                        Text("ihr → \(ihr)").font(.callout)
                    }
                    if let sie = conjugation.imperativ_sie {
                        Text("Sie → \(sie)").font(.callout)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Exemplos").font(.subheadline.bold()).foregroundStyle(.secondary)
            ForEach(Array(conjugation.examples.enumerated()), id: \.offset) { _, ex in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.de).font(.callout)
                    if let pt = ex.pt {
                        Text(pt).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Observação").font(.subheadline.bold()).foregroundStyle(.secondary)
            Text(notes)
                .font(.caption)
                .padding(8)
                .background(Color.yellow.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
