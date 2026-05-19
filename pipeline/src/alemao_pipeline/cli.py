"""CLI principal — `python -m alemao_pipeline <subcomando>`."""

from __future__ import annotations

import logging

import typer
from rich.console import Console
from rich.table import Table

from . import config, db, embeddings, ingest, retriever
from . import seed_lessons as seed_lessons_mod
from . import seed_readings as seed_readings_mod

app = typer.Typer(no_args_is_help=True, add_completion=False)
console = Console()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)


@app.command(name="ingest")
def ingest_cmd(
    only: str | None = typer.Option(None, "--only", help="Nome do PDF a ingerir (resto pulado)"),
    skip_embeddings: bool = typer.Option(
        False, "--skip-embeddings", help="Não chamar Gemini para embeddings"
    ),
    no_ocr: bool = typer.Option(False, "--no-ocr", help="Desabilita OCR (mais rápido)"),
) -> None:
    """Processa PDFs em pipeline/books/."""
    typer.echo(f"books_dir = {config.BOOKS_DIR}")
    typer.echo(f"output_dir = {config.OUTPUT_DIR}")
    ingest.ingest_directory(
        only=only,
        skip_embeddings=skip_embeddings,
        ocr=not no_ocr,
    )


@app.command()
def embed(
    book_id: str | None = typer.Option(None, "--book-id", help="Embeda apenas chunks deste livro"),
) -> None:
    """Reroda só a etapa de embeddings em chunks pendentes."""
    conn = db.connect(config.library_db_path())
    stats = embeddings.embed_pending(conn, book_id=book_id)
    console.print(
        f"[green]+{stats.chunks_embedded} embeddings[/green] "
        f"(batches={stats.batches}, errors={stats.api_errors})"
    )
    conn.close()


@app.command()
def stats() -> None:
    """Mostra estatísticas do conteúdo gerado."""
    lib_path = config.library_db_path()
    dict_path = config.dictionary_db_path()

    if not lib_path.exists():
        console.print("[yellow]library.sqlite ainda não existe[/yellow]")
        return

    conn = db.connect(lib_path)
    books = conn.execute(
        "SELECT type, COUNT(*) as n FROM books GROUP BY type"
    ).fetchall()
    chunks_total = conn.execute("SELECT COUNT(*) as n FROM chunks").fetchone()["n"]
    chunks_embedded = conn.execute(
        "SELECT COUNT(*) as n FROM chunks WHERE embedding IS NOT NULL"
    ).fetchone()["n"]
    tokens = conn.execute(
        "SELECT COALESCE(SUM(token_count), 0) as t FROM chunks"
    ).fetchone()["t"]

    t = Table(title="Library", show_header=True, header_style="bold cyan")
    t.add_column("Métrica")
    t.add_column("Valor", justify="right")
    for row in books:
        t.add_row(f"Livros ({row['type']})", str(row["n"]))
    t.add_row("Chunks totais", str(chunks_total))
    t.add_row("Chunks com embedding", str(chunks_embedded))
    t.add_row("Tokens (estimado)", f"{tokens:,}")
    console.print(t)

    # Por livro
    rows = conn.execute(
        """
        SELECT b.title, b.type, b.level_cefr, b.page_count,
               COUNT(c.id) as chunks,
               SUM(CASE WHEN c.embedding IS NOT NULL THEN 1 ELSE 0 END) as embedded
        FROM books b LEFT JOIN chunks c ON c.book_id = b.id
        GROUP BY b.id
        ORDER BY b.title
        """
    ).fetchall()
    if rows:
        t2 = Table(title="Por livro", show_header=True, header_style="bold cyan")
        t2.add_column("Título")
        t2.add_column("Tipo")
        t2.add_column("Nível")
        t2.add_column("Páginas", justify="right")
        t2.add_column("Chunks", justify="right")
        t2.add_column("Embedded", justify="right")
        for r in rows:
            t2.add_row(
                (r["title"] or "—")[:50],
                r["type"] or "—",
                r["level_cefr"] or "—",
                str(r["page_count"] or 0),
                str(r["chunks"] or 0),
                str(r["embedded"] or 0),
            )
        console.print(t2)
    conn.close()

    # Dictionary
    if dict_path.exists():
        dc = db.connect(dict_path)
        n_entries = dc.execute("SELECT COUNT(*) as n FROM entries").fetchone()["n"]
        sources = dc.execute(
            "SELECT source, COUNT(*) as n FROM entries GROUP BY source ORDER BY n DESC"
        ).fetchall()
        t3 = Table(title="Dictionary", show_header=True, header_style="bold cyan")
        t3.add_column("Fonte")
        t3.add_column("Entradas", justify="right")
        for s in sources:
            t3.add_row(s["source"] or "—", str(s["n"]))
        t3.add_row("[bold]Total[/bold]", f"[bold]{n_entries}[/bold]")
        console.print(t3)
        dc.close()


@app.command()
def sample(
    book_id: str | None = typer.Option(None, "--book-id"),
    n: int = typer.Option(3, "--n", help="Quantos chunks mostrar"),
) -> None:
    """Mostra amostras de chunks para inspecionar qualidade do parsing."""
    conn = db.connect(config.library_db_path())
    where = "WHERE c.book_id = ?" if book_id else ""
    params = (book_id,) if book_id else ()
    rows = conn.execute(
        f"""
        SELECT c.id, c.section_title, c.page_start, c.page_end, c.text, b.title
        FROM chunks c JOIN books b ON b.id = c.book_id
        {where}
        ORDER BY RANDOM() LIMIT ?
        """,
        (*params, n),
    ).fetchall()
    for r in rows:
        header = (
            f"[bold]{r['title']}[/bold] · {r['section_title'] or '—'} "
            f"· p.{r['page_start']}-{r['page_end']}"
        )
        console.rule(header)
        console.print(r["text"][:1500])
        console.print()
    conn.close()


@app.command()
def init() -> None:
    """Apenas inicializa os schemas (útil para validar instalação)."""
    db.init_library(config.library_db_path()).close()
    db.init_dictionary(config.dictionary_db_path()).close()
    console.print(f"[green]✓[/green] {config.library_db_path()}")
    console.print(f"[green]✓[/green] {config.dictionary_db_path()}")


@app.command()
def retrieve(
    query: str = typer.Argument(..., help="Pergunta ou tópico em alemão ou português"),
    n: int = typer.Option(5, "--n", help="Número de hits a retornar"),
    show_text: bool = typer.Option(True, "--text/--no-text", help="Mostra texto dos chunks"),
) -> None:
    """Faz retrieval híbrido (FTS5 + cosine + RRF) e imprime os top hits."""
    hits = retriever.retrieve(query, limit=n)
    if not hits:
        console.print("[yellow]Nenhum resultado.[/yellow]")
        return
    for i, h in enumerate(hits, 1):
        header = (
            f"[bold cyan]#{i}[/bold cyan] · score={h.score:.4f} "
            f"· fts_rank={h.fts_rank or '—'} dense_rank={h.dense_rank or '—'}"
        )
        console.print(header)
        console.print(
            f"  [bold]{h.book_title}[/bold] · {h.section_title or '—'} "
            f"· p.{h.page_start}-{h.page_end}"
        )
        if show_text:
            console.print(f"  [dim]{h.text[:400]}{'...' if len(h.text) > 400 else ''}[/dim]")
        console.print()


@app.command(name="seed-lessons")
def seed_lessons_cmd(
    only: list[str] = typer.Option(
        None, "--only", help="Apenas estes topic_ids (pode repetir)"
    ),
    delay: float = typer.Option(1.0, "--delay", help="Segundos entre gerações"),
) -> None:
    """Gera lições iniciais por tópico canônico (sources.yml) via RAG + Gemini."""
    seed_lessons_mod.generate_all(only_topics=only or None, delay_seconds=delay)


@app.command(name="seed-readings")
def seed_readings_cmd(
    only: list[str] = typer.Option(
        None, "--only", help="Apenas estes reading IDs (pode repetir)"
    ),
    delay: float = typer.Option(0.5, "--delay", help="Segundos entre gerações"),
) -> None:
    """Gera readings (textos de leitura) seed por nível CEFR."""
    seed_readings_mod.generate_all(only_ids=only or None, delay_seconds=delay)


if __name__ == "__main__":
    app()
