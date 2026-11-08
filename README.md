# LensControl

A small macOS menu-bar app to remote-control a Nikon Z5 II over USB while it
is used as a webcam (HDMI → Elgato Cam Link 4K). It talks to the camera through
the open-source [libgphoto2](http://gphoto.org) library in-process — no Nikon
software, one ~80 MB menu-bar process, reads and writes in ~2 ms, and a live
preview of what the camera sees.

What it controls — the **movie**-mode properties, i.e. what the HDMI feed shows.
The Z5 II keeps separate stills and video settings; the named gphoto2 keys
(`whitebalance`, `iso`, `isoauto` …) are the stills ones and either do nothing
to video or are rejected while the mode switch is on video, so several controls
use raw Nikon PTP codes:

| Panel        | key                          | Notes                                 |
|--------------|------------------------------|---------------------------------------|
| Live preview | `capture_preview`            | USB live view, 640×360 at up to 20 fps (camera delivers 29); toggle with the eye button |
| Shutter      | `movieshutterspeed`          | 1/30 … 1/8000                         |
| Aperture     | `movief-number`              | lens dependent                        |
| ISO          | `movieiso`                   | 100 … 204800                          |
| Auto ISO     | `d0ad` MovISOAutoControl     | "Auto ISO control (mode M)" in the video menu |
| Max ISO      | `d0ae` MovISOAutoHighLimit   | shown when Auto ISO is on             |
| EV           | `movieexposurecompensation`  | −3 … +3 in ⅓ steps                    |
| WB mode      | `d23a` MovieWhiteBalance     | Auto, Direct sunlight, …, Colour temperature, Same as photo settings; raw codes mapped in `CameraModel.movieWhiteBalanceNames` |
| Kelvin       | `d21a` MovieWbColorTemp      | 2500 – 10000 K, step 10; shown in Colour-temperature mode |
| AF mode      | `liveviewaffocus`            | AF-S / AF-F / MF                      |
| Autofocus now| `autofocusdrive`             | one AF cycle                          |
| Mic          | `microphone`                 | Auto / High / Medium (this one is the movie property) |

Verified by measuring the live-view image: changing the stills `whitebalance`
or `d01e` leaves the frame's colour untouched, while `d23a`/`d21a` swing the
red/blue ratio from 0.5 (2500 K) to 3.6 (10000 K).

The header shows model, battery, and the mode-dial position (`M`, `A`, …),
which can only be changed on the camera itself.

**Presets** — the bar under the header saves the current values of every
control above as a named preset (⌘1–⌘9 apply the first nine). Applying
writes only the values that differ, in one gphoto2 session (~1 s); anything
the camera rejects (a read-only property in the current mode, an aperture the
mounted lens doesn't have) is listed in the warning banner and the rest still
applies. Presets live in `~/Library/Application Support/LensControl/presets.json`.

**Window mode** — the ⧉ button in the popover footer (⌘O) opens the same
panel as a floating window with a "Keep on top" checkbox, for parking it next
to a call. Both views share state and refresh together.

## Requirements

- macOS 14+
- `brew install libgphoto2` (tested with 2.5.34; `brew install gphoto2` pulls it
  in too and gives you the CLI for poking at properties)
- Camera in **video** mode, USB set to PTP/MTP (the default), connected directly
  or through a hub. The Cam Link only carries HDMI; all control goes over USB.

## Build & install

```sh
./build.sh                                  # → build/LensControl.app
cp -R build/LensControl.app /Applications/
open /Applications/LensControl.app
```

`swift test` runs the parser unit tests and — if a camera is connected — an
integration test that nudges movie ISO one step and puts it back.

## How it works

`Sources/LensControl/GPhoto2.swift` is an actor around the libgphoto2 C API
(`Sources/CGPhoto2` is the module map for the Homebrew headers). It opens one
PTP session on first use and keeps it while the popover or window is on
screen — libgphoto2 isn't thread-safe, so the actor runs on its own serial
queue and every camera call happens there. When nothing is on screen the
session is closed so the `gphoto2` CLI (or Lightroom) can have the camera.
Writes are optimistic and followed by a re-read so the UI converges on what
the camera accepted; the panel polls every 2 s while open.

Measured on the Z5 II (see `docs/z5ii-gphoto2-config-dump.txt` for every
property gphoto2 exposes on this body, 399 in total):

```
in-process libgphoto2:  connect 90–115 ms · read a key 2 ms · write 2 ms · 14 keys 30 ms
                        live view 640×360 JPEG, ~40 KB, 29 fps
gphoto2 CLI (for comparison, one process per call):
                        --get-config 0.14 s · --set-config 0.40 s
```

The first version shelled out to the CLI; it was replaced because each process
gets a stale first live-view frame and two processes can't share the USB
session, which rules out a preview alongside the controls.

## Adding a control

1. Find the key in `docs/z5ii-gphoto2-config-dump.txt` (or `gphoto2 --list-all-config`).
2. Add it to `CameraModel.keys`.
3. Add a `choiceRow` / `toggleRow` in `ContentView.controls`.

RADIO entries work out of the box; RANGE entries need a control like
`KelvinControl`.

## Live preview

The eye button in the header toggles the camera's USB live view: 640×360 JPEG
frames pulled through the same session at up to 20 fps (the camera renders
~29; libgphoto2 hands back the previous frame when asked faster). It is a
preview for judging exposure and colour, not a substitute for the Cam Link's
HDMI signal. Live view is switched off again when the preview is hidden, the
panel closes, or the app quits.

## Design

`docs/design-brief.md` is a brief for Claude Design covering both
presentations, all states, and the presets UI.

## Caveats

- Lightroom, Photos and Image Capture browse cameras through macOS's
  `ptpcamerad`, which claims the USB interface ("Could not claim the USB
  device"). On a claim failure the app SIGKILLs `mscamerad-xpc` and
  `ptpcamerad` (they run as you and ignore SIGTERM; `launchctl bootout` is
  blocked by SIP) and retries once; if the other app is still open it will
  simply grab the camera again, so quit it.
- `swift test` includes live-camera tests; they skip when the camera is
  missing or busy, so close the app's panel first.
- Properties that the current mode dial position makes read-only are shown
  disabled (e.g. shutter/aperture in `A`/`S`/`P`).
- gphoto2 identifies the Z5 II as a generic "USB PTP Class Camera"; the Nikon
  driver still works fully because it is selected by PTP vendor extension.
