"""Gera 60 verbos comuns alemães com tabelas de conjugação completas.

Tabelas geradas por verbo:
- Präsens: ich / du / er-sie-es / wir / ihr / sie-Sie
- Präteritum: ich / du / er-sie-es / wir / ihr / sie-Sie
- Perfekt: aux (haben|sein) + Partizip II
- Konjunktiv II: ich / du / er-sie-es / wir / ihr / sie-Sie
- Imperativ (du / ihr / Sie) — opcional para B1+

Output: `output/seed_verbs.json`
"""
from __future__ import annotations

import json
import logging
import time
from pathlib import Path

from pydantic import BaseModel, Field
from rich.console import Console

from . import config, gemini

logger = logging.getLogger(__name__)
console = Console()


# Lista curada de 60 verbos: top frequência + irregulares importantes + modais.
VERBS: list[dict] = [
    # ----- Modais (6) -----
    {"id": "können", "infinitive": "können", "level": "A1", "theme": "modal"},
    {"id": "müssen", "infinitive": "müssen", "level": "A1", "theme": "modal"},
    {"id": "wollen", "infinitive": "wollen", "level": "A1", "theme": "modal"},
    {"id": "sollen", "infinitive": "sollen", "level": "A1", "theme": "modal"},
    {"id": "dürfen", "infinitive": "dürfen", "level": "A2", "theme": "modal"},
    {"id": "mögen", "infinitive": "mögen", "level": "A1", "theme": "modal"},

    # ----- Auxiliares (3) -----
    {"id": "sein", "infinitive": "sein", "level": "A1", "theme": "hilfsverb"},
    {"id": "haben", "infinitive": "haben", "level": "A1", "theme": "hilfsverb"},
    {"id": "werden", "infinitive": "werden", "level": "A1", "theme": "hilfsverb"},

    # ----- Regulares comuns (8) -----
    {"id": "machen", "infinitive": "machen", "level": "A1", "theme": "alltag"},
    {"id": "spielen", "infinitive": "spielen", "level": "A1", "theme": "alltag"},
    {"id": "lernen", "infinitive": "lernen", "level": "A1", "theme": "alltag"},
    {"id": "arbeiten", "infinitive": "arbeiten", "level": "A1", "theme": "arbeit"},
    {"id": "wohnen", "infinitive": "wohnen", "level": "A1", "theme": "alltag"},
    {"id": "kaufen", "infinitive": "kaufen", "level": "A1", "theme": "alltag"},
    {"id": "fragen", "infinitive": "fragen", "level": "A1", "theme": "kommunikation"},
    {"id": "sagen", "infinitive": "sagen", "level": "A1", "theme": "kommunikation"},

    # ----- Irregulares (starke + gemischt) — top frequência (20) -----
    {"id": "gehen", "infinitive": "gehen", "level": "A1", "theme": "bewegung"},
    {"id": "kommen", "infinitive": "kommen", "level": "A1", "theme": "bewegung"},
    {"id": "fahren", "infinitive": "fahren", "level": "A1", "theme": "bewegung"},
    {"id": "fliegen", "infinitive": "fliegen", "level": "A2", "theme": "bewegung"},
    {"id": "laufen", "infinitive": "laufen", "level": "A2", "theme": "bewegung"},
    {"id": "essen", "infinitive": "essen", "level": "A1", "theme": "essen"},
    {"id": "trinken", "infinitive": "trinken", "level": "A1", "theme": "essen"},
    {"id": "schlafen", "infinitive": "schlafen", "level": "A1", "theme": "alltag"},
    {"id": "sprechen", "infinitive": "sprechen", "level": "A1", "theme": "kommunikation"},
    {"id": "lesen", "infinitive": "lesen", "level": "A1", "theme": "alltag"},
    {"id": "schreiben", "infinitive": "schreiben", "level": "A1", "theme": "alltag"},
    {"id": "sehen", "infinitive": "sehen", "level": "A1", "theme": "wahrnehmung"},
    {"id": "geben", "infinitive": "geben", "level": "A1", "theme": "alltag"},
    {"id": "nehmen", "infinitive": "nehmen", "level": "A1", "theme": "alltag"},
    {"id": "finden", "infinitive": "finden", "level": "A1", "theme": "alltag"},
    {"id": "denken", "infinitive": "denken", "level": "A2", "theme": "kognition"},
    {"id": "wissen", "infinitive": "wissen", "level": "A1", "theme": "kognition"},
    {"id": "verstehen", "infinitive": "verstehen", "level": "A2", "theme": "kognition"},
    {"id": "helfen", "infinitive": "helfen", "level": "A2", "theme": "alltag"},
    {"id": "bleiben", "infinitive": "bleiben", "level": "A2", "theme": "alltag"},

    # ----- Reflexivos comuns (4) -----
    {"id": "sich_freuen", "infinitive": "sich freuen", "level": "A2", "theme": "emotion"},
    {"id": "sich_treffen", "infinitive": "sich treffen", "level": "A2", "theme": "kommunikation"},
    {"id": "sich_interessieren", "infinitive": "sich interessieren", "level": "B1", "theme": "emotion"},
    {"id": "sich_erinnern", "infinitive": "sich erinnern", "level": "B1", "theme": "kognition"},

    # ----- Separáveis comuns (8) -----
    {"id": "anfangen", "infinitive": "anfangen", "level": "A2", "theme": "alltag"},
    {"id": "aufstehen", "infinitive": "aufstehen", "level": "A1", "theme": "alltag"},
    {"id": "einkaufen", "infinitive": "einkaufen", "level": "A2", "theme": "alltag"},
    {"id": "fernsehen", "infinitive": "fernsehen", "level": "A2", "theme": "alltag"},
    {"id": "mitkommen", "infinitive": "mitkommen", "level": "A2", "theme": "bewegung"},
    {"id": "umsteigen", "infinitive": "umsteigen", "level": "B1", "theme": "reisen"},
    {"id": "vorbereiten", "infinitive": "vorbereiten", "level": "B1", "theme": "alltag"},
    {"id": "zumachen", "infinitive": "zumachen", "level": "A2", "theme": "alltag"},

    # ----- Inseparáveis / B1+ (11) -----
    {"id": "beginnen", "infinitive": "beginnen", "level": "A2", "theme": "alltag"},
    {"id": "bekommen", "infinitive": "bekommen", "level": "A2", "theme": "alltag"},
    {"id": "besuchen", "infinitive": "besuchen", "level": "A1", "theme": "soziales"},
    {"id": "erklären", "infinitive": "erklären", "level": "A2", "theme": "kommunikation"},
    {"id": "erzählen", "infinitive": "erzählen", "level": "A2", "theme": "kommunikation"},
    {"id": "gefallen", "infinitive": "gefallen", "level": "A2", "theme": "emotion"},
    {"id": "vergessen", "infinitive": "vergessen", "level": "A2", "theme": "kognition"},
    {"id": "verlieren", "infinitive": "verlieren", "level": "B1", "theme": "alltag"},
    {"id": "versuchen", "infinitive": "versuchen", "level": "B1", "theme": "alltag"},
    {"id": "verlassen", "infinitive": "verlassen", "level": "B1", "theme": "bewegung"},
    {"id": "entscheiden", "infinitive": "entscheiden", "level": "B2", "theme": "kognition"},

    # ===== EXPANSÃO: +60 verbos irregulares e úteis =====

    # ----- Mais separáveis comuns (10) -----
    {"id": "anrufen", "infinitive": "anrufen", "level": "A1", "theme": "kommunikation"},
    {"id": "anbieten", "infinitive": "anbieten", "level": "A2", "theme": "alltag"},
    {"id": "ansehen", "infinitive": "ansehen", "level": "A2", "theme": "wahrnehmung"},
    {"id": "aussehen", "infinitive": "aussehen", "level": "A2", "theme": "wahrnehmung"},
    {"id": "anziehen", "infinitive": "anziehen", "level": "A1", "theme": "alltag"},
    {"id": "ausziehen", "infinitive": "ausziehen", "level": "A2", "theme": "alltag"},
    {"id": "einsteigen", "infinitive": "einsteigen", "level": "A2", "theme": "reisen"},
    {"id": "aussteigen", "infinitive": "aussteigen", "level": "A2", "theme": "reisen"},
    {"id": "einschlafen", "infinitive": "einschlafen", "level": "A2", "theme": "alltag"},
    {"id": "mitnehmen", "infinitive": "mitnehmen", "level": "A2", "theme": "alltag"},

    # ----- Strong verbs A1-A2 frequentes (15) -----
    {"id": "lassen", "infinitive": "lassen", "level": "A2", "theme": "alltag"},
    {"id": "halten", "infinitive": "halten", "level": "A2", "theme": "alltag"},
    {"id": "tragen", "infinitive": "tragen", "level": "A2", "theme": "alltag"},
    {"id": "fallen", "infinitive": "fallen", "level": "A2", "theme": "bewegung"},
    {"id": "fangen", "infinitive": "fangen", "level": "B1", "theme": "alltag"},
    {"id": "heißen", "infinitive": "heißen", "level": "A1", "theme": "kommunikation"},
    {"id": "treffen", "infinitive": "treffen", "level": "A2", "theme": "soziales"},
    {"id": "stehen", "infinitive": "stehen", "level": "A1", "theme": "alltag"},
    {"id": "sitzen", "infinitive": "sitzen", "level": "A1", "theme": "alltag"},
    {"id": "liegen", "infinitive": "liegen", "level": "A1", "theme": "alltag"},
    {"id": "rufen", "infinitive": "rufen", "level": "A2", "theme": "kommunikation"},
    {"id": "tun", "infinitive": "tun", "level": "A2", "theme": "alltag"},
    {"id": "ziehen", "infinitive": "ziehen", "level": "B1", "theme": "alltag"},
    {"id": "schließen", "infinitive": "schließen", "level": "A2", "theme": "alltag"},
    {"id": "schneiden", "infinitive": "schneiden", "level": "A2", "theme": "alltag"},

    # ----- Movimento e ação (10) -----
    {"id": "schwimmen", "infinitive": "schwimmen", "level": "A2", "theme": "bewegung"},
    {"id": "springen", "infinitive": "springen", "level": "A2", "theme": "bewegung"},
    {"id": "steigen", "infinitive": "steigen", "level": "B1", "theme": "bewegung"},
    {"id": "rennen", "infinitive": "rennen", "level": "B1", "theme": "bewegung"},
    {"id": "klettern", "infinitive": "klettern", "level": "B1", "theme": "bewegung"},
    {"id": "werfen", "infinitive": "werfen", "level": "B1", "theme": "alltag"},
    {"id": "fließen", "infinitive": "fließen", "level": "B1", "theme": "natur"},
    {"id": "wachsen", "infinitive": "wachsen", "level": "B1", "theme": "natur"},
    {"id": "sterben", "infinitive": "sterben", "level": "B1", "theme": "alltag"},
    {"id": "verschwinden", "infinitive": "verschwinden", "level": "B1", "theme": "bewegung"},

    # ----- Comunicação / Cognição (8) -----
    {"id": "bringen", "infinitive": "bringen", "level": "A1", "theme": "alltag"},
    {"id": "empfehlen", "infinitive": "empfehlen", "level": "B1", "theme": "kommunikation"},
    {"id": "raten", "infinitive": "raten", "level": "B1", "theme": "kognition"},
    {"id": "erkennen", "infinitive": "erkennen", "level": "B1", "theme": "kognition"},
    {"id": "schweigen", "infinitive": "schweigen", "level": "B2", "theme": "kommunikation"},
    {"id": "schreien", "infinitive": "schreien", "level": "B1", "theme": "kommunikation"},
    {"id": "lügen", "infinitive": "lügen", "level": "B1", "theme": "kommunikation"},
    {"id": "vorschlagen", "infinitive": "vorschlagen", "level": "B1", "theme": "kommunikation"},

    # ----- Eventos / Estados (7) -----
    {"id": "geschehen", "infinitive": "geschehen", "level": "B1", "theme": "alltag"},
    {"id": "passieren", "infinitive": "passieren", "level": "A2", "theme": "alltag"},
    {"id": "stattfinden", "infinitive": "stattfinden", "level": "B1", "theme": "alltag"},
    {"id": "scheinen", "infinitive": "scheinen", "level": "B1", "theme": "wahrnehmung"},
    {"id": "klingen", "infinitive": "klingen", "level": "B1", "theme": "wahrnehmung"},
    {"id": "stinken", "infinitive": "stinken", "level": "B2", "theme": "wahrnehmung"},
    {"id": "riechen", "infinitive": "riechen", "level": "B1", "theme": "wahrnehmung"},

    # ----- Ações específicas (6) -----
    {"id": "backen", "infinitive": "backen", "level": "A2", "theme": "essen"},
    {"id": "waschen", "infinitive": "waschen", "level": "A1", "theme": "alltag"},
    {"id": "schießen", "infinitive": "schießen", "level": "B2", "theme": "alltag"},
    {"id": "gewinnen", "infinitive": "gewinnen", "level": "B1", "theme": "alltag"},
    {"id": "schlagen", "infinitive": "schlagen", "level": "B1", "theme": "alltag"},
    {"id": "greifen", "infinitive": "greifen", "level": "B1", "theme": "alltag"},

    # ----- Reflexivos B1+ (4) -----
    {"id": "sich_beeilen", "infinitive": "sich beeilen", "level": "B1", "theme": "alltag"},
    {"id": "sich_entschuldigen", "infinitive": "sich entschuldigen", "level": "A2", "theme": "kommunikation"},
    {"id": "sich_unterhalten", "infinitive": "sich unterhalten", "level": "B1", "theme": "kommunikation"},
    {"id": "sich_setzen", "infinitive": "sich setzen", "level": "A2", "theme": "alltag"},
]


# Schema retornado pelo Gemini
class PersonForms(BaseModel):
    ich: str
    du: str
    er: str   # er/sie/es
    wir: str
    ihr: str
    sie: str  # sie pl. = Sie formal


class VerbExample(BaseModel):
    de: str
    pt: str


class VerbConjugationSchema(BaseModel):
    infinitive: str
    translation_pt: str = Field(description="Tradução para português brasileiro")
    is_irregular: bool = Field(description="True se for starkes/gemischtes Verb")
    is_separable: bool = Field(description="True se for verbo separável (anfangen, aufstehen...)")
    is_reflexive: bool = Field(description="True se for verbo reflexivo (sich freuen...)")
    perfekt_aux: str = Field(description="'haben' ou 'sein'")
    partizip_ii: str = Field(description="Partizip II (ex: gegangen, gemacht)")
    praesens: PersonForms
    praeteritum: PersonForms
    konjunktiv_ii: PersonForms
    imperativ_du: str = Field(description="Forma imperativa para 'du' (ex: 'Geh!')")
    imperativ_ihr: str = Field(description="Forma imperativa para 'ihr' (ex: 'Geht!')")
    imperativ_sie: str = Field(description="Forma imperativa para 'Sie' (ex: 'Gehen Sie!')")
    examples: list[VerbExample] = Field(
        default_factory=list,
        description="2-3 exemplos com tradução em PT",
    )
    notes_pt: str = Field(
        default="",
        description="Observação curta em PT (uso, irregularidades, falsos cognatos)",
    )


SYSTEM = """\
Você é um especialista em gramática alemã. Receberá um infinitivo e deve retornar
um JSON com tabelas COMPLETAS de conjugação.

Formato exato:

{
  "infinitive": "...",
  "translation_pt": "tradução em PT (1-3 sentidos principais)",
  "is_irregular": bool,
  "is_separable": bool,
  "is_reflexive": bool,
  "perfekt_aux": "haben" | "sein",
  "partizip_ii": "...",
  "praesens": {"ich":"", "du":"", "er":"", "wir":"", "ihr":"", "sie":""},
  "praeteritum": {"ich":"", "du":"", "er":"", "wir":"", "ihr":"", "sie":""},
  "konjunktiv_ii": {"ich":"", "du":"", "er":"", "wir":"", "ihr":"", "sie":""},
  "imperativ_du": "...",
  "imperativ_ihr": "...",
  "imperativ_sie": "...",
  "examples": [{"de":"...", "pt":"..."}],
  "notes_pt": "observação curta"
}

Regras críticas:
- Para verbos separáveis (ex: aufstehen), em Präsens/Präteritum a partícula vai
  separada no fim (ich stehe ... auf). Inclua a partícula no final: "stehe auf",
  "stand auf", "stünde auf".
- Para verbos reflexivos, mostre com pronome: "freue mich", "freust dich" etc.
- Para Konjunktiv II irregular, dê a forma sintética quando existe (ginge, käme,
  hätte); para verbos onde só a forma com würden é natural, dê com würden
  ("würde machen").
- Verbos de movimento e mudança de estado usam "sein" como auxiliar.
- Para sein/haben/werden, use as formas corretas (bin/bist/ist..., war/warst/war...).

Retorne APENAS JSON.
"""


def generate_one(item: dict) -> dict | None:
    inf = item["infinitive"]
    console.print(f"[cyan]→[/cyan] [bold]{inf}[/bold] ({item['level']}, {item['theme']})")

    try:
        result: VerbConjugationSchema = gemini.generate_structured(
            f"Infinitivo: {inf}",
            VerbConjugationSchema,
            system_instruction=SYSTEM,
            temperature=0.05,
        )
    except Exception as e:
        console.print(f"  [red]Falha: {e}[/red]")
        logger.exception("verb gen falhou em %s", inf)
        return None

    data = result.model_dump()
    data["id"] = item["id"]
    data["level_cefr"] = item["level"]
    data["theme"] = item["theme"]
    console.print(
        f"  [green]✓[/green] perfekt: {data['perfekt_aux']} + {data['partizip_ii']} · "
        f"irregular: {data['is_irregular']}"
    )
    return data


def generate_all(
    *,
    output_path: Path | None = None,
    only_ids: list[str] | None = None,
    delay_seconds: float = 0.4,
    skip_existing: bool = True,
) -> list[dict]:
    output_path = Path(output_path or (config.OUTPUT_DIR / "seed_verbs.json"))

    verbs = VERBS
    if only_ids:
        verbs = [v for v in verbs if v["id"] in only_ids]

    existing: dict[str, dict] = {}
    if output_path.exists():
        try:
            existing_list = json.loads(output_path.read_text(encoding="utf-8"))
            existing = {v["id"]: v for v in existing_list if "id" in v}
        except Exception as e:
            console.print(f"[yellow]Não consegui ler {output_path.name}: {e}[/yellow]")

    if skip_existing and not only_ids:
        before = len(verbs)
        verbs = [v for v in verbs if v["id"] not in existing]
        skipped = before - len(verbs)
        if skipped:
            console.print(f"[dim]Pulando {skipped} verbos já gerados[/dim]")

    console.print(f"[bold]Gerando {len(verbs)} verbos[/bold]\n")

    merged = dict(existing)

    def _persist() -> None:
        payload = [merged[k] for k in sorted(merged.keys())]
        output_path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    new_verbs: list[dict] = []
    for v in verbs:
        data = generate_one(v)
        if data:
            merged[data["id"]] = data
            new_verbs.append(data)
            _persist()
        time.sleep(delay_seconds)

    console.print(
        f"\n[bold green]✓[/bold green] {len(new_verbs)} novos, "
        f"{len(merged)} no total em {output_path}"
    )
    return new_verbs
