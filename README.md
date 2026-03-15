# LogiRemap

Small macOS menu bar app that remaps an `MX Master 3` / `MX Master 3 Mac`:

- Thumb wheel left/right -> system volume down/up
- Back side button -> Wispr Flow push-to-talk

## Run

```bash
swift build
.build/debug/LogiRemap
```

Or:

```bash
swift run
```

To build a normal macOS app bundle that is easier to grant in Accessibility:

```bash
./scripts/build_app_bundle.sh
open dist/LogiRemap.app
```

## Requirements

- macOS 13+
- Accessibility permission for `LogiRemap`
- Wispr Flow installed if you want the push-to-talk remap

## Notes

- Remapping only activates when a matching MX Master 3 device is connected.
- The app checks `~/Library/Application Support/Wispr Flow/config.json` and expects shortcut `4099` to be bound to `ptt`.
- If Wispr Flow is not running, the Back button falls through to normal behavior.
