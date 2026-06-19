import XCTest
@testable import GardenCore

final class EngineTests: XCTestCase {
    func testStepIsDeterministic() {
        let g = Levels.level1.initial
        let rules = Levels.level1.intendedRules
        XCTAssertEqual(GrowthEngine.step(g, rules: rules),
                       GrowthEngine.step(g, rules: rules))
    }

    func testGrowthIsMonotonic() {
        let g = Levels.level1.initial
        let frames = GrowthEngine.grow(g, rules: Levels.level1.intendedRules, maxSteps: 4)
        for i in 1..<frames.count {
            let prev = frames[i - 1].flowerPositions()
            let curr = frames[i].flowerPositions()
            XCTAssertTrue(prev.isSubset(of: curr), "step \(i) removed a flower")
        }
    }

    func testRocksBlockGrowth() {
        var g = Grid(width: 5, height: 1)
        g[0, 0] = .flower("A")
        g[2, 0] = .rock
        let frames = GrowthEngine.grow(g, rules: ["A": Rule([.east])], maxSteps: 10)
        XCTAssertEqual(frames.last![3, 0], .empty)
        XCTAssertEqual(frames.last![1, 0], .flower("A"))
    }

    func testAvoidInhibition() {
        // B should refuse to grow into a cell orthogonally adjacent to A.
        var g = Grid(width: 5, height: 1)
        g[0, 0] = .flower("B")
        g[3, 0] = .flower("A")
        let frames = GrowthEngine.grow(g, rules: ["B": Rule([.east], avoid: "A")], maxSteps: 10)
        // (2,0) is adjacent to A at (3,0) -> blocked; B stops at (1,0).
        XCTAssertEqual(frames.last![1, 0], .flower("B"))
        XCTAssertEqual(frames.last![2, 0], .empty)
    }

    func testNeedActivation() {
        // B may only grow into cells adjacent to A. A is a vertical wall at x=2;
        // B starts left of it and should hug the wall but never leave column 1.
        let w = 4, h = 3
        var g = Grid(width: w, height: h)
        for y in 0..<h { g[2, y] = .flower("A") }
        g[1, h - 1] = .flower("B")
        let frames = GrowthEngine.grow(g, rules: ["B": Rule(Set(Direction.allCases), need: "A")],
                                       maxSteps: 6)
        let last = frames.last!
        for y in 0..<h { XCTAssertEqual(last[1, y], .flower("B"), "B should climb column 1") }
        // Column 0 is never adjacent to A, so activation keeps B out entirely.
        for y in 0..<h { XCTAssertEqual(last[0, y], .empty, "B must not reach column 0") }
    }

    func testNeedWithoutActivatorNeverGrows() {
        // No A present at all: a needy B can never satisfy activation.
        var g = Grid(width: 5, height: 1)
        g[0, 0] = .flower("B")
        let frames = GrowthEngine.grow(g, rules: ["B": Rule([.east], need: "A")], maxSteps: 5)
        XCTAssertEqual(frames.last!.flowerPositions().count, 1)
    }

    func testClusteredBloomNeedsSupport() {
        // An L-tromino: only the cell completing the square has >=2 A neighbors.
        var g = Grid(width: 6, height: 6)
        g[1, 1] = .flower("A"); g[2, 1] = .flower("A"); g[1, 2] = .flower("A")
        let frames = GrowthEngine.grow(g, rules: ["A": Rule(Set(Direction.allCases), min: 2)],
                                       maxSteps: 6)
        let last = frames.last!
        // (2,2) touches (2,1) and (1,2) -> two supports -> blooms, squaring the block.
        XCTAssertEqual(last[2, 2], .flower("A"))
        // Cells touching only one A must stay empty (no thin spikes / no spill).
        XCTAssertEqual(last[3, 1], .empty)
        XCTAssertEqual(last[0, 1], .empty)
        XCTAssertEqual(last[3, 3], .empty)
    }
}

final class LevelTests: XCTestCase {
    /// Every built-in level must be solvable by its intended rules.
    func testAllLevelsSolvable() {
        for (i, lvl) in Levels.all.enumerated() {
            let frames = GrowthEngine.grow(lvl.initial, rules: lvl.intendedRules, maxSteps: lvl.sunlight)
            let report = GrowthEngine.evaluate(frames: frames, target: lvl.target)
            XCTAssertTrue(report.isWin, "level \(i + 1) (\(lvl.name)) should be solvable")
        }
    }

    func testLevel1MatchesAtIntendedStep() {
        let lvl = Levels.level1
        let frames = GrowthEngine.grow(lvl.initial, rules: lvl.intendedRules, maxSteps: lvl.sunlight)
        XCTAssertEqual(GrowthEngine.evaluate(frames: frames, target: lvl.target).winStep,
                       lvl.intendedSteps)
    }

    func testLevel2WrongRuleSpills() {
        let lvl = Levels.level2
        let frames = GrowthEngine.grow(lvl.initial,
                                       rules: ["A": Rule([.north, .east, .south, .west])],
                                       maxSteps: lvl.sunlight)
        XCTAssertFalse(GrowthEngine.evaluate(frames: frames, target: lvl.target).isWin)
        XCTAssertGreaterThan(frames.last!.flowerPositions().subtracting(lvl.target.positions).count, 0)
    }

    func testLevel4WrongColorIsNotAWin() {
        // If both spread the same way without splitting, colors land in wrong halves.
        let lvl = Levels.level4
        let frames = GrowthEngine.grow(lvl.initial,
                                       rules: ["A": Rule([.east]), "B": Rule([.east])],
                                       maxSteps: lvl.sunlight)
        XCTAssertFalse(GrowthEngine.evaluate(frames: frames, target: lvl.target).isWin)
    }

    func testParseRule() {
        XCTAssertEqual(parseRule("A=NSEW")?.1, Rule(Set(Direction.allCases)))
        XCTAssertEqual(parseRule("B=E")?.1, Rule([.east]))
        XCTAssertEqual(parseRule("B=NSEW~A")?.1.avoidColor, "A")
        XCTAssertEqual(parseRule("B=NSEW+A")?.1.needColor, "A")
        let both = parseRule("C=NE+A~B")?.1
        XCTAssertEqual(both?.needColor, "A")
        XCTAssertEqual(both?.avoidColor, "B")
        XCTAssertEqual(both?.directions, [.north, .east])
        XCTAssertEqual(parseRule("A=NSEW*2")?.1.minNeighbors, 2)
        let cluster = parseRule("B=NE*3+A")?.1
        XCTAssertEqual(cluster?.minNeighbors, 3)
        XCTAssertEqual(cluster?.needColor, "A")
        XCTAssertEqual(cluster?.directions, [.north, .east])
    }

    func testIntendedStepWithinSunlight() {
        // Each level must be winnable inside its sunlight budget.
        for (i, lvl) in Levels.all.enumerated() {
            XCTAssertLessThanOrEqual(lvl.intendedSteps, lvl.sunlight,
                                     "level \(i + 1) (\(lvl.name)) needs more sunlight than it has")
        }
    }

    func testTidePoolsLeavesHolesButFloodsRest() {
        // The two A spots and their orthogonal halos must stay empty; everything
        // else should be filled by B.
        let lvl = Levels.level7
        let frames = GrowthEngine.grow(lvl.initial, rules: lvl.intendedRules, maxSteps: lvl.sunlight)
        let last = frames.last!
        let holes = Set([Position(2, 2), Position(4, 4)].flatMap { a -> [Position] in
            [a] + Direction.allCases.map { Position(a.x + $0.delta.dx, a.y + $0.delta.dy) }
        })
        var filled = 0
        for y in 0..<last.height { for x in 0..<last.width {
            let p = Position(x, y)
            if holes.contains(p) {
                XCTAssertNotEqual(last[p].flowerColor, "B", "B should leave a pool at \(p)")
            } else {
                if last[p].isFlower { filled += 1 }
            }
        } }
        XCTAssertGreaterThan(filled, 30, "B should flood most of the 7x7 bed")
    }

    func testBudgetLevelDeclaresLimit() {
        XCTAssertEqual(Levels.level8.maxDirections, 2)
        // The intended solution must respect the level's own direction budget.
        let used = Levels.level8.intendedRules.values.reduce(0) { $0 + $1.directions.count }
        XCTAssertLessThanOrEqual(used, Levels.level8.maxDirections!)
    }
}
