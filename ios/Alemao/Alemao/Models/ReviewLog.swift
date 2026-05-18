import Foundation
import SwiftData

@Model
final class ReviewLog {
    @Attribute(.unique) var id: UUID
    var cardId: UUID
    var reviewedAt: Date
    var rating: Int           // 0=again, 1=hard, 2=good, 3=easy
    var previousInterval: Int
    var newInterval: Int

    init(
        id: UUID = UUID(),
        cardId: UUID,
        reviewedAt: Date = .now,
        rating: Int,
        previousInterval: Int,
        newInterval: Int
    ) {
        self.id = id
        self.cardId = cardId
        self.reviewedAt = reviewedAt
        self.rating = rating
        self.previousInterval = previousInterval
        self.newInterval = newInterval
    }
}
