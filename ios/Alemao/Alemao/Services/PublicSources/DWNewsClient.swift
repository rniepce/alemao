import Foundation

/// Cliente para o feed RSS "Nachrichten leicht" da Deutsche Welle —
/// notícias diárias em alemão simplificado (~B1).
///
/// Feed RSS oficial: https://rss.dw.com/rdf/rss-de-news_easy
/// Sem auth, sem rate limit (uso normal). Atualiza ~1×/dia.
///
/// Retorna lista de `DWNewsItem` com título + descrição curta + link + data.
final class DWNewsClient {
    static let shared = DWNewsClient()

    private let session: URLSession
    private let feedURL: URL

    init(session: URLSession = .shared) {
        self.session = session
        self.feedURL = URL(string: "https://rss.dw.com/rdf/rss-de-news_easy")!
    }

    enum DWError: LocalizedError {
        case network(Error)
        case parsing(String)

        var errorDescription: String? {
            switch self {
            case .network(let e): return "DW: \(e.localizedDescription)"
            case .parsing(let m): return "DW parser: \(m)"
            }
        }
    }

    func fetch() async throws -> [DWNewsItem] {
        var request = URLRequest(url: feedURL, timeoutInterval: 12)
        request.setValue("Alemao/0.1 (https://github.com/rniepce/alemao)", forHTTPHeaderField: "User-Agent")
        let data: Data
        do {
            let (responseData, _) = try await session.data(for: request)
            data = responseData
        } catch {
            throw DWError.network(error)
        }
        let parser = RSSParser()
        guard let items = parser.parse(data) else {
            throw DWError.parsing("XMLParser falhou")
        }
        return items
    }
}

struct DWNewsItem: Identifiable, Hashable {
    let id: String           // link como identificador único
    let title: String
    let description: String
    let link: String
    let pubDate: Date?
}

// MARK: - Parser

/// Parser SAX simples para RDF/RSS (DW usa RDF, mas o esquema é idêntico em campos básicos).
private final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [DWNewsItem] = []
    private var inItem: Bool = false
    private var currentElement: String = ""
    private var currentTitle: String = ""
    private var currentDescription: String = ""
    private var currentLink: String = ""
    private var currentDate: String = ""

    func parse(_ data: Data) -> [DWNewsItem]? {
        let xml = XMLParser(data: data)
        xml.delegate = self
        guard xml.parse() else { return nil }
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        currentElement = elementName.lowercased()
        if currentElement == "item" {
            inItem = true
            currentTitle = ""
            currentDescription = ""
            currentLink = ""
            currentDate = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch currentElement {
        case "title":       currentTitle += string
        case "description": currentDescription += string
        case "link":        currentLink += string
        case "dc:date", "pubdate", "date":
            currentDate += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.lowercased() == "item" {
            let pubDate = parseDate(currentDate.trimmingCharacters(in: .whitespacesAndNewlines))
            let item = DWNewsItem(
                id: currentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                description: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                link: currentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                pubDate: pubDate
            )
            if !item.title.isEmpty {
                items.append(item)
            }
            inItem = false
        }
        currentElement = ""
    }

    private func parseDate(_ s: String) -> Date? {
        // dc:date tipicamente em ISO 8601: 2024-01-15T10:30:00Z
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        // pubDate tipicamente RFC 822
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return rfc.date(from: s)
    }
}
