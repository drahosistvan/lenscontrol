# Design brief — LensControl (macOS)

Paste this into Claude Design.

---

Design a small native macOS utility called **LensControl**. It remote-controls a Nikon mirrorless camera (Z5 II) over USB while the camera is being used as a webcam through an HDMI capture card. The user is on a video call or streaming and wants to tweak exposure and colour *without touching the camera or leaving the call*. The app is a thin wrapper around the open-source `gphoto2` tool; it must feel instant, quiet and native — a Mac utility, not a camera-brand app.

The name says what it does: it controls, from the menu bar, the settings you'd otherwise reach for on the lens and body. Use "LensControl" as one word, capital L and C, in the window title, About text and app icon; never "Lens Control" or "Lenscontrol".

## Two presentations of the same content

1. **Menu-bar popover** (primary, always available). A camera icon in the menu bar opens a compact panel, ~330 pt wide, that fits on one screen without scrolling. Optimised for a 5-second interaction: open, change one thing, close.
2. **Floating window** (optional). Same controls, opened from the popover ("Open as window", ⌘O) or via the Window menu. Meant to sit beside a video-call app for a whole session. May use a little more room (e.g. two columns, larger slider) and should feel at home alongside FaceTime/Zoom. Supports "keep on top" as a toggle.

Both share one state and update live; changing a value in one reflects in the other.

## Controls (in this order)

**Header**: camera model (e.g. "Nikon Z5 II") — the app's own name appears only in the window title bar and the menu-bar icon's tooltip, not inside the panel. Battery %, mode-dial position as a small badge (`M`, `A`, `S`, `P`) — the dial can't be changed from the app, so the badge is informational. A tiny activity indicator while a command is in flight (each write takes ~0.4 s).

**Exposure**
- Shutter — discrete list: 1/30 … 1/8000
- Aperture — discrete list: f/2 … f/16 (depends on lens)
- ISO — discrete list: 100 … 204800
- Auto ISO — switch; when on, an extra **Max ISO** row appears
- EV compensation — −3 … +3 in ⅓ steps; 0 should be visually "home"

**White balance**
- Mode — Auto, Daylight, Cloudy, Shade, Tungsten, Fluorescent, Flash, Colour temperature, Preset, Natural light auto
- Kelvin — 2500–10000 K, step 10, only visible in Colour-temperature mode. Slider plus −100/+100 nudge buttons and a numeric readout. Commit on release, not per pixel.

**Focus & audio**
- AF mode — AF-S, AF-F (continuous), Manual
- "Autofocus now" button (one AF cycle)
- Mic sensitivity — Auto / High / Medium

**Presets** (new)
- A row/menu of named presets, e.g. "Daylight desk", "Evening lamp", "Ring light".
- Actions: *Apply*, *Save current as…* (asks for a name), *Update* (overwrite with current camera values), *Rename*, *Delete*.
- A preset stores every writable value above. Applying shows progress (it's ~1 s) and, if the camera rejects some values (e.g. an aperture the mounted lens can't reach), reports which ones without undoing the rest.
- Show which preset is active only when the camera's current values match it exactly; otherwise show "Custom".

**Footer**: "Updated 5 s ago", Refresh (⌘R), Quit (⌘Q) in the popover; the window has a normal title bar instead.

## States to design

- Connecting (first read, ~0.2 s — probably just a spinner in the header).
- Connected (normal).
- **No camera on USB** — friendly empty state: "Turn the camera on and check the cable", with a retry.
- **gphoto2 not installed** — show the one-line install command in monospace.
- **Read-only control** — when the mode dial makes a property un-editable (e.g. shutter in `A` mode), the control is disabled with a tooltip explaining why; don't hide it.
- **Write rejected** — an inline, dismissible warning under the controls, one line, with the camera's reason. The control snaps back to the real value.
- Busy indicator during writes; controls stay enabled (writes are queued in order).

## Feel

- Native macOS 14+ SwiftUI: system fonts, standard pickers/switches/sliders, vibrancy in the popover, light and dark mode, respects Reduce Motion.
- Dense but calm. Labels right-aligned in a two-column grid, values left. Section headers small-caps secondary.
- No camera-brand styling, no skeuomorphic dials. The only colour is semantic (warning banner, active preset tint).
- Keyboard: arrow keys move through pickers; ⌘1…⌘9 apply presets 1–9.
- Icons: a monochrome template glyph for the menu bar (a lens/aperture ring reads better at 16 pt than a whole camera and echoes the name), and a full macOS app icon for the window/Dock — a lens seen head-on, aperture blades visible, on the standard rounded-square. No text in the icon.

## Deliverables

1. Menu-bar popover: connected state, with Auto ISO on and Colour-temperature WB (so all optional rows are visible).
2. Same popover: "No camera" state and "write rejected" banner.
3. Floating window layout titled "LensControl", including the presets area and "keep on top" control.
4. "Save preset as…" interaction.
5. Menu-bar glyph and app icon for LensControl.
6. Component notes: spacing, type scale, how disabled/read-only differs from normal, dark-mode variants.
