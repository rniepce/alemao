# Setup do Widget Extension

Os arquivos do widget já estão em `ios/Alemao/AlemaoWidgets/`. Para integrá-los no Xcode (3 minutos):

## 1. Adicionar Widget Extension target

1. No Xcode, com `Alemao.xcodeproj` aberto:
2. **File → New → Target…**
3. iOS → **Widget Extension** → Next
4. Preencha:
   - **Product Name**: `AlemaoWidgets`
   - **Team**: seu Apple ID
   - **Bundle Identifier**: deixa o Xcode preencher (`Rafael-Niepce.Alemao.AlemaoWidgets`)
   - **Include Configuration App Intent**: ❌ **desmarcar** (usamos `StaticConfiguration`)
   - **Embed in Application**: **Alemao**
5. Finish
6. Se o Xcode perguntar "Activate AlemaoWidgets scheme?" → **Activate**

O Xcode vai gerar uma pasta nova `AlemaoWidgets/` com `AlemaoWidgetsBundle.swift`, `AlemaoWidgets.swift`, `Info.plist`, etc.

## 2. Substituir os arquivos gerados pelos nossos

Os nossos arquivos já estão em `ios/Alemao/AlemaoWidgets/` (no disco). Você precisa fazer o Xcode reconhecer:

**Opção A — via Finder (mais rápido):**
1. Feche o Xcode (Cmd+Q)
2. No Finder, navegue até `ios/Alemao/AlemaoWidgets/` (gerada pelo Xcode no passo 1)
3. **Apague** os arquivos `.swift` que o Xcode gerou (`AlemaoWidgetsBundle.swift`, `AlemaoWidgets.swift` etc)
4. Não há mais nada a fazer — nossos arquivos já estão lá com os mesmos nomes. O Xcode usa `PBXFileSystemSynchronizedRootGroup` (igual ao app principal), então qualquer `.swift` nessa pasta vira parte do target automaticamente.
5. Reabra Xcode

**Opção B — via Xcode UI:**
1. No Project Navigator, expanda o group `AlemaoWidgets`
2. Right-click nos `.swift` gerados → Delete → **Move to Trash**
3. Right-click no group → **Add Files to "Alemao"** → selecione nossos 4 arquivos em `ios/Alemao/AlemaoWidgets/`
4. ❌ Copy items if needed, ⚪ Create groups, ✅ Target: AlemaoWidgets

## 3. Configurar App Group (compartilhamento de dados)

**Target `Alemao` (app principal):**
1. Selecione o target Alemao → **Signing & Capabilities**
2. `+ Capability` → **App Groups**
3. Marque (ou crie se não existir) `group.dev.alemao.shared`

**Target `AlemaoWidgets`:**
1. Selecione o target AlemaoWidgets → **Signing & Capabilities**
2. `+ Capability` → **App Groups**
3. Marque o mesmo `group.dev.alemao.shared`

> O entitlements file (`Alemao.entitlements` e `AlemaoWidgets.entitlements`) já tem o App Group declarado, mas o Xcode precisa confirmar com o Developer Portal — daí o passo via UI.

## 4. Build & Test

1. Selecione o scheme **Alemao** (não AlemaoWidgets)
2. Cmd+R para rodar no simulador ou device
3. No iPhone, segure a home screen → **+** no canto → busque "Alemão" → arraste o widget pra tela

Os widgets disponíveis:

| Widget | Tamanhos | Mostra |
|---|---|---|
| **Palavra do dia** | Small, Medium | Headword + gênero colorido + tradução + cards pendentes |
| **Streak** | Small, Circular (lock), Rectangular (lock), Inline (lock) | Dias seguidos + XP + pendentes |

## 5. Quando os dados aparecem?

O widget é atualizado em 3 momentos:
1. **App launch** — o `HomeView` chama `WidgetDataPublisher.publish()` ao iniciar
2. **Após cada review SRS** — o `ReviewSessionView` republica com a palavra recém-revisada como "palavra do dia"
3. **A cada hora** — o `TimelineProvider` renova automaticamente

Se o widget estiver vazio depois de instalar:
- Abra o app e revise pelo menos 1 card de vocabulário
- O widget vai se atualizar em segundos
