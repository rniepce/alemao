# Design System — Alemão

Tokens e componentes reutilizáveis. Adoção **gradual** — código antigo migra
conforme for tocado, não há "big bang refactor".

## Tokens (`Alemao/DesignSystem/DesignTokens.swift`)

### Spacing — escala 8pt

```swift
AppSpacing.xs   // 4   (badges adjacentes)
AppSpacing.sm   // 8   (linhas em listas)
AppSpacing.md   // 12  (subseções de card)
AppSpacing.lg   // 16  (padding default)
AppSpacing.xl   // 24  (separação entre seções)
AppSpacing.xxl  // 32  (topo de tela)
```

### Corner radius

```swift
AppRadius.small  // 8   (chips, capsules)
AppRadius.card   // 12  (cards padrão)
AppRadius.modal  // 16  (sheets, painéis destacados)
```

### Opacity para backgrounds

```swift
AppOpacity.subtle  // 0.06  (cards terciários)
AppOpacity.medium  // 0.12  (cards padrão, hover)
AppOpacity.strong  // 0.20  (pills, badges destacados)
```

### Cores — sempre nominais, nunca literais

```swift
// Gênero gramatical
Color.genderMasculine   // der → blue
Color.genderFeminine    // die → red
Color.genderNeuter      // das → green
Color.genderPlural      // plural → purple
Color.forGender("der")  // helper

// Tempos verbais
Color.tensePraesens     // blue
Color.tensePraeteritum  // orange
Color.tenseKonjunktivII // purple

// Feedback
Color.success           // verde
Color.danger            // vermelho
Color.warning           // laranja
Color.info              // azul

// Tags de verbo
Color.tagSeparable      // roxo
Color.tagReflexive      // rosa
Color.tagIrregular      // laranja

// Marca
Color.accentColor       // teal #1A8E9E (light) / #2DB5C8 (dark)
```

## Componentes

### `.appCard()` modifier

Substitui o padrão `padding + background + clipShape` que aparecia ~38× no app.

```swift
VStack { ... }.appCard()                                  // subtle, radius card
VStack { ... }.appCard(tone: .medium)                     // mais visível
VStack { ... }.appCard(tone: .strong, radius: .modal)
```

### `StatBubble`

Mostra valor + label compacto. Substitui 3 cópias do mesmo componente.

```swift
StatBubble(value: "120", label: "verbos")
StatBubble(value: "80%", label: "taxa", tint: .success)
StatBubble(date: card.nextReviewDate, label: "próxima revisão")
```

### `LevelBadge`

Pill compacto para nível CEFR ou tag. Substitui 15+ instâncias do padrão
`Text + padding + opacity + Capsule`.

```swift
LevelBadge("B1")                                  // accentColor
LevelBadge("separável", tint: .tagSeparable, size: .small)
LevelBadge("Präteritum", tint: .tensePraeteritum)
```

### `LoadingHStack`

Spinner + texto inline. Substitui 4 padrões repetidos.

```swift
LoadingHStack(message: "Gerando lição…")
LoadingHStack(message: "Conectando…", controlSize: .small)
```

## Princípios

1. **Nomes semânticos sempre** — `Color.success` em vez de `.green`,
   `Color.tensePraesens` em vez de `.blue`. Quando a paleta mudar, refatorar é trivial.
2. **3 níveis, não 9** — Use 3 opacidades, 3 raios, 6 espaçamentos. Convergir é
   melhor que ter 1000 valores intermediários.
3. **Componentize quando 3+** — Se o mesmo padrão aparece 3 vezes, extraia.
4. **Acessibilidade primeiro** — Use `.semibold` em vez de `.bold()` (aceita
   Dynamic Type), `@ScaledMetric` para tamanhos hardcoded, e `accessibilityLabel`
   em elementos sem texto.

## Migração

A adoção é incremental. Critério de quando refatorar para tokens:

| Trigger | Ação |
|---|---|
| Você está modificando uma view | Migre cores hardcoded para tokens nominais |
| Cria componente novo | Use tokens desde o início |
| Vê 3+ cópias do mesmo padrão | Extraia para `DesignSystem/` |
| Encontra função duplicada | Mova para extension global |

Não há ETA para "100% adoção" — o sistema funciona com migração gradual.
