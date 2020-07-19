import Foundation

extension Comparable {
    func clamped(minValue: Self, maxValue: Self) -> Self {
        return min(max(self, minValue), maxValue)
    }
}
