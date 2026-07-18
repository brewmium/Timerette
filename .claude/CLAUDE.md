# Timerette

macOS menu-bar quick-timer. Global hotkey (default Ctrl-Opt-Cmd-T), type a
duration (`2.5`, `90s`, `3d22h`) or a clock time (`3:30pm`, `15:00`), Return --
the countdown lives in the menu bar. Sibling app to Launchette: same stack,
same patterns.

## Posture: Active Development

## Stack
- Pure AppKit (no SwiftUI), zero third-party dependencies
- Swift Package Manager (executable target "timerette")
- Carbon API for the global hotkey
- UserNotifications + NSSound + CoreAudio for the fire alert path

## Build
- `make build` -- compile and create .app bundle
- `make run` -- build and launch
- `make test` -- unit tests (InputParser, TimeFormat, persistence)
- `make install` -- copy to /Applications

## Requirements
- macOS 13+

## Spec
docs/SPEC.md is the source of truth -- feature spec, architecture, reuse map
from Launchette, phased implementation plan.
