import Foundation

/// A growth rule for one flower color (the "growth rule card" the player assigns).
///
/// - `directions`: which way the flower spreads each sunlight step.
/// - `avoidColor`: optional *inhibition* — the flower refuses to grow into any cell
///   orthogonally adjacent to a flower of this other color. One species keeps its
///   distance from another, carving deliberate gaps.
/// - `needColor`: optional *activation* — the flower may grow into a cell only if
///   that cell is orthogonally adjacent to a flower of this other color. One species
///   can only spread while hugging another.
/// - `minNeighbors`: optional *clustering* — the flower blooms into a cell only if
///   that cell already touches at least this many flowers of its own color. With
///   `0` (default) it spreads freely; with `2` it only fills well-supported cells
///   (concavities), squaring shapes off and refusing thin spikes or spilling.
///
/// Activation + inhibition together are the discrete echo of Turing's
/// reaction-diffusion system: an activator and an inhibitor producing spots,
/// stripes and outlines.
///
/// A color with no rule never grows (a static seed / "planted" flower).
public struct Rule: Equatable, Sendable {
    public var directions: Set<Direction>
    public var avoidColor: Character?
    public var needColor: Character?
    public var minNeighbors: Int

    public init(_ directions: Set<Direction>, avoid avoidColor: Character? = nil,
                need needColor: Character? = nil, min minNeighbors: Int = 0) {
        self.directions = directions
        self.avoidColor = avoidColor
        self.needColor = needColor
        self.minNeighbors = minNeighbors
    }
}

public typealias RuleSet = [Character: Rule]

/// How a (partial) garden compares to the level's target shape.
public struct MatchReport: Sendable {
    public let winStep: Int?
    public let bestStep: Int
    public let missing: Int
    public let overflow: Int
    public var isWin: Bool { winStep != nil }
}

/// The deterministic cellular-automaton growth engine.
///
/// Growth is monotonic (flowers are only added) and simultaneous (every existing
/// flower spreads from the previous frame). Because growth is monotonic, an exact
/// match — when it exists — happens at exactly one moment, which is what gives the
/// puzzle its bite.
public enum GrowthEngine {

    /// Is any orthogonal neighbor of `p` a flower of `color`? (inhibition check)
    private static func isOrthAdjacent(to color: Character, in grid: Grid, at p: Position) -> Bool {
        for dir in Direction.allCases {
            let (dx, dy) = dir.delta
            let q = Position(p.x + dx, p.y + dy)
            if grid.inBounds(q), grid[q].flowerColor == color { return true }
        }
        return false
    }

    /// How many orthogonal neighbors of `p` are flowers of `color`? (clustering check)
    private static func countOrthAdjacent(to color: Character, in grid: Grid, at p: Position) -> Int {
        var n = 0
        for dir in Direction.allCases {
            let (dx, dy) = dir.delta
            let q = Position(p.x + dx, p.y + dy)
            if grid.inBounds(q), grid[q].flowerColor == color { n += 1 }
        }
        return n
    }

    /// Advance the garden one sunlight step.
    public static func step(_ grid: Grid, rules: RuleSet) -> Grid {
        var next = grid
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let p = Position(x, y)
                guard let color = grid[p].flowerColor,
                      let rule = rules[color] else { continue }
                for dir in rule.directions.sorted(by: { $0.rawValue < $1.rawValue }) {
                    let (dx, dy) = dir.delta
                    let np = Position(x + dx, y + dy)
                    guard grid.inBounds(np), next[np] == .empty else { continue }
                    // Inhibition: don't grow next to the avoided species.
                    if let avoid = rule.avoidColor,
                       isOrthAdjacent(to: avoid, in: grid, at: np) { continue }
                    // Activation: only grow next to the needed species.
                    if let need = rule.needColor,
                       !isOrthAdjacent(to: need, in: grid, at: np) { continue }
                    // Clustering: only bloom where well-supported by its own kind.
                    if rule.minNeighbors > 0,
                       countOrthAdjacent(to: color, in: grid, at: np) < rule.minNeighbors { continue }
                    next[np] = .flower(color)
                }
            }
        }
        return next
    }

    /// Grow up to `maxSteps`, returning every frame (index 0 = initial). Stops
    /// early once the garden stops changing.
    public static func grow(_ grid: Grid, rules: RuleSet, maxSteps: Int) -> [Grid] {
        var frames = [grid]
        var current = grid
        for _ in 0..<maxSteps {
            let next = step(current, rules: rules)
            frames.append(next)
            if next == current { break }
            current = next
        }
        return frames
    }

    /// Compare a sequence of frames against the target.
    public static func evaluate(frames: [Grid], target: Target) -> MatchReport {
        var winStep: Int? = nil
        var bestStep = 0
        var bestScore = Int.max
        var bestMissing = target.positions.count
        var bestOverflow = 0

        for (i, frame) in frames.enumerated() {
            let flowers = frame.flowerPositions()
            let missing = target.positions.filter { !target.isSatisfied(frame, $0) }.count
            let overflow = flowers.subtracting(target.positions).count
            let score = missing + overflow
            if score < bestScore {
                bestScore = score
                bestStep = i
                bestMissing = missing
                bestOverflow = overflow
            }
            if missing == 0 && overflow == 0 && winStep == nil {
                winStep = i
            }
        }
        return MatchReport(winStep: winStep, bestStep: bestStep,
                           missing: bestMissing, overflow: bestOverflow)
    }
}
