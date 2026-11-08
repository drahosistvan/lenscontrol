# LensControl

Remote-control an interchangeable-lens camera over USB while it works as a
webcam. The camera's HDMI output goes into a capture card; LensControl talks
to the body over USB (PTP) and lets you change exposure, white balance, focus
and audio from the desktop without touching the camera or leaving the call.

Built and tested against a Nikon Z5 II; the property map is the camera's
movie-mode settings, i.e. what the HDMI feed shows.

| Platform | Status | Where |
|----------|--------|-------|
| macOS 14+ | working, menu-bar app on libgphoto2 | [`apps/macos`](apps/macos) |
| Linux | planned | [`apps/linux`](apps/linux) |
| Windows | planned | [`apps/windows`](apps/windows) |
| Landing page | planned, Hugo one-pager | [`site`](site) |

## Layout

```
apps/macos/     Swift package: the macOS menu-bar / window app, build script, tests
apps/linux/     placeholder, see docs/architecture.md
apps/windows/   placeholder, see docs/architecture.md
shared/         platform-neutral contracts: preset file format, property map notes
docs/           design brief, camera property dump, cross-platform architecture
site/           Hugo landing page (store links only)
```

## Documents

- [`docs/architecture.md`](docs/architecture.md): how the platforms share
  camera knowledge and where each one gets USB access.
- [`docs/design-brief.md`](docs/design-brief.md): the UI brief, both
  presentations, all states, presets.
- [`docs/z5ii-gphoto2-config-dump.txt`](docs/z5ii-gphoto2-config-dump.txt):
  every property gphoto2 exposes on the Z5 II (399).
- [`shared/presets.schema.json`](shared/presets.schema.json): the preset file
  every platform reads and writes.
