"""Classifica um livro a partir das primeiras páginas via Gemini.

Output: BookMetadata com type, title, author, level_cefr opcional, language.
"""

from __future__ import annotations

import logging
from typing import Literal

from pydantic import BaseModel, Field

from . import gemini
from .extract import ExtractedDocument

logger = logging.getLogger(__name__)


BookType = Literal["grammar", "workbook", "dictionary", "reader", "other"]
CEFRLevel = Literal["A1", "A2", "B1", "B2", "C1", "C2"]


class BookMetadata(BaseModel):
    type: BookType = Field(description="Tipo do livro")
    title: str = Field(description="Título do livro")
    author: str | None = Field(default=None, description="Autor(es) do livro")
    level_cefr: CEFRLevel | None = Field(
        default=None,
        description="Nível CEFR alvo do livro, se aplicável (A1-C2)",
    )
    language: str = Field(
        default="de",
        description="Idioma principal do livro (código ISO, ex: de, pt, en)",
    )
    bilingual: bool = Field(
        default=False,
        description="Verdadeiro se o livro é bilíngue (ex: dicionário PT-DE)",
    )
    summary: str = Field(
        default="",
        description="Resumo de 1-2 frases sobre o conteúdo e abordagem do livro",
    )


SYSTEM_PROMPT = """\
Você é um classificador de materiais de aprendizado de alemão. Receberá as
primeiras páginas extraídas de um PDF e deve retornar JSON com:
- type: um de [grammar, workbook, dictionary, reader, other]
  * grammar: livro-texto de gramática (Hammer's, Duden, Schaum's...)
  * workbook: cadernos de exercícios, Übungsbuch, Arbeitsbuch
  * dictionary: dicionários (DE-DE, DE-PT, DE-EN, Wörterbuch)
  * reader: leitores graduados, contos, romances, antologias
  * other: qualquer outro tipo
- title, author quando identificáveis
- level_cefr: A1, A2, B1, B2, C1 ou C2 se o livro indicar nível (capa, prefácio)
- language: idioma principal de instrução (de, pt, en); se for dicionário bilíngue,
  use o idioma de instrução
- bilingual: true se houver tradução para outro idioma no corpo do material
- summary: 1-2 frases descrevendo conteúdo e abordagem

Responda APENAS o JSON estruturado.
"""


def classify_book(doc: ExtractedDocument, *, first_n_pages: int = 10) -> BookMetadata:
    """Classifica um documento extraído via Gemini structured output."""
    sample = doc.first_n_pages_text(first_n_pages)
    if not sample.strip():
        # Fallback: livro só com imagens e OCR falhou. Marca como "other".
        logger.warning("Sem texto extraído de %s; classificando como 'other'", doc.source_path.name)
        return BookMetadata(
            type="other",
            title=doc.source_path.stem,
            summary="Não foi possível extrair texto do PDF.",
        )

    prompt = (
        f"Nome do arquivo: {doc.source_path.name}\n"
        f"Páginas analisadas: {min(first_n_pages, doc.page_count)} de {doc.page_count}\n"
        f"Primeira parte do texto extraído:\n\n---\n{sample[:8000]}\n---"
    )

    meta = gemini.generate_structured(
        prompt,
        BookMetadata,
        system_instruction=SYSTEM_PROMPT,
        temperature=0.2,
    )

    # Sanity check: se o título veio vazio, usa o nome do arquivo
    if not meta.title.strip():
        meta.title = doc.source_path.stem

    return meta
