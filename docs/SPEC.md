# Timerette -- Spec & Implementation Plan

A menu-bar quick-timer for macOS. Sibling to Launchette: same stack, same
patterns, same "one hotkey, do the thing, get out of the way" philosophy.

The whole point: **hotkey, `2.5`, Return, done.** A 2m30s timer is running and
the UI is already gone. No app switch, no mouse, no ceremony.

---

## 1. What it is

The Apple Clock app can run a short timer, but starting one is clumsy -- launch
it, find the tab, spin a picker, hit start. And it can't do "3 days 22 hours"
(the way an auction shows time left) without you doing the mental math and faking
a calendar alarm. Timerette replaces all of that with a global hotkey and a text
field. Type a duration however you think about it -- `2.5`, `90s`, `1h30m`,
`3d22h` -- or a clock time -- `3:30pm`, `15:00` -- press Return, and it runs in
the background with its countdown in the menu bar.

It is a menu-bar-only app (no Dock icon, no window) exactly like Launchette. It
holds a small user-managed list of one-click preset timers, runs several at
once, and its running timers survive a quit or a reboot.

### Non-goals

- Not a stopwatch, not a world clock. Only countdown timers and same-day/next-day
  clock alarms.
- **No weekday or recurring alarms.** "Every Tuesday" is calendar territory --
  explicitly out of scope. (For "3 days out," you type `3d` -- no calendar
  needed.)
- No accounts, no sync, no AI. Like Launchette: it does one thing fast.
- No preferences window sprawl -- settings live in the menu bar.

---

## 2. The money path (must be airtight)

```
  press Ctrl-Opt-Cmd-T      panel appears, text field focused and empty
  type  2.5                 live row reads "Start a 2m 30s timer" (auto-selected)
  press Return              panel vanishes; menu bar shows a 2m 30s countdown
```

`2.5` -> a 2m 30s timer is the canonical path and must never regress. Three
keypaths through the same panel, all ending with the panel gone and a timer
running:

1. **Type + Return** -- the primary path above.
2. **Arrow + Return** -- open panel, arrow down onto a preset row, Return.
3. **Click** -- open panel, click a preset row (or the Start button).

And one path that never opens the panel:

4. **Menu click** -- click the menu-bar icon, click a preset under "Presets".

Everything in this spec exists to keep those paths crisp.

---

## 3. Feature spec

### 3.1 Menu-bar status item

- Uses `NSStatusItem` with `variableLength` so the countdown text fits.
- **Idle (no running timers):** just the Timerette icon (a stopwatch glyph),
  template-rendered so it adapts to light/dark menu bars.
- **Running:** icon + the remaining time of the **soonest-to-fire** timer, in
  monospaced digits so it does not jitter. Format below.
- **Multiple timers:** a small orange count **badge bubble** on the icon corner,
  shown only when count >= 2. The text still tracks the soonest one.
- **Ringing:** a timer that hit zero shows `0s` until stopped.
- Ticks once per second on a single repeating timer in `.common` run-loop mode
  (keeps updating while a menu is open or a window is dragged).

**Countdown format** (one `compact(remaining)` formatter, used menu-bar and
everywhere a duration is shown): single-letter `d`/`h`/`m`/`s` units,
space-separated, **no colons**. Consistent at every scale -- show from the
largest non-zero unit down to the smallest non-zero unit, keeping any interior
zeros, trimming zero units at the ends.

| Remaining               | Shows          |
|-------------------------|----------------|
| 36 sec                  | `36s`          |
| 5 min 14 sec            | `5m 14s`       |
| 2 hr 3 min 7 sec        | `2h 3m 7s`     |
| 4 day 3 hr 3 min 1 sec  | `4d 3h 3m 1s`  |
| round 3-min preset      | `3m`           |
| 2 hr 0 min 7 sec        | `2h 0m 7s`     |

```
  idle           [(S)]
  one timer      [(S) 2m 30s]
  three timers   [(S) 2m 30s (3)]       <- (3) is a drawn orange badge, not text
  a multi-day    [(S) 4d 3h 3m 1s]
```

**Note / caveat:** a colored (non-template) badge will not auto-invert when the
menu is highlighted. Acceptable for v1; a text fallback (` 2m 30s x3`) is trivial
if the badge looks wrong. Decide after seeing it.

### 3.2 Global hotkey

- Carbon `RegisterEventHotKey`, identical mechanism to Launchette (the same one
  Alfred/LaunchBar use). Lifted almost verbatim from Launchette's `AppDelegate`.
- **Default: Ctrl-Opt-Cmd-T** (`keyCode` 0x11 for "T", modifiers
  `controlKey | optionKey | cmdKey`).
- Re-bindable from the menu via the same `HotKeyRecorderPanel` Launchette uses.
  Persisted in `UserDefaults` (`hotKeyKeyCode`, `hotKeyModifiers`).
- Pressing the hotkey **toggles** the entry panel -- same `togglePanel()` shape
  as Launchette.

### 3.3 Timer entry panel

Built on Launchette's `SearchPanel` skeleton: a `.nonactivatingPanel`, floating
level, vibrancy (`NSVisualEffectView`, `.hudWindow`), rounded corners, a 1.5pt
stroke in Timerette's accent (warm orange, ~`#FF8A00`). Opens centered
horizontally, upper third of the active screen (reuse Launchette's `ScreenMode`).

Layout:

```
+----------------------------------------------------------+
|  (S)   2.5|                                              |   text field: big, auto-focused, empty on open
+----------------------------------------------------------+
|  > Start a 2m 30s timer                          Return   |   live preview row (auto-selected while typing)
|  ------------------------------------------------------  |
|  1m timer                                                 |   preset rows (shown when field is empty)
|  3m timer                                                 |
|  5m timer                                                 |
|  Tea                                                3m    |   (a labeled one)
+----------------------------------------------------------+
```

Behavior:

- On open: field cleared and focused; preset rows listed below; **first preset
  row selected** (so Return-with-empty-field starts that preset -- mirrors
  Launchette auto-selecting row 0).
- As the user types, the parser (3.4) runs live, like Launchette's inline math.
  The list collapses to a single **preview row**, auto-selected:
  - duration -> `Start a 2m 30s timer`, `Start a 3d 22h timer`
  - clock time -> `Alarm at 3:30 PM  (in 1h 47m 3s)`
  - unparseable -> a muted hint; Return does nothing (subtle field shake is a
    nice-to-have).
- **Up/Down** move selection; **Return** starts the selected row; **Esc**
  dismisses without starting; clicking a row starts it; **click-away/blur**
  dismisses (Launchette's `windowDidResignKey`).
- A **Start button** at the field's right edge equals Return. (Pause is a
  running-timer action; it lives in the menu, 3.6.)
- After any start, the panel dismisses immediately and focus returns to the
  previously-frontmost app (Launchette's `previousApp` restore).

**Optional (nice-to-have): inline label.** Leftover words become the timer's
label -- `2.5 tea` -> a 2m 30s timer labeled "tea". MVP can ship without it; the
grammar reserves room.

### 3.4 Input parser (`InputParser`)

Plays `MathEvaluator`'s role but resolves to a fire time, not raw seconds -- so
durations and clock alarms flow through one code path:

```
	enum TimerInput {
		case duration(TimeInterval)   // relative span; fireDate = now + span
		case clockTime(Date)          // absolute, resolved to next occurrence
	}
	func parse(_ s: String) -> TimerInput?
```

**The one rule:** a colon or an am/pm marker means **clock time**; everything
else is a **duration**, and a bare number is **minutes**.

Case-insensitive, trimmed, first match wins:

1. Empty -> `nil`.
2. **Clock time** -- contains `:` OR ends in `am`/`pm`/`a`/`p`:
   - `HH:MM` 24-hour, or `H`/`H:MM` with a meridiem. `a`=am, `p`=pm.
   - `15:00`->3:00 PM, `9:30`->9:30 AM, `3:30pm`/`3:30p`->3:30 PM,
     `3pm`/`3p`->3:00 PM, `9am`/`9a`->9:00 AM, `12a`->midnight, `12p`->noon.
   - Resolved to the **next future occurrence** (today if still ahead, else
     tomorrow) via `Calendar.nextDate(after:matching:matchingPolicy:.nextTime)`,
     which also handles DST.
   - A bare `3` is *not* a clock time (no colon/meridiem) -- it's 3 minutes. Use
     `3p`/`3a`/`3:00` for an o'clock.
3. **Duration** -- otherwise. Tokenize into number(+optional unit) runs; units
   `d`/`h`/`m`/`s`, decimals allowed:
   - A lone unit-less number -> **minutes**: `2.5`->150s, `15`->900s.
   - A number with a unit -> that unit: `2d`, `3h`, `45m`, `90s`, `1.5h`.
   - A trailing unit-less number **after** a unit -> the next-smaller unit
     (d->h->m->s): `2h30`->2h30m, `15m45`->15m45s, `3d22`->3d22h.
   - Sum all components. `<= 0` -> `nil`; clamp an absurd max (99d); round to
     whole seconds. Reject two bare numbers (`15 45`) or a stray unit-less number
     mid-sequence.

| Input             | Result            |
|-------------------|-------------------|
| `2.5`             | 2m 30s timer      |
| `15`              | 15m timer         |
| `15m45`           | 15m 45s timer     |
| `2h30`            | 2h 30m timer      |
| `90s`             | 1m 30s timer      |
| `2d`              | 2-day timer       |
| `3d22h`           | 3d 22h timer      |
| `1.5h`            | 1h 30m timer      |
| `15:00`           | alarm 3:00 PM     |
| `9:30`            | alarm 9:30 AM     |
| `3:30pm` / `3:30p`| alarm 3:30 PM     |
| `3pm` / `3p`      | alarm 3:00 PM     |
| `9am` / `9a`      | alarm 9:00 AM     |
| `` / `abc` / `0`  | nil (no start)    |

### 3.5 Timers (model + engine)

**`CountdownTimer`** (model): `id: UUID`, `label: String?`,
`kind: durationTimer | clockAlarm`, `total: TimeInterval`, `fireDate: Date`,
`state: running | paused | ringing`, `remainingWhenPaused: TimeInterval?`. For a
`clockAlarm`, a display target ("3:00 PM") is derived from `fireDate`.

**`TimerStore`** (plays AppIndex's role -- owns state, drives the tick, persists):

- `start(TimerInput, label:)` (duration -> `fireDate = now + span`; clockTime ->
  `fireDate =` the resolved date), `pause`, `resume`, `cancel`, `addTime`
  (+1m), `restart` (back to the full total; duration timers only),
  `stopRinging`.
- `soonest` -> the running timer with the nearest `fireDate`; drives the
  menu-bar text.
- Remaining is always `fireDate - Date()`, **never** a decremented counter -- so
  it is correct across display sleep and drift, and it makes clock alarms and
  multi-day timers just work.
- One 1s tick (`.common` mode) recomputes menu-bar text/badges and live-updates
  any open menu titles.
- **Fire:** at `Date() >= fireDate`, transition **running -> ringing** and start
  the alert (3.7); after the 10s chime (or a Stop) it is removed. If several fire
  in one tick, each rings.

**Persistence (v1 -- required, because days exist).** A 3-day auction timer must
outlive a quit or reboot.

- On every change, `TimerStore` writes active timers to
  `~/Library/Application Support/Timerette/timers.json` (id, label, kind,
  `fireDate`; paused timers store `remainingWhenPaused` + paused state).
- On launch (including after reboot): load, then for each timer **re-arm it if
  `fireDate` is still in the future**; **drop any already expired** -- no
  retroactive chime for something that ended while the app wasn't running. Paused
  timers restore paused.
- **Sleep vs. off, made explicit:** app *running* + machine sleeps past a
  fireDate -> fires on wake (late-but-fired). App *not running* (quit/reboot) +
  fireDate passed -> silently dropped on next launch. (A "missed timers" note on
  launch is a possible later nicety.)

### 3.6 The status menu

Rebuilt on open (`menuNeedsUpdate`), running titles live-updated on the tick
while open. Sections: **running / -- / presets / -- / settings + quit.**

```
  Tea -- 2m 28s                     >     submenu: Pause | +1m | Start Over | Cancel
  Alarm 3:00 PM -- 1h 47m 3s        >     submenu: Pause | +1m | Cancel
  ----------------------------------
  New Timer...                Ctrl-Opt-Cmd-T
  1m
  3m
  "Tea" (3m)                              <- a labeled preset
  1h
  ----------------------------------
  Settings...
  Quit Timerette
```

- **Running section:** one item per active timer. Duration timers read
  `label -- remaining` (unlabeled -> `2m 30s timer -- remaining`); clock alarms
  read `Alarm 3:00 PM -- remaining`. Each has a submenu: Pause/Resume, +1m,
  Start Over (duration timers only -- an alarm is pinned to wall time),
  Cancel. A **ringing** timer reads `... -- Time's up` with a **Stop**. If none
  running: a disabled "No timers running".
- **Presets section:** `New Timer...` (opens the panel; shows the hotkey hint),
  then one row per preset that starts it **immediately without the panel** --
  unlabeled reads just the duration (`5m`), labeled reads `"<label>" (<dur>)`.
- **Settings + quit:** `Settings...` opens the settings window (3.8/3.9)
  and `Quit Timerette`.

### 3.7 Alerts on fire

At zero a timer enters **ringing** for up to **10 seconds**, then clears itself:

- **Chime (10s):** the selected alert sound loops via `NSSound` (`.loops = true`)
  and stops after 10s -- or earlier by any Stop (the chip, the menu's ringing
  row, or the notification). Sound is picked in the settings window.
- **Notification:** a local `UNUserNotificationCenter` notification always fires,
  carrying the label (or duration/target) and a Stop action. Authorization
  requested once on first launch.
- **Muted-audio chip:** if the default output device is **muted or at zero
  volume**, the chime is inaudible, so Timerette pops its own **notification
  chip** -- a small always-on-top orange card near the menu bar with the label +
  "Time's up" and a Stop, auto-dismissing when ringing ends. Mute/volume read
  from CoreAudio (`kAudioDevicePropertyMute`, falling back to virtual main
  volume == 0).
- **Guaranteed-visible rule:** the chip also shows whenever OS notifications are
  unavailable (auth denied). A finished timer is **never** silent *and* never
  invisible -- if you can't hear it, you can see it.

### 3.8 Presets (CRUD)

**`Preset`** (model): `id: UUID`, `label: String?`, `total: TimeInterval`,
`sortOrder: Int`. `Codable`. The label is **optional** -- an unlabeled preset
goes by its duration ("5m timer"), same voice as an unlabeled running timer.
Presets are **durations only** (a one-click clock alarm has no fixed target
without recurrence, which is out of scope).

**`PresetStore`** (AppIndex's persistence role): loads/saves
`~/Library/Application Support/Timerette/presets.json`. Seeds defaults on first
run so the panel is never empty -- unlabeled, in order:

```
  1m   3m   5m   10m   15m   30m   1h
```

**Management UI:** the Presets section of the settings window (`SettingsPanel`,
3.9) -- a plain editable list: click a cell and type; the edit commits when you
leave the field (Return/Tab/click away), no separate save step. Durations
parse via `InputParser` (duration track only; a clock-time entry is rejected
there). Drag rows to reorder; `+` / `-` add and remove.

Presets surface in the panel's row list and the menu's Presets section; both
start a timer with one action.

### 3.9 Settings & persistence summary

One settings window (`SettingsPanel`, reached via the menu's `Settings...`):
the editable preset list on top (3.8), then hotkey (current binding + a
Change... button that opens the recorder), an Alert Sound popup (previews on
pick), and a Launch at Login checkbox.

| What                | Where stored                                    |
|---------------------|-------------------------------------------------|
| Hotkey              | `UserDefaults` (`hotKeyKeyCode/Modifiers`)      |
| Alert sound         | `UserDefaults`                                  |
| Screen mode         | `UserDefaults` (reuse Launchette's `ScreenMode`)|
| Launch at Login     | `SMAppService.mainApp` (system-managed)         |
| Presets             | `App Support/Timerette/presets.json`            |
| Running timers      | `App Support/Timerette/timers.json` (fireDates; restored if still future) |

The 10-second chime duration is fixed in v1 (configurable later).

---

## 4. Architecture

### 4.1 Stack (mirror Launchette exactly)

- Pure AppKit, no SwiftUI, no third-party dependencies.
- Swift Package Manager, `swift-tools-version: 5.10`, `.macOS(.v13)`.
- Carbon for the global hotkey; `ServiceManagement` for launch-at-login;
  `UserNotifications` for alerts; `NSSound` for the chime; CoreAudio to detect a
  muted output device; `Calendar`/`Foundation` for clock-time resolution.
- `LSUIElement` true -> menu-bar-only, no Dock icon.
- Ad-hoc code-signed in the Makefile (`codesign --sign -`).

### 4.2 File layout

```
  timerette/
    Package.swift              target "timerette"; links Carbon (+ UserNotifications)
    Makefile                   build / run / clean / install / uninstall (from Launchette)
    README.md
    LICENSE.md                 Brewmium LLC license (copied)
    .gitignore                 .build/ , Timerette.app/
    .claude/CLAUDE.md          repo posture + build notes
    Resources/Info.plist       com.brewmium.timerette , LSUIElement true
    docs/
      SPEC.md                  <- this file
    Sources/timerette/
      main.swift               accessory-app bootstrap (from Launchette)
      AppDelegate.swift        status item, hotkey, menu building, wiring
      TimerEntryPanel.swift    the floating input panel (from SearchPanel)
      InputParser.swift        text -> TimerInput (duration | clockTime)
      TimeFormat.swift         the compact() countdown format (36s / 5m 14s / 4d 3h 3m 1s)
      TimerStore.swift         active timers, tick, soonest, fire, disk persistence
      CountdownTimer.swift     model (may fold into TimerStore)
      PresetStore.swift        preset CRUD + JSON persistence (from AppIndex)
      ManagePresetsPanel.swift preset management UI (from ManageAppsPanel)
      HotKeyRecorder.swift     recorder panel (extracted from Launchette AppDelegate)
      MenuBarView.swift        compose icon + monospaced time + count badge
      AlertChip.swift          muted/fallback "Time's up" floating card (new)
      AudioState.swift         CoreAudio mute / zero-volume check (new)
```

### 4.3 Reuse map (Launchette -> Timerette)

| Launchette source            | Timerette use                         | Effort   |
|------------------------------|---------------------------------------|----------|
| `main.swift`                 | `main.swift`                          | verbatim |
| Carbon hotkey block in `AppDelegate` | hotkey block in `AppDelegate` | verbatim |
| `HotKeyRecorderPanel`        | `HotKeyRecorder.swift`                | verbatim |
| `SearchPanel` (chrome, vibrancy, show/dismiss, placement, key handling, rows) | `TimerEntryPanel` | adapt |
| `MathEvaluator`              | `InputParser` (same shape; two-track grammar, returns `TimerInput`) | rewrite body |
| `AppIndex` (JSON load/save)  | `PresetStore` + `TimerStore` persistence | adapt |
| `ManageAppsPanel`            | `ManagePresetsPanel`                  | adapt    |
| `Makefile`,`Package.swift`,`Info.plist`,`LICENSE.md`,`.gitignore` | same | rename only |
| menu-building in `AppDelegate` | menu-building (3 sections)          | rewrite  |
| -- (new)                     | `TimerStore`, `CountdownTimer`, `TimeFormat`, `MenuBarView`, `AlertChip`, `AudioState` | new |

About half is lift-and-rename; the genuinely new code is the timer engine +
persistence, the clock-time resolution, the countdown format, the fire/alert path
(10s chime + muted chip), and the menu.

> Future thought (not v1): the Carbon hotkey + recorder + accessory-app chrome is
> now duplicated with Launchette. If a third menu-bar app appears, extract a
> shared Swift package. For two apps, copy beats a shared dependency across two
> independent public repos.

### 4.4 Data flow

```
  hotkey ---> AppDelegate.togglePanel() ---> TimerEntryPanel.show()
                                                 |
                          types/selects, Return  v
                        InputParser.parse(text) -> .duration | .clockTime
                                                 |
                                                 v
                     TimerStore.start(input) -> CountdownTimer(fireDate)
                        |                              |
        writes timers.json (persist)      1s tick (.common)
        restored on next launch if still     |
        in the future                        v
                             TimeFormat.compact(soonest) --> NSStatusItem
                             menu open? live-update running titles
                                                 |
                            Date() >= fireDate   v
                     running -> ringing: 10s NSSound loop
                     + UNNotification ; if muted/denied -> AlertChip
```

---

## 5. Implementation plan (phased)

Each phase is independently runnable with an acceptance check. Ordered so the
money path lights up at Phase 3.

**Phase 0 -- Repo scaffold.** Copy Launchette's `Package.swift`, `Makefile`,
`Info.plist`, `LICENSE.md`, `.gitignore`, `.claude/CLAUDE.md`; rename to
Timerette, bundle id `com.brewmium.timerette`. `main.swift` accessory bootstrap.
Empty status item + Quit.
*Accept:* `make run` shows a menu-bar icon with a working Quit; no Dock icon.

**Phase 1 -- Hotkey + panel shell.** Lift the Carbon hotkey code and
`HotKeyRecorder`. Build `TimerEntryPanel` from `SearchPanel`: vibrancy panel,
auto-focused field, Esc/blur dismiss, correct screen placement. Default bind
Ctrl-Opt-Cmd-C.
*Accept:* hotkey toggles the panel; field focused; Esc and click-away close it;
Change Hotkey... works.

**Phase 2 -- Input parser (two-track).** `InputParser` per 3.4 returning
`TimerInput`, with the 3.4 examples table as a `swift test` checklist (this is
the one piece with real logic -- `2.5`, `15m45`, `3d22h`, `15:00`, `3p` all
covered). `TimeFormat.compact` per the 3.1 format. Wire the live preview row
(duration and clock-time strings); Return logs the resolved fireDate for now.
*Accept:* every table row parses correctly; preview updates live; `2.5` reads
"Start a 2m 30s timer" and `3p` reads "Alarm at 3:00 PM".

**Phase 3 -- Engine + menu-bar countdown (money path lights up).**
`CountdownTimer` + `TimerStore` (start/tick/soonest/fire-stub). `MenuBarView`
renders icon + soonest via `TimeFormat` + orange count badge. Return actually
starts a timer and dismisses.
*Accept:* hotkey -> `2.5` -> Return shows `2m 30s` counting down; a second timer
shows the soonest + a `2` badge; `3d22h` shows `3d 22h ...`.

**Phase 4 -- The menu.** Three-section menu per 3.6; per-timer submenu
(Pause/Resume, +1m, Cancel); live titles while open; New Timer..., Change
Hotkey..., Launch at Login, Quit; clock alarms read "Alarm 3:00 PM -- ...".
*Accept:* menu matches the 3.6 mockup; pause/resume/cancel/+1m work; rows count
down while open.

**Phase 5 -- Presets CRUD.** `Preset` + `PresetStore` with seeded defaults;
presets in the panel and the menu; `ManagePresetsPanel` with Add/Edit/Remove
(duration field via `InputParser`, clock-time rejected).
*Accept:* add/edit/delete survives relaunch; one-click start from panel and menu;
empty-field Return starts the first preset.

**Phase 6 -- Alerts (10s chime + muted chip).** On fire: running -> ringing; loop
the selected `NSSound` for 10s (Stop halts early) + always post a
`UNUserNotificationCenter` notification (auth on launch). Read output mute via
`AudioState`; if muted/zero -- or notifications unavailable -- show `AlertChip`
with a Stop.
*Accept:* fires within ~1s of zero, including after display sleep; chime rings
~10s and Stop cuts it; muting audio shows the orange chip; a labeled notification
appears when allowed.

**Phase 7 -- Persistence (survive quit + reboot).** `TimerStore` writes
`timers.json` on change; on launch, re-arm future timers, drop expired, restore
paused. This is what makes multi-day/auction timers trustworthy.
*Accept:* start a timer, `Quit`, relaunch -> it's still counting from the correct
fireDate; a timer whose fireDate passed while quit does not appear (and does not
chime); a reboot mid-timer restores it.

**Phase 8 -- Polish + README.** Accent orange + stopwatch icon/badge; jitter-free
monospaced menu-bar text; optional inline label parsing; finalize `README.md`
(usage / build / install, mirroring Launchette's).
*Accept:* the money paths in section 2 are crisp; README documents them.

---

## 6. Repo & conventions

- **GitHub:** new public repo `brewmium/Timerette`. Lives locally at
  `personal/timerette/`, its own git repo, alongside Launchette -- the parent
  `projects/.gitignore` already ignores all of `personal/`.
- **License:** Brewmium LLC license, copied from Launchette.
- **Code style:** tab indentation (visual width 4), ASCII in source, matching
  Launchette and the ecosystem convention.
- **`.claude/CLAUDE.md`:** posture Active Development; stack + build notes, same
  shape as Launchette's.
- **README:** Launchette's voice -- terse, feature-list, build-from-source +
  `make install`, requirements (macOS 13+).

---

## 7. Open decisions (for Eric)

Only one left; everything else is settled below.

1. **Count badge vs text** for multiple timers: drawn orange badge bubble
   (default) vs text suffix (`2m 30s x3`). Easy to swap after seeing it live.
2. ~~**Default preset set**~~ -- decided: unlabeled 1m / 3m / 5m / 10m / 15m /
   30m / 1h, in order.

**Settled:** name = Timerette; accent = warm orange (~`#FF8A00`, tunable);
parser = two tracks (bare number = minutes incl. `2.5`; units `d/h/m/s`;
trailing-number shorthand `15m45`/`2h30`; colon or am/pm/a/p = clock time,
next-occurrence); menu-bar countdown in labeled `d/h/m/s`, no colons --
`36s` / `5m 14s` / `2h 3m 7s` / `4d 3h 3m 1s`; alarms show a countdown (not the
target); on-fire = 10-second chime + muted-audio notification chip; running
timers persist across quit/reboot (future ones restored, expired dropped); no
weekday/recurring alarms; menu order running / presets / settings+quit; menu bar
shows the soonest timer; hotkey default Ctrl-Opt-Cmd-C; menu-bar-only, no Dock.

---

## 8. Later (v1.1+)

- Configurable chime duration / optional ring-until-dismissed.
- "Missed timers" note on launch for ones that expired while quit.
- Inline label parsing (`2.5 tea`) and "save current entry as preset".
- Unit aliases (`min`/`sec`/`hr`/`day`).
- Reorder presets by drag; per-preset custom sound.
- **Explicitly out (v2 at earliest):** weekday and recurring alarms
  (`every tuesday`) -- that's calendar territory, not Timerette's lane.
