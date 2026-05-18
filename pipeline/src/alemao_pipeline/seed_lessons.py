"""Gerador de seed lessons: lições iniciais por tópico canônico.

Para cada tópico em sources.yml (Akkusativ, Dativ, Konjunktiv II, etc.):
1. Faz retrieval na biblioteca buscando trechos relevantes
2. Envia o contexto retrieved + o tópico para Gemini com schema estruturado
3. Recebe JSON com explicação, exemplos, exercícios e citações
4. Salva tudo em seed_lessons.json

Esse JSON é bundleado no app iOS e oferece conteúdo de qualidade desde o primeiro
launch, sem precisar chamar a API a cada lição.
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path

import yaml
from pydantic import BaseModel, Field
from rich.console import Console

from . import config, gemini, retriever

logger = logging.getLogger(__name__)
console = Console()


# ---------- Schema da lição --------------------------------------------------


class Citation(BaseModel):
    book_id: str = Field(description="ID do livro de origem")
    book_title: str = Field(description="Título do livro")
    section_title: str | None = Field(default=None, description="Título da seção/capítulo")
    page_start: int = Field(description="Página inicial")
    page_end: int = Field(description="Página final")
    excerpt: str = Field(description="Trecho citado (até 200 caracteres)")


class Example(BaseModel):
    de: str = Field(description="Frase em alemão")
    pt: str = Field(description="Tradução em português")
    note: str | None = Field(default=None, description="Observação opcional")


class ExerciseQuestion(BaseModel):
    question: str = Field(description="Enunciado em português ou alemão")
    answer: str = Field(description="Resposta esperada")
    explanation: str | None = Field(default=None, description="Explicação curta da resposta")


class Lesson(BaseModel):
    topic_id: str = Field(description="ID do tópico, conforme sources.yml")
    title: str = Field(description="Título da lição em português")
    level_cefr: str = Field(description="Nível CEFR: A1, A2, B1, B2, C1, C2")
    summary: str = Field(description="Resumo de 1-2 frases em português")
    explanation_md: str = Field(
        description=(
            "Explicação detalhada em português (Markdown). Use listas, "
            "tabelas e exemplos quando ajudar. Aprofunde-se no tópico, "
            "como faria um professor experiente."
        )
    )
    examples: list[Example] = Field(
        default_factory=list,
        description="5-10 exemplos com tradução",
    )
    exercises: list[ExerciseQuestion] = Field(
        default_factory=list,
        description="3-5 exercícios para o aluno praticar",
    )
    citations: list[Citation] = Field(
        default_factory=list,
        description="Trechos dos livros usados como base (preencha com os recuperados)",
    )


# ---------- Prompt -----------------------------------------------------------

SYSTEM_PROMPT = """\
Você é um professor experiente de alemão para falantes de português, que prepara
lições didáticas claras e bem fundamentadas.

Receberá:
- Um tópico de gramática alemã (ex: "Akkusativ", "Konjunktiv II")
- Um nível CEFR alvo (A1-C2)
- Trechos relevantes de livros de gramática (em inglês ou alemão)

Sua tarefa é gerar uma LIÇÃO em português brasileiro, com:
1. Explicação didática completa, em Markdown (use ## headings, listas, tabelas
   quando ajudar). Inclua nuances e exceções importantes.
2. 5-10 exemplos com tradução (de → pt). Use frases naturais, não artificiais.
3. 3-5 exercícios variados (preenchimento, escolha, tradução). Inclua a resposta.
4. Citações: para cada trecho de livro que você usou como base, registre book_id,
   título, página e um excerpt curto (até 200 caracteres). Preserve os IDs e
   metadata exatamente como vieram nos trechos fornecidos.

Importante:
- A explicação é SUA (transformativa), inspirada nos trechos. NÃO copie blocos.
- Se um tópico tiver múltiplas regras, organize com subtítulos.
- Mantenha o português natural e amigável, sem ser informal demais.
- Adapte a profundidade ao nível CEFR (A1=básico, C1=avançado).
"""


def _format_context(hits: list) -> str:
    """Formata os hits do retriever como contexto para o prompt."""
    parts = []
    for i, h in enumerate(hits, 1):
        parts.append(
            f"[Trecho {i}] "
            f"book_id={h.book_id} | "
            f"livro={h.book_title!r} | "
            f"seção={h.section_title!r} | "
            f"páginas {h.page_start}-{h.page_end}\n\n"
            f"{h.text}\n"
            f"--- fim do trecho {i} ---"
        )
    return "\n\n".join(parts)


def generate_lesson(topic_id: str, title: str, level: str) -> Lesson | None:
    """Gera uma lição para um tópico usando RAG + Gemini."""
    console.print(f"[cyan]→[/cyan] [bold]{topic_id}[/bold] ({level}) — {title}")

    # 1. Retrieval: usar título + sinônimos comuns
    query = f"{title} {topic_id} grammar rules examples"
    hits = retriever.retrieve(query, limit=8, fts_pool=20, dense_pool=20)
    if not hits:
        console.print("  [yellow]Nenhum trecho relevante encontrado; pulando[/yellow]")
        return None
    console.print(f"  {len(hits)} trechos recuperados")

    # 2. Gerar via Gemini
    context = _format_context(hits)
    prompt = (
        f"Tópico: {title} (id={topic_id})\n"
        f"Nível CEFR alvo: {level}\n\n"
        f"Trechos da biblioteca:\n\n{context}\n\n"
        f"Gere a lição em JSON conforme o schema."
    )
    try:
        lesson = gemini.generate_structured(
            prompt,
            Lesson,
            system_instruction=SYSTEM_PROMPT,
            temperature=0.4,
        )
    except Exception as e:
        console.print(f"  [red]Falha ao gerar: {e}[/red]")
        logger.exception("Falha em %s", topic_id)
        return None

    # 3. Garantir consistência mínima dos campos
    lesson.topic_id = topic_id
    if not lesson.title:
        lesson.title = title
    if not lesson.level_cefr:
        lesson.level_cefr = level

    console.print(
        f"  [green]✓[/green] {len(lesson.examples)} exemplos, "
        f"{len(lesson.exercises)} exercícios, {len(lesson.citations)} citações"
    )
    return lesson


def generate_all(
    *,
    sources_yml: Path | None = None,
    output_path: Path | None = None,
    only_topics: list[str] | None = None,
    delay_seconds: float = 1.0,
) -> list[Lesson]:
    sources_yml = Path(sources_yml or config.SOURCES_YAML)
    output_path = Path(output_path or config.seed_lessons_path())

    with sources_yml.open(encoding="utf-8") as f:
        sources = yaml.safe_load(f)

    topics = sources.get("seed_lessons", {}).get("topics", [])
    if only_topics:
        topics = [t for t in topics if t["id"] in only_topics]
    if not topics:
        console.print("[yellow]Nenhum tópico configurado em sources.yml[/yellow]")
        return []

    console.print(f"[bold]Gerando {len(topics)} lições[/bold]\n")

    lessons: list[Lesson] = []
    for t in topics:
        lesson = generate_lesson(t["id"], t["title"], t.get("level", "B1"))
        if lesson:
            lessons.append(lesson)
        time.sleep(delay_seconds)  # rate limiting suave

    # Persistir
    payload = [json.loads(lesson.model_dump_json()) for lesson in lessons]
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    console.print(f"\n[bold green]✓[/bold green] {len(lessons)} lições salvas em {output_path}")
    return lessons
