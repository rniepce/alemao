"""Schemas SQLite e funções utilitárias para library.sqlite e dictionary.sqlite.

library.sqlite:
    - books      (metadata)
    - chunks     (texto + embedding BLOB)
    - chunks_fts (full-text search, FTS5)

dictionary.sqlite:
    - entries    (palavras com gênero, traduções, exemplos)

Embeddings ficam como BLOB de float32 little-endian dentro da tabela `chunks`.
A busca por cosseno é feita via sqlite-vec quando disponível, ou força bruta em
Python como fallback (aceitável para 5-15k chunks em desktop; no iOS usaremos
sqlite-vec compilada como extensão).
"""

from __future__ import annotations

import sqlite3
import struct
from collections.abc import Iterable
from pathlib import Path
from typing import Any

try:
    import sqlite_vec
    _SQLITE_VEC_AVAILABLE = True
except ImportError:  # pragma: no cover
    _SQLITE_VEC_AVAILABLE = False


# ---------- Conexão ----------------------------------------------------------

def connect(path: Path | str, *, load_vec: bool = True) -> sqlite3.Connection:
    """Abre conexão SQLite com pragmas razoáveis e carrega sqlite-vec se disponível."""
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA synchronous = NORMAL")
    conn.execute("PRAGMA foreign_keys = ON")

    if load_vec and _SQLITE_VEC_AVAILABLE:
        try:
            conn.enable_load_extension(True)
            sqlite_vec.load(conn)
            conn.enable_load_extension(False)
        except (sqlite3.OperationalError, AttributeError):
            # Builds de Python sem suporte a load_extension (raro em macOS via uv)
            pass
    return conn


# ---------- Library DB -------------------------------------------------------

LIBRARY_SCHEMA = """
CREATE TABLE IF NOT EXISTS books (
    id              TEXT PRIMARY KEY,
    title           TEXT,
    author          TEXT,
    type            TEXT NOT NULL,  -- grammar|workbook|dictionary|reader|public
    level_cefr      TEXT,
    language        TEXT DEFAULT 'de',
    source          TEXT NOT NULL DEFAULT 'personal',  -- personal|dw|goethe|...
    file_path       TEXT,  -- relativo a Resources/Books/ no iOS; NULL se não bundleado
    file_hash       TEXT,  -- sha256 do PDF, para idempotência
    page_count      INTEGER,
    ingested_at     TEXT,
    extra_json      TEXT   -- metadata adicional do classifier
);

CREATE TABLE IF NOT EXISTS chunks (
    id              TEXT PRIMARY KEY,
    book_id         TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    chunk_index     INTEGER NOT NULL,
    page_start      INTEGER,
    page_end        INTEGER,
    section_title   TEXT,
    text            TEXT NOT NULL,
    text_hash       TEXT NOT NULL,  -- sha256 do texto, para idempotência de embeddings
    embedding       BLOB,           -- 768 float32 little-endian
    embedding_model TEXT,
    token_count     INTEGER
);

CREATE INDEX IF NOT EXISTS idx_chunks_book ON chunks(book_id);
CREATE INDEX IF NOT EXISTS idx_chunks_text_hash ON chunks(text_hash);

-- Full-text search sobre o texto dos chunks
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
    text,
    content='chunks',
    content_rowid='rowid',
    tokenize='unicode61 remove_diacritics 2'
);

-- Triggers para manter FTS5 sincronizado
CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN
    INSERT INTO chunks_fts(rowid, text) VALUES (new.rowid, new.text);
END;
CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN
    INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.rowid, old.text);
END;
CREATE TRIGGER IF NOT EXISTS chunks_au AFTER UPDATE ON chunks BEGIN
    INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.rowid, old.text);
    INSERT INTO chunks_fts(rowid, text) VALUES (new.rowid, new.text);
END;
"""


def init_library(path: Path | str) -> sqlite3.Connection:
    conn = connect(path)
    conn.executescript(LIBRARY_SCHEMA)
    conn.commit()
    return conn


# ---------- Dictionary DB ----------------------------------------------------

DICTIONARY_SCHEMA = """
CREATE TABLE IF NOT EXISTS entries (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    headword          TEXT NOT NULL,
    headword_lower    TEXT NOT NULL,
    gender            TEXT,                 -- der|die|das|NULL
    pos               TEXT,                 -- noun|verb|adj|adv|...
    translations_json TEXT NOT NULL DEFAULT '[]',  -- ["traduções", ...]
    examples_json     TEXT NOT NULL DEFAULT '[]',  -- [{de, pt?}, ...]
    notes             TEXT,
    source            TEXT NOT NULL,        -- nome do livro ou 'wiktionary' etc.
    source_book_id    TEXT REFERENCES books(id),  -- só se vier de PDF importado
    source_page       INTEGER,
    UNIQUE(headword_lower, source)
);

CREATE INDEX IF NOT EXISTS idx_entries_headword ON entries(headword_lower);
CREATE INDEX IF NOT EXISTS idx_entries_source ON entries(source);
"""


def init_dictionary(path: Path | str) -> sqlite3.Connection:
    conn = connect(path)
    conn.executescript(DICTIONARY_SCHEMA)
    conn.commit()
    return conn


# ---------- Embedding (de)serialization --------------------------------------

def encode_embedding(vector: Iterable[float]) -> bytes:
    """Serializa um vetor de floats em bytes float32 little-endian."""
    vec = list(vector)
    return struct.pack(f"<{len(vec)}f", *vec)


def decode_embedding(blob: bytes) -> list[float]:
    """Decodifica bytes float32 little-endian em lista de floats."""
    n = len(blob) // 4
    return list(struct.unpack(f"<{n}f", blob))


# ---------- Inserções utilitárias -------------------------------------------

def upsert_book(conn: sqlite3.Connection, book: dict[str, Any]) -> None:
    cols = (
        "id",
        "title",
        "author",
        "type",
        "level_cefr",
        "language",
        "source",
        "file_path",
        "file_hash",
        "page_count",
        "ingested_at",
        "extra_json",
    )
    placeholders = ",".join("?" for _ in cols)
    assignments = ",".join(f"{c}=excluded.{c}" for c in cols if c != "id")
    conn.execute(
        f"INSERT INTO books ({','.join(cols)}) VALUES ({placeholders}) "
        f"ON CONFLICT(id) DO UPDATE SET {assignments}",
        tuple(book.get(c) for c in cols),
    )


def insert_chunks(conn: sqlite3.Connection, chunks: Iterable[dict[str, Any]]) -> None:
    cols = (
        "id",
        "book_id",
        "chunk_index",
        "page_start",
        "page_end",
        "section_title",
        "text",
        "text_hash",
        "embedding",
        "embedding_model",
        "token_count",
    )
    placeholders = ",".join("?" for _ in cols)
    rows = [tuple(c.get(col) for col in cols) for c in chunks]
    conn.executemany(
        f"INSERT OR REPLACE INTO chunks ({','.join(cols)}) VALUES ({placeholders})",
        rows,
    )


def upsert_dictionary_entry(conn: sqlite3.Connection, entry: dict[str, Any]) -> None:
    cols = (
        "headword",
        "headword_lower",
        "gender",
        "pos",
        "translations_json",
        "examples_json",
        "notes",
        "source",
        "source_book_id",
        "source_page",
    )
    placeholders = ",".join("?" for _ in cols)
    assignments = ",".join(
        f"{c}=excluded.{c}" for c in cols if c not in ("headword_lower", "source")
    )
    conn.execute(
        f"INSERT INTO entries ({','.join(cols)}) VALUES ({placeholders}) "
        f"ON CONFLICT(headword_lower, source) DO UPDATE SET {assignments}",
        tuple(entry.get(c) for c in cols),
    )


def book_already_ingested(conn: sqlite3.Connection, file_hash: str) -> str | None:
    """Retorna o book.id se o file_hash já estiver registrado, senão None."""
    row = conn.execute(
        "SELECT id FROM books WHERE file_hash = ? LIMIT 1", (file_hash,)
    ).fetchone()
    return row["id"] if row else None
