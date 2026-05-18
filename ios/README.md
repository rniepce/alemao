# Alemão — App iOS (Trilha B)

App SwiftUI nativo que consome o output da Trilha A (`pipeline/`) bundleado em
`Resources/PrebuiltContent/`.

## Pré-requisitos

- **Xcode 15+** (testado em Xcode 26)
- **iOS 17+** como deployment target
- **xcodegen** para gerar o `.xcodeproj` a partir de `project.yml`. Instale via uma destas opções:

  ```bash
  # opção A: Homebrew (caso instale brew depois)
  brew install xcodegen

  # opção B: Mint
  mint install yonaskolb/xcodegen

  # opção C: baixar binário da release oficial
  curl -L https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip -o /tmp/xcodegen.zip
  unzip /tmp/xcodegen.zip -d /tmp/xcodegen
  sudo /tmp/xcodegen/install.sh
  ```

  Se preferir **não usar xcodegen**, abra `ios/` no Xcode e crie um novo iOS App Project no mesmo
  diretório, mantendo os arquivos `Alemao/*.swift` (Xcode os incorpora automaticamente).
  Adicione o pacote Swift `https://github.com/groue/GRDB.swift` em Package Dependencies.

## Setup

### 1. Sincronizar o conteúdo do pipeline

```bash
# da raiz do monorepo:
./scripts/sync_content.sh

# ou se quiser bundlear os PDFs também (build pessoal/sideload):
./scripts/sync_content.sh --with-pdfs
```

Isso copia `pipeline/output/{library,dictionary}.sqlite` e `*.json` para
`ios/Alemao/Resources/PrebuiltContent/`.

### 2. Gerar o .xcodeproj

```bash
cd ios
xcodegen generate
open Alemao.xcodeproj
```

### 3. Configurar signing

No Xcode → target Alemao → Signing & Capabilities → escolha sua equipe pessoal.

Para sync via iCloud (opcional nesta fase):
- Adicionar capability **iCloud** → marcar **CloudKit**
- Criar container `iCloud.dev.alemao.userdata` (ou ajustar bundle id)

### 4. Build & Run

Selecione um simulador iPhone 15 Pro (ou seu device pessoal), e rode.

## Funcionalidades implementadas (Fases 5-12)

8 abas no app, todas funcionais:

- **Início** — Dashboard com saudação, streak, plano diário (4 tarefas), lição sugerida, estatísticas
- **Vocab** — Decks, revisão SRS (SM-2), flashcards com gênero colorido, áudio TTS de-DE, "Errei/Difícil/Bom/Fácil"
- **Gramática** — 20 seed lessons (Akkusativ, Konjunktiv II, etc.) + "Pergunte ao tutor" (RAG) + Geração on-demand
- **Leitura** — Geração de textos sob demanda no nível CEFR escolhido, com **tap-to-translate** em qualquer palavra, glossário e quiz de compreensão
- **Escrita** — Editor + diário de entradas + correção estruturada (erros por categoria com citações clicáveis aos livros)
- **Fala** — 5 role-plays (café Berlim A1 → debate clima C1), **speech-to-speech via Gemini Live API** (microfone → Gemini → áudio nativo de volta)
- **Biblioteca** — Lista dos livros bundleados + tela debug "Testar busca (RAG)" com FTS5+cosine+RRF
- **Ajustes** — BYOK (Keychain), teste de conexão, stats do conteúdo

Onboarding completo no primeiro launch:
1. Boas-vindas com 4 destaques
2. Coleta de chave Gemini + teste imediato
3. Perfil (nome)
4. Teste de nivelamento adaptativo (12 questões geradas pelo LLM)
5. Resultado CEFR estimado → cria `User`

## Próximas fases (não implementadas)

- **Fase 13** — UserLibrary on-device (importar PDFs adicionais sem usar o pipeline Python)
- **Fase 14** — Polimento: widgets iOS, notificações de revisão SRS, testes UI

## Arquitetura

Veja `~/.claude/plans/idempotent-crafting-oasis.md` para o plano completo.

Diretórios:
- `Alemao/Models/` — SwiftData @Model (estado do usuário; sincroniza via CloudKit)
- `Alemao/Services/LLM/` — APIKeyStore (Keychain), LLMClient (proto), GeminiClient (REST)
- `Alemao/Services/Library/` — LibraryDB, DictionaryDB, Retriever, SourceRouter, SeedLessonLoader
- `Alemao/Features/` — Home, Library, Settings (uma pasta por feature)
- `Alemao/Resources/PrebuiltContent/` — output do pipeline (read-only, bundleado)
