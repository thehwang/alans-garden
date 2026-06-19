import Foundation

/// ASCII rendering of a garden, with a target overlay so the match state is
/// immediately readable.
public enum Renderer {

    /// Overlay a grid against the target:
    ///   - flower satisfying its target cell -> the color letter (good)
    ///   - flower on a target cell but wrong color -> 'x'
    ///   - flower off the target -> '!' (spilled over)
    ///   - empty target cell -> '_' (still missing)
    ///   - empty non-target cell -> '.'
    ///   - rock -> '#'
    public static func overlay(_ grid: Grid, target: Target) -> String {
        var lines: [String] = []
        for y in 0..<grid.height {
            var row = ""
            for x in 0..<grid.width {
                let p = Position(x, y)
                let inTarget = target.cells[p] != nil
                switch grid[p] {
                case .rock:
                    row += " #"
                case let .flower(c):
                    if inTarget {
                        row += target.isSatisfied(grid, p) ? " \(c)" : " x"
                    } else {
                        row += " !"
                    }
                case .empty:
                    row += inTarget ? " _" : " ."
                }
            }
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    /// Render the target shape itself:
    ///   - target cell needing a specific color -> that uppercase letter
    ///   - target cell accepting any flower -> 'T'
    ///   - seed already planted -> lowercase letter
    ///   - rock -> '#', else '.'
    public static func targetMap(_ grid: Grid, target: Target) -> String {
        var lines: [String] = []
        for y in 0..<grid.height {
            var row = ""
            for x in 0..<grid.width {
                let p = Position(x, y)
                if case let .flower(c) = grid[p] {
                    row += " \(Character(String(c).lowercased()))"
                } else if grid[p] == .rock {
                    row += " #"
                } else if let req = target.cells[p] {
                    switch req {
                    case .any: row += " T"
                    case .exact(let c): row += " \(c)"
                    }
                } else {
                    row += " ."
                }
            }
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }
}
