import Foundation

/// A grid coordinate. Origin top-left; y grows downward (for display).
public struct Position: Hashable, Sendable {
    public let x: Int
    public let y: Int
    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

/// The four growth directions a flower can spread in.
public enum Direction: Int, CaseIterable, Sendable {
    case north = 0, east, south, west

    public var delta: (dx: Int, dy: Int) {
        switch self {
        case .north: return (0, -1)
        case .east: return (1, 0)
        case .south: return (0, 1)
        case .west: return (-1, 0)
        }
    }

    /// Single-letter code used by rule strings (e.g. "NSEW").
    public var code: Character {
        switch self {
        case .north: return "N"
        case .east: return "E"
        case .south: return "S"
        case .west: return "W"
        }
    }

    public static func from(code: Character) -> Direction? {
        Direction.allCases.first { $0.code == Character(String(code).uppercased()) }
    }
}

/// One cell of the garden.
///
/// A flower carries a "color" id (a single character such as "A"). In game terms
/// this is a kind of plant; under the hood it's just a cell state for the
/// cellular automaton.
public enum Cell: Equatable, Sendable {
    case empty
    case rock
    case flower(Character)

    public var isFlower: Bool {
        if case .flower = self { return true }
        return false
    }
    public var flowerColor: Character? {
        if case let .flower(c) = self { return c }
        return nil
    }
}

/// The garden grid. Row-major storage.
public struct Grid: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var cells: [Cell]

    public init(width: Int, height: Int, fill: Cell = .empty) {
        self.width = width
        self.height = height
        self.cells = Array(repeating: fill, count: width * height)
    }

    public func inBounds(_ p: Position) -> Bool {
        p.x >= 0 && p.x < width && p.y >= 0 && p.y < height
    }

    private func index(_ p: Position) -> Int { p.y * width + p.x }

    public subscript(_ p: Position) -> Cell {
        get { cells[index(p)] }
        set { cells[index(p)] = newValue }
    }

    public subscript(_ x: Int, _ y: Int) -> Cell {
        get { self[Position(x, y)] }
        set { self[Position(x, y)] = newValue }
    }

    /// All positions currently holding a flower.
    public func flowerPositions() -> Set<Position> {
        var set = Set<Position>()
        for y in 0..<height {
            for x in 0..<width {
                if self[x, y].isFlower { set.insert(Position(x, y)) }
            }
        }
        return set
    }
}
