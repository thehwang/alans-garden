-- Alan's Garden — automated demo driver for Hammerspoon.
--
-- Drives the macOS app with real mouse clicks (so the demo shows genuine
-- "solving") and paints timed subtitles via hs.canvas. Hammerspoon does NOT
-- record: start a screen recording (QuickTime, or `screencapture -v demo.mov`)
-- first, then run this. Add background music in post, e.g.:
--   ffmpeg -i demo.mov -i music.mp3 -map 0:v -map 1:a -c:v copy -shortest demo_final.mp4
--
-- How to run: open Alan's Garden, then in the Hammerspoon console:
--   dofile("/Users/hwang/Cursor/personal/AlansGarden/prototype/tools/demo.lua")
--
-- Geometry facts this relies on (keep in sync with the app):
--   * window content = scene = 1000 x 680, scaleMode .aspectFit (1:1, no scaling)
--   * scene origin is bottom-left; screen point = (f.x + sx, f.y + f.h - sy)
--   * one growth step animates for 0.45s; the win caption holds ~5.3s
--   * a single-species rule card sits at cy = 450; its controls (scene coords):
--       ↑(736,488) ↓(736,412) ←(698,450) →(774,450)
--       need(846,470)  avoid(846,442)  cluster(846,414)
--       Sunrise button center (816,219)

local APP = "GardenApp"
local SCENE_H = 680
local STEP = 0.45   -- seconds per growth step, from sunrise()

-- Button centres in SCENE coordinates (bottom-left origin).
local B = {
  up = {736, 488}, down = {736, 412}, left = {698, 450}, right = {774, 450},
  need = {846, 470}, avoid = {846, 442}, cluster = {846, 414},
  sunrise = {816, 219},
}

-- ---- helpers ---------------------------------------------------------------

local TITLE = "Alan's Garden"

-- Find the game window. By title first (most reliable), then by app name/path.
local function gardenWin()
  local w = hs.window.find(TITLE)
  if w then return w end
  local app = hs.application.get(APP) or hs.application.get(TITLE)
  if app and app:mainWindow() then return app:mainWindow() end
  for _, a in ipairs(hs.application.runningApplications()) do
    local p = a:path() or ""
    if (a:name() or ""):find("Garden") or p:find("GardenApp") then
      if a:mainWindow() then return a:mainWindow() end
    end
  end
  return nil
end

-- Print every running app name (run if the window still isn't found).
function listApps()
  for _, a in ipairs(hs.application.runningApplications()) do print(a:name()) end
end

local function focus()
  local w = gardenWin()
  if w then w:application():activate(true); w:focus()
  else hs.application.launchOrFocus(APP) end
end

local function click(btn)
  local w = gardenWin()
  if not w then
    hs.alert("Garden window not found — run listApps() in the console")
    print("Garden window not found. Running apps:"); listApps()
    return
  end
  w:application():activate(true); w:focus()
  local f = w:frame()
  hs.eventtap.leftClick({ x = f.x + btn[1], y = f.y + f.h - btn[2] })
end

local function key(k) focus(); hs.eventtap.keyStroke({}, k, 0) end

-- Subtitle overlay. Built when the demo starts, pinned to the bottom of the
-- screen that actually holds the game window (handles multi-monitor setups).
local cap = nil

local function buildCaption(sf)
  if cap then cap:delete() end
  cap = hs.canvas.new({ x = sf.x, y = sf.y + sf.h - 132, w = sf.w, h = 96 })
  cap[1] = { type = "rectangle", action = "fill",
             fillColor = { alpha = 0.5, red = 0, green = 0, blue = 0 },
             roundedRectRadii = { xRadius = 16, yRadius = 16 },
             frame = { x = sf.w * 0.10, y = 12, w = sf.w * 0.80, h = 70 } }
  cap[2] = { type = "text", text = "", textSize = 28, textAlignment = "center",
             textColor = { white = 1.0 },
             frame = { x = sf.w * 0.10, y = 28, w = sf.w * 0.80, h = 44 } }
  cap:level(hs.canvas.windowLevels.overlay)
end

-- Place the caption band on the game window's screen (fallback: main screen).
local function captionScreenFrame()
  local w = gardenWin()
  if w and w:screen() then return w:screen():frame() end
  return hs.screen.mainScreen():frame()
end

-- Voiceover (optional): speak each caption aloud via macOS TTS, in sync with the
-- subtitle. With NARRATE=false the demo is silent (subtitles only) and no speech
-- object is created — so a TTS/API hiccup can never stall the demo timeline.
local NARRATE = false    -- subtitles only; set true to also speak captions aloud
local VOICE_RATE = 180   -- words/min; ~175-185 reads clearly without dragging
local voice = nil

if NARRATE then
  voice = hs.speech.new()
  -- Pin Samantha so it sounds the same on any Mac. Voice identifiers vary by
  -- macOS version; try the known ones and keep the first that applies. Wrapped
  -- in pcall so any speech-API difference can't abort the whole script.
  if voice then
    pcall(function()
      for _, id in ipairs({
        "com.apple.voice.enhanced.en-US.Samantha",
        "com.apple.voice.compact.en-US.Samantha",
        "com.apple.speech.synthesis.voice.samantha",
      }) do
        voice:voice(id)                 -- get/set: pass id to set, no arg to read
        if voice:voice() == id then break end
      end
      voice:rate(VOICE_RATE)
      print("Demo voice:", voice:voice() or "(system default)", "rate", voice:rate())
    end)
  end
end

local function speak(t)
  if not NARRATE or not voice or not t or t == "" then return end
  local s = t:gsub(">=%s*", "at least "):gsub("·", ", "):gsub("—", " - "):gsub("…", "")
  voice:stop()                                  -- avoid the "busy -> dropped" bug
  hs.timer.doAfter(0.06, function() if voice then voice:speak(s) end end)
end

local function caption(t)
  if not cap then return end
  cap[2].text = t or ""
  if t and t ~= "" then cap:show(); speak(t) else cap:hide() end
end

-- Sequential timeline: each at(gap, fn) fires `gap` seconds after the previous.
--
-- IMPORTANT: keep the timer objects in a *global* table. If they were local,
-- Lua's GC could collect them after dofile() returns and pending timers would
-- silently stop firing partway through (the demo would freeze mid-run). Also
-- cancel any leftover timers from a previous run so re-running can't overlap.
if gardenDemoTimers then
  for _, t in ipairs(gardenDemoTimers) do if t and t.stop then t:stop() end end
end
gardenDemoTimers = {}
local clock = 0
local function at(gap, fn)
  clock = clock + gap
  gardenDemoTimers[#gardenDemoTimers + 1] = hs.timer.doAfter(clock, fn)
end

-- ---- the script ------------------------------------------------------------
-- Two representative real-solve levels: L5 (Turing inhibition) and L9 (clustering).

at(0.3, function()
  focus()
  buildCaption(captionScreenFrame())   -- captions land on the game's own screen
  caption("Alan's Garden — flowers are tiny programs")
end)

-- Captions are sparse and complete sentences, with the button-clicking done
-- silently in between, so each spoken line has time to finish before the next.

-- Level 5 — inhibition: B floods the bed but keeps its distance from A.
at(2.6, function() key("5"); caption("Turing's morphogenesis, as a puzzle") end)
at(1.6, function() click(B.up) end)        -- click B's rule (silent)
at(0.5, function() click(B.down) end)
at(0.5, function() click(B.left) end)
at(0.5, function() click(B.right) end)
at(0.6, function() click(B.avoid) end)
at(1.0, function() click(B.sunrise); caption("Plant B spreads everywhere, but avoids crowding A") end)
at(6.8, function() caption("A Turing spot: order grown from one simple rule") end)

-- Level 9 — clustering: fill the outlined block without spilling.
at(4.0, function() key("9"); caption("A deeper rule: clustering") end)
at(1.6, function() click(B.up) end)        -- click A's rule (silent)
at(0.5, function() click(B.down) end)
at(0.5, function() click(B.left) end)
at(0.5, function() click(B.right) end)
at(0.6, function() click(B.cluster) end)
at(1.0, function() click(B.sunrise); caption("It blooms only where well-supported, filling the frame exactly") end)
at(5.0, function() caption("Alan's Garden — a bloom for Alan Turing · June Solstice") end)

at(5.5, function() caption(""); if cap then cap:delete(); cap = nil end end)

hs.alert("Demo started — recording? (~" .. string.format("%.0f", clock) .. "s)")
