import AppKit
import SpriteKit
import GardenCore

// A tiny AppKit host for the SpriteKit garden scene. Built programmatically so it
// runs straight from `swift run GardenApp` (no storyboard / .xcodeproj).

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var scene: GardenScene!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = CGSize(width: 1000, height: 680)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Alan's Garden"
        window.center()

        let skView = SKView(frame: NSRect(origin: .zero, size: size))
        skView.ignoresSiblingOrder = true

        scene = GardenScene(size: size)
        scene.scaleMode = .aspectFit
        skView.presentScene(scene)

        // Hover support: deliver mouse-moved events to the scene.
        let tracking = NSTrackingArea(rect: skView.bounds,
                                      options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                      owner: skView, userInfo: nil)
        skView.addTrackingArea(tracking)

        window.contentView = skView
        window.acceptsMouseMovedEvents = true
        window.makeFirstResponder(skView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
