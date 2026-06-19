# Alan's Garden — MVP prototype

Validates the core gameplay: **grid cellular automaton + exact target matching**.

> You give each flower a *growth rule* (which directions it spreads), press
> Sunrise, and the garden grows by that rule. The goal is to make the flowers
> bloom into the target pattern **exactly** — no more (no spilling `!`), no less
> (no gaps `_`). This is the smallest playable core of Turing's morphogenesis,
> wrapped as a gardening puzzle (pure logic + terminal visualization).

## Structure

```
Sources/GardenCore/      reusable core library
  Grid.swift             grid / cell / direction / position
  GrowthEngine.swift     deterministic CA: grow one step, run frames, match target
  Level.swift            level model + built-in puzzles + rule parsing
  Renderer.swift         ASCII rendering (target overlay, match state readable at a glance)
Sources/garden/          command-line demo (prints the growth frame by frame)
Sources/GardenApp/       macOS GUI (SpriteKit)
  main.swift             pure-code AppKit host (window + SKView, no .xcodeproj)
  GardenScene.swift      board / target ghosts / flower rendering + rule toggles + growth animation + bloom feedback
Tests/                   determinism / monotonic growth / level solvability / wrong-rule failure
tools/demo.lua           Hammerspoon driver that auto-plays the demo with subtitles
```

## Levels (mechanic ramp)

| # | Name | Teaches |
|---|------|---------|
| 1 | First Bloom | Four-way bloom → diamond |
| 2 | Garden Path | Direction control (east-only → line; bloom spills) |
| 3 | Around the Stone | Rocks shape the path (rubble carves an L-corridor; spreading fills it) |
| 4 | Two Beds | Multi-color: A/B clash, split the bed exactly |
| 5 | Keep Your Distance | **Inhibition**: B fills the bed but avoids A, leaving a plus-shaped gap (discrete morphogenesis) |
| 6 | Climbing Rose | **Activation**: B grows only beside A (`+A`), climbing the static trellis instead of flooding |
| 7 | Tide Pools | **Inhibition as spots**: B floods the bed but avoids every A, leaving plus-shaped pools (Turing spots as negative space) |
| 8 | Sunrise Corner | **Budget**: fill only the NE quarter, using at most 2 directions — pick the right two |
| 9 | Fill the Frame | **Clustering**: fill the outlined block without spilling (`*2`) |
| 10 | Two Quilts | Two species, two clustered blocks at once, no bleeding into the gap |

> Activation `+X` (grow only next to X) + inhibition `~X` (avoid X) = the discrete
> pair behind Turing reaction-diffusion systems, enough to make borders, spots, and stripes emerge.

## Run (GUI · macOS)

```bash
swift run GardenApp
```

> ⚠️ Launch from a real **Terminal.app** (or Xcode) so the window appears —
> from a non-GUI session (e.g. some automation/SSH environments) the process
> runs but no window shows.

Controls:
- The faint **ghost cells** on the board are the target pattern (a tinted ghost
  means that cell wants that color); `#` is a rock.
- Each flower has direction toggles (↑ → ↓ ←) and rule pills (avoid X / need X /
  cluster ≥k) — light them up to apply.
- **☀ Sunrise** grows the garden frame by frame; the top sun bar is the step budget.
- Growing into the target **blossoms** with a success cue; missing it tells you
  plainly how many cells are short or spilled.
- **Hint** fills a reference solution, **Reset** clears to seeds, **Next** advances.

## Run (CLI · frame-by-frame ASCII)

```bash
swift run garden --level 1            # diamond
swift run garden --level 4            # two-color split
swift run garden --level 5            # inhibition: B avoids A, leaving a gap
swift run garden --level 6            # activation: B climbs the A trellis
swift run garden --level 7            # inhibition spots: plus-shaped pools
swift run garden --level 8            # budget: fill only the NE corner

# try your own rules
swift run garden --level 2 --rule A=E --steps 6     # east only
swift run garden --level 2 --rule A=NSEW --steps 3  # deliberate bloom → screen full of ! (spill)
swift run garden --level 5 --rule B=NSEW~A          # ~A = avoid A
swift run garden --level 6 --rule B=NSEW+A          # +A = grow only next to A

swift run garden --list   # list levels
swift run garden --help
```

Rule syntax: `A=NSEW` (all directions) / `A=E` (east only) / `B=NSEW~A` (avoid A) /
`B=NSEW+A` (grow only next to A) / `A=NSEW*2` (cluster, needs ≥2 same-color neighbors)

Legend: `letter` = correct flower · `x` = wrong color · `!` = spill · `_` = not grown yet · `.` = empty · `#` = rock

## Tests

```bash
swift test
```

## How the pieces map

| Concept | Prototype implementation |
|---|---|
| Core loop (set rules → grow → match) | `GrowthEngine.grow` + `evaluate` |
| Growth rule cards (directional spread) | `RuleSet` + `GrowthEngine.step` |
| Readable cause-effect, target-driven | frame-by-frame ASCII + exact match win/lose |

## Demo automation

[`tools/demo.lua`](tools/demo.lua) is a Hammerspoon script that auto-plays two
real solves (Level 5 inhibition, Level 9 clustering) with timed subtitles, for
recording the trailer. Record the screen separately (QuickTime / `screencapture`),
then add music in post.
