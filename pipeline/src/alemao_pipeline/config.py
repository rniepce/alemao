"""Configuração centralizada — lê .env e expõe defaults."""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

PIPELINE_ROOT = Path(__file__).resolve().parents[2]
BOOKS_DIR = PIPELINE_ROOT / "books"
OUTPUT_DIR = PIPELINE_ROOT / "output"
SOURCES_YAML = PIPELINE_ROOT / "sources.yml"

load_dotenv(PIPELINE_ROOT / ".env")


def _env(name: str, default: str | None = None, *, required: bool = False) -> str:
    val = os.getenv(name, default)
    if required and not val:
        raise RuntimeError(f"Variável de ambiente obrigatória ausente: {name}")
    return val or ""


def gemini_api_key() -> str:
    return _env("GEMINI_API_KEY", required=True)


TEXT_MODEL = _env("GEMINI_TEXT_MODEL", "gemini-3.5-flash")
EMBEDDING_MODEL = _env("GEMINI_EMBEDDING_MODEL", "gemini-embedding-001")
EMBEDDING_DIMENSION = int(_env("EMBEDDING_DIMENSION", "768"))
EMBED_BATCH_SIZE = int(_env("EMBED_BATCH_SIZE", "100"))
EMBED_RPM = int(_env("EMBED_RPM", "200"))

TESSERACT_CMD = _env("TESSERACT_CMD", "")


def library_db_path() -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    return OUTPUT_DIR / "library.sqlite"


def dictionary_db_path() -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    return OUTPUT_DIR / "dictionary.sqlite"


def seed_lessons_path() -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    return OUTPUT_DIR / "seed_lessons.json"


def books_meta_path() -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    return OUTPUT_DIR / "books_meta.json"
