import SwiftUI
import WidgetKit

/// Bundle de widgets do app Alemão. Adiciona aqui novos widgets conforme criar.
@main
struct AlemaoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WordOfTheDayWidget()
        StreakWidget()
    }
}
