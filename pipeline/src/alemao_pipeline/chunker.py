"""Chunking semântico TOC-aware para PDFs de gramática, workbooks e readers.

Estratégia:
1. Se a TOC do PDF está disponível, usamos cada entrada como uma "seção". O texto
   de uma seção vai do início da página da entrada até logo antes da próxima entrada.
2. Cada seção é depois dividida em sub-chunks de ~target_tokens tokens, com overlap.
3. Se não há TOC útil, caímos para chunking por janela deslizante baseado em
   tamanho, respeitando quebras de parágrafo quando possível.

Tokens são estimados heurísticamente como ~4 caracteres por token (suficiente
para dimensionar chunks; a contagem exata só importa pra cost estimation).
"""

from __future__ import annotations

import hashlib
import re
import uuid
from dataclasses import dataclass

from .extract import ExtractedDocument, ExtractedPage, TOCEntry

TARGET_TOKENS = 800
OVERLAP_TOKENS = 100
MIN_CHUNK_TOKENS = 50  # chunks menores que isso são mesclados com o próximo
CHARS_PER_TOKEN = 4  # estimativa grosseira pra alemão

PARAGRAPH_SPLIT = re.compile(r"\n{2,}")


@dataclass
class Chunk:
    id: str
    book_id: str
    chunk_index: int
    page_start: int
    page_end: int
    section_title: str | None
    text: str
    text_hash: str
    token_count: int


def _estimate_tokens(text: str) -> int:
    return max(1, len(text) // CHARS_PER_TOKEN)


def _page_text_map(pages: list[ExtractedPage]) -> dict[int, str]:
    return {p.page_number: p.text for p in pages}


def _slice_by_pages(pages: list[ExtractedPage], start: int, end: int) -> tuple[str, int, int]:
    """Retorna (texto_concatenado, page_start, page_end) inclusivo."""
    selected = [p for p in pages if start <= p.page_number <= end]
    if not selected:
        return "", start, end
    text = "\n\n".join(p.text for p in selected if p.text.strip())
    return text, selected[0].page_number, selected[-1].page_number


def _section_spans(
    toc: list[TOCEntry], total_pages: int
) -> list[tuple[str | None, int, int]]:
    """Calcula (título, página inicial, página final inclusivo) de cada seção da TOC.

    Usa só entradas de nível 1 e 2 para evitar fragmentação excessiva.
    """
    relevant = [e for e in toc if e.level <= 2]
    if not relevant:
        return [(None, 1, total_pages)]

    spans: list[tuple[str | None, int, int]] = []
    for i, entry in enumerate(relevant):
        end_page = relevant[i + 1].page - 1 if i + 1 < len(relevant) else total_pages
        if end_page < entry.page:
            end_page = entry.page
        spans.append((entry.title, entry.page, end_page))
    return spans


def _split_into_subchunks(
    text: str,
    *,
    target_tokens: int = TARGET_TOKENS,
    overlap_tokens: int = OVERLAP_TOKENS,
) -> list[str]:
    """Divide um texto longo em sub-chunks, tentando respeitar parágrafos."""
    target_chars = target_tokens * CHARS_PER_TOKEN
    overlap_chars = overlap_tokens * CHARS_PER_TOKEN

    if len(text) <= target_chars * 1.2:
        return [text.strip()] if text.strip() else []

    paragraphs = [p.strip() for p in PARAGRAPH_SPLIT.split(text) if p.strip()]
    chunks: list[str] = []
    buf: list[str] = []
    buf_len = 0

    for para in paragraphs:
        if buf_len + len(para) > target_chars and buf:
            chunks.append("\n\n".join(buf))
            # Inicia próximo buffer com overlap (últimos parágrafos do anterior)
            if overlap_chars > 0:
                overlap_buf: list[str] = []
                overlap_len = 0
                for prev in reversed(buf):
                    if overlap_len + len(prev) > overlap_chars:
                        break
                    overlap_buf.insert(0, prev)
                    overlap_len += len(prev)
                buf = overlap_buf
                buf_len = overlap_len
            else:
                buf = []
                buf_len = 0
        buf.append(para)
        buf_len += len(para)

    if buf:
        chunks.append("\n\n".join(buf))

    # Se um único parágrafo for monstruoso, força corte por caractere
    final: list[str] = []
    for c in chunks:
        if len(c) > target_chars * 2:
            for start in range(0, len(c), target_chars - overlap_chars):
                final.append(c[start : start + target_chars])
        else:
            final.append(c)

    return [c.strip() for c in final if c.strip()]


RawChunk = tuple[str, str | None, int, int]


def _merge_small_chunks(raw: list[RawChunk]) -> list[RawChunk]:
    """Mescla chunks consecutivos abaixo de MIN_CHUNK_TOKENS com o próximo."""
    merged: list[RawChunk] = []
    buf_text = ""
    buf_section: str | None = None
    buf_ps = 0
    buf_pe = 0

    for text, section, ps, pe in raw:
        if not buf_text:
            buf_text, buf_section, buf_ps, buf_pe = text, section, ps, pe
            continue
        if _estimate_tokens(buf_text) < MIN_CHUNK_TOKENS:
            buf_text = f"{buf_text}\n\n{text}"
            buf_pe = pe
            # mantém section do início (mais informativo)
        else:
            merged.append((buf_text, buf_section, buf_ps, buf_pe))
            buf_text, buf_section, buf_ps, buf_pe = text, section, ps, pe

    if buf_text:
        merged.append((buf_text, buf_section, buf_ps, buf_pe))
    return merged


def chunk_document(doc: ExtractedDocument, book_id: str) -> list[Chunk]:
    """Gera lista de Chunks para um documento extraído."""
    spans = _section_spans(doc.toc, doc.page_count)

    # Primeira passada: textos brutos com metadata
    raw: list[RawChunk] = []
    for section_title, p_start, p_end in spans:
        text, real_start, real_end = _slice_by_pages(doc.pages, p_start, p_end)
        if not text.strip():
            continue
        for sub in _split_into_subchunks(text):
            raw.append((sub, section_title, real_start, real_end))

    # Mescla chunks pequenos
    merged = _merge_small_chunks(raw)

    chunks: list[Chunk] = []
    for i, (text, section_title, real_start, real_end) in enumerate(merged):
        text_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()
        chunks.append(
            Chunk(
                id=str(uuid.uuid4()),
                book_id=book_id,
                chunk_index=i,
                page_start=real_start,
                page_end=real_end,
                section_title=section_title,
                text=text,
                text_hash=text_hash,
                token_count=_estimate_tokens(text),
            )
        )
    return chunks


def chunk_to_dict(c: Chunk) -> dict:
    return {
        "id": c.id,
        "book_id": c.book_id,
        "chunk_index": c.chunk_index,
        "page_start": c.page_start,
        "page_end": c.page_end,
        "section_title": c.section_title,
        "text": c.text,
        "text_hash": c.text_hash,
        "embedding": None,
        "embedding_model": None,
        "token_count": c.token_count,
    }
