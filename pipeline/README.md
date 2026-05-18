# Alemão Content Pipeline

Pipeline Python que processa PDFs pessoais de aprendizado de alemão e gera artefatos SQLite + JSON consumidos pelo app iOS.

## Pré-requisitos

- **Python 3.11+** (recomendado via [`uv`](https://docs.astral.sh/uv/))
- **Tesseract** (para OCR de PDFs escaneados):
  ```bash
  brew install tesseract tesseract-lang
  brew install poppler   # para pdf2image
  ```
- **Chave da API Gemini** — obter em https://aistudio.google.com/apikey

## Setup

```bash
cd pipeline
uv sync                        # instala dependências do pyproject.toml
cp .env.example .env           # depois edite e coloque sua GEMINI_API_KEY
```

Valide a instalação:
```bash
uv run python -m alemao_pipeline init
# Deve criar output/library.sqlite e output/dictionary.sqlite vazios
```

## Uso

### 1. Coloque seus PDFs em `books/`

```
pipeline/books/
├── hammers-german-grammar.pdf
├── schaums-german-grammar.pdf
├── pons-worterbuch-pt-de.pdf
└── ...
```

Tipos esperados (detectados automaticamente):
- **grammar** — livros-texto de gramática
- **workbook** — cadernos de exercícios
- **dictionary** — dicionários (entrarão em `dictionary.sqlite` ao invés de chunks)
- **reader** — leitores graduados, contos
- **other** — qualquer outro

### 2. Ingestão completa

```bash
uv run python -m alemao_pipeline ingest
```

Para cada PDF:
1. Extrai texto via PyMuPDF (+ OCR via Tesseract em páginas escaneadas)
2. Classifica via Gemini → grammar / workbook / dictionary / reader
3. Se dicionário: parseia entradas estruturadas (regex + LLM fallback)
4. Caso contrário: chunka semanticamente (TOC-aware) e gera embeddings via `gemini-embedding-001`

### 3. Variações úteis

```bash
# Ingere apenas um PDF
uv run python -m alemao_pipeline ingest --only hammers-german-grammar.pdf

# Pula embeddings (mais rápido; depois roda separado)
uv run python -m alemao_pipeline ingest --skip-embeddings
uv run python -m alemao_pipeline embed

# Sem OCR (apenas texto extraível)
uv run python -m alemao_pipeline ingest --no-ocr
```

### 4. Inspecionar resultados

```bash
uv run python -m alemao_pipeline stats        # contagens por livro
uv run python -m alemao_pipeline sample       # amostras de chunks aleatórios
uv run python -m alemao_pipeline sample --book-id book_XYZ --n 5
```

### 5. Testar retrieval (RAG end-to-end)

```bash
uv run python -m alemao_pipeline retrieve "Akkusativ pronouns"
uv run python -m alemao_pipeline retrieve "verbos modais" --n 3
```

Retorna os top-N chunks via híbrido FTS5 (lexical) + cosine (semântico) + RRF.

### 6. Gerar seed lessons (lições iniciais por tópico)

```bash
uv run python -m alemao_pipeline seed-lessons
# ou só alguns tópicos:
uv run python -m alemao_pipeline seed-lessons --only akkusativ --only dativ
```

Gera `output/seed_lessons.json` com lições estruturadas em português (explicação,
exemplos, exercícios e citações com page numbers) para cada tópico de
`sources.yml`. Esse JSON é bundleado no app iOS para conteúdo offline desde o
primeiro launch.

### 7. Exportar para o iOS

```bash
../scripts/sync_content.sh                # só os SQLites + JSONs (default)
../scripts/sync_content.sh --with-pdfs    # também copia os PDFs (build pessoal)
```

Copia `output/*` → `ios/Alemao/Resources/PrebuiltContent/`.

## Output

Após ingest, em `pipeline/output/`:

| Arquivo | Conteúdo |
| --- | --- |
| `library.sqlite` | Tabelas `books`, `chunks` (com embeddings), `chunks_fts` (FTS5) |
| `dictionary.sqlite` | Tabela `entries` (palavras + traduções + exemplos) |
| `books_meta.json` | Resumo de todos os livros ingeridos (para iOS) |
| `seed_lessons.json` | (futuro) Lições iniciais geradas por tópico |

## Arquitetura

```
books/*.pdf
   │
   ├─→ extract.py (PyMuPDF + pytesseract)
   │       │
   │       ▼
   ├─→ classify.py (Gemini → type)
   │       │
   │       ▼
   ├─→ se 'dictionary':  dict_parser.py → dictionary.sqlite
   │
   └─→ senão: chunker.py → embeddings.py → library.sqlite
```

## Idempotência

- O hash SHA-256 do PDF é registrado em `books.file_hash`. Re-rodar `ingest` pula livros já processados.
- Chunks têm `text_hash`; embeddings só são re-gerados se o modelo mudar.
- Re-rode com segurança após adicionar novos PDFs em `books/`.

## Custos estimados (Gemini)

Para 10 livros médios (~300 pp cada):
- Classificação: 10 chamadas Flash ≈ $0.01
- Embeddings: ~5.000 chunks × ~800 tokens ≈ 4M tokens → ~$0.50–1.00 com `gemini-embedding-001`
- Dict parsing LLM fallback: variável (poucos centavos)

## Próximos comandos (a implementar)

- `fetch-public` — baixar DW Learn German, Wiktionary, Tatoeba
- `seed-lessons` — gerar lições iniciais por tópico em `seed_lessons.json`
- `export-ios` — copiar output para `ios/Alemao/Resources/PrebuiltContent/`
