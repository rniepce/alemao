# Setup do projeto Xcode (sem xcodegen)

Como integrar os 50 arquivos Swift já existentes em `ios/Alemao/` num projeto Xcode novo.

## 1. Renomear a pasta atual temporariamente

Para o Xcode não dar conflito ao criar a estrutura padrão dele:

```bash
cd /Users/danielabueno/Downloads/alemao/ios
mv Alemao _swift_files
```

## 2. Criar o projeto no Xcode

1. Abrir **Xcode** → **File → New → Project…**
2. iOS → **App** → Next
3. Preencher:
   - **Product Name**: `Alemao`
   - **Team**: seu Apple ID (pode setar depois)
   - **Organization Identifier**: `dev.alemao` (Bundle Id final: `dev.alemao.Alemao`)
   - **Interface**: **SwiftUI**
   - **Language**: **Swift**
   - **Storage**: **SwiftData**
   - **Host in CloudKit**: deixe **marcado** (sync via iCloud)
   - **Include Tests**: opcional (eu sugiro marcar)
4. Next
5. **Save in**: `/Users/danielabueno/Downloads/alemao/ios/`
6. **Source Control**: **desmarque** (o monorepo raiz já tem git)
7. Create

Resultado: Xcode cria `ios/Alemao.xcodeproj` + `ios/Alemao/` com:
- `AlemaoApp.swift` (placeholder)
- `ContentView.swift` (placeholder)
- `Item.swift` (modelo SwiftData de exemplo)
- `Assets.xcassets/`
- `Preview Content/`

## 3. Fundir os arquivos reais com a pasta do Xcode

**Feche o Xcode** (Cmd+Q) para evitar locks.

```bash
cd /Users/danielabueno/Downloads/alemao/ios

# Remove placeholders que o Xcode criou
rm -f Alemao/AlemaoApp.swift Alemao/ContentView.swift Alemao/Item.swift

# Apaga Assets.xcassets do _swift_files (vamos usar a que o Xcode criou)
rm -rf _swift_files/Resources/Assets.xcassets

# Copia TODO o resto pra dentro de Alemao/
cp -R _swift_files/* Alemao/

# Limpa
rm -rf _swift_files
```

Agora `ios/Alemao/` tem:
- `AlemaoApp.swift` (nosso, com schema completo)
- `RootView.swift`
- `Components/`, `Features/`, `Models/`, `Services/`
- `Resources/PrebuiltContent/` (4 arquivos do pipeline)
- `Assets.xcassets/` (criada pelo Xcode)
- `Preview Content/`

## 4. Reabrir o Xcode e adicionar os arquivos ao target

```bash
open Alemao.xcodeproj
```

No **Project Navigator** (sidebar esquerda):

1. **Right-click no group `Alemao`** → **Add Files to "Alemao"…**
2. Selecione (Cmd+click) **cada uma** dessas pastas em `ios/Alemao/`:
   - `Components`
   - `Features`
   - `Models`
   - `Services`
   - **e os 2 arquivos soltos** `AlemaoApp.swift` e `RootView.swift`
3. Opções do diálogo:
   - **Destination**: ✅ **Copy items if needed** → **DESMARCADO**
   - **Added folders**: ⚪ **Create groups** (NÃO folder references) — para o código Swift
   - **Add to targets**: ✅ **Alemao** marcado
4. Add

5. Agora **especificamente para o conteúdo bundleado**:
   - Right-click `Alemao` group → **Add Files to "Alemao"…**
   - Selecione **apenas** `Resources/PrebuiltContent`
   - Opções:
     - Copy items if needed: **DESMARCADO**
     - **Create folder references** (✅) — fica azul no Xcode, copia o diretório intacto pro bundle
     - Add to targets: **Alemao**
   - Add

> **Por que folder reference para PrebuiltContent?** Porque o código usa `Bundle.main.url(forResource: …, subdirectory: "PrebuiltContent")`, que exige que `PrebuiltContent/` seja preservada como subdiretório no app bundle.

## 5. Adicionar a dependência GRDB

1. No Xcode: **File → Add Package Dependencies…**
2. URL no canto superior direito: `https://github.com/groue/GRDB.swift`
3. Dependency Rule: **Up to Next Major Version** — `7.7.1`
4. Add Package
5. No diálogo seguinte: marque **GRDB** + Target: **Alemao** → Add Package

## 6. Permissões no Info.plist

1. Selecione o target **Alemao** no inspector do projeto
2. Aba **Info** → seção **Custom iOS Target Properties**
3. Adicione (botão `+`):

| Key | Type | Value |
|---|---|---|
| `Privacy - Microphone Usage Description` | String | `O Alemão usa o microfone para você praticar conversação em alemão.` |
| `Privacy - Speech Recognition Usage Description` | String | `O Alemão usa reconhecimento de fala para avaliar sua pronúncia.` |
| `Privacy - Camera Usage Description` | String | `O Alemão usa a câmera para reconhecer texto em alemão.` |

(O Xcode mostra "Privacy - …" mas internamente é `NSMicrophoneUsageDescription` etc.)

## 7. Signing & Capabilities

1. Target Alemao → aba **Signing & Capabilities**
2. **Team**: seu Apple ID (gratuito serve)
3. **Bundle Identifier**: `dev.alemao.Alemao` (ou qualquer único pra você)
4. **Sign in with Apple** (obrigatório — usado no onboarding):
   - Botão `+ Capability` → **Sign in with Apple**
   - O Xcode cria automaticamente o entitlement `com.apple.developer.applesignin`
   - (Já existe um arquivo `Alemao/Alemao.entitlements` no repo, mas o Xcode pode criar um novo — qualquer um funciona)
5. iCloud (opcional mas recomendado, pra sync entre devices):
   - Botão `+ Capability` → **iCloud**
   - Marcar **CloudKit**
   - Container: deixar o Xcode criar `iCloud.dev.alemao.Alemao` automaticamente
6. Background Modes (opcional, pra Live API persistir em background):
   - `+ Capability` → **Background Modes**
   - Marcar **Audio, AirPlay, and Picture in Picture**

> **Sign in with Apple no Free Developer Account?** Sim, funciona. A Apple
> exige uma Apple Developer Program ($99/ano) apenas para publicar na App Store;
> sideload e Sign in with Apple funcionam normalmente em devices físicos com
> Apple ID gratuito (provisioning automático do Xcode).

## 8. Build & Run

1. No topo do Xcode, ao lado do botão Play, selecione um simulador: **iPhone 15 Pro** (ou seu device físico)
2. **Cmd+B** para build
3. Se compilou, **Cmd+R** para rodar

### Esperado no primeiro launch

1. Tela de onboarding:
   - Boas-vindas
   - Cole sua chave Gemini → "Salvar e testar" → ✅
   - Seu nome
   - Teste de nivelamento de 12 questões (gerado pelo Gemini)
   - Resultado CEFR estimado → "Começar"
2. Dashboard Início com 8 abas funcionais

## Erros comuns

### "Cannot find type 'X' in scope" no build
Você esqueceu de adicionar algum arquivo `.swift` ao target. Volte ao passo 4 e confirme que todos os arquivos em `Components/`, `Features/`, `Models/`, `Services/` estão no target Alemao.

→ Selecione o arquivo no navigator → File Inspector (Cmd+Opt+1) → na seção **Target Membership**, confirme que **Alemao** está marcado.

### "library.sqlite não encontrado no bundle"
Você adicionou `PrebuiltContent/` como Group em vez de Folder Reference. Remova e re-adicione como **Folder Reference** (pasta fica **azul** no navigator, não amarela).

### Build falha com "GRDB" not found
A dependência SPM não baixou. Tente:
- Xcode → File → Packages → **Reset Package Caches**
- Build de novo

### Microfone "permission denied" rodando no simulador
O simulador respeita as permissões. Settings → Privacy → Microphone → ativar Alemao.

## Pronto

Quando funcionar, lembre de:
1. Commitar `Alemao.xcodeproj/` no monorepo (não os `xcuserdata/`, que já estão no `.gitignore`)
2. Quando quiser ver os PDFs nas citações: `./scripts/sync_content.sh --with-pdfs` e re-add `Resources/Books` como folder reference no Xcode
