# Contributing to StayMic

Thanks for considering a contribution — bug reports, fixes, and small
focused features are all welcome.

## Getting set up

1. Install [Xcode](https://developer.apple.com/xcode/) 16 or later on macOS 14+.
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
3. Clone the repo and generate the project:

   ```bash
   git clone https://github.com/2nm-studio/staymic.git
   cd staymic
   xcodegen generate
   open StayMic.xcodeproj
   ```

## Project structure

The Xcode project (`StayMic.xcodeproj`) is generated from
[`project.yml`](project.yml) and checked into the repository. **Do not
hand-edit `StayMic.xcodeproj`** — change `project.yml` or add/remove
files under `StayMic/`, then run `xcodegen generate` again and commit
the regenerated project alongside your change. CI verifies the two are
in sync and fails the build otherwise.

```text
StayMic/
├── App/          # App and Scene entry point
├── Audio/        # CoreAudio wrapper, device model, property listeners
├── Controllers/  # Volume lock and default-microphone lock logic
├── UI/           # SwiftUI menu bar and settings views
├── Services/     # Preferences persistence, launch-at-login
└── Resources/    # Info.plist, entitlements, asset catalog
```

## Guiding principle: no polling

StayMic's entire value proposition is that it reacts to CoreAudio
events instead of checking state on a timer. Any change that adds a
`Timer`, `DispatchSourceTimer`, or a loop with `sleep`/`asyncAfter` to
watch for volume, device-list, or default-device changes will be
rejected — express the behavior as a CoreAudio property listener
instead (see `CoreAudioPropertyListener` and `AudioDeviceMonitor`).

## Making changes

- Keep pull requests focused on one change.
- Match the existing code style (no header comments, doc comments only
  where the *why* isn't obvious from the code).
- If you touch CoreAudio-facing code, please describe how you tested
  it (e.g. "toggled input volume in System Settings while StayMic was
  running and confirmed the menu bar updated without polling").
- Run a Debug build locally before opening a PR: CI will do the same,
  but catching build errors early saves a round trip.

## Reporting bugs

Please include:

- macOS version and Mac model (Apple Silicon / Intel)
- The microphone(s) involved (built-in, USB, Bluetooth, etc.)
- Steps to reproduce, and what you expected to happen instead

## Security issues

Please don't open a public issue for a security concern — see
[SECURITY.md](SECURITY.md).
