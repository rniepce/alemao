# Alemão — App de aprendizado de alemão

Monorepo com duas trilhas:

- **`pipeline/`** — Pipeline Python que processa seus PDFs (gramática, workbooks, dicionários), baixa conteúdo de sites públicos (DW, Wiktionary, Tatoeba) e gera SQLite + JSON bundleados no app iOS.
- **`ios/`** — App iOS nativo (SwiftUI) que consome o output do pipeline. (Ainda não implementado — começa após pipeline estar validado.)

## Quick start (pipeline)

```bash
cd pipeline
uv sync                          # instala dependências
cp .env.example .env             # configurar GEMINI_API_KEY
# colocar seus PDFs em pipeline/books/
uv run python -m alemao_pipeline ingest
uv run python -m alemao_pipeline stats
```

Veja `pipeline/README.md` para detalhes completos.

## Decisões arquiteturais

Veja `~/.claude/plans/idempotent-crafting-oasis.md` para o plano completo.
