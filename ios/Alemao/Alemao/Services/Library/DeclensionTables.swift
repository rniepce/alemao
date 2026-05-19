import Foundation

/// Tabelas de declinação alemãs (hardcoded, deterministas — não precisam Gemini).
///
/// Cobertura:
/// - 4 casos: Nominativ, Akkusativ, Dativ, Genitiv
/// - Cada categoria tem 3 gêneros (m/f/n) + plural quando aplicável
enum DeclensionCase: String, CaseIterable, Identifiable {
    case nominativ, akkusativ, dativ, genitiv
    var id: String { rawValue }
    var label: String {
        switch self {
        case .nominativ: return "Nominativ"
        case .akkusativ: return "Akkusativ"
        case .dativ: return "Dativ"
        case .genitiv: return "Genitiv"
        }
    }
    var shortLabel: String {
        switch self {
        case .nominativ: return "Nom"
        case .akkusativ: return "Akk"
        case .dativ: return "Dat"
        case .genitiv: return "Gen"
        }
    }
    var question: String {
        switch self {
        case .nominativ: return "Wer? Was?"
        case .akkusativ: return "Wen? Was?"
        case .dativ: return "Wem?"
        case .genitiv: return "Wessen?"
        }
    }
}

enum DeclensionGender: String, CaseIterable, Identifiable {
    case masculine = "m", feminine = "f", neuter = "n", plural = "pl"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .masculine: return "Masculino"
        case .feminine: return "Feminino"
        case .neuter: return "Neutro"
        case .plural: return "Plural"
        }
    }
    var shortLabel: String {
        switch self {
        case .masculine: return "der"
        case .feminine: return "die"
        case .neuter: return "das"
        case .plural: return "pl."
        }
    }
}

/// Uma tabela de declinação: nome + linhas indexadas por gênero/caso.
struct DeclensionTable: Identifiable {
    let id: String
    let title: String
    let summary: String
    /// `[gender][case] -> forma`
    let cells: [DeclensionGender: [DeclensionCase: String]]
    /// Notas extras (regras especiais)
    let notes: [String]
}

enum DeclensionTables {
    static let all: [DeclensionTable] = [
        definiteArticle,
        indefiniteArticle,
        possessiveMein,
        personalPronouns,
        demonstrativeDieser,
        adjectiveWeak,
        adjectiveMixed,
        adjectiveStrong,
        nDeklination,
    ]

    /// der/die/das/die (artigo definido)
    static let definiteArticle = DeclensionTable(
        id: "definite_article",
        title: "Artigos Definidos",
        summary: "der / die / das + plural die — declinação dos artigos definidos.",
        cells: [
            .masculine: [.nominativ: "der", .akkusativ: "den", .dativ: "dem", .genitiv: "des"],
            .feminine:  [.nominativ: "die", .akkusativ: "die", .dativ: "der", .genitiv: "der"],
            .neuter:    [.nominativ: "das", .akkusativ: "das", .dativ: "dem", .genitiv: "des"],
            .plural:    [.nominativ: "die", .akkusativ: "die", .dativ: "den", .genitiv: "der"],
        ],
        notes: [
            "Masculino e Neutro têm formas iguais em Nominativ/Akkusativ? Não — apenas Neutro tem (das=das). Masculino muda (der→den).",
            "Genitiv singular m/n acompanha -s ou -es no substantivo: des Mannes, des Kindes.",
            "Dativ plural acompanha -n no substantivo: den Kindern, den Männern.",
        ]
    )

    /// ein/eine/ein (artigo indefinido) e kein (mesma declinação)
    static let indefiniteArticle = DeclensionTable(
        id: "indefinite_article",
        title: "Artigos Indefinidos / kein",
        summary: "ein / eine / ein. Plural não existe — usa-se 'keine' para negar plural.",
        cells: [
            .masculine: [.nominativ: "ein", .akkusativ: "einen", .dativ: "einem", .genitiv: "eines"],
            .feminine:  [.nominativ: "eine", .akkusativ: "eine", .dativ: "einer", .genitiv: "einer"],
            .neuter:    [.nominativ: "ein", .akkusativ: "ein", .dativ: "einem", .genitiv: "eines"],
            .plural:    [.nominativ: "keine", .akkusativ: "keine", .dativ: "keinen", .genitiv: "keiner"],
        ],
        notes: [
            "'ein/eine/ein' não tem plural. Para plural, use 'keine' (negação) ou nenhum artigo.",
            "kein/keine/kein segue exatamente este mesmo padrão.",
            "Pronomes possessivos (mein, dein, sein, ihr, unser, euer, Ihr) também seguem este padrão.",
        ]
    )

    /// mein/meine/mein — exemplo de possessivo (todos seguem o mesmo padrão de ein-)
    static let possessiveMein = DeclensionTable(
        id: "possessive_mein",
        title: "Pronomes Possessivos (mein)",
        summary: "Padrão de declinação para mein, dein, sein, ihr, unser, euer, Ihr.",
        cells: [
            .masculine: [.nominativ: "mein", .akkusativ: "meinen", .dativ: "meinem", .genitiv: "meines"],
            .feminine:  [.nominativ: "meine", .akkusativ: "meine", .dativ: "meiner", .genitiv: "meiner"],
            .neuter:    [.nominativ: "mein", .akkusativ: "mein", .dativ: "meinem", .genitiv: "meines"],
            .plural:    [.nominativ: "meine", .akkusativ: "meine", .dativ: "meinen", .genitiv: "meiner"],
        ],
        notes: [
            "Substitua 'mein' por: dein (teu), sein (dele), ihr (dela/deles), unser (nosso), euer (vosso), Ihr (de você formal).",
            "ATENÇÃO: 'unser' e 'euer' frequentemente perdem o 'e' final antes de sufixo: 'unseren' → 'unsren' (coloquial).",
            "Em frases com substantivo, o pronome possessivo concorda com o GÊNERO E NÚMERO do substantivo possuído (não do possuidor).",
        ]
    )

    /// Pronomes pessoais — declinação completa
    static let personalPronouns = DeclensionTable(
        id: "personal_pronouns",
        title: "Pronomes Pessoais",
        summary: "ich / du / er / sie / es / wir / ihr / sie/Sie — em todos os 4 casos.",
        cells: [
            // Hack: usamos masculine=1ª pessoa sg, feminine=2ª pessoa sg, neuter=3ª pessoa sg, plural=3ª pessoa plural
            // Mas isso conflita. Vou usar uma estrutura ad-hoc dentro da view.
            // Por ora, marcamos com formato linha-única: "ich/mich/mir/meiner" etc.
            .masculine: [.nominativ: "ich", .akkusativ: "mich", .dativ: "mir", .genitiv: "meiner"],
            .feminine:  [.nominativ: "du",  .akkusativ: "dich", .dativ: "dir", .genitiv: "deiner"],
            .neuter:    [.nominativ: "er/sie/es", .akkusativ: "ihn/sie/es", .dativ: "ihm/ihr/ihm", .genitiv: "seiner/ihrer/seiner"],
            .plural:    [.nominativ: "wir/ihr/sie", .akkusativ: "uns/euch/sie", .dativ: "uns/euch/ihnen", .genitiv: "unser/euer/ihrer"],
        ],
        notes: [
            "Sie formal (qualquer pessoa, singular ou plural) usa sempre o pronome de 3ª pessoa plural: Sie/Sie/Ihnen.",
            "Formas de Genitiv (meiner, deiner, ihrer) são raras em alemão moderno — quase só literário.",
            "Pronomes pessoais SEMPRE precedem substantivos no campo central: 'Er hat es mir gegeben' (não 'Er hat mir es...').",
        ]
    )

    /// dieser/diese/dieses — pronome demonstrativo, declina como der/die/das
    static let demonstrativeDieser = DeclensionTable(
        id: "demonstrative_dieser",
        title: "Demonstrativos (dieser)",
        summary: "dieser / diese / dieses — declina como o artigo definido (der/die/das).",
        cells: [
            .masculine: [.nominativ: "dieser", .akkusativ: "diesen", .dativ: "diesem", .genitiv: "dieses"],
            .feminine:  [.nominativ: "diese",  .akkusativ: "diese",  .dativ: "dieser", .genitiv: "dieser"],
            .neuter:    [.nominativ: "dieses", .akkusativ: "dieses", .dativ: "diesem", .genitiv: "dieses"],
            .plural:    [.nominativ: "diese",  .akkusativ: "diese",  .dativ: "diesen", .genitiv: "dieser"],
        ],
        notes: [
            "Mesmo padrão para: jeder (cada), jener (aquele), welcher (qual), mancher (alguns), solcher (tal).",
            "Note que adjetivos APÓS dieser/jeder usam declinação FRACA (ver tabela 'Adjetivos com Artigo Definido').",
        ]
    )

    /// Adjetivos — declinação FRACA (após der/die/das, dieser, jener...)
    static let adjectiveWeak = DeclensionTable(
        id: "adjective_weak",
        title: "Adjetivos: Declinação FRACA",
        summary: "Após artigo definido (der/die/das) ou dieser/jeder. Terminações: -e ou -en.",
        cells: [
            .masculine: [.nominativ: "-e", .akkusativ: "-en", .dativ: "-en", .genitiv: "-en"],
            .feminine:  [.nominativ: "-e", .akkusativ: "-e",  .dativ: "-en", .genitiv: "-en"],
            .neuter:    [.nominativ: "-e", .akkusativ: "-e",  .dativ: "-en", .genitiv: "-en"],
            .plural:    [.nominativ: "-en",.akkusativ: "-en", .dativ: "-en", .genitiv: "-en"],
        ],
        notes: [
            "Regra de bolso: 5 'islands' levam -e (Nominativ todos m/f/n + Akkusativ f/n). Todo o resto: -en.",
            "Exemplo: der gute Mann, die gute Frau, das gute Kind, die guten Kinder (plural).",
            "Após: der, die, das, den, dem, des, dieser, jener, jeder, mancher, welcher, solcher, alle.",
        ]
    )

    /// Adjetivos — declinação MISTA (após ein/eine/ein, kein, mein, dein...)
    static let adjectiveMixed = DeclensionTable(
        id: "adjective_mixed",
        title: "Adjetivos: Declinação MISTA",
        summary: "Após ein/eine/ein, kein, possessivos. Mistura de -e/-er/-es e -en.",
        cells: [
            .masculine: [.nominativ: "-er", .akkusativ: "-en", .dativ: "-en", .genitiv: "-en"],
            .feminine:  [.nominativ: "-e",  .akkusativ: "-e",  .dativ: "-en", .genitiv: "-en"],
            .neuter:    [.nominativ: "-es", .akkusativ: "-es", .dativ: "-en", .genitiv: "-en"],
            .plural:    [.nominativ: "-en", .akkusativ: "-en", .dativ: "-en", .genitiv: "-en"],
        ],
        notes: [
            "Quando o artigo (ein, kein, mein) NÃO mostra gênero claro, o adjetivo precisa mostrar: '-er' (m), '-es' (n).",
            "Exemplo: ein guter Mann, eine gute Frau, ein gutes Kind, meine guten Kinder.",
            "Acusativo masculino: einen guten Mann (o 'guten' vê o '-en' do 'einen', vira fraca).",
        ]
    )

    /// Adjetivos — declinação FORTE (sem artigo)
    static let adjectiveStrong = DeclensionTable(
        id: "adjective_strong",
        title: "Adjetivos: Declinação FORTE",
        summary: "Sem artigo. O adjetivo assume as terminações dos artigos definidos (exceto Genitiv).",
        cells: [
            .masculine: [.nominativ: "-er", .akkusativ: "-en", .dativ: "-em", .genitiv: "-en"],
            .feminine:  [.nominativ: "-e",  .akkusativ: "-e",  .dativ: "-er", .genitiv: "-er"],
            .neuter:    [.nominativ: "-es", .akkusativ: "-es", .dativ: "-em", .genitiv: "-en"],
            .plural:    [.nominativ: "-e",  .akkusativ: "-e",  .dativ: "-en", .genitiv: "-er"],
        ],
        notes: [
            "Exemplo: 'Guter Wein ist teuer.' (vinho bom é caro) — sem artigo, adjetivo carrega a 'tag' do gênero.",
            "ATENÇÃO Genitiv m/n: termina em -en (não -es) porque o substantivo já carrega -es: 'guten Weines'.",
            "Comum com: numerais (drei rote Äpfel), expressões partitivas (etwas/wenig/viel/genug + adj forte).",
        ]
    )

    /// N-Deklination — substantivos masculinos fracos
    static let nDeklination = DeclensionTable(
        id: "n_deklination",
        title: "N-Deklination (substantivos fracos)",
        summary: "Substantivos masculinos que terminam em -en/-n em todos os casos exceto Nominativ singular.",
        cells: [
            // singular masculine + plural — só uso m e plural
            .masculine: [.nominativ: "Mensch",   .akkusativ: "Menschen", .dativ: "Menschen", .genitiv: "Menschen"],
            .plural:    [.nominativ: "Menschen", .akkusativ: "Menschen", .dativ: "Menschen", .genitiv: "Menschen"],
        ],
        notes: [
            "Substantivos típicos: Mensch, Junge, Herr (Herrn singular!), Kollege, Student, Polizist, Tourist, Präsident.",
            "Pegadinha: 'mit dem Mann' (regular) MAS 'mit dem Studenten' (n-deklination — não 'Student').",
            "No singular Akkusativ/Dativ/Genitiv: adicione -en (ou -n se já termina em -e como Junge → Jungen).",
            "Outros: terminam em -ist, -ent, -ant, -log, -nom, ou denotam pessoas/animais machos.",
        ]
    )
}
