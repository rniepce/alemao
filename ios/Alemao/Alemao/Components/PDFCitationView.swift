import PDFKit
import SwiftUI

/// Visualiza um PDF bundleado em uma página específica.
///
/// Usado para abrir citações: tocar em "Hammer's, p. 142" → mostra a página 142
/// do PDF.
///
/// Resolução: o PDF é procurado em `Resources/Books/<filePath>`. Se o PDF não
/// estiver bundleado (App Store build, sem `--with-pdfs`), uma mensagem
/// explicativa é mostrada.
struct PDFCitationView: View {
    let bookTitle: String
    /// Nome do arquivo do PDF (de `books.file_path`), ex: "hammers-grammar.pdf"
    let filePath: String?
    let pageStart: Int
    let pageEnd: Int

    var body: some View {
        Group {
            if let url = resolvePDFURL() {
                PDFKitView(url: url, targetPage: pageStart)
                    .edgesIgnoringSafeArea(.bottom)
            } else {
                ContentUnavailableView {
                    Label("PDF não bundleado", systemImage: "doc.questionmark")
                } description: {
                    Text(
                        "O PDF de \(bookTitle) não foi incluído nesta build do app. " +
                        "Para ver as páginas originais (p. \(pageStart)\(pageEnd > pageStart ? "-\(pageEnd)" : "")), " +
                        "rode `scripts/sync_content.sh --with-pdfs` e refaça o build."
                    )
                }
                .padding()
            }
        }
        .navigationTitle(bookTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resolvePDFURL() -> URL? {
        guard let filePath, !filePath.isEmpty else { return nil }
        let baseName = (filePath as NSString).deletingPathExtension
        let ext = (filePath as NSString).pathExtension.isEmpty ? "pdf" : (filePath as NSString).pathExtension
        return Bundle.main.url(
            forResource: baseName,
            withExtension: ext,
            subdirectory: "Books"
        )
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL
    let targetPage: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(false)
        if let doc = PDFDocument(url: url) {
            view.document = doc
            // Páginas PDFKit são 0-indexed
            let zeroIndex = max(0, min(doc.pageCount - 1, targetPage - 1))
            if let page = doc.page(at: zeroIndex) {
                view.go(to: page)
            }
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        guard let doc = uiView.document else { return }
        let zeroIndex = max(0, min(doc.pageCount - 1, targetPage - 1))
        if let page = doc.page(at: zeroIndex), uiView.currentPage != page {
            uiView.go(to: page)
        }
    }
}
