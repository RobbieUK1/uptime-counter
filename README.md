# Uptime Counter

A bare uptime label for the Omarchy bar. That is the whole idea: one number on
the bar, a menu on right-click, nothing else.

## What it does

The bar shows how long the machine has been up. Right-click the label and a
menu opens where you pick:

- **Format** — one of eight, each row previewing the live value in that format
- **Suffix** — `UT:`, `Uptime:` or `Icon only`
- **Clock icon** — show or hide

Your choices are saved to
`~/.config/omarchy/bar/uptime-counter-settings.json` and restored on the next
shell start.

Left-click is left alone on purpose. The bar keeps it, so the label never eats
a click or a drag that was meant for something else. Hovering still shows a
tooltip with the full breakdown in every unit at once.

## Formats

| # | Format                      | Example             |
|---|-----------------------------|---------------------|
| 0 | days / hours / minutes      | `12d 3h 45m`        |
| 1 | hours / minutes             | `291h 27m`          |
| 2 | weeks / days / hours / mins | `1w 5d 3h 45m`      |
| 3 | the two largest units       | `1w 5d`             |
| 4 | total hours                 | `6,955h`            |
| 5 | total minutes               | `417,271m`          |
| 6 | total seconds               | `25,036,263s`       |
| 7 | total milliseconds          | `25,036,263,000ms`  |

Rows 0–3 drop leading zero units, so an hour-old machine reads `3h 45m`
rather than `0d 3h 45m`. Seconds are the floor: an uptime under a minute still
reads as something.

## Why it is cheap

`/proc/uptime` is read **once a minute** and interpolated from `Date.now()`
in between, so a display that ticks every 50ms costs a timer, not a process per
frame. Rebasing every 60s also means the displayed value cannot drift away
from the kernel's, the way a pure `+1s` counter would.

Beyond that:

- The bar's text is only rewritten when the formatted string actually changes,
  so `12d 3h 45m` re-lays out once a minute rather than sixty times.
- The 50ms timer only runs for the millisecond format. Every other format
  cannot show a change between whole seconds, so the original 20Hz tick for the
  seconds format was recomputing an identical string nineteen times out of
  twenty.
- The menu's eight preview strings are built once a second, and only while the
  menu is actually open.
- Settings writes are debounced, so running through the menu lands as one
  atomic write rather than one per click, and an unchanged file is not
  rewritten at all — re-picking the row you already have is a no-op.
- The one-second timer skips its own label pass while the millisecond format
  is active, since the 50ms timer already owns the label by then.

## Install

Copy the directory to `~/.config/omarchy/plugins/robbie.uptime-counter/`, then
add the widget to your bar:

```json
"right": [
  { "id": "robbie.uptime-counter" }
]
```

`shell.json` hot-reloads on save. To force a reload of plugin code:

```sh
omarchy-shell shell rescanPlugins
```

or restart the shell with `omarchy restart shell`.

## Relation to `robbie.uptime`

This is a separate plugin, not a mode of
[`robbie.uptime`](https://github.com/RobbieUK1/omarchy-uptime) — that one opens
a panel of uptime, keyboard and screen-time graphs. Nothing here reads the
keyboard, touches the webcam, spawns a daemon or writes an activity log. The
only file it reads is `/proc/uptime`, and the only file it writes is its own
settings file.

## License

MIT
