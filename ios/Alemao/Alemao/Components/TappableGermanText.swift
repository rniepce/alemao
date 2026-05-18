import SwiftUI

/// Renderiza texto alemão onde cada token (palavra) é tocável.
/// Tocar abre `WordLookupPopup`.
///
/// Não usamos NSAttributedString com links porque queremos um sheet customizado.
/// Em vez disso, splittamos o texto e renderizamos cada palavra como botão.
struct TappableGermanText: View {
    let text: String
    let sourceChunkId: String?
    let sourceBookId: String?
    let sourcePage: Int?

    @State private var tappedWord: TappedWord?

    /// Identifiable para sheet(item:).
    struct TappedWord: Identifiable {
        let id = UUID()
        let word: String
        let sentence: String
    }

    init(
        _ text: String,
        sourceChunkId: String? = nil,
        sourceBookId: String? = nil,
        sourcePage: Int? = nil
    ) {
        self.text = text
        self.sourceChunkId = sourceChunkId
        self.sourceBookId = sourceBookId
        self.sourcePage = sourcePage
    }

    var body: some View {
        TokenFlow(tokens: tokens, onTap: handleTap)
            .sheet(item: $tappedWord) { tw in
                WordLookupPopup(
                    word: tw.word,
                    contextSentence: tw.sentence,
                    sourceChunkId: sourceChunkId,
                    sourceBookId: sourceBookId,
                    sourcePage: sourcePage
                )
                .presentationDetents([.medium, .large])
            }
    }

    private var tokens: [Token] {
        Tokenizer.tokenize(text)
    }

    private func handleTap(_ token: Token) {
        guard token.isWord else { return }
        // Encontra a frase contendo este token (split por . ! ?)
        let sentence = Tokenizer.containingSentence(of: token, in: text) ?? text
        tappedWord = TappedWord(word: token.value, sentence: sentence)
    }
}

// MARK: - Tokenizer

struct Token: Hashable {
    let value: String       // texto exato
    let isWord: Bool        // true se for token alfabético/numérico tocável
    let range: Range<String.Index>
}

enum Tokenizer {
    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = text.startIndex
        while current < text.endIndex {
            let c = text[current]
            if c.isLetter || c.isNumber {
                // Token de palavra
                let start = current
                while current < text.endIndex,
                      text[current].isLetter || text[current].isNumber || text[current] == "-" {
                    current = text.index(after: current)
                }
                tokens.append(Token(
                    value: String(text[start..<current]),
                    isWord: true,
                    range: start..<current
                ))
            } else {
                // Whitespace, pontuação, etc
                let start = current
                current = text.index(after: current)
                tokens.append(Token(
                    value: String(text[start..<current]),
                    isWord: false,
                    range: start..<current
                ))
            }
        }
        return tokens
    }

    /// Retorna a frase (separada por . ! ?) que contém o range do token.
    static func containingSentence(of token: Token, in text: String) -> String? {
        // Acha o terminador anterior ao token
        var start = text.startIndex
        var cursor = text.startIndex
        while cursor < token.range.lowerBound {
            let c = text[cursor]
            if c == "." || c == "!" || c == "?" || c == "\n" {
                start = text.index(after: cursor)
            }
            cursor = text.index(after: cursor)
        }
        // Acha o próximo terminador após o token
        var end = text.endIndex
        cursor = token.range.upperBound
        while cursor < text.endIndex {
            let c = text[cursor]
            if c == "." || c == "!" || c == "?" || c == "\n" {
                end = cursor
                break
            }
            cursor = text.index(after: cursor)
        }
        // Skip leading whitespace
        while start < end, text[start].isWhitespace {
            start = text.index(after: start)
        }
        return String(text[start..<end]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Layout de tokens em linhas

private struct TokenFlow: View {
    let tokens: [Token]
    let onTap: (Token) -> Void

    var body: some View {
        // Usa Text com inline buttons via concatenação não funciona com taps individuais.
        // Solução: cada token como Text com onTapGesture, juntando via concatenação visual.
        // Para texto longo é mais simples renderizar como flow de Texts (LazyVStack de linhas).
        // Vamos usar a abordagem nativa: AttributedString com custom attributes não suporta
        // tap por palavra facilmente. Usamos um único Text e identificamos palavra via
        // SpatialTapGesture + posição. Mas isso é frágil.
        //
        // Abordagem pragmática: usar um Layout que quebra em linhas, com cada palavra
        // como elemento clicável separado.
        WrapHStack(tokens: tokens, onTap: onTap)
    }
}

/// Layout simples que quebra tokens em linhas.
private struct WrapHStack: View {
    let tokens: [Token]
    let onTap: (Token) -> Void

    var body: some View {
        FlowLayout(spacing: 0) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                if token.isWord {
                    Text(token.value)
                        .foregroundStyle(.primary)
                        .onTapGesture { onTap(token) }
                } else {
                    Text(token.value).foregroundStyle(.primary)
                }
            }
        }
    }
}

/// Custom Layout para flow horizontal com quebra de linha.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowMaxHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth + size.width > containerWidth, rowWidth > 0 {
                height += rowMaxHeight
                rowWidth = 0
                rowMaxHeight = 0
            }
            rowWidth += size.width
            rowMaxHeight = max(rowMaxHeight, size.height)
        }
        height += rowMaxHeight
        return CGSize(width: containerWidth.isFinite ? containerWidth : rowWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowMaxHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowMaxHeight
                rowMaxHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowMaxHeight = max(rowMaxHeight, size.height)
        }
    }
}
