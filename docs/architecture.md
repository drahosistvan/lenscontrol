# Cross-platform architecture

LensControl exists on macOS today. This note fixes what the Windows and Linux
versions share with it, what stays platform-specific, and where each platform
gets at the camera. It is a plan, not a description of shipped code; the
checklist at the end is what has to happen before the first non-macOS app.

## What is shared

Everything that is *about the camera* rather than *about the OS*:

1. **Property map.** Which PTP properties the panel edits, their display
   names, choice lists and ranges, and which ones the mode dial makes
   read-only. Today this lives in `apps/macos/Sources/LensControl/CameraModel.swift`
   (`keys`, `presetKeys`, `movieWhiteBalanceNames`, the read-only rules). It
   moves to `shared/` as data when the second platform starts, so no platform
   re-derives it from the dump.
2. **Preset file.** `presets.json` is already platform-neutral: an array of
   `{id, name, values}` where `values` maps a gphoto2 key to the value as the
   panel shows it. The schema is `shared/presets.schema.json`. A preset saved
   on one platform must apply on another.
3. **Apply semantics.** Write only the values that differ, in `presetKeys`
   order (mode-like settings first so Kelvin and Max ISO land on a camera
   ready for them), keep going when the camera rejects one, report the
   rejected keys. Optimistic write followed by a re-read.
4. **UX spec and brand.** `docs/design-brief.md`, the icon and the name. Each
   platform renders it with native controls; layout, control order, states
   and copy stay the same.

## What is platform-specific

- Camera access (below).
- Shell integration: menu bar on macOS, system tray / StatusNotifier on Linux,
  notification-area icon on Windows; the floating always-on-top window.
- Packaging and updates.

## Camera access per platform

| | Transport | Status | Caveat |
|---|---|---|---|
| macOS | libgphoto2 in-process (Homebrew) | done | `ptpcamerad` claims the camera when Photos / Image Capture / Lightroom run; the app kills it and retries once |
| Linux | libgphoto2, its home platform | planned | `gvfs-gphoto2` auto-mounts PTP cameras and holds the interface, same symptom as `ptpcamerad`; needs a udev rule or telling gvfs to ignore the device |
| Windows | open question, see below | planned | libgphoto2 on Windows needs the WinUSB/libusb driver swapped in with Zadig, which replaces the stock PTP/MTP driver; not acceptable for end users |

### Windows options

1. **WPD MTP pass-through.** Windows Portable Devices exposes raw PTP/MTP
   operations through the MTP extension commands
   (`WPD_COMMAND_MTP_EXT_EXECUTE_COMMAND_WITHOUT_DATA_PHASE`, `…_WITH_DATA_TO_READ`,
   `…_WITH_DATA_TO_WRITE`). That is enough for `GetDevicePropValue` /
   `SetDevicePropValue` on the Nikon vendor codes the panel uses, with the
   stock driver and no admin step. Live view (`capture_preview`) needs the
   Nikon-specific start-live-view and get-live-view-image operations through
   the same path. This is the first thing to prototype.
2. **Nikon SDK.** Covers everything, but is closed, needs developer
   registration, and ties the Windows app to one brand.
3. **libgphoto2 + driver swap.** Works for a developer, not for a user.

Recommendation: prototype option 1 against the Z5 II before writing any UI.
If it cannot drive live view, ship the Windows app without live preview first.

## Code sharing strategy

Two ways to share the camera knowledge:

- **A. Share data, not code.** Property map and preset schema as JSON in
  `shared/`; each platform in its native stack (Swift here, Rust or C with GTK4
  / libadwaita on Linux, C# / WinUI 3 on Windows) with a thin PTP layer of its
  own. Cheapest to start, every platform stays idiomatic, the risk is three
  implementations of the apply logic drifting.
- **B. Shared core library.** One PTP core (Rust is the natural choice: libusb
  on Linux, a WPD backend on Windows, could even replace libgphoto2 on macOS
  later) exposing the property model and apply logic over a C ABI; native
  UIs on top. More upfront work, one place for camera quirks.

Start with A. Move to B only if the Windows WPD work produces a PTP stack
anyway, at which point the Linux app can use it too instead of libgphoto2.

## Repository layout

```
apps/macos/      Swift package (current app)
apps/linux/      future
apps/windows/    future
shared/          presets.schema.json, property map once extracted
docs/            this file, design brief, property dump
site/            Hugo landing page
```

Each app directory is self-contained: its own build, its own README, its own
tests. Nothing in `apps/*` imports from another app; shared material goes
through `shared/`.

## Before the first non-macOS app

- [ ] Extract the property map from `CameraModel.swift` into
      `shared/properties.json` and make the macOS app read it (or generate the
      Swift from it) so there is one source.
- [ ] Add a preset round-trip test that validates `presets.json` against
      `shared/presets.schema.json`.
- [ ] Windows: prototype WPD pass-through `GetDevicePropValue` on `movieiso`
      (0xD0xx Nikon code, see the dump) with the stock driver.
- [ ] Linux: confirm libgphoto2 + a udev rule gives a non-root user the camera
      with gvfs running, measure read/write latency like the macOS README does.
- [ ] Decide the Linux toolkit after a tray-icon spike (StatusNotifier works
      out of the box on KDE; GNOME needs the AppIndicator extension).
