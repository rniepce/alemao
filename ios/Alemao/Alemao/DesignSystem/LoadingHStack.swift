import SwiftUI

/// Indicador de loading inline reutilizável: spinner + label.
///
/// Substitui 4 padrões repetidos com pequenas variações em
/// ConversationView, GenerateLessonView, WritingEntryDetailView, ReadingView.
///
/// Uso:
/// ```swift
/// LoadingHStack(message: "Gerando lição…")
/// LoadingHStack(message: "Conectando…", controlSize: .small)
/// ```
struct LoadingHStack: View {
    let message: String
    let controlSize: ControlSize
    let foregroundStyle: HierarchicalShapeStyle

    init(
        message: String,
        controlSize: ControlSize = .regular,
        foregroundStyle: HierarchicalShapeStyle = .secondary
    ) {
        self.message = message
        self.controlSize = controlSize
        self.foregroundStyle = foregroundStyle
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ProgressView()
                .controlSize(controlSize)
            Text(message)
                .font(.callout)
                .foregroundStyle(foregroundStyle)
        }
    }
}

#Preview {
    VStack {
        LoadingHStack(message: "Gerando lição…")
        LoadingHStack(message: "Carregando notícias…", controlSize: .small)
    }
    .padding()
}
