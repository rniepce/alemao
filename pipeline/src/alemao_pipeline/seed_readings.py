"""Gera textos de leitura (readings) seed para o app iOS.

Output: `output/seed_readings.json` com lista de readings cobrindo todos os
níveis CEFR. O app iOS carrega isso na primeira execução via SeedReadingLoader.

Cada reading tem:
- title (em alemão)
- level_cefr
- topic (descrição em PT do tema)
- body_de (texto em alemão)
- glossary (palavras-chave com tradução PT)
- comprehension_questions

Save incremental (idêntico a seed_lessons.py).
"""
from __future__ import annotations

import json
import logging
import time
from pathlib import Path

from rich.console import Console

from . import config, gemini
from .retriever import retrieve as retrieve_fn

logger = logging.getLogger(__name__)
console = Console()


# Temas curados, agrupados por nível CEFR. ~5 por nível.
READING_TOPICS: list[dict] = [
    # A1 — vocabulário básico, presente, frases curtas
    {"id": "a1_meu_dia", "level": "A1", "topic": "Meu dia: rotina matinal simples (acordar, café, escola/trabalho)"},
    {"id": "a1_familia", "level": "A1", "topic": "Minha família: pais, irmãos, idade, profissão"},
    {"id": "a1_no_cafe", "level": "A1", "topic": "No café: pedindo bebida e comida"},
    {"id": "a1_meu_quarto", "level": "A1", "topic": "Meu quarto: móveis e objetos"},
    {"id": "a1_hobbies", "level": "A1", "topic": "Hobbies: o que gosto de fazer no tempo livre"},

    # A2 — passado simples, descrições, planos
    {"id": "a2_viagem_berlim", "level": "A2", "topic": "Uma viagem de fim de semana a Berlim"},
    {"id": "a2_supermercado", "level": "A2", "topic": "No supermercado: lista de compras e conversa com atendente"},
    {"id": "a2_clima", "level": "A2", "topic": "Clima e estações: previsão do tempo na Alemanha"},
    {"id": "a2_apartamento", "level": "A2", "topic": "Procurando apartamento: pedido para visita"},
    {"id": "a2_aniversario", "level": "A2", "topic": "Aniversário do amigo: convite e festa"},

    # B1 — narrativa mais elaborada, opiniões, indireto
    {"id": "b1_oktoberfest", "level": "B1", "topic": "A Oktoberfest: história, tradições e curiosidades"},
    {"id": "b1_transporte_publico", "level": "B1", "topic": "Transporte público em Munique: experiência de um estrangeiro"},
    {"id": "b1_emprego", "level": "B1", "topic": "Entrevista de emprego: dicas e relato"},
    {"id": "b1_ecologia", "level": "B1", "topic": "Vida sustentável: reciclagem alemã (Pfand, Mülltrennung)"},
    {"id": "b1_universidade", "level": "B1", "topic": "Estudar em uma universidade alemã"},

    # B2 — argumentos, vocabulário avançado, registros formais
    {"id": "b2_homeoffice", "level": "B2", "topic": "Home office na Alemanha: vantagens e desvantagens"},
    {"id": "b2_arte_dada", "level": "B2", "topic": "Arte contemporânea alemã: panorama atual"},
    {"id": "b2_idiomatischer_text", "level": "B2", "topic": "Expressões idiomáticas alemãs e seus significados"},
    {"id": "b2_kuendigung", "level": "B2", "topic": "Cancelando um contrato (Kündigung): exemplo formal"},
    {"id": "b2_klima_debatte", "level": "B2", "topic": "Debate sobre energia nuclear na Alemanha"},

    # C1 — análise complexa, abstrato, registro acadêmico
    {"id": "c1_immanuel_kant", "level": "C1", "topic": "Immanuel Kant: legado filosófico em 5 parágrafos"},
    {"id": "c1_industrie_40", "level": "C1", "topic": "Indústria 4.0 e a economia alemã"},
    {"id": "c1_migration", "level": "C1", "topic": "Imigração na Alemanha pós-2015: aspectos sociais"},
    {"id": "c1_bauhaus", "level": "C1", "topic": "Bauhaus: a escola que mudou o design mundial"},
    {"id": "c1_demokratie", "level": "C1", "topic": "Democracia direta vs representativa: o exemplo suíço-alemão"},
]


SYSTEM_PROMPT = """\
Você é um autor de textos didáticos em alemão. Produza um texto de leitura adequado
ao nível CEFR pedido, sobre o tópico solicitado. Retorne APENAS JSON neste formato:

{
  "title": "Título em alemão (curto)",
  "level_cefr": "A1|A2|B1|B2|C1|C2",
  "body_de": "Texto principal em alemão, em 3-5 parágrafos.",
  "glossary": [{"de": "palavra ou expressão alemã", "pt": "tradução em PT"}],
  "comprehension_questions": [{"question": "...em alemão", "answer": "...em alemão"}]
}

Regras:
- body_de em alemão claro adequado ao nível (vocabulário, sintaxe, frases).
- Tamanho-alvo: A1 ~80 palavras, A2 ~120, B1 ~180, B2 ~250, C1 ~320.
- Glossary com 5-10 palavras-chave do texto.
- 3-5 perguntas de compreensão.
- Use opcionalmente trechos do contexto fornecido (livros pessoais) como inspiração.
"""


def _format_context(hits: list) -> str:
    if not hits:
        return ""
    parts = [
        "Trechos da biblioteca (referência opcional para vocabulário/estilo):\n"
    ]
    for i, h in enumerate(hits, 1):
        parts.append(f"[{i}] {h.book_title}: {h.text[:300]}...")
    return "\n\n".join(parts)


def generate_one(item: dict) -> dict | None:
    topic_id = item["id"]
    level = item["level"]
    topic = item["topic"]
    console.print(f"[cyan]→[/cyan] [bold]{topic_id}[/bold] ({level}) — {topic}")

    # Retrieval opcional pra contexto
    try:
        hits = retrieve_fn(topic, limit=3)
    except Exception as e:
        logger.warning("retrieve falhou para %s: %s", topic_id, e)
        hits = []

    context = _format_context(hits)
    prompt = (
        f"Tópico: {topic}\nNível CEFR: {level}\n"
        f"{context if context else ''}\n\nGere o texto agora."
    )

    # Schema-free generation usando responseSchema=None — pedimos JSON na instrução
    try:
        from pydantic import BaseModel, Field

        class GlossItem(BaseModel):
            de: str
            pt: str

        class CompQ(BaseModel):
            question: str
            answer: str

        class Reading(BaseModel):
            title: str
            level_cefr: str
            body_de: str
            glossary: list[GlossItem]
            comprehension_questions: list[CompQ]

        result = gemini.generate_structured(
            prompt, Reading, system_instruction=SYSTEM_PROMPT, temperature=0.6
        )
    except Exception as e:
        console.print(f"  [red]Falha: {e}[/red]")
        logger.exception("seed reading falhou em %s", topic_id)
        return None

    console.print(
        f"  [green]✓[/green] '{result.title}' — {len(result.body_de.split())} palavras, "
        f"{len(result.glossary)} glossário, {len(result.comprehension_questions)} perguntas"
    )
    return {
        "id": topic_id,
        "title": result.title,
        "level_cefr": result.level_cefr,
        "topic": topic,
        "body_de": result.body_de,
        "glossary": [g.model_dump() for g in result.glossary],
        "comprehension_questions": [q.model_dump() for q in result.comprehension_questions],
    }


def generate_all(
    *,
    output_path: Path | None = None,
    only_ids: list[str] | None = None,
    delay_seconds: float = 0.5,
    skip_existing: bool = True,
) -> list[dict]:
    output_path = Path(output_path or (config.OUTPUT_DIR / "seed_readings.json"))

    topics = READING_TOPICS
    if only_ids:
        topics = [t for t in topics if t["id"] in only_ids]
    if not topics:
        console.print("[yellow]Nenhum tópico de reading configurado[/yellow]")
        return []

    # Carrega existentes
    existing: dict[str, dict] = {}
    if output_path.exists():
        try:
            existing_list = json.loads(output_path.read_text(encoding="utf-8"))
            existing = {r["id"]: r for r in existing_list if "id" in r}
        except Exception as e:
            console.print(f"[yellow]Não consegui ler {output_path.name}: {e}[/yellow]")

    if skip_existing and not only_ids:
        before = len(topics)
        topics = [t for t in topics if t["id"] not in existing]
        skipped = before - len(topics)
        if skipped > 0:
            console.print(f"[dim]Pulando {skipped} readings já gerados[/dim]")

    console.print(f"[bold]Gerando {len(topics)} readings[/bold]\n")

    merged: dict[str, dict] = dict(existing)

    def _persist() -> None:
        payload = [merged[k] for k in sorted(merged.keys())]
        output_path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    new_readings: list[dict] = []
    for t in topics:
        reading = generate_one(t)
        if reading:
            merged[reading["id"]] = reading
            new_readings.append(reading)
            _persist()
        time.sleep(delay_seconds)

    console.print(
        f"\n[bold green]✓[/bold green] {len(new_readings)} novos, "
        f"{len(merged)} no total em {output_path}"
    )
    return new_readings
