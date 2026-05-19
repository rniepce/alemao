"""Gera decks temáticos de vocabulário comum.

6 decks × ~40 palavras = ~240 cards:
- Família & relacionamentos
- Comida & bebida
- Viagem & transporte
- Trabalho & profissões
- Corpo humano & saúde
- Números, cores & tempo

Cada palavra tem: headword, gender, translation_pt, example_de+pt, level_cefr.

Output: `output/seed_vocab.json`
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


# Listas curadas por tema. As palavras seguem ordenação aprox. por frequência/utilidade.
THEMES: dict[str, dict] = {
    "familie": {
        "title": "Família e Relacionamentos",
        "level_default": "A1",
        "words": [
            "Familie", "Vater", "Mutter", "Eltern", "Sohn", "Tochter", "Kind",
            "Bruder", "Schwester", "Geschwister", "Großvater", "Großmutter",
            "Onkel", "Tante", "Cousin", "Cousine", "Mann", "Frau", "Ehemann",
            "Ehefrau", "Freund", "Freundin", "Junge", "Mädchen", "Baby",
            "verheiratet", "ledig", "geschieden", "schwanger", "Hochzeit",
            "Geburtstag", "Liebe", "lieben", "küssen", "umarmen", "streiten",
            "Beziehung", "Familienmitglied", "Verwandte", "Nachbar",
        ],
    },
    "essen": {
        "title": "Comida e Bebida",
        "level_default": "A1",
        "words": [
            "Essen", "Frühstück", "Mittagessen", "Abendessen", "Brot", "Butter",
            "Käse", "Wurst", "Schinken", "Ei", "Milch", "Wasser", "Kaffee",
            "Tee", "Saft", "Bier", "Wein", "Apfel", "Banane", "Tomate",
            "Kartoffel", "Salat", "Fleisch", "Fisch", "Hähnchen", "Reis",
            "Nudeln", "Suppe", "Kuchen", "Schokolade", "Zucker", "Salz",
            "Pfeffer", "Restaurant", "Kellner", "Speisekarte", "Rechnung",
            "lecker", "hungrig", "durstig", "kochen", "essen", "trinken",
        ],
    },
    "reisen": {
        "title": "Viagem e Transporte",
        "level_default": "A2",
        "words": [
            "Reise", "Urlaub", "Flugzeug", "Zug", "Bus", "Auto", "Fahrrad",
            "U-Bahn", "Straßenbahn", "Taxi", "Bahnhof", "Flughafen",
            "Haltestelle", "Hotel", "Hostel", "Pension", "Zimmer", "Bett",
            "Koffer", "Rucksack", "Pass", "Ticket", "Fahrkarte", "Karte",
            "Stadt", "Land", "Strand", "Berg", "See", "Fluss", "Brücke",
            "Straße", "Weg", "Reservierung", "Ankunft", "Abfahrt",
            "Verspätung", "Gepäck", "fahren", "fliegen", "buchen", "ankommen",
        ],
    },
    "arbeit": {
        "title": "Trabalho e Profissões",
        "level_default": "A2",
        "words": [
            "Arbeit", "Beruf", "Job", "Büro", "Firma", "Unternehmen", "Chef",
            "Kollege", "Kollegin", "Mitarbeiter", "Lehrer", "Lehrerin", "Arzt",
            "Ärztin", "Ingenieur", "Anwalt", "Polizist", "Verkäufer", "Koch",
            "Friseur", "Bäcker", "Krankenschwester", "Manager", "Sekretär",
            "Praktikant", "Bewerbung", "Lebenslauf", "Vorstellungsgespräch",
            "Gehalt", "Lohn", "Pause", "Urlaubstag", "Sitzung", "Termin",
            "Computer", "Drucker", "E-Mail", "Telefon", "Meeting",
            "arbeiten", "verdienen", "kündigen",
        ],
    },
    "koerper": {
        "title": "Corpo e Saúde",
        "level_default": "A2",
        "words": [
            "Körper", "Kopf", "Haar", "Auge", "Nase", "Mund", "Ohr", "Zahn",
            "Hals", "Schulter", "Arm", "Hand", "Finger", "Bauch", "Rücken",
            "Bein", "Knie", "Fuß", "Herz", "Lunge", "Magen", "Haut",
            "Knochen", "Blut", "Muskel", "Gesundheit", "Krankheit", "Schmerz",
            "Fieber", "Erkältung", "Grippe", "Husten", "Kopfschmerzen",
            "Bauchschmerzen", "Medikament", "Tablette", "Arzt", "Apotheke",
            "Krankenhaus", "krank", "gesund", "wehtun",
        ],
    },
    "zahlen_farben": {
        "title": "Números, Cores e Tempo",
        "level_default": "A1",
        "words": [
            "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht",
            "neun", "zehn", "zwanzig", "hundert", "tausend",
            "rot", "blau", "grün", "gelb", "schwarz", "weiß", "braun", "grau",
            "orange", "rosa", "lila",
            "Stunde", "Minute", "Sekunde", "Tag", "Woche", "Monat", "Jahr",
            "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag",
            "heute", "morgen", "gestern", "jetzt", "spät", "früh",
        ],
    },

    # ===== EXPANSÃO: +6 decks temáticos =====

    "staedte": {
        "title": "Cidades e Geografia Alemã",
        "level_default": "A2",
        "words": [
            "Berlin", "München", "Hamburg", "Köln", "Frankfurt", "Stuttgart",
            "Düsseldorf", "Leipzig", "Dresden", "Hannover", "Bremen", "Nürnberg",
            "Bundesland", "Bayern", "Sachsen", "Hessen", "Niedersachsen",
            "Rheinland-Pfalz", "Norden", "Süden", "Osten", "Westen",
            "Hauptstadt", "Großstadt", "Kleinstadt", "Dorf", "Land", "Bundesrepublik",
            "Grenze", "Berg", "Tal", "Fluss", "Rhein", "Donau", "Elbe",
            "Alpen", "Schwarzwald", "Ostsee", "Nordsee", "Sehenswürdigkeit",
            "Brandenburger Tor", "Schloss", "Dom",
        ],
    },

    "medien": {
        "title": "Mídia e Tecnologia",
        "level_default": "B1",
        "words": [
            "Medien", "Internet", "Nachricht", "Zeitung", "Zeitschrift", "Magazin",
            "Fernsehen", "Radio", "Podcast", "Sendung", "Film", "Serie",
            "Schauspieler", "Schauspielerin", "Regisseur", "Kanal", "Sender",
            "Werbung", "Anzeige", "Streaming", "Plattform", "Soziale Medien",
            "Beitrag", "Kommentar", "Like", "teilen", "abonnieren", "folgen",
            "Computer", "Laptop", "Handy", "Smartphone", "App", "Bildschirm",
            "Tastatur", "Maus", "WLAN", "Passwort", "Konto",
            "klicken", "herunterladen", "hochladen", "speichern", "löschen", "drucken",
        ],
    },

    "hobbies": {
        "title": "Hobbies e Tempo Livre",
        "level_default": "A2",
        "words": [
            "Hobby", "Freizeit", "Sport", "Musik", "Kunst", "Lesen", "Tanzen",
            "Wandern", "Reisen", "Kochen", "Garten", "Fotografie", "Film",
            "Theater", "Konzert", "Museum", "Ausstellung", "Bibliothek",
            "Fußball", "Tennis", "Schwimmen", "Yoga", "Fitness", "Joggen",
            "Fahrradfahren", "Skifahren", "Surfen", "Schach", "Karten",
            "Brettspiel", "Videospiel", "Buch", "Roman", "Comic",
            "Gitarre", "Klavier", "Lied", "Band", "Festival",
            "Pinsel", "Stift", "Kamera", "Foto", "malen", "singen", "spielen",
        ],
    },

    "religion": {
        "title": "Religião e Filosofia",
        "level_default": "B2",
        "words": [
            "Religion", "Gott", "Glaube", "Kirche", "Kathedrale", "Kapelle",
            "Tempel", "Moschee", "Synagoge", "Pfarrer", "Priester", "Pastor",
            "Mönch", "Nonne", "Bibel", "Koran", "Tora", "Gebet", "Messe",
            "Gottesdienst", "Predigt", "Christentum", "Judentum", "Islam",
            "Buddhismus", "Hinduismus", "Atheismus", "Spiritualität", "Seele",
            "Geist", "Engel", "Heilige", "Himmel", "Hölle", "Paradies",
            "Sünde", "Vergebung", "Gnade", "Wunder",
            "beten", "glauben", "taufen", "segnen",
            "Philosophie", "Ethik", "Moral",
        ],
    },

    "politik": {
        "title": "Política e Sociedade",
        "level_default": "B2",
        "words": [
            "Politik", "Regierung", "Bundeskanzler", "Bundespräsident", "Minister",
            "Bundestag", "Bundesrat", "Partei", "Koalition", "Opposition",
            "Wahl", "Wähler", "Wahlrecht", "Stimme", "Mehrheit", "Minderheit",
            "Demokratie", "Diktatur", "Monarchie", "Republik", "Verfassung",
            "Grundgesetz", "Gesetz", "Recht", "Pflicht", "Bürger", "Bürgerin",
            "Staat", "Land", "Nation", "Europa", "EU", "Vereinte Nationen",
            "Krieg", "Frieden", "Migration", "Asyl", "Integration",
            "Demonstration", "Protest", "Streik",
            "wählen", "regieren", "entscheiden", "abstimmen",
        ],
    },

    "finanzen": {
        "title": "Dinheiro e Finanças",
        "level_default": "A2",
        "words": [
            "Geld", "Euro", "Cent", "Münze", "Geldschein", "Bargeld",
            "Bank", "Konto", "Kontonummer", "IBAN", "Kreditkarte", "EC-Karte",
            "Überweisung", "Lastschrift", "Geldautomat", "Wechselkurs",
            "Einkommen", "Gehalt", "Lohn", "Steuer", "Rente", "Versicherung",
            "Kredit", "Schulden", "Sparen", "Investition", "Aktie", "Fonds",
            "Inflation", "Rechnung", "Quittung", "Preis", "Kosten", "Ausgabe",
            "Einnahme", "Gewinn", "Verlust", "Budget", "billig", "teuer",
            "bezahlen", "kaufen", "verkaufen", "sparen", "leihen",
        ],
    },
}


class WordEntry(BaseModel):
    headword: str
    gender: str | None = Field(
        default=None,
        description="'der', 'die' ou 'das' para substantivos; null caso contrário",
    )
    pos: str = Field(description="noun|verb|adj|adv|prep|conj|num|interj")
    translation_pt: str = Field(description="Tradução em PT (1-3 sentidos principais)")
    example_de: str = Field(description="Exemplo curto e natural em alemão")
    example_pt: str = Field(description="Tradução em PT do exemplo")


class WordList(BaseModel):
    entries: list[WordEntry]


SYSTEM = """\
Você prepara cards de vocabulário alemão-português brasileiro.

Receberá uma lista de palavras alemãs e o nível CEFR alvo. Para cada palavra,
retorne JSON estruturado:

{
  "entries": [
    {
      "headword": "palavra alemã",
      "gender": "der" | "die" | "das" | null,
      "pos": "noun" | "verb" | "adj" | "adv" | "prep" | "conj" | "num" | "interj",
      "translation_pt": "tradução em PT (curta, 1-3 sentidos)",
      "example_de": "frase curta natural em alemão",
      "example_pt": "tradução em PT da frase"
    }
  ]
}

Regras:
- gender APENAS para substantivos (pos=noun); senão null.
- Tradução em português brasileiro, simples, sem firulas.
- Exemplo natural, sem ser artificial. Curto (5-10 palavras).
- Preserve a ordem das palavras da entrada.
- Retorne APENAS JSON.
"""


def generate_theme(theme_id: str, theme: dict, *, batch_size: int = 20) -> list[dict]:
    """Gera entries para um tema, em batches de batch_size palavras."""
    words = theme["words"]
    level = theme["level_default"]
    console.print(f"[bold]→ Tema {theme_id}[/bold] ({theme['title']}, {level}): {len(words)} palavras")

    all_entries: list[dict] = []
    for i in range(0, len(words), batch_size):
        batch = words[i : i + batch_size]
        prompt = (
            f"Nível CEFR alvo: {level}\nTema: {theme['title']}\n\n"
            f"Palavras a processar (na ordem):\n" + "\n".join(f"- {w}" for w in batch)
        )
        try:
            result: WordList = gemini.generate_structured(
                prompt, WordList, system_instruction=SYSTEM, temperature=0.1
            )
        except Exception as e:
            console.print(f"  [red]Falha batch {i}: {e}[/red]")
            logger.exception("vocab gen falhou em tema %s batch %d", theme_id, i)
            continue
        for entry in result.entries:
            data = entry.model_dump()
            data["level_cefr"] = level
            data["theme"] = theme_id
            data["theme_title"] = theme["title"]
            all_entries.append(data)
        console.print(
            f"  [green]✓[/green] batch {i // batch_size + 1}: "
            f"+{len(result.entries)} palavras"
        )
    return all_entries


def generate_all(
    *,
    output_path: Path | None = None,
    only_themes: list[str] | None = None,
    skip_existing: bool = True,
    delay_seconds: float = 1.0,
) -> list[dict]:
    output_path = Path(output_path or (config.OUTPUT_DIR / "seed_vocab.json"))

    themes = THEMES
    if only_themes:
        themes = {k: v for k, v in themes.items() if k in only_themes}

    existing: dict[str, list[dict]] = {}
    if output_path.exists():
        try:
            existing_list = json.loads(output_path.read_text(encoding="utf-8"))
            for entry in existing_list:
                t = entry.get("theme")
                existing.setdefault(t, []).append(entry)
        except Exception as e:
            console.print(f"[yellow]Não consegui ler {output_path.name}: {e}[/yellow]")

    merged: dict[str, list[dict]] = dict(existing)

    def _persist() -> None:
        flat = [e for entries in merged.values() for e in entries]
        output_path.write_text(
            json.dumps(flat, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    new_total = 0
    for theme_id, theme in themes.items():
        if skip_existing and not only_themes and theme_id in existing:
            console.print(f"[dim]Tema {theme_id} já gerado, pulando[/dim]")
            continue
        entries = generate_theme(theme_id, theme)
        merged[theme_id] = entries
        new_total += len(entries)
        _persist()
        time.sleep(delay_seconds)

    flat = [e for entries in merged.values() for e in entries]
    console.print(
        f"\n[bold green]✓[/bold green] {new_total} novas palavras, "
        f"{len(flat)} no total em {output_path}"
    )
    return flat
