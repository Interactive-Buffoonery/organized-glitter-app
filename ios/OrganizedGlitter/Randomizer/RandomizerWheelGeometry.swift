import Foundation

enum RandomizerWheelGeometry {
  static func normalized(_ angle: Double) -> Double {
    let remainder = angle.truncatingRemainder(dividingBy: 360)
    return remainder < 0 ? remainder + 360 : remainder
  }

  static func indexUnderPointer(rotation: Double, count: Int) -> Int? {
    guard count > 0, rotation.isFinite else { return nil }
    return min(count - 1, Int(normalized(270 - rotation) / (360 / Double(count))))
  }

  static func targetRotation(
    from rotation: Double, winnerIndex: Int, count: Int, turns: Int = 5
  ) -> Double? {
    guard count > 0, (0..<count).contains(winnerIndex), rotation.isFinite, turns >= 0 else {
      return nil
    }
    let center = (Double(winnerIndex) + 0.5) * 360 / Double(count)
    let target = normalized(270 - center)
    return rotation + Double(turns) * 360 + normalized(target - normalized(rotation))
  }
}

struct RandomizerWheelSpin: Equatable, Sendable {
  let selectionID: UUID
  let startRotation: Double
  let endRotation: Double
  let winnerIndex: Int
  let count: Int
}

struct RandomizerItemSelection: Equatable, Sendable {
  private(set) var ids: Set<LocalRecordKey>?

  mutating func selectAll() { ids = nil }
  mutating func selectNone() { ids = [] }

  mutating func setSelected(
    _ id: LocalRecordKey, selected: Bool, candidates: [RandomizerCandidate]
  ) {
    let available = Set(candidates.map(\.id))
    guard available.contains(id) else { return }
    var ids = self.ids ?? available
    if selected { ids.insert(id) }
    else { ids.remove(id) }
    self.ids = ids
  }

  mutating func toggle(_ id: LocalRecordKey, candidates: [RandomizerCandidate]) {
    setSelected(id, selected: !(ids?.contains(id) ?? true), candidates: candidates)
  }

  mutating func reconcile(candidates: [RandomizerCandidate]) {
    guard let ids, !ids.isEmpty else { return }
    let remaining = ids.intersection(candidates.map(\.id))
    self.ids = remaining.isEmpty ? nil : remaining
  }
}

struct RandomizerSpinFeedback {
  private let spin: RandomizerWheelSpin
  private var previousIndex: Int?
  private var previousTime: Double = 0
  private var isCancelled = false

  init(spin: RandomizerWheelSpin) { self.spin = spin }

  mutating func cancel() { isCancelled = true }

  mutating func tick(at elapsed: Double) -> Bool {
    guard !isCancelled, elapsed.isFinite, elapsed >= 0.1, elapsed < 3,
      elapsed - previousTime >= 0.1 else { return false }
    previousTime = elapsed
    let progress = Self.easeOut(elapsed / 3)
    let rotation = spin.startRotation + (spin.endRotation - spin.startRotation) * progress
    let index = RandomizerWheelGeometry.indexUnderPointer(rotation: rotation, count: spin.count)
    defer { previousIndex = index }
    return index != nil && index != previousIndex
  }

  static func easeOut(_ fraction: Double) -> Double {
    let x = min(1, max(0, fraction))
    var low = 0.0
    var high = 1.0
    for _ in 0..<24 {
      let t = (low + high) / 2
      let curveX = 3 * (1 - t) * t * t * 0.58 + t * t * t
      if curveX < x { low = t } else { high = t }
    }
    let t = (low + high) / 2
    return 3 * (1 - t) * t * t + t * t * t
  }
}
