import SwiftUI

/// Pill compacto para mostrar nível CEFR ou label categórico.
///
/// Substitui o padrão repetido 15+ vezes:
/// ```
/// Text("B1").font(.caption2.bold())
///   .padding(.horizontal, 6).padding(.vertical, 2)
///   .background(Color.accentColor.opacity(0.2))
///   .clipShape(Capsule())
/// ```
///
/// Uso:
/// ```swift
/// LevelBadge("B1")
/// LevelBadge("separável", tint: .tagSeparable)
/// LevelBadge("irregular", tint: .tagIrregular, size: .small)
/// ```
struct LevelBadge: View {
    let text: String
    let tint: Color
    let size: Size

    enum Size {
        case small, regular
        var font: Font {
            switch self {
            case .small: return .caption2.bold()
            case .regular: return .caption.bold()
            }
        }
        var hPadding: CGFloat {
            switch self {
            case .small: return 5
            case .regular: return AppSpacing.sm
            }
        }
        var vPadding: CGFloat {
            switch self {
            case .small: return 2
            case .regular: return 3
            }
        }
    }

    init(_ text: String, tint: Color = .accentColor, size: Size = .regular) {
        self.text = text
        self.tint = tint
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(size.font)
            .padding(.horizontal, size.hPadding)
            .padding(.vertical, size.vPadding)
            .background(tint.opacity(AppOpacity.strong))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

#Preview {
    HStack {
        LevelBadge("A1")
        LevelBadge("B2")
        LevelBadge("separável", tint: .tagSeparable, size: .small)
        LevelBadge("reflexivo", tint: .tagReflexive, size: .small)
        LevelBadge("irregular", tint: .tagIrregular)
    }
    .padding()
}
