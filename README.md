# Timerette

The Apple Clock app can run a timer, but starting one is a whole production -- launch it, find the tab, spin a picker, hit start. Timerette is a global hotkey and a text field.

**Ctrl-Opt-Cmd-C**, type `2.5`, **Return** -- a 2m 30s timer is counting down in your menu bar and the UI is already gone.

## Features

- **Type a duration however you think about it** -- `2.5` (a bare number is minutes), `90s`, `1h30m`, `2h30`, `3d22h`. Decimals work.
- **Clock alarms** -- `3:30pm`, `3p`, `15:00`. Resolves to the next occurrence: today if still ahead, else tomorrow. DST handled.
- **Multi-day timers** -- `3d22h` for that auction ending Thursday. No mental math, no calendar event.
- **Survives quit and reboot** -- remaining time is anchored to the fire date, not a ticking counter. Anything that expired while the app was off is dropped silently, no retroactive alarm.
- **Menu-bar countdown** -- the soonest timer counts down next to the icon in monospaced digits (`2m 30s`, `4d 3h 3m 1s`); an orange badge shows when 2+ run.
- **Presets** -- Tea 3m, Coffee 4m, Pomodoro 25m, Break 10m out of the box; edit to taste. One click from the menu, or Return on an empty panel.
- **Inline labels** -- `2.5 tea` starts a 2m 30s timer named "tea".
- **Pause / +1m / Cancel** per running timer, right in the menu.
- **Never silent and invisible** -- on fire: a 10-second chime plus a notification with a Stop button. Audio muted or notifications denied? An orange always-on-top chip appears instead.
- **Configurable hotkey** -- defaults to Ctrl-Opt-Cmd-C. Change it from the menu bar.
- **Launch at Login** -- one-click toggle.
- **Menu bar only** -- no Dock icon, no window, just a countdown where you can see it.

## Requirements

- macOS 13+

## Install

### Build from source

```
git clone https://github.com/brewmium/Timerette.git
cd Timerette
make install
```

This compiles and copies `Timerette.app` to `/Applications/`.

### Run without installing

```
make run
```

## Usage

- **Ctrl-Opt-Cmd-C** (or your configured hotkey) to open the panel
- Type a duration (`2.5`, `90s`, `1h30m`) or a clock time (`3:30pm`, `15:00`) -- the preview updates live -- **Return** starts it
- **Return** on an empty field starts the first preset; **arrow keys** pick another; **Esc** dismisses
- Click the menu bar icon to pause, +1m, or cancel running timers, start presets one-click, edit presets, change the hotkey or alert sound
- `swift test` covers the parser, the countdown format, and persistence

## Stack

Pure AppKit. No SwiftUI, no dependencies, no package manager bloat. Carbon API for the global hotkey (same mechanism Alfred and LaunchBar use). Sibling app to [Launchette](https://github.com/brewmium/Launchette).

## License

Free for personal use. See [LICENSE.md](LICENSE.md) for details.
