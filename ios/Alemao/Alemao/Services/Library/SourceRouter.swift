import Foundation

/// Decide a hierarquia de fontes a usar por feature.
/// Hierarquia configurável (futuro): por enquanto define defaults sensatos.
enum FeatureSlot {
    case grammar           // explicações gramaticais
    case reading           // textos para leitura
    case vocabLookup       // tap-to-translate
    case writingCorrection // correção de escrita
    case freeQuestion      // "pergunte ao tutor"
}

enum ContentSource: String, CaseIterable {
    case bundleLibrary   // library.sqlite + dictionary.sqlite
    case publicLive      // DW news, etc (futuro)
    case llmOnly         // geração pura, sem retrieval
}

struct SourceRouter {
    /// Ordem de preferência por slot.
    func sources(for slot: FeatureSlot) -> [ContentSource] {
        switch slot {
        case .grammar:           return [.bundleLibrary, .llmOnly]
        case .reading:           return [.bundleLibrary, .publicLive, .llmOnly]
        case .vocabLookup:       return [.bundleLibrary, .publicLive, .llmOnly]
        case .writingCorrection: return [.bundleLibrary, .llmOnly]
        case .freeQuestion:      return [.bundleLibrary, .llmOnly]
        }
    }
}
