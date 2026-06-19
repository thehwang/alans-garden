import Foundation
import GardenCore

// Alan's Garden — MVP prototype (grid cellular automaton + exact target match).
//
// You set growth rules, the garden grows step by step, and we check whether the
// bloom exactly matches the target shape. This CLI prints each frame so the
// growth and the match are easy to read.

struct Options {
    var level = 1
    var rules: RuleSet = [:]
    var steps: Int? = nil
    var listLevels = false
}

func parseOptions() -> Options {
    var o = Options()
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    func value() -> String? { i + 1 < args.count ? args[i + 1] : nil }
    while i < args.count {
        switch args[i] {
        case "--level": if let v = value(), let n = Int(v) { o.level = n; i += 1 }
        case "--steps": if let v = value(), let n = Int(v) { o.steps = n; i += 1 }
        case "--rule":
            if let v = value(), let (c, dirs) = parseRule(v) { o.rules[c] = dirs; i += 1 }
        case "--list": o.listLevels = true
        case "--help", "-h":
            print("""
            Alan's Garden — MVP prototype

            Usage: garden [options]
              --level N        Play level N (default 1)
              --rule A=NSEW    Set color A to spread North/South/East/West
              --rule A=E       Set color A to spread East only (repeatable)
              --rule B=NSEW~A  Spread B, but avoid growing next to A (inhibition)
              --rule B=NSEW+A  Spread B, but only next to A (activation)
              --rule A=NSEW*2  Spread A, but only into cells touching >=2 of its own (clustering)
              --steps N        Sunlight steps to grow (default: level's intended)
              --list           List levels
              (no rule given)  Runs the level's intended solution as a demo
            """)
            exit(0)
        default: break
        }
        i += 1
    }
    return o
}

func describeRules(_ rules: RuleSet) -> String {
    rules.sorted { $0.key < $1.key }.map { color, rule in
        let codes = rule.directions.sorted { $0.rawValue < $1.rawValue }
            .map { String($0.code) }.joined()
        let avoid = rule.avoidColor.map { "~\($0)" } ?? ""
        let need = rule.needColor.map { "+\($0)" } ?? ""
        let cluster = rule.minNeighbors > 0 ? "*\(rule.minNeighbors)" : ""
        return "\(color)→\(codes.isEmpty ? "·" : codes)\(need)\(avoid)\(cluster)"
    }.joined(separator: "  ")
}

let opt = parseOptions()

if opt.listLevels {
    for (i, lvl) in Levels.all.enumerated() {
        print("\(i + 1). \(lvl.name) — \(lvl.hint)")
    }
    exit(0)
}

guard opt.level >= 1 && opt.level <= Levels.all.count else {
    print("No such level. Use --list.")
    exit(1)
}
let level = Levels.all[opt.level - 1]

// Use the player's rules if given, otherwise demo the intended solution.
let usingDemo = opt.rules.isEmpty
let rules = usingDemo ? level.intendedRules : opt.rules
let steps = opt.steps ?? (usingDemo ? level.intendedSteps : level.sunlight)

print("═══════════════════════════════════════════")
print("  Alan's Garden — Level \(opt.level): \(level.name)")
print("═══════════════════════════════════════════")
print("Goal: grow the flowers to exactly fill the target (T).")
print("Hint: \(level.hint)")
print("")
print("Target shape (T = target, lowercase = seed, # = rock):")
print(Renderer.targetMap(level.initial, target: level.target))
print("")
print("Rules: \(describeRules(rules))   Sunlight: \(steps) steps\(usingDemo ? "  [demo]" : "")")
print("Legend: letter = correct flower   x = wrong color   ! = spilled over   _ = missing   . = empty   # = rock")
print("")

let frames = GrowthEngine.grow(level.initial, rules: rules, maxSteps: steps)
for (i, frame) in frames.enumerated() {
    print("Step \(i):")
    print(Renderer.overlay(frame, target: level.target))
    print("")
}

let report = GrowthEngine.evaluate(frames: frames, target: level.target)
print("───────────────────────────────────────────")
if let win = report.winStep {
    print("✓ Solved! The garden exactly matched the target at step \(win).")
} else {
    print("✗ Not matched. Best at step \(report.bestStep): \(report.missing) missing, \(report.overflow) spilled over.")
    print("  Tip: change directions or step count so the bloom fills T exactly.")
}
