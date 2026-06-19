import Foundation

/// A puzzle: a starting garden, a target to grow into, a sunlight budget, and a
/// known-good solution (for the auto-demo / hints).
public struct Level: Sendable {
    public let name: String
    public let hint: String
    public let initial: Grid
    public let target: Target
    public let sunlight: Int
    public let intendedRules: RuleSet
    public let intendedSteps: Int
    /// Optional puzzle constraint: the most direction-toggles the player may use in
    /// total across all plants. `nil` = unlimited.
    public let maxDirections: Int?

    public init(name: String, hint: String, initial: Grid, target: Target,
                sunlight: Int, intendedRules: RuleSet, intendedSteps: Int,
                maxDirections: Int? = nil) {
        self.name = name
        self.hint = hint
        self.initial = initial
        self.target = target
        self.sunlight = sunlight
        self.intendedRules = intendedRules
        self.intendedSteps = intendedSteps
        self.maxDirections = maxDirections
    }
}

/// Parse a rule string:
///   "A=NSEW"     spread in all four directions
///   "A=E"        spread East only
///   "B=NSEW~A"   spread, but avoid growing next to color A (inhibition)
///   "B=NSEW+A"   spread, but only next to color A (activation)
///   "A=NSEW*2"   spread, but only into cells touching >=2 of its own (clustering)
public func parseRule(_ s: String) -> (Character, Rule)? {
    let halves = s.split(separator: "=", maxSplits: 1)
    guard halves.count == 2,
          let color = halves[0].trimmingCharacters(in: .whitespaces).first else { return nil }

    let chars = Array(halves[1])
    var dirs = Set<Direction>()
    var avoid: Character? = nil
    var need: Character? = nil
    var minN = 0
    var i = 0
    while i < chars.count {
        let ch = chars[i]
        if ch == "~", i + 1 < chars.count {
            avoid = Character(String(chars[i + 1]).uppercased()); i += 2; continue
        }
        if ch == "+", i + 1 < chars.count {
            need = Character(String(chars[i + 1]).uppercased()); i += 2; continue
        }
        if ch == "*", i + 1 < chars.count, let d = chars[i + 1].wholeNumberValue {
            minN = d; i += 2; continue
        }
        if let d = Direction.from(code: ch) { dirs.insert(d) }
        i += 1
    }
    return (color, Rule(dirs, avoid: avoid, need: need, min: minN))
}

public enum Levels {
    public static let all: [Level] = [level1, level2, level3, level4, level5,
                                      level6, level7, level8, level9, level10]

    /// Author a level by example: grow the seeds under the intended rules until the
    /// garden settles, then use that finished garden as the exact target. This
    /// guarantees the intended solution is winnable and computes the true number of
    /// steps it takes, so `sunlight` only has to be generous enough.
    private static func designed(name: String, hint: String, initial: Grid,
                                 rules: RuleSet, sunlight: Int,
                                 maxDirections: Int? = nil) -> Level {
        let frames = GrowthEngine.grow(initial, rules: rules, maxSteps: max(sunlight, 64))
        let target = Target.from(frames.last!)
        return Level(name: name, hint: hint, initial: initial, target: target,
                     sunlight: sunlight, intendedRules: rules,
                     intendedSteps: frames.count - 1, maxDirections: maxDirections)
    }

    /// 1 — First Bloom: a seed blooming outward fills a diamond.
    public static var level1: Level {
        var g = Grid(width: 7, height: 7)
        g[3, 3] = .flower("A")
        var t = Set<Position>()
        for y in 0..<7 { for x in 0..<7 where abs(x - 3) + abs(y - 3) <= 2 { t.insert(Position(x, y)) } }
        return Level(name: "First Bloom",
                     hint: "Let the seed bloom outward in every direction for 2 sunny steps.",
                     initial: g, target: .shape(t), sunlight: 4,
                     intendedRules: ["A": Rule([.north, .east, .south, .west])], intendedSteps: 2)
    }

    /// 2 — Garden Path: a straight line. Blooming overflows; spread East only.
    public static var level2: Level {
        var g = Grid(width: 7, height: 5)
        g[0, 2] = .flower("A")
        var t = Set<Position>()
        for x in 0..<7 { t.insert(Position(x, 2)) }
        return Level(name: "Garden Path",
                     hint: "A straight path, not a bush. Spread East only so it doesn't spill.",
                     initial: g, target: .shape(t), sunlight: 8,
                     intendedRules: ["A": Rule([.east])], intendedSteps: 6)
    }

    /// 3 — Around the Stone: rocks carve an L-corridor; flooding fills just the path.
    public static var level3: Level {
        var g = Grid(width: 7, height: 7, fill: .rock)
        // Carve an L-shaped corridor: bottom row then right column.
        var corridor = Set<Position>()
        for x in 1...5 { corridor.insert(Position(x, 5)) }   // bottom arm
        for y in 1...5 { corridor.insert(Position(5, y)) }   // up the right side
        for p in corridor { g[p] = .empty }
        g[1, 5] = .flower("A")
        return Level(name: "Around the Stone",
                     hint: "The stones carve the path. Bloom and the corridor fills itself.",
                     initial: g, target: .shape(corridor), sunlight: 12,
                     intendedRules: ["A": Rule([.north, .east, .south, .west])], intendedSteps: 9)
    }

    /// 4 — Two Beds: two species race to split a bed cleanly down the middle.
    public static var level4: Level {
        var g = Grid(width: 6, height: 1)
        g[0, 0] = .flower("A")
        g[5, 0] = .flower("B")
        var cells = [Position: RequiredColor]()
        for x in 0...2 { cells[Position(x, 0)] = .exact("A") }
        for x in 3...5 { cells[Position(x, 0)] = .exact("B") }
        return Level(name: "Two Beds",
                     hint: "Two plants, one bed. Send A East and B West so they meet in the middle.",
                     initial: g, target: Target(cells: cells), sunlight: 6,
                     intendedRules: ["A": Rule([.east]), "B": Rule([.west])], intendedSteps: 2)
    }

    /// 5 — Keep Your Distance: B fills the bed but politely leaves a gap around A.
    /// Inhibition (avoid A) carves a plus-shaped hole. This is the morphogenesis idea.
    public static var level5: Level {
        let w = 7, h = 5
        var g = Grid(width: w, height: h)
        let a = Position(3, 2)
        g[a] = .flower("A")          // static repellent (A has no rule)
        g[0, 2] = .flower("B")       // B seed
        // Halo = A's cell + its 4 orthogonal neighbors (B must avoid these).
        var halo: Set<Position> = [a]
        for d in Direction.allCases { let (dx, dy) = d.delta; halo.insert(Position(a.x + dx, a.y + dy)) }
        var cells = [Position: RequiredColor]()
        for y in 0..<h { for x in 0..<w {
            let p = Position(x, y)
            if p == a { cells[p] = .exact("A") }
            else if !halo.contains(p) { cells[p] = .exact("B") }
            // halo (minus A) stays empty: not a target cell
        } }
        return Level(name: "Keep Your Distance",
                     hint: "B should fill the whole bed but avoid crowding A. Bloom B with ~A.",
                     initial: g, target: Target(cells: cells), sunlight: 14,
                     intendedRules: ["B": Rule([.north, .east, .south, .west], avoid: "A")],
                     intendedSteps: 12)
    }

    /// 6 — Climbing Rose: a static trellis of A. B may bloom in all directions but
    /// only *next to* A (activation), so it climbs the trellis instead of flooding.
    public static var level6: Level {
        let w = 7, h = 5
        var g = Grid(width: w, height: h)
        for y in 0..<h { g[3, y] = .flower("A") }   // static trellis, no rule
        g[2, h - 1] = .flower("B")                  // B seed at the foot
        return designed(name: "Climbing Rose",
                        hint: "B should climb the trellis A, not flood the bed. Bloom B but make it need A (+A).",
                        initial: g,
                        rules: ["B": Rule([.north, .east, .south, .west], need: "A")],
                        sunlight: 8)
    }

    /// 7 — Tide Pools: two well-spaced interior A. B floods the whole bed but avoids
    /// A, leaving a plus-shaped pool around each — Turing spots as negative space.
    public static var level7: Level {
        var g = Grid(width: 7, height: 7)
        g[Position(2, 2)] = .flower("A")
        g[Position(4, 4)] = .flower("A")
        g[Position(0, 6)] = .flower("B")
        return designed(name: "Tide Pools",
                        hint: "Flood the bed with B, but keep a clear pool around every A. Bloom B with ~A.",
                        initial: g,
                        rules: ["B": Rule([.north, .east, .south, .west], avoid: "A")],
                        sunlight: 20)
    }

    /// 8 — Sunrise Corner: a budget puzzle. Fill only the north-east quarter from a
    /// central seed. You get just two directions — pick the right two.
    public static var level8: Level {
        var g = Grid(width: 7, height: 5)
        g[3, 2] = .flower("A")
        return designed(name: "Sunrise Corner",
                        hint: "Only the north-east quarter. You may use just 2 directions — choose wisely.",
                        initial: g,
                        rules: ["A": Rule([.north, .east])],
                        sunlight: 6, maxDirections: 2)
    }

    /// 9 — Fill the Frame: the outline of a block is planted. Plain blooming spills
    /// outside; clustering (*2) fills only the well-supported interior, squaring the
    /// block off exactly without spilling into the surrounding bed.
    public static var level9: Level {
        let w = 7, h = 7
        var g = Grid(width: w, height: h)
        for x in 1...5 { g[x, 1] = .flower("A"); g[x, 5] = .flower("A") }
        for y in 1...5 { g[1, y] = .flower("A"); g[5, y] = .flower("A") }
        return designed(name: "Fill the Frame",
                        hint: "Fill the outlined block — but plain blooming spills outside. Bloom A only where it is well-supported, touching >=2 of its own (*2).",
                        initial: g,
                        rules: ["A": Rule(Set(Direction.allCases), min: 2)],
                        sunlight: 10)
    }

    /// 10 — Two Quilts: two outlined blocks to fill at once with two species, each
    /// clustering (*2) so neither spills nor bleeds into the gap between them.
    public static var level10: Level {
        let w = 9, h = 5
        var g = Grid(width: w, height: h)
        func frame(_ ox: Int, _ c: Character) {
            for x in ox...(ox + 2) { g[x, 1] = .flower(c); g[x, 3] = .flower(c) }
            for y in 1...3 { g[ox, y] = .flower(c); g[ox + 2, y] = .flower(c) }
        }
        frame(1, "A")
        frame(5, "B")
        return designed(name: "Two Quilts",
                        hint: "Fill both blocks without spilling or bleeding into the gap. Both A and B bloom only where well-supported (*2).",
                        initial: g,
                        rules: ["A": Rule(Set(Direction.allCases), min: 2),
                                "B": Rule(Set(Direction.allCases), min: 2)],
                        sunlight: 8)
    }
}
