"""Gera e persiste embeddings para chunks no library.sqlite.

Idempotente: chunks que já têm embedding com o modelo atual são pulados.
"""

from __future__ import annotations

import logging
import sqlite3
import time
from collections.abc import Iterable
from dataclasses import dataclass

from . import config, db, gemini

logger = logging.getLogger(__name__)


@dataclass
class EmbeddingStats:
    chunks_embedded: int = 0
    chunks_skipped: int = 0
    batches: int = 0
    api_errors: int = 0


def _pending_chunks(
    conn: sqlite3.Connection,
    *,
    book_id: str | None = None,
    embedding_model: str = config.EMBEDDING_MODEL,
) -> list[sqlite3.Row]:
    """Retorna chunks que ainda precisam de embedding (NULL ou modelo diferente)."""
    where = "(embedding IS NULL OR embedding_model IS NULL OR embedding_model != ?)"
    params: list = [embedding_model]
    if book_id:
        where += " AND book_id = ?"
        params.append(book_id)
    rows = conn.execute(
        f"SELECT id, text FROM chunks WHERE {where} ORDER BY rowid",
        params,
    ).fetchall()
    return rows


def _batched(items: list, size: int) -> Iterable[list]:
    for i in range(0, len(items), size):
        yield items[i : i + size]


def embed_pending(
    conn: sqlite3.Connection,
    *,
    book_id: str | None = None,
    embedding_model: str | None = None,
    batch_size: int | None = None,
    rpm: int | None = None,
) -> EmbeddingStats:
    """Embeda todos os chunks pendentes, atualizando o BLOB e o modelo.

    Aplica rate limiting simples: dorme entre batches para não exceder RPM.
    """
    model = embedding_model or config.EMBEDDING_MODEL
    bs = batch_size or config.EMBED_BATCH_SIZE
    rpm_limit = rpm or config.EMBED_RPM
    min_interval = 60.0 / max(1, rpm_limit) * bs  # segundos mínimos entre batches

    pending = _pending_chunks(conn, book_id=book_id, embedding_model=model)
    stats = EmbeddingStats(chunks_skipped=0)

    if not pending:
        logger.info("Nenhum chunk pendente de embedding (book_id=%s, model=%s)", book_id, model)
        return stats

    logger.info(
        "Embedding %d chunks em batches de %d (modelo=%s, rpm=%d)",
        len(pending),
        bs,
        model,
        rpm_limit,
    )

    last_batch_started = 0.0
    for batch in _batched(pending, bs):
        # Throttle
        elapsed = time.monotonic() - last_batch_started
        if elapsed < min_interval and last_batch_started > 0:
            time.sleep(min_interval - elapsed)
        last_batch_started = time.monotonic()

        texts = [row["text"] for row in batch]
        ids = [row["id"] for row in batch]
        try:
            vectors = gemini.embed_batch(texts, model=model)
        except Exception as e:
            logger.exception("Falha de embedding no batch: %s", e)
            stats.api_errors += 1
            continue

        if len(vectors) != len(ids):
            logger.error(
                "Mismatch: %d ids vs %d vectors no batch — pulando",
                len(ids),
                len(vectors),
            )
            stats.api_errors += 1
            continue

        rows = [
            (db.encode_embedding(vec), model, cid)
            for cid, vec in zip(ids, vectors, strict=False)
        ]
        conn.executemany(
            "UPDATE chunks SET embedding = ?, embedding_model = ? WHERE id = ?",
            rows,
        )
        conn.commit()
        stats.chunks_embedded += len(rows)
        stats.batches += 1
        logger.info(
            "Batch %d concluído (%d/%d chunks)",
            stats.batches,
            stats.chunks_embedded,
            len(pending),
        )

    return stats
