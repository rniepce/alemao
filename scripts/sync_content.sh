#!/usr/bin/env bash
# Copia os artefatos do pipeline para o bundle do app iOS.
#
# Uso: ./scripts/sync_content.sh [--with-pdfs]
#
# Por padrão copia só library.sqlite + dictionary.sqlite + JSONs.
# Com --with-pdfs também copia os PDFs originais para Resources/Books/
# (use apenas para builds pessoais — NÃO para App Store).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIPELINE_OUTPUT="$ROOT/pipeline/output"
PIPELINE_BOOKS="$ROOT/pipeline/books"
IOS_PREBUILT="$ROOT/ios/Alemao/Alemao/Resources/PrebuiltContent"
IOS_BOOKS="$ROOT/ios/Alemao/Alemao/Resources/Books"

WITH_PDFS=0
for arg in "$@"; do
  case "$arg" in
    --with-pdfs) WITH_PDFS=1 ;;
    -h|--help)
      echo "Uso: $0 [--with-pdfs]"
      exit 0
      ;;
  esac
done

if [[ ! -d "$PIPELINE_OUTPUT" ]]; then
  echo "Erro: $PIPELINE_OUTPUT não existe. Rode o pipeline primeiro." >&2
  exit 1
fi

mkdir -p "$IOS_PREBUILT"

echo "→ Copiando artefatos do pipeline para $IOS_PREBUILT"
for f in library.sqlite dictionary.sqlite books_meta.json \
         seed_lessons.json seed_readings.json \
         seed_vocab.json seed_verbs.json; do
  src="$PIPELINE_OUTPUT/$f"
  if [[ -f "$src" ]]; then
    cp -v "$src" "$IOS_PREBUILT/"
  else
    echo "  (ausente: $f — pule se ainda não foi gerado)"
  fi
done

if [[ "$WITH_PDFS" -eq 1 ]]; then
  echo ""
  echo "→ Copiando PDFs originais para $IOS_BOOKS"
  mkdir -p "$IOS_BOOKS"
  if compgen -G "$PIPELINE_BOOKS/*.pdf" > /dev/null; then
    cp -v "$PIPELINE_BOOKS"/*.pdf "$IOS_BOOKS/"
  else
    echo "  (nenhum PDF em $PIPELINE_BOOKS)"
  fi
  echo ""
  echo "⚠️  Lembre-se: PDFs originais só em builds pessoais. Remova antes de publicar."
fi

echo ""
echo "✓ Sync concluído."
