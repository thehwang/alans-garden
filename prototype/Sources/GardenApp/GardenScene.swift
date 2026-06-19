import SpriteKit
import GardenCore
import CoreGraphics
import AppKit

/// The garden puzzle, visualized — a summer-solstice dusk where "programs" bloom
/// into flowers.
///
/// Readability-first: the target shape (and required colors) are drawn as faint
/// dashed ghosts on the soil so you always see the goal; you assign each plant's
/// growth directions with toggle buttons; pressing "Sunrise" grows the garden step
/// by step; the status line explains, in plain words, what happened.
final class GardenScene: SKScene {

    // MARK: Palette
    private enum C {
        static let text   = SKColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1)
        static let dim    = SKColor(red: 0.66, green: 0.70, blue: 0.84, alpha: 1)
        static let sun    = SKColor(red: 1.00, green: 0.86, blue: 0.46, alpha: 1)
        static let win    = SKColor(red: 0.55, green: 0.92, blue: 0.62, alpha: 1)
        static let spill  = SKColor(red: 1.00, green: 0.46, blue: 0.52, alpha: 1)
        static let accent = SKColor(red: 0.45, green: 0.78, blue: 0.95, alpha: 1)

        // Dusk sky, top -> bottom.
        static let sky = [
            SKColor(red: 0.06, green: 0.07, blue: 0.16, alpha: 1),
            SKColor(red: 0.13, green: 0.11, blue: 0.26, alpha: 1),
            SKColor(red: 0.27, green: 0.16, blue: 0.31, alpha: 1),
            SKColor(red: 0.42, green: 0.24, blue: 0.31, alpha: 1),
        ]

        static func flower(_ c: Character) -> SKColor {
            switch c {
            case "A": return SKColor(red: 0.26, green: 0.84, blue: 0.66, alpha: 1) // emerald
            case "B": return SKColor(red: 0.99, green: 0.46, blue: 0.64, alpha: 1) // rose
            case "C": return SKColor(red: 1.00, green: 0.78, blue: 0.40, alpha: 1) // amber
            default:  return SKColor(red: 0.74, green: 0.66, blue: 0.96, alpha: 1) // lavender
            }
        }
    }

    // MARK: Layout
    private let boardArea = CGRect(x: 44, y: 96, width: 588, height: 470)
    private let panelRect = CGRect(x: 656, y: 84, width: 320, height: 516)
    private var panelX: CGFloat { panelRect.minX + 24 }

    // MARK: Painted art assets
    private static let artDir = "/Users/hwang/Cursor/personal/AlansGarden/prototype/Art/"
    private var texCache: [String: SKTexture] = [:]
    /// Loads a painted texture by filename, cached. Returns nil if the asset is missing
    /// so the scene can fall back to its procedural look.
    private func art(_ name: String) -> SKTexture? {
        if let t = texCache[name] { return t }
        guard let img = NSImage(contentsOfFile: Self.artDir + name) else { return nil }
        let t = SKTexture(image: img)
        texCache[name] = t
        return t
    }

    /// A rounded panel filled with a painted texture, via a crop mask (reliable, unlike
    /// SKShapeNode.fillTexture). Returns a node whose origin is the scene origin.
    private func texturedPanel(_ rect: CGRect, radius: CGFloat, texture: SKTexture) -> SKNode {
        let crop = SKCropNode()
        let mask = SKShapeNode(path: CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        mask.fillColor = .white
        mask.strokeColor = .clear
        crop.maskNode = mask
        let s = SKSpriteNode(texture: texture)
        let ts = texture.size()
        let scale = max(rect.width / ts.width, rect.height / ts.height)
        s.size = CGSize(width: ts.width * scale, height: ts.height * scale)
        s.position = CGPoint(x: rect.midX, y: rect.midY)
        crop.addChild(s)
        return crop
    }

    // MARK: State
    private var levelIndex = 0
    private var level: Level { Levels.all[levelIndex] }
    private var rules: RuleSet = [:]
    private var displayGrid = Grid(width: 1, height: 1)
    private var shownPositions = Set<Position>()
    private var isAnimating = false

    private var cell: CGFloat = 60
    private var boardOrigin = CGPoint.zero

    // MARK: Layers / nodes
    private let skyLayer = SKNode()
    private let boardLayer = SKNode()
    private let previewLayer = SKNode()
    private let flowerLayer = SKNode()
    private let controlLayer = SKNode()
    private var statusLabel: SKLabelNode!
    private var titleLabel: SKLabelNode!
    private var subtitleLabel: SKLabelNode!
    private var captionLabel: SKLabelNode!
    private var budgetLabel: SKLabelNode!
    private var sun: SKNode!
    private var daylightTrack: SKShapeNode!
    private var warmOverlay: SKSpriteNode!

    private var flowerNodes: [Position: SKNode] = [:]

    // Cached textures.
    private lazy var softDot: SKTexture = softCircleTexture(diameter: 96)
    private var petalTex: [Character: SKTexture] = [:]

    /// Turing on morphogenesis — shown when a garden blooms into its target.
    private let quotes = [
        "“A system of chemicals… may develop a pattern.” — A. M. Turing",
        "Order, grown from a simple rule.",
        "The chemical basis of morphogenesis, in bloom.",
        "From one seed and one rule — a whole pattern.",
    ]

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        scaleMode = .aspectFit
        skyLayer.zPosition = -10
        boardLayer.zPosition = 0
        previewLayer.zPosition = 0.8
        flowerLayer.zPosition = 1
        controlLayer.zPosition = 10
        addChild(skyLayer)
        addChild(boardLayer)
        addChild(previewLayer)
        addChild(flowerLayer)
        addChild(controlLayer)
        buildChrome()
        loadLevel(0)
    }

    // MARK: Chrome (background, panels, header, daylight)

    private func buildChrome() {
        // Painted dusk-garden backdrop (falls back to a gradient if the art is missing).
        if let bg = art("garden-bg.png") {
            let s = SKSpriteNode(texture: bg)
            let ts = bg.size()
            let scale = max(size.width / ts.width, size.height / ts.height)
            s.size = CGSize(width: ts.width * scale, height: ts.height * scale)
            s.position = CGPoint(x: size.width / 2, y: size.height / 2)
            s.zPosition = -5
            skyLayer.addChild(s)
        } else {
            let sky = SKSpriteNode(texture: gradientTexture(size: size, colors: C.sky,
                                                            locations: [0, 0.45, 0.78, 1], horizontal: false))
            sky.position = CGPoint(x: size.width / 2, y: size.height / 2)
            sky.size = size
            sky.zPosition = -5
            skyLayer.addChild(sky)
        }

        // Warm daylight wash, faded in while the garden grows.
        warmOverlay = SKSpriteNode(color: SKColor(red: 1.0, green: 0.72, blue: 0.42, alpha: 1), size: size)
        warmOverlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        warmOverlay.blendMode = .add
        warmOverlay.alpha = 0
        warmOverlay.zPosition = -4
        skyLayer.addChild(warmOverlay)

        // Soft solstice sun-glow over the garden.
        let glow = SKSpriteNode(texture: softDot)
        glow.size = CGSize(width: 620, height: 620)
        glow.color = SKColor(red: 1.0, green: 0.72, blue: 0.5, alpha: 1)
        glow.colorBlendFactor = 1
        glow.alpha = 0.16
        glow.blendMode = .add
        glow.position = CGPoint(x: boardArea.midX, y: boardArea.maxY + 40)
        glow.zPosition = -3
        skyLayer.addChild(glow)

        // Planter bed: an opaque, rounded soil board so every cell reads cleanly,
        // no matter how busy the painted backdrop is behind it.
        let bedRect = boardArea.insetBy(dx: -16, dy: -16)
        let crop = SKCropNode()
        let mask = SKShapeNode(path: CGPath(roundedRect: bedRect, cornerWidth: 22, cornerHeight: 22, transform: nil))
        mask.fillColor = .white
        mask.strokeColor = .clear
        crop.maskNode = mask
        if let soil = art("soil-wood.png") {
            let s = SKSpriteNode(texture: soil)
            let ts = soil.size()
            let scale = max(bedRect.width / ts.width, bedRect.height / ts.height)
            s.size = CGSize(width: ts.width * scale, height: ts.height * scale)
            s.position = CGPoint(x: bedRect.midX, y: bedRect.midY)
            crop.addChild(s)
        } else {
            let fallback = SKSpriteNode(color: SKColor(red: 0.16, green: 0.12, blue: 0.08, alpha: 1),
                                        size: bedRect.size)
            fallback.position = CGPoint(x: bedRect.midX, y: bedRect.midY)
            crop.addChild(fallback)
        }
        crop.zPosition = -2
        skyLayer.addChild(crop)
        // Warm wooden rim around the soil.
        let rim = roundedRect(bedRect, radius: 22, fill: .clear,
                              stroke: SKColor(red: 0.34, green: 0.22, blue: 0.12, alpha: 0.95), lineWidth: 5)
        rim.zPosition = -1.8
        skyLayer.addChild(rim)

        // Frosted side panel — warm dark wood over the painted scene.
        let panel = roundedRect(panelRect, radius: 20,
                                fill: SKColor(red: 0.12, green: 0.09, blue: 0.07, alpha: 0.80),
                                stroke: SKColor(red: 0.40, green: 0.28, blue: 0.16, alpha: 0.9), lineWidth: 3)
        panel.zPosition = -1.5
        skyLayer.addChild(panel)

        // Header.
        titleLabel = label("Alan's Garden", size: 26, color: C.text, weight: .bold)
        titleLabel.horizontalAlignmentMode = .left
        titleLabel.position = CGPoint(x: 44, y: size.height - 42)
        addChild(titleLabel)

        subtitleLabel = label("", size: 13, color: C.dim, weight: .medium)
        subtitleLabel.horizontalAlignmentMode = .left
        subtitleLabel.position = CGPoint(x: 44, y: size.height - 64)
        addChild(subtitleLabel)

        // Daylight track + travelling sun.
        let trackRect = CGRect(x: size.width - 360, y: size.height - 46, width: 316, height: 10)
        daylightTrack = roundedRect(trackRect, radius: 5,
                                    fill: SKColor(white: 1, alpha: 0.10),
                                    stroke: SKColor(white: 1, alpha: 0.08), lineWidth: 1)
        addChild(daylightTrack)

        sun = makeSun(radius: 11)
        sun.position = CGPoint(x: trackRect.minX, y: trackRect.midY)
        addChild(sun)

        // Narrator: a kindly gardener-scientist in the bottom-left corner who "speaks"
        // through the status line — Mr. Midnight's storyteller, reimagined for the garden.
        var statusX: CGFloat = 44
        if let face = art("narrator.png") {
            let m: CGFloat = 84
            let rect = CGRect(x: 20, y: 8, width: m, height: m)
            let back = roundedRect(rect, radius: 20,
                                   fill: SKColor(red: 0.12, green: 0.09, blue: 0.07, alpha: 0.92),
                                   stroke: SKColor(red: 0.40, green: 0.28, blue: 0.16, alpha: 0.95), lineWidth: 2)
            addChild(back)
            let crop = SKCropNode()
            let mask = SKShapeNode(path: CGPath(roundedRect: rect, cornerWidth: 20, cornerHeight: 20, transform: nil))
            mask.fillColor = .white; mask.strokeColor = .clear
            crop.maskNode = mask
            let s = SKSpriteNode(texture: face)
            let ts = face.size()
            let scale = (m * 1.32) / ts.height
            s.size = CGSize(width: ts.width * scale, height: ts.height * scale)
            s.position = CGPoint(x: rect.midX, y: rect.midY)
            crop.addChild(s)
            addChild(crop)
            statusX = rect.maxX + 14
        }

        // Status line on a soft bar (the narrator's speech).
        let statusBar = roundedRect(CGRect(x: statusX, y: 30, width: size.width - statusX - 44, height: 40), radius: 12,
                                    fill: SKColor(white: 0, alpha: 0.30),
                                    stroke: SKColor(white: 1, alpha: 0.08), lineWidth: 1)
        statusBar.zPosition = -1.2
        skyLayer.addChild(statusBar)

        statusLabel = label("", size: 14, color: C.text, weight: .medium)
        statusLabel.horizontalAlignmentMode = .left
        statusLabel.position = CGPoint(x: statusX + 16, y: 50)
        statusLabel.preferredMaxLayoutWidth = size.width - statusX - 76
        statusLabel.numberOfLines = 2
        statusLabel.verticalAlignmentMode = .center
        addChild(statusLabel)

        // Panel header.
        let ph = label("Growth rules", size: 16, color: C.text, weight: .bold)
        ph.horizontalAlignmentMode = .left
        ph.position = CGPoint(x: panelX, y: panelRect.maxY - 30)
        ph.zPosition = -1
        skyLayer.addChild(ph)

        // Sunlight / direction-budget readout.
        budgetLabel = label("", size: 11, color: C.dim, weight: .medium)
        budgetLabel.horizontalAlignmentMode = .left
        budgetLabel.position = CGPoint(x: panelX, y: panelRect.maxY - 48)
        addChild(budgetLabel)

        // Poetic caption shown on a win.
        captionLabel = label("", size: 15, color: C.win, weight: .semibold)
        captionLabel.horizontalAlignmentMode = .center
        captionLabel.position = CGPoint(x: boardArea.midX, y: boardArea.minY - 8)
        captionLabel.alpha = 0
        addChild(captionLabel)
    }

    // MARK: Load a level

    private func loadLevel(_ index: Int) {
        levelIndex = (index + Levels.all.count) % Levels.all.count
        rules = [:]
        displayGrid = level.initial
        shownPositions = level.initial.flowerPositions()
        titleLabel.text = "Alan's Garden"
        subtitleLabel.text = "Level \(levelIndex + 1)/\(Levels.all.count)  ·  \(level.name)"
        captionLabel.removeAllActions(); captionLabel.alpha = 0
        computeBoardGeometry()
        buildBoard()
        buildControls()
        redrawFlowers(animated: false)
        updatePreview()
        setStatus(level.hint, color: C.dim)
        resetSun()
    }

    private func computeBoardGeometry() {
        let c = min(boardArea.width / CGFloat(level.initial.width),
                    boardArea.height / CGFloat(level.initial.height), 74)
        cell = c
        let bw = c * CGFloat(level.initial.width)
        let bh = c * CGFloat(level.initial.height)
        boardOrigin = CGPoint(x: boardArea.midX - bw / 2, y: boardArea.midY - bh / 2)
    }

    /// Cell center. Grid y=0 is the top row, so flip vertically for SpriteKit.
    private func center(_ p: Position) -> CGPoint {
        CGPoint(x: boardOrigin.x + CGFloat(p.x) * cell + cell / 2,
                y: boardOrigin.y + CGFloat(level.initial.height - 1 - p.y) * cell + cell / 2)
    }

    private func cellRect(_ p: Position, inset: CGFloat) -> CGRect {
        CGRect(x: boardOrigin.x + CGFloat(p.x) * cell + inset,
               y: boardOrigin.y + CGFloat(level.initial.height - 1 - p.y) * cell + inset,
               width: cell - inset * 2, height: cell - inset * 2)
    }

    private func buildBoard() {
        boardLayer.removeAllChildren()
        for y in 0..<level.initial.height {
            for x in 0..<level.initial.width {
                let p = Position(x, y)
                let rect = cellRect(p, inset: 3)
                if level.initial[p] == .rock {
                    boardLayer.addChild(makePebble(in: rect))
                    continue
                }
                // Soil tile.
                let tile = roundedRect(rect, radius: 9,
                                       fill: SKColor(white: 1, alpha: 0.05),
                                       stroke: SKColor(white: 1, alpha: 0.05), lineWidth: 1)
                boardLayer.addChild(tile)

                // Target ghost: tinted halo + dashed outline so the goal is readable.
                if let req = level.target.cells[p] {
                    let tint: SKColor = {
                        switch req {
                        case .any: return C.dim
                        case .exact(let c): return C.flower(c)
                        }
                    }()
                    let halo = roundedRect(rect, radius: 9,
                                           fill: tint.withAlphaComponent(0.12),
                                           stroke: .clear, lineWidth: 0)
                    boardLayer.addChild(halo)

                    let base = CGPath(roundedRect: rect.insetBy(dx: 3, dy: 3),
                                      cornerWidth: 8, cornerHeight: 8, transform: nil)
                    let dashed = base.copy(dashingWithPhase: 0, lengths: [5, 4])
                    let ghost = SKShapeNode(path: dashed)
                    ghost.strokeColor = tint.withAlphaComponent(0.6)
                    ghost.lineWidth = 1.5
                    ghost.fillColor = .clear
                    boardLayer.addChild(ghost)
                }
            }
        }
    }

    // MARK: Flowers

    private func redrawFlowers(animated: Bool) {
        flowerLayer.removeAllChildren()
        flowerNodes.removeAll()
        let flowers = displayGrid.flowerPositions()

        // Stems: connect each grown flower back to a same-colour neighbour, so the
        // spread reads as a vine rather than scattered dots. Seeds get no stem.
        for p in flowers {
            guard let color = displayGrid[p].flowerColor,
                  !level.initial[p].isFlower else { continue }
            for d in Direction.allCases {
                let q = Position(p.x + d.delta.dx, p.y + d.delta.dy)
                guard displayGrid.inBounds(q), displayGrid[q].flowerColor == color else { continue }
                let path = CGMutablePath()
                path.move(to: center(q)); path.addLine(to: center(p))
                let stem = SKShapeNode(path: path)
                stem.strokeColor = mix(C.flower(color), SKColor(red: 0.2, green: 0.4, blue: 0.2, alpha: 1), 0.55)
                    .withAlphaComponent(0.55)
                stem.lineWidth = max(2, cell * 0.07)
                stem.lineCap = .round
                stem.zPosition = 0
                flowerLayer.addChild(stem)
                break
            }
        }

        for p in flowers {
            guard let color = displayGrid[p].flowerColor else { continue }
            let satisfied = level.target.isSatisfied(displayGrid, p)
            let node = makeFlower(color, radius: cell * 0.33, warn: !satisfied,
                                  seed: p.x * 73 &+ p.y * 131)
            node.position = center(p)
            node.zPosition = 1
            flowerLayer.addChild(node)
            flowerNodes[p] = node

            if animated && !shownPositions.contains(p) {
                node.setScale(0.02)
                node.alpha = 0
                node.run(.group([
                    .fadeIn(withDuration: 0.22),
                    .sequence([.scale(to: 1.15, duration: 0.22), .scale(to: 1.0, duration: 0.14)]),
                ]))
            }
        }
        shownPositions = flowers
    }

    /// Faint ghosts where the garden would grow on the next sunlight step — bridges
    /// "set a rule" and "see what it does" before you commit to Sunrise.
    private func updatePreview() {
        previewLayer.removeAllChildren()
        guard !isAnimating else { return }
        let next = GrowthEngine.step(displayGrid, rules: rules)
        let newCells = next.flowerPositions().subtracting(displayGrid.flowerPositions())
        for p in newCells {
            guard let color = next[p].flowerColor else { continue }
            let dot = SKShapeNode(circleOfRadius: cell * 0.16)
            dot.fillColor = C.flower(color).withAlphaComponent(0.5)
            dot.strokeColor = C.flower(color).withAlphaComponent(0.8)
            dot.lineWidth = 1.5
            dot.position = center(p)
            dot.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.35, duration: 0.7),
                .fadeAlpha(to: 0.9, duration: 0.7),
            ])))
            previewLayer.addChild(dot)
        }
    }

    /// The look of each species: petal count, petal size (× radius), how far petals
    /// sit from the centre, whether there's a second inner ring, and the core sizes.
    private func species(_ color: Character) -> (count: Int, pw: CGFloat, ph: CGFloat,
                                                 off: CGFloat, layered: Bool,
                                                 core: CGFloat, pollen: CGFloat) {
        switch color {
        case "A": return (9, 0.36, 1.28, 0.58, false, 0.42, 0.22) // daisy
        case "B": return (5, 0.78, 1.02, 0.40, true,  0.34, 0.0)  // rose (layered)
        case "C": return (6, 0.64, 1.22, 0.52, false, 0.46, 0.24) // tulip / sun
        default:  return (6, 0.62, 1.16, 0.50, false, 0.46, 0.22)
        }
    }

    private func hash(_ n: Int) -> Int {
        var x = UInt32(truncatingIfNeeded: n &* 2654435761)
        x ^= x >> 13; x = x &* 2246822519; x ^= x >> 16
        return Int(x)
    }

    private func makeFlower(_ color: Character, radius r0: CGFloat, warn: Bool,
                            seed: Int, sway: Bool = true) -> SKNode {
        let s = species(color)
        let base0 = C.flower(color)

        // Per-instance variety so a bed of one species isn't a field of clones.
        let sizeJ = 1 + CGFloat(hash(seed) % 21 - 10) / 100          // ±10% size
        let r = r0 * sizeJ
        let brightJ = CGFloat(hash(seed &* 3) % 17 - 8) / 100         // ±8% brightness
        let base = brightJ >= 0 ? mix(base0, .white, brightJ) : mix(base0, .black, -brightJ)
        let baseAngle = CGFloat(hash(seed &* 7) % 360) * .pi / 180

        // Painted flower art (preferred). Falls back to the vector flower below.
        if let bloomTex = art("flower-\(color).png") {
            let node = SKNode()
            node.zRotation = baseAngle

            let shadow = SKSpriteNode(texture: softDot)
            shadow.size = CGSize(width: r * 2.6, height: r * 1.2)
            shadow.color = .black
            shadow.colorBlendFactor = 1
            shadow.alpha = 0.22
            shadow.position = CGPoint(x: 0, y: -r * 0.85)
            node.addChild(shadow)

            let glow = SKSpriteNode(texture: softDot)
            glow.size = CGSize(width: r * 3.2, height: r * 3.2)
            glow.color = base0
            glow.colorBlendFactor = 1
            glow.alpha = 0.18
            glow.blendMode = .add
            node.addChild(glow)

            let bloom = SKSpriteNode(texture: bloomTex)
            let side = r * 2.85
            bloom.size = CGSize(width: side, height: side)
            bloom.color = brightJ >= 0 ? .white : .black
            bloom.colorBlendFactor = abs(brightJ) * 0.55
            node.addChild(bloom)

            if warn {
                let warnRing = SKShapeNode(circleOfRadius: r * 1.5)
                warnRing.strokeColor = C.spill
                warnRing.lineWidth = 3
                warnRing.fillColor = .clear
                warnRing.glowWidth = 2
                node.addChild(warnRing)
            }
            if sway {
                let amp = 0.04 + CGFloat(hash(seed &* 11) % 4) / 100
                let dur = 1.5 + Double(hash(seed &* 13) % 8) / 10
                node.run(.sequence([
                    .wait(forDuration: Double(hash(seed &* 17) % 14) / 10),
                    .repeatForever(.sequence([
                        .rotate(byAngle: amp, duration: dur),
                        .rotate(byAngle: -amp * 2, duration: dur * 2),
                        .rotate(byAngle: amp, duration: dur),
                    ])),
                ]), withKey: "sway")
            }
            return node
        }

        let node = SKNode()
        node.zRotation = baseAngle

        // Soft contact shadow to ground the flower on the soil.
        let shadow = SKSpriteNode(texture: softDot)
        shadow.size = CGSize(width: r * 2.4, height: r * 1.1)
        shadow.color = .black
        shadow.colorBlendFactor = 1
        shadow.alpha = 0.18
        shadow.position = CGPoint(x: 0, y: -r * 0.55)
        node.addChild(shadow)

        let glow = SKSpriteNode(texture: softDot)
        glow.size = CGSize(width: r * 3.4, height: r * 3.4)
        glow.color = base
        glow.colorBlendFactor = 1
        glow.alpha = 0.28
        glow.blendMode = .add
        node.addChild(glow)

        // Petals: teardrop silhouettes with a base→tip gradient, slightly varied in
        // length, overlapping — reads as a flower rather than a ring of ovals.
        let tex = petalTexture(for: color)
        let edge = mix(base, .black, 0.22).withAlphaComponent(0.22)
        func ring(count: Int, scale: CGFloat, twist: CGFloat, alpha: CGFloat) {
            for i in 0..<count {
                let a = CGFloat(i) * (.pi * 2 / CGFloat(count)) + twist
                let lenJ = 1 + CGFloat(hash(seed &+ i &* 101) % 11 - 5) / 100
                let petal = SKShapeNode(path: petalPath(width: r * s.pw * scale,
                                                        height: r * s.ph * scale * lenJ))
                petal.fillColor = .white
                petal.fillTexture = tex
                petal.strokeColor = edge
                petal.lineWidth = 1
                petal.alpha = alpha
                petal.position = CGPoint(x: cos(a) * r * 0.12, y: sin(a) * r * 0.12)
                petal.zRotation = a - .pi / 2
                node.addChild(petal)
            }
        }
        ring(count: s.count, scale: 1.0, twist: 0, alpha: 0.95)
        if s.layered {
            ring(count: s.count, scale: 0.6, twist: .pi / CGFloat(s.count), alpha: 1.0)
        }

        // Center: a soft pollen disc with stamen flecks.
        let centerColor = (color == "B") ? mix(base, .black, 0.12) : mix(C.sun, base, 0.35)
        let core = SKShapeNode(circleOfRadius: r * s.core)
        core.fillColor = centerColor
        core.strokeColor = mix(centerColor, .black, 0.2).withAlphaComponent(0.3)
        core.lineWidth = 1
        node.addChild(core)

        if s.pollen > 0 {
            let stamen = 9
            for i in 0..<stamen {
                let a = CGFloat(i) * (.pi * 2 / CGFloat(stamen))
                let dot = SKShapeNode(circleOfRadius: max(1, r * 0.05))
                dot.fillColor = mix(centerColor, .white, 0.5)
                dot.strokeColor = .clear
                dot.position = CGPoint(x: cos(a) * r * s.core * 0.55, y: sin(a) * r * s.core * 0.55)
                node.addChild(dot)
            }
        }

        if warn {
            let warnRing = SKShapeNode(circleOfRadius: r * 1.35)
            warnRing.strokeColor = C.spill
            warnRing.lineWidth = 3
            warnRing.fillColor = .clear
            warnRing.glowWidth = 1
            node.addChild(warnRing)
        }

        // Gentle, desynchronised idle sway so the garden feels alive.
        if sway {
            let amp = 0.04 + CGFloat(hash(seed &* 11) % 4) / 100
            let dur = 1.5 + Double(hash(seed &* 13) % 8) / 10
            node.run(.sequence([
                .wait(forDuration: Double(hash(seed &* 17) % 14) / 10),
                .repeatForever(.sequence([
                    .rotate(byAngle: amp, duration: dur),
                    .rotate(byAngle: -amp * 2, duration: dur * 2),
                    .rotate(byAngle: amp, duration: dur),
                ])),
            ]), withKey: "sway")
        }
        return node
    }

    private func makePebble(in rect: CGRect) -> SKNode {
        let node = SKNode()
        let body = SKShapeNode(ellipseOf: CGSize(width: rect.width * 0.92, height: rect.height * 0.82))
        body.position = CGPoint(x: rect.midX, y: rect.midY)
        body.fillColor = SKColor(red: 0.34, green: 0.35, blue: 0.40, alpha: 1)
        body.strokeColor = SKColor(white: 0, alpha: 0.25)
        body.lineWidth = 1
        node.addChild(body)
        let hi = SKShapeNode(ellipseOf: CGSize(width: rect.width * 0.46, height: rect.height * 0.30))
        hi.position = CGPoint(x: rect.midX - rect.width * 0.12, y: rect.midY + rect.height * 0.16)
        hi.fillColor = SKColor(white: 1, alpha: 0.16)
        hi.strokeColor = .clear
        node.addChild(hi)
        return node
    }

    private func makeSun(radius r: CGFloat) -> SKNode {
        let node = SKNode()
        let glow = SKSpriteNode(texture: softDot)
        glow.size = CGSize(width: r * 5, height: r * 5)
        glow.color = C.sun
        glow.colorBlendFactor = 1
        glow.alpha = 0.5
        glow.blendMode = .add
        node.addChild(glow)
        let disc = SKShapeNode(circleOfRadius: r)
        disc.fillColor = C.sun
        disc.strokeColor = .clear
        node.addChild(disc)
        return node
    }

    private func resetSun() {
        sun.removeAllActions()
        sun.position = CGPoint(x: daylightTrack.frame.minX, y: sun.position.y)
    }

    // MARK: Controls

    private var controllableColors: [Character] { level.intendedRules.keys.sorted() }

    private func otherColor(_ c: Character) -> Character? {
        level.initial.flowerPositions()
            .compactMap { level.initial[$0].flowerColor }
            .first { $0 != c }
    }

    private var directionsUsed: Int { rules.values.reduce(0) { $0 + $1.directions.count } }

    private func buildControls() {
        controlLayer.removeAllChildren()

        if let maxD = level.maxDirections {
            budgetLabel.text = "Sunlight: \(level.sunlight) steps   ·   directions \(directionsUsed)/\(maxD)"
            budgetLabel.fontColor = directionsUsed > maxD ? C.spill : C.dim
        } else {
            budgetLabel.text = "Sunlight: \(level.sunlight) steps"
            budgetLabel.fontColor = C.dim
        }

        var cardTop: CGFloat = panelRect.maxY - 76
        for color in controllableColors {
            buildRuleCard(color: color, topY: cardTop)
            cardTop -= 168
        }

        let bx = panelX
        let bw = panelRect.width - 48
        pillButton(name: "btn|sunrise", text: "☀  Sunrise — grow",
                   rect: CGRect(x: bx, y: 196, width: bw, height: 46), style: .primary)
        pillButton(name: "btn|hint", text: "Hint",
                   rect: CGRect(x: bx, y: 150, width: bw / 2 - 5, height: 36), style: .ghost)
        pillButton(name: "btn|reset", text: "Reset",
                   rect: CGRect(x: bx + bw / 2 + 5, y: 150, width: bw / 2 - 5, height: 36), style: .ghost)
        pillButton(name: "btn|next", text: "Next level  ›",
                   rect: CGRect(x: bx, y: 106, width: bw, height: 36), style: .ghost)
    }

    private func buildRuleCard(color: Character, topY: CGFloat) {
        let rule = rules[color]
        let cardRect = CGRect(x: panelX - 8, y: topY - 132, width: panelRect.width - 32, height: 140)
        if let parch = art("parchment.png") {
            controlLayer.addChild(texturedPanel(cardRect, radius: 14, texture: parch))
            let border = roundedRect(cardRect, radius: 14, fill: .clear,
                                     stroke: SKColor(red: 0.36, green: 0.24, blue: 0.12, alpha: 0.85),
                                     lineWidth: 1.5)
            controlLayer.addChild(border)
        } else {
            let card = roundedRect(cardRect, radius: 14,
                                   fill: SKColor(white: 1, alpha: 0.05),
                                   stroke: SKColor(white: 1, alpha: 0.07), lineWidth: 1)
            controlLayer.addChild(card)
        }

        // Header: mini flower swatch + name.
        let swatch = makeFlower(color, radius: 12, warn: false, seed: 1, sway: false)
        swatch.position = CGPoint(x: panelX + 12, y: topY - 4)
        swatch.setScale(0.85)
        controlLayer.addChild(swatch)

        let inkOnParchment = SKColor(red: 0.30, green: 0.19, blue: 0.08, alpha: 1)
        let name = label("Plant \(color)", size: 14, color: inkOnParchment, weight: .bold)
        name.horizontalAlignmentMode = .left
        name.position = CGPoint(x: panelX + 34, y: topY - 8)
        controlLayer.addChild(name)

        // Direction toggles, plus-arranged, circular.
        let cx: CGFloat = panelX + 56, cy: CGFloat = topY - 74
        let s: CGFloat = 32, gap: CGFloat = 6
        func dirRect(_ dx: CGFloat, _ dy: CGFloat) -> CGRect {
            CGRect(x: cx + dx * (s + gap) - s / 2, y: cy + dy * (s + gap) - s / 2, width: s, height: s)
        }
        let dirs: [(Direction, CGFloat, CGFloat, String)] = [
            (.north, 0, 1, "↑"), (.south, 0, -1, "↓"),
            (.west, -1, 0, "←"), (.east, 1, 0, "→"),
        ]
        for (d, dx, dy, glyph) in dirs {
            let on = rule?.directions.contains(d) ?? false
            pillButton(name: "dir|\(color)|\(d.code)", text: glyph,
                       rect: dirRect(dx, dy), style: on ? .on : .toggle)
        }

        // Modifier pills on the right: activation / inhibition (mutually exclusive,
        // need a second species) and clustering (works even for a single species).
        let px = cx + 50, pw: CGFloat = 120, ph: CGFloat = 26
        if let other = otherColor(color) {
            pillButton(name: "need|\(color)", text: "need \(other)",
                       rect: CGRect(x: px, y: cy + 20, width: pw, height: ph),
                       style: rule?.needColor != nil ? .on : .toggle)
            pillButton(name: "avoid|\(color)", text: "avoid \(other)",
                       rect: CGRect(x: px, y: cy - 8, width: pw, height: ph),
                       style: rule?.avoidColor != nil ? .on : .toggle)
        }
        let minN = rule?.minNeighbors ?? 0
        pillButton(name: "cluster|\(color)", text: minN > 0 ? "cluster \u{2265}\(minN)" : "cluster",
                   rect: CGRect(x: px, y: cy - 36, width: pw, height: ph),
                   style: minN > 0 ? .on : .toggle)
    }

    private enum BtnStyle { case primary, ghost, toggle, on }

    @discardableResult
    private func pillButton(name: String, text: String, rect: CGRect, style: BtnStyle) -> SKNode {
        let radius = min(rect.height / 2, 14)
        let fill: SKColor
        let stroke: SKColor
        let textColor: SKColor
        switch style {
        case .primary: fill = C.sun;                       stroke = .clear;                       textColor = SKColor(red: 0.25, green: 0.16, blue: 0.05, alpha: 1)
        case .on:      fill = C.accent;                    stroke = .clear;                       textColor = SKColor(red: 0.06, green: 0.12, blue: 0.18, alpha: 1)
        case .ghost:   fill = SKColor(white: 1, alpha: 0.08); stroke = SKColor(white: 1, alpha: 0.16); textColor = C.text
        case .toggle:  fill = SKColor(red: 0.30, green: 0.20, blue: 0.10, alpha: 0.16); stroke = SKColor(red: 0.32, green: 0.21, blue: 0.10, alpha: 0.45); textColor = SKColor(red: 0.32, green: 0.21, blue: 0.10, alpha: 1)
        }
        let node = roundedRect(rect, radius: radius, fill: fill, stroke: stroke,
                               lineWidth: stroke == SKColor.clear ? 0 : 1)
        node.name = name

        if style == .primary || style == .on {
            let glow = SKSpriteNode(texture: softDot)
            glow.size = CGSize(width: rect.width * 1.05, height: rect.height * 2.4)
            glow.color = fill
            glow.colorBlendFactor = 1
            glow.alpha = 0.35
            glow.blendMode = .add
            glow.zPosition = -1
            glow.position = CGPoint(x: rect.midX, y: rect.midY)
            node.addChild(glow)
        }

        let weight: NSFont.Weight = (style == .primary || style == .on) ? .bold : .medium
        let lbl = label(text, size: style == .primary ? 16 : 14, color: textColor, weight: weight)
        lbl.position = CGPoint(x: rect.midX, y: rect.midY)
        lbl.verticalAlignmentMode = .center
        lbl.horizontalAlignmentMode = .center
        node.addChild(lbl)
        controlLayer.addChild(node)
        return node
    }

    // MARK: Input

    /// The named button node under a scene point, if any.
    private func namedNode(at p: CGPoint) -> SKNode? {
        for hit in nodes(at: p) {
            var node: SKNode? = hit
            while let n = node {
                if n.name != nil { return n }
                node = n.parent
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        guard !isAnimating else { return }
        guard let node = namedNode(at: event.location(in: self)), let name = node.name else { return }
        flash(node)
        handle(name)
    }

    override func mouseMoved(with event: NSEvent) {
        let node = namedNode(at: event.location(in: self))
        (node != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: loadLevel(levelIndex - 1); return   // ←
        case 124: loadLevel(levelIndex + 1); return   // →
        default: break
        }
        guard let ch = event.charactersIgnoringModifiers?.lowercased().first else { return }
        switch ch {
        case " ", "g": if !isAnimating { sunrise() }
        case "h": if !isAnimating { rules = level.intendedRules; buildControls(); updatePreview(); setStatus("Showing a known solution — press ☀ Sunrise.", color: C.dim) }
        case "r": if !isAnimating { resetGarden() }
        case "n": loadLevel(levelIndex + 1)
        case "1"..."9":
            if let d = ch.wholeNumberValue, d >= 1, d <= Levels.all.count { loadLevel(d - 1) }
        default: break
        }
    }

    /// Quick press feedback.
    private func flash(_ node: SKNode) {
        node.run(.sequence([.scale(to: 0.97, duration: 0.05), .scale(to: 1.0, duration: 0.08)]))
    }

    private func handle(_ name: String) {
        let parts = name.split(separator: "|").map(String.init)
        switch parts.first {
        case "dir":
            guard parts.count == 3, let color = parts[1].first,
                  let d = Direction.from(code: parts[2].first ?? " ") else { return }
            var r = rules[color] ?? Rule([])
            if r.directions.contains(d) {
                r.directions.remove(d)
            } else {
                if let maxD = level.maxDirections, directionsUsed >= maxD {
                    setStatus("Direction budget reached (\(maxD)). Turn one off first.", color: C.spill)
                    return
                }
                r.directions.insert(d)
            }
            rules[color] = r
            buildControls()
            updatePreview()
            describeRule(color)
        case "avoid":
            guard parts.count == 2, let color = parts[1].first else { return }
            var r = rules[color] ?? Rule([])
            if r.avoidColor == nil { r.avoidColor = otherColor(color); r.needColor = nil }
            else { r.avoidColor = nil }
            rules[color] = r
            buildControls()
            updatePreview()
            describeRule(color)
        case "need":
            guard parts.count == 2, let color = parts[1].first else { return }
            var r = rules[color] ?? Rule([])
            if r.needColor == nil { r.needColor = otherColor(color); r.avoidColor = nil }
            else { r.needColor = nil }
            rules[color] = r
            buildControls()
            updatePreview()
            describeRule(color)
        case "cluster":
            guard parts.count == 2, let color = parts[1].first else { return }
            var r = rules[color] ?? Rule([])
            switch r.minNeighbors {       // cycle off -> >=2 -> >=3 -> off
            case 0: r.minNeighbors = 2
            case 2: r.minNeighbors = 3
            default: r.minNeighbors = 0
            }
            rules[color] = r
            buildControls()
            updatePreview()
            describeRule(color)
        case "btn":
            switch parts[1] {
            case "sunrise": sunrise()
            case "reset": resetGarden()
            case "hint": rules = level.intendedRules; buildControls(); updatePreview(); setStatus("Showing a known solution — press ☀ Sunrise.", color: C.dim)
            case "next": loadLevel(levelIndex + 1)
            default: break
            }
        default: break
        }
    }

    // MARK: Grow

    private func resetGarden() {
        captionLabel.removeAllActions(); captionLabel.alpha = 0
        displayGrid = level.initial
        shownPositions = level.initial.flowerPositions()
        redrawFlowers(animated: false)
        updatePreview()
        setStatus(level.hint, color: C.dim)
        resetSun()
    }

    private func sunrise() {
        guard !isAnimating else { return }
        let frames = GrowthEngine.grow(level.initial, rules: rules, maxSteps: level.sunlight)
        guard frames.count > 1 else {
            setStatus("Nothing grows yet — give a plant some directions first.", color: C.dim)
            return
        }
        isAnimating = true
        previewLayer.removeAllChildren()
        captionLabel.removeAllActions(); captionLabel.alpha = 0
        displayGrid = level.initial
        shownPositions = level.initial.flowerPositions()
        redrawFlowers(animated: false)

        let stepDur = 0.45
        let total = Double(frames.count) * stepDur
        resetSun()
        sun.run(.moveTo(x: daylightTrack.frame.maxX, duration: total))
        warmOverlay.removeAllActions()
        warmOverlay.run(.sequence([
            .fadeAlpha(to: 0.12, duration: total * 0.5),
            .fadeAlpha(to: 0, duration: total * 0.5),
        ]))

        var actions: [SKAction] = []
        for frame in frames.dropFirst() {
            actions.append(.wait(forDuration: stepDur))
            actions.append(.run { [weak self] in
                self?.displayGrid = frame
                self?.redrawFlowers(animated: true)
            })
        }
        actions.append(.run { [weak self] in self?.finishGrow(frames: frames) })
        run(.sequence(actions))
    }

    private func finishGrow(frames: [Grid]) {
        let report = GrowthEngine.evaluate(frames: frames, target: level.target)
        isAnimating = false
        if let win = report.winStep {
            displayGrid = frames[win]
            redrawFlowers(animated: false)
            setStatus("✓ The garden bloomed into the target at step \(win)!", color: C.win)
            blossom()
            winFlash()
            showCaption(quotes[levelIndex % quotes.count])
        } else {
            redrawFlowers(animated: false)
            updatePreview()
            setStatus("✗ \(report.missing) cell(s) missing, \(report.overflow) spilled over — adjust directions or steps.", color: C.spill)
            shakeSpilled()
        }
    }

    private func winFlash() {
        let flash = roundedRect(boardArea.insetBy(dx: -16, dy: -16), radius: 22,
                                fill: SKColor(white: 1, alpha: 1), stroke: .clear, lineWidth: 0)
        flash.zPosition = 40
        flash.alpha = 0
        flash.blendMode = .add
        addChild(flash)
        flash.run(.sequence([
            .fadeAlpha(to: 0.35, duration: 0.12),
            .fadeAlpha(to: 0, duration: 0.6),
            .removeFromParent(),
        ]))
    }

    private func showCaption(_ text: String) {
        captionLabel.text = text
        captionLabel.removeAllActions()
        captionLabel.alpha = 0
        captionLabel.run(.sequence([
            .fadeAlpha(to: 1, duration: 0.5),
            .wait(forDuration: 4.0),
            .fadeAlpha(to: 0, duration: 0.8),
        ]))
    }

    private func shakeSpilled() {
        for (p, node) in flowerNodes where !level.target.isSatisfied(displayGrid, p) {
            node.run(.sequence([
                .moveBy(x: -4, y: 0, duration: 0.04),
                .moveBy(x: 8, y: 0, duration: 0.08),
                .moveBy(x: -8, y: 0, duration: 0.08),
                .moveBy(x: 4, y: 0, duration: 0.04),
            ]))
        }
    }

    private func blossom() {
        for node in flowerLayer.children {
            node.run(.sequence([.scale(to: 1.28, duration: 0.18), .scale(to: 1.0, duration: 0.20)]))
        }
        let e = SKEmitterNode()
        e.particleTexture = softDot
        e.numParticlesToEmit = 60
        e.particleBirthRate = 600
        e.particleLifetime = 1.5
        e.particleLifetimeRange = 0.6
        e.emissionAngleRange = .pi * 2
        e.particleSpeed = 140
        e.particleSpeedRange = 90
        e.particleAlpha = 0.9
        e.particleAlphaSpeed = -0.7
        e.particleScale = 0.18
        e.particleScaleRange = 0.12
        e.particleScaleSpeed = -0.06
        e.particleColorBlendFactor = 1
        e.particleColor = C.sun
        e.particleBlendMode = .add
        e.position = CGPoint(x: boardArea.midX, y: boardArea.midY)
        e.zPosition = 50
        addChild(e)
        e.run(.sequence([.wait(forDuration: 2.2), .removeFromParent()]))
    }

    // MARK: Status helpers

    private func describeRule(_ color: Character) {
        let r = rules[color]
        let dirs = r?.directions ?? []
        let arrows = [Direction.north, .east, .south, .west]
            .filter { dirs.contains($0) }
            .map { String($0.code) }
            .joined(separator: " ")
        var text = "Plant \(color) spreads: " + (arrows.isEmpty ? "(pick a direction)" : arrows)
        if let need = r?.needColor { text += "   ·   only next to \(need)" }
        if let avoid = r?.avoidColor { text += "   ·   avoiding \(avoid)" }
        if let m = r?.minNeighbors, m > 0 { text += "   ·   only where \u{2265}\(m) of its own" }
        text += "   —   press ☀ Sunrise"
        setStatus(text, color: C.text)
    }

    private func setStatus(_ text: String, color: SKColor) {
        statusLabel.text = text
        statusLabel.fontColor = color
    }

    // MARK: Drawing helpers

    private func roundedRect(_ rect: CGRect, radius: CGFloat, fill: SKColor,
                             stroke: SKColor, lineWidth: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(rect: rect, cornerRadius: radius)
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = lineWidth
        node.isAntialiased = true
        return node
    }

    private func label(_ text: String, size: CGFloat, color: SKColor,
                       weight: NSFont.Weight = .regular) -> SKLabelNode {
        let node = SKLabelNode(text: text)
        node.fontName = roundedFontName(weight: weight)
        node.fontSize = size
        node.fontColor = color
        node.verticalAlignmentMode = .center
        return node
    }

    private func roundedFontName(weight: NSFont.Weight) -> String {
        let base = NSFont.systemFont(ofSize: 16, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded),
           let f = NSFont(descriptor: d, size: 16),
           NSFont(name: f.fontName, size: 16) != nil {
            return f.fontName
        }
        return base.fontName
    }

    /// A teardrop petal pointing up: narrow rounded base at the origin, widening to
    /// a rounded tip at (0, height).
    private func petalPath(width w: CGFloat, height h: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addCurve(to: CGPoint(x: 0, y: h),
                   control1: CGPoint(x: w * 0.58, y: h * 0.12),
                   control2: CGPoint(x: w * 0.42, y: h * 0.98))
        p.addCurve(to: CGPoint(x: 0, y: 0),
                   control1: CGPoint(x: -w * 0.42, y: h * 0.98),
                   control2: CGPoint(x: -w * 0.58, y: h * 0.12))
        p.closeSubpath()
        return p
    }

    private func petalTexture(for color: Character) -> SKTexture {
        if let t = petalTex[color] { return t }
        let base = C.flower(color)
        let tex = gradientTexture(size: CGSize(width: 48, height: 120),
                                  colors: [mix(base, .white, 0.55), base, mix(base, .black, 0.16)],
                                  locations: [0, 0.55, 1], horizontal: false)
        petalTex[color] = tex
        return tex
    }

    private func mix(_ a: SKColor, _ b: SKColor, _ t: CGFloat) -> SKColor {
        let ca = a.usingColorSpace(.deviceRGB) ?? a
        let cb = b.usingColorSpace(.deviceRGB) ?? b
        return SKColor(red: ca.redComponent * (1 - t) + cb.redComponent * t,
                       green: ca.greenComponent * (1 - t) + cb.greenComponent * t,
                       blue: ca.blueComponent * (1 - t) + cb.blueComponent * t,
                       alpha: 1)
    }

    // MARK: Texture factories

    private func gradientTexture(size: CGSize, colors: [SKColor], locations: [CGFloat],
                                 horizontal: Bool) -> SKTexture {
        let w = max(1, Int(size.width)), h = max(1, Int(size.height))
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let grad = CGGradient(colorsSpace: space,
                                    colors: colors.map { $0.cgColor } as CFArray,
                                    locations: locations) else {
            return SKTexture()
        }
        // colors are top->bottom, so start at the top (y=h).
        let start = horizontal ? CGPoint(x: 0, y: 0) : CGPoint(x: 0, y: h)
        let end = horizontal ? CGPoint(x: w, y: 0) : CGPoint(x: 0, y: 0)
        ctx.drawLinearGradient(grad, start: start, end: end, options: [])
        guard let img = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: img)
    }

    private func softCircleTexture(diameter: CGFloat) -> SKTexture {
        let d = max(2, Int(diameter))
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: d, height: d, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let grad = CGGradient(colorsSpace: space,
                                    colors: [SKColor(white: 1, alpha: 1).cgColor,
                                             SKColor(white: 1, alpha: 0).cgColor] as CFArray,
                                    locations: [0, 1]) else {
            return SKTexture()
        }
        let c = CGPoint(x: d / 2, y: d / 2)
        ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0,
                               endCenter: c, endRadius: CGFloat(d) / 2, options: [])
        guard let img = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: img)
    }
}
