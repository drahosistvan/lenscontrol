# LensControl for Linux

Planned. Nothing here yet.

Plan of record is in [`docs/architecture.md`](../../docs/architecture.md):
libgphoto2 for camera access (its home platform), a tray / StatusNotifier
entry point, the same panel as the macOS app rendered with a native toolkit,
presets read from `$XDG_CONFIG_HOME/lenscontrol/presets.json` in the format
described by [`shared/presets.schema.json`](../../shared/presets.schema.json).

First spike: confirm a non-root user can claim the Z5 II with gvfs running
(udev rule or a gvfs ignore), then measure read/write latency the way the
macOS README does.
