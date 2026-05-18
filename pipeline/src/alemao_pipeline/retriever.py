"""Retriever híbrido (FTS5 + cosine) para validar o RAG do lado Python.

A mesma lógica será portada para Swift no app iOS. Este módulo serve como:
1. Referência viva do algoritmo de retrieval
2. Ferramenta de debug e qualidade — `python -m alemao_pipeline retrieve "<query>"`
3. Base para o gerador de seed lessons (que precisa fazer retrieval por tópico)
"""

from __future__ import annotations

import math
import sqlite3
from dataclasses import dataclass

from . import config, db, gemini


@dataclass
class Hit:
    chunk_id: str
    book_id: str
    book_title: str
    section_title: str | None
    page_start: int
    page_end: int
    text: str
    score: float  # score final RRF
    fts_rank: int | None = None
    dense_rank: int | None = None


def _cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b, strict=False))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return dot / (na * nb) if na > 0 and nb > 0 else 0.0


def fts_search(conn: sqlite3.Connection, query: str, *, limit: int = 20) -> list[tuple[str, float]]:
    """Busca FTS5. Retorna [(chunk_id, bm25_score), ...] em ordem de relevância."""
    # FTS5 usa MATCH syntax. Escapamos aspas duplas e tokenizamos termos comuns
    # para criar uma query OR/AND razoável. Para simplicidade, usamos OR.
    tokens = [t for t in query.split() if t.isalnum() or any(c.isalnum() for c in t)]
    if not tokens:
        return []
    fts_query = " OR ".join(f'"{t}"' for t in tokens)
    try:
        rows = conn.execute(
            """
            SELECT c.id, bm25(chunks_fts) AS rank_score
            FROM chunks_fts
            JOIN chunks c ON c.rowid = chunks_fts.rowid
            WHERE chunks_fts MATCH ?
            ORDER BY rank_score LIMIT ?
            """,
            (fts_query, limit),
        ).fetchall()
    except sqlite3.OperationalError:
        # Query inválida pra FTS — retorna vazio
        return []
    # bm25 retorna scores negativos onde menor é melhor → invertemos
    return [(r["id"], -r["rank_score"]) for r in rows]


def dense_search(
    conn: sqlite3.Connection,
    query_vector: list[float],
    *,
    limit: int = 20,
) -> list[tuple[str, float]]:
    """Busca por cosseno em todos os chunks com embedding.

    Versão força-bruta em Python — adequada para até ~10k chunks. O Swift no iOS
    usará sqlite-vec compilado quando disponível. Para o pipeline Python, basta.
    """
    rows = conn.execute(
        "SELECT id, embedding FROM chunks WHERE embedding IS NOT NULL"
    ).fetchall()
    scored: list[tuple[str, float]] = []
    for r in rows:
        vec = db.decode_embedding(r["embedding"])
        scored.append((r["id"], _cosine(query_vector, vec)))
    scored.sort(key=lambda x: x[1], reverse=True)
    return scored[:limit]


def reciprocal_rank_fusion(
    *rankings: list[tuple[str, float]],
    k: int = 60,
    limit: int = 8,
) -> list[tuple[str, float, dict[int, int]]]:
    """RRF: combina múltiplas listas ranqueadas em uma única ordem.

    score(c) = sum over rankings of 1 / (k + rank_in_ranking)

    Args:
        rankings: cada ranking é uma lista [(id, score), ...] já em ordem.
        k: constante RRF (60 é o default da literatura).
        limit: quantos resultados retornar.

    Returns:
        Lista de (chunk_id, score_rrf, {ranking_idx: position_1based}).
    """
    fused: dict[str, float] = {}
    positions: dict[str, dict[int, int]] = {}
    for r_idx, ranking in enumerate(rankings):
        for pos, (cid, _) in enumerate(ranking, start=1):
            fused[cid] = fused.get(cid, 0.0) + 1.0 / (k + pos)
            positions.setdefault(cid, {})[r_idx] = pos

    ordered = sorted(fused.items(), key=lambda x: x[1], reverse=True)[:limit]
    return [(cid, score, positions[cid]) for cid, score in ordered]


def retrieve(
    query: str,
    *,
    limit: int = 8,
    fts_pool: int = 20,
    dense_pool: int = 20,
    library_path: str | None = None,
) -> list[Hit]:
    """Pipeline completa: query → FTS + dense → RRF → Hits enriquecidos."""
    conn = db.connect(library_path or str(config.library_db_path()))

    # 1. FTS
    fts = fts_search(conn, query, limit=fts_pool)

    # 2. Dense
    query_vecs = gemini.embed_batch([query], task_type="RETRIEVAL_QUERY")
    if not query_vecs:
        return []
    dense = dense_search(conn, query_vecs[0], limit=dense_pool)

    # 3. RRF
    fused = reciprocal_rank_fusion(fts, dense, limit=limit)

    # 4. Buscar metadata dos chunks vencedores
    ids = [c for c, _, _ in fused]
    if not ids:
        return []
    placeholders = ",".join("?" for _ in ids)
    meta_rows = conn.execute(
        f"""
        SELECT c.id, c.book_id, c.section_title, c.page_start, c.page_end, c.text,
               b.title AS book_title
        FROM chunks c JOIN books b ON b.id = c.book_id
        WHERE c.id IN ({placeholders})
        """,
        ids,
    ).fetchall()
    meta_by_id = {r["id"]: r for r in meta_rows}

    hits: list[Hit] = []
    for cid, score, positions in fused:
        m = meta_by_id.get(cid)
        if not m:
            continue
        hits.append(
            Hit(
                chunk_id=cid,
                book_id=m["book_id"],
                book_title=m["book_title"],
                section_title=m["section_title"],
                page_start=m["page_start"],
                page_end=m["page_end"],
                text=m["text"],
                score=score,
                fts_rank=positions.get(0),
                dense_rank=positions.get(1),
            )
        )
    conn.close()
    return hits
