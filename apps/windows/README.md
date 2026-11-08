# LensControl for Windows

Planned. Nothing here yet.

Plan of record is in [`docs/architecture.md`](../../docs/architecture.md).
The open question is camera access: libgphoto2 on Windows needs a driver
swap, so the first spike is a Windows Portable Devices (WPD) MTP pass-through
prototype that reads and writes one Nikon movie property with the stock
driver. UI and tray integration come after that works. Presets live in
`%APPDATA%\LensControl\presets.json` in the format described by
[`shared/presets.schema.json`](../../shared/presets.schema.json).
