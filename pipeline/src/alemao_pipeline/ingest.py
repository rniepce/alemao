"""Orquestração de ingestão: PDF → extract → classify → chunk/dict → embed."""

from __future__ import annotations

import datetime as dt
import json
import logging
from pathlib import Path

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn

from . import chunker, classify, config, db, dict_parser, embeddings, extract

logger = logging.getLogger(__name__)
console = Console()


def _now_iso() -> str:
    return dt.datetime.now(dt.UTC).isoformat()


def _book_id_from_hash(file_hash: str) -> str:
    """ID determinístico para o livro a partir do hash, encurtado."""
    return f"book_{file_hash[:16]}"


def ingest_pdf(
    pdf_path: Path,
    *,
    library_conn,
    dict_conn,
    skip_embeddings: bool = False,
    ocr: bool = True,
) -> dict:
    """Processa um PDF do início ao fim. Retorna metadata resumida."""
    console.print(f"[bold cyan]→[/bold cyan] {pdf_path.name}")

    # 1. Extrair texto
    with Progress(SpinnerColumn(), TextColumn("[progress.description]{task.description}"),
                  transient=True) as p:
        p.add_task("Extraindo texto (PyMuPDF + OCR)...", total=None)
        doc = extract.extract_document(pdf_path, ocr=ocr)

    # Idempotência: se livro já foi ingerido e não há chunks pendentes, pula
    existing_id = db.book_already_ingested(library_conn, doc.file_hash)
    if existing_id:
        console.print(f"  [dim]já ingerido como {existing_id}; checando embeddings pendentes[/dim]")
        book_id = existing_id
    else:
        book_id = _book_id_from_hash(doc.file_hash)

    console.print(
        f"  páginas={doc.page_count}, ocr_pages={doc.ocr_pages}, "
        f"toc_entries={len(doc.toc)}"
    )

    # 2. Classificar (e persistir book) — só quando ainda não foi ingerido.
    if not existing_id:
        with Progress(SpinnerColumn(), TextColumn("[progress.description]{task.description}"),
                      transient=True) as p:
            p.add_task("Classificando com Gemini...", total=None)
            meta = classify.classify_book(doc)
        console.print(
            f"  [green]type={meta.type}[/green] title={meta.title!r} "
            f"author={meta.author!r} level={meta.level_cefr}"
        )
        book_row = {
            "id": book_id,
            "title": meta.title,
            "author": meta.author,
            "type": meta.type,
            "level_cefr": meta.level_cefr,
            "language": meta.language,
            "source": "personal",
            "file_path": pdf_path.name,
            "file_hash": doc.file_hash,
            "page_count": doc.page_count,
            "ingested_at": _now_iso(),
            "extra_json": json.dumps(
                {
                    "summary": meta.summary,
                    "bilingual": meta.bilingual,
                    "ocr_pages": doc.ocr_pages,
                },
                ensure_ascii=False,
            ),
        }
        db.upsert_book(library_conn, book_row)
        library_conn.commit()
    else:
        # Livro já está no banco — não chamamos classify nem sobrescrevemos a row.
        # Apenas carregamos a metadata existente para o caminho condicional abaixo.
        row = library_conn.execute(
            "SELECT type, title, author, level_cefr, language FROM books WHERE id = ?",
            (existing_id,),
        ).fetchone()
        meta = classify.BookMetadata(
            type=row["type"] if row else "other",
            title=row["title"] if row else pdf_path.stem,
            author=row["author"] if row else None,
            level_cefr=row["level_cefr"] if row else None,
            language=row["language"] if row else "de",
        )

    # 4. Branch por tipo
    if meta.type == "dictionary":
        console.print("  [yellow]Parseando entradas do dicionário...[/yellow]")
        entries = dict_parser.parse_dictionary(doc, use_llm_fallback=True)
        console.print(f"  {len(entries)} entradas extraídas")
        for entry in entries:
            db.upsert_dictionary_entry(
                dict_conn,
                dict_parser.entry_to_dict_row(
                    entry, source=meta.title, source_book_id=book_id
                ),
            )
        dict_conn.commit()
    else:
        # Chunking para books que não são dicionários
        if not existing_id:
            console.print("  Chunking...")
            chunks = chunker.chunk_document(doc, book_id)
            console.print(f"  {len(chunks)} chunks criados")
            chunk_rows = [chunker.chunk_to_dict(c) for c in chunks]
            db.insert_chunks(library_conn, chunk_rows)
            library_conn.commit()

        # Embeddings (só se não pulado)
        if not skip_embeddings:
            console.print("  Embedando chunks pendentes...")
            stats = embeddings.embed_pending(library_conn, book_id=book_id)
            console.print(
                f"  [green]+{stats.chunks_embedded} embeddings[/green] "
                f"(batches={stats.batches}, errors={stats.api_errors})"
            )

    return {
        "book_id": book_id,
        "title": meta.title,
        "type": meta.type,
        "file": pdf_path.name,
        "page_count": doc.page_count,
        "level_cefr": meta.level_cefr,
    }


def ingest_directory(
    books_dir: Path | None = None,
    *,
    only: str | None = None,
    skip_embeddings: bool = False,
    ocr: bool = True,
) -> list[dict]:
    """Ingere todos os PDFs em books_dir (ou apenas um se `only` for fornecido)."""
    books_dir = Path(books_dir or config.BOOKS_DIR)
    if not books_dir.exists():
        raise FileNotFoundError(f"Diretório de livros não encontrado: {books_dir}")

    pdfs = sorted(books_dir.glob("*.pdf"))
    if only:
        pdfs = [p for p in pdfs if p.name == only or p.stem == only]

    if not pdfs:
        console.print(f"[yellow]Nenhum PDF encontrado em {books_dir}[/yellow]")
        return []

    console.print(f"[bold]Encontrados {len(pdfs)} PDF(s)[/bold] em {books_dir}\n")

    library_conn = db.init_library(config.library_db_path())
    dict_conn = db.init_dictionary(config.dictionary_db_path())

    results: list[dict] = []
    for pdf in pdfs:
        try:
            results.append(
                ingest_pdf(
                    pdf,
                    library_conn=library_conn,
                    dict_conn=dict_conn,
                    skip_embeddings=skip_embeddings,
                    ocr=ocr,
                )
            )
        except Exception as e:
            console.print(f"[red]Falha em {pdf.name}: {e}[/red]")
            logger.exception("Falha ao ingerir %s", pdf)

    # Escreve books_meta.json com TODOS os livros do banco (não só os desta rodada),
    # para que --only não corrompa o snapshot global.
    meta_path = config.books_meta_path()
    all_books = [
        dict(r)
        for r in library_conn.execute(
            """
            SELECT id AS book_id, title, author, type, file_path AS file,
                   page_count, level_cefr, language, source, ingested_at
            FROM books
            ORDER BY title
            """
        )
    ]
    meta_path.write_text(
        json.dumps(all_books, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    console.print(f"\n[bold green]✓[/bold green] Metadata salva em {meta_path}")

    library_conn.close()
    dict_conn.close()
    return results
