# shared

Platform-neutral contracts. Nothing here is executable; every app under
`apps/` reads or validates against these.

- `presets.schema.json`: the preset file every platform reads and writes.
  Location per platform:
  - macOS: `~/Library/Application Support/LensControl/presets.json`
  - Linux: `$XDG_CONFIG_HOME/lenscontrol/presets.json` (planned)
  - Windows: `%APPDATA%\LensControl\presets.json` (planned)
- `properties.json` (not yet extracted): the camera property map, today in
  `apps/macos/Sources/LensControl/CameraModel.swift`. See
  `docs/architecture.md` for when it moves here.

Values in a preset are stored as the panel shows them, which is the string
form gphoto2 uses for that key: a RADIO choice (`"1/125"`, `"f/2"`,
`"Single-servo AF"`), a RANGE number as text (`"4000"`), or a raw PTP code for
the keys gphoto2 does not name (`"d23a": "32786"`).
