"""Parser de dicionários — extrai entradas estruturadas de PDFs classificados como `dictionary`.

Estratégia:
1. Tenta extrair com regex padrões comuns:
   - "Wort  der/die/das  tradução; tradução2"
   - "Wort, m.  tradução"
   - "Headword (n.) translation"
2. Para páginas onde o regex falha (layout complexo, colunas), envia trecho para
   Gemini com prompt estruturado.

Padrões variam muito entre dicionários, então o regex serve como caminho rápido
e o LLM como fallback robusto.
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass, field

from pydantic import BaseModel, Field

from . import gemini
from .extract import ExtractedDocument

logger = logging.getLogger(__name__)


# Padrão simples: palavra (com letra maiúscula opcional para alemão), gênero opcional, traduções
# Ex: "Haus  das  casa, lar"
#     "gehen  v  ir, andar"
#     "schön  adj  bonito, belo"
ENTRY_REGEX = re.compile(
    r"""^
        (?P<headword>[A-ZÄÖÜa-zäöüß][\w\-äöüÄÖÜß]+)   # palavra
        \s+
        (?:(?P<gender>der|die|das)\s+)?              # gênero opcional
        (?:(?P<pos>v|n|adj|adv|prep|conj)\.?\s+)?    # pos opcional
        (?P<translations>[^\n]+)                      # resto da linha = traduções
    """,
    re.VERBOSE | re.MULTILINE,
)


@dataclass
class ParsedEntry:
    headword: str
    gender: str | None = None
    pos: str | None = None
    translations: list[str] = field(default_factory=list)
    examples: list[dict] = field(default_factory=list)
    notes: str | None = None
    source_page: int | None = None


class LLMEntry(BaseModel):
    headword: str = Field(description="Palavra de cabeçalho")
    gender: str | None = Field(default=None, description="der, die ou das (substantivos)")
    pos: str | None = Field(
        default=None, description="Classe gramatical (noun, verb, adj, adv, prep, conj)"
    )
    translations: list[str] = Field(default_factory=list)
    examples: list[dict] = Field(
        default_factory=list,
        description="Lista de exemplos no formato [{'de': '...', 'pt': '...'}]",
    )


class LLMEntries(BaseModel):
    entries: list[LLMEntry] = Field(default_factory=list)


LLM_SYSTEM = """\
Você é um parser de dicionários alemães. Receberá um trecho de página de
dicionário e deve extrair as entradas individuais como JSON.

Para cada entrada, identifique:
- headword: a palavra cabeçalho (sem artigo)
- gender: "der", "die" ou "das" se for substantivo, senão null
- pos: "noun", "verb", "adj", "adv", "prep", "conj" ou null
- translations: lista de traduções (separe por vírgula se vierem juntas)
- examples: lista de exemplos como [{"de": "frase alemã", "pt": "tradução"}]

Ignore cabeçalhos, números de página e notas editoriais. Se uma linha não for
uma entrada clara, pule.

Retorne {"entries": [...]}.
"""


def parse_page_regex(page_number: int, text: str) -> list[ParsedEntry]:
    """Tenta extrair entradas via regex. Retorna lista (possivelmente vazia)."""
    entries: list[ParsedEntry] = []
    for m in ENTRY_REGEX.finditer(text):
        headword = m.group("headword").strip()
        # Filtros heurísticos: pular números, cabeçalhos óbvios, palavras muito curtas
        if len(headword) < 2 or headword.isupper():
            continue
        translations_raw = m.group("translations").strip()
        translations = [t.strip() for t in re.split(r"[,;]", translations_raw) if t.strip()]
        if not translations:
            continue
        entries.append(
            ParsedEntry(
                headword=headword,
                gender=m.group("gender"),
                pos=m.group("pos"),
                translations=translations,
                source_page=page_number,
            )
        )
    return entries


def parse_page_llm(page_number: int, text: str) -> list[ParsedEntry]:
    """Fallback via Gemini para páginas com layout complexo."""
    if len(text.strip()) < 100:
        return []
    try:
        result = gemini.generate_structured(
            f"Página {page_number}:\n\n{text[:6000]}",
            LLMEntries,
            system_instruction=LLM_SYSTEM,
            temperature=0.1,
        )
    except Exception as e:
        logger.warning("LLM parse falhou na página %d: %s", page_number, e)
        return []

    return [
        ParsedEntry(
            headword=e.headword,
            gender=e.gender,
            pos=e.pos,
            translations=e.translations,
            examples=e.examples,
            source_page=page_number,
        )
        for e in result.entries
        if e.headword.strip()
    ]


def parse_dictionary(
    doc: ExtractedDocument,
    *,
    use_llm_fallback: bool = True,
    llm_min_entries_threshold: int = 5,
) -> list[ParsedEntry]:
    """Extrai entradas de um dicionário inteiro.

    Args:
        doc: documento extraído.
        use_llm_fallback: se True, usa Gemini em páginas com poucos hits via regex.
        llm_min_entries_threshold: páginas com menos de N entradas via regex são
            re-processadas pelo LLM (assumindo que regex falhou no layout).
    """
    all_entries: list[ParsedEntry] = []
    for page in doc.pages:
        regex_entries = parse_page_regex(page.page_number, page.text)
        if use_llm_fallback and len(regex_entries) < llm_min_entries_threshold:
            llm_entries = parse_page_llm(page.page_number, page.text)
            # Mescla: prefere LLM se vier mais rico
            if len(llm_entries) > len(regex_entries):
                all_entries.extend(llm_entries)
            else:
                all_entries.extend(regex_entries)
        else:
            all_entries.extend(regex_entries)

    return all_entries


def entry_to_dict_row(
    entry: ParsedEntry, *, source: str, source_book_id: str | None
) -> dict:
    return {
        "headword": entry.headword,
        "headword_lower": entry.headword.lower(),
        "gender": entry.gender,
        "pos": entry.pos,
        "translations_json": json.dumps(entry.translations, ensure_ascii=False),
        "examples_json": json.dumps(entry.examples, ensure_ascii=False),
        "notes": entry.notes,
        "source": source,
        "source_book_id": source_book_id,
        "source_page": entry.source_page,
    }
