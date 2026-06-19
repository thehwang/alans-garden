import Foundation

/// What a target cell requires: any flower, or a specific color (species).
public enum RequiredColor: Equatable, Sendable {
    case any
    case exact(Character)
}

/// The shape (and optionally the coloring) a level wants the garden to grow into.
///
/// `cells` maps each target position to what must be there. A position not in the
/// map must stay empty — a flower there counts as "spilled over".
public struct Target: Sendable {
    public let cells: [Position: RequiredColor]

    public init(cells: [Position: RequiredColor]) {
        self.cells = cells
    }

    /// Single-color / shape-only target: any flower fills these positions.
    public static func shape(_ positions: Set<Position>) -> Target {
        Target(cells: Dictionary(uniqueKeysWithValues: positions.map { ($0, .any) }))
    }

    /// Build an exact-color target from a finished garden. Handy for authoring a
    /// level: design the seeds + intended rules, grow them, and snapshot the
    /// result as the goal — guaranteeing the intended solution is winnable.
    public static func from(_ grid: Grid) -> Target {
        var cells = [Position: RequiredColor]()
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                if let c = grid[x, y].flowerColor { cells[Position(x, y)] = .exact(c) }
            }
        }
        return Target(cells: cells)
    }

    public var positions: Set<Position> { Set(cells.keys) }

    /// Is the target satisfied at `p` by the current garden?
    public func isSatisfied(_ grid: Grid, _ p: Position) -> Bool {
        guard let color = grid[p].flowerColor else { return false }
        switch cells[p] {
        case .none: return false            // not a target cell
        case .some(.any): return true
        case .some(.exact(let c)): return color == c
        }
    }
}
