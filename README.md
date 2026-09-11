# Swiss Railway Clock

Hans Hilfiker's 1944 Bahnhofsuhr as an Omarchy bar widget — set to a place
you are not in.

Out of the box it shows **your own time** — whatever this machine's timezone
is — so it is a station clock first and a world clock only if you ask. Point
it somewhere else and it stays there: an office in another country, a market
open, someone you call.

Because `timezone` stores `local` rather than the resolved zone name, a clock
left on local keeps following the system timezone if that later changes (a
laptop that travels, a `timedatectl set-timezone`).

![the widget in the bar](preview.png)

## What it draws

- The SBB dial: white face, black bezel, twelve bar markers with sixty minute
  ticks once the face is big enough to carry them.
- Blunt black hands. The minute hand does not creep — it is held and then
  snaps, the way a slave clock waits for the master clock's minute impulse.
- The red paddle second hand, in **stop-to-go**: it sweeps a full turn in
  58.5 seconds, then waits at 12 for the next minute. That pause is the whole
  character of the design, so it is on by default.

At bar size the face drops the minute ticks and thickens the hands, the same
trade the small platform clocks make against the big concourse ones.

## Interactions

| Gesture | Effect |
|---|---|
| left click | panel: the big face, the date, and the location list |
| right click | next location in the list |
| middle click | show/hide the digital time beside the face |
| scroll | previous / next location |

In the panel, `↑`/`↓` (or `k`/`j`) move and `Enter` picks a location;
`Esc` closes. Picking a location writes it to `shell.json`, so it survives
restarts. The first row is always where you actually are, marked `(local)`,
so going back to your own time is one click rather than a timezone you have
to remember the name of.

## Settings

Set these in Setup > Plugins, or inline in the widget's `shell.json` entry:

```json
{ "id": "ronnie.swissclock", "timezone": "Asia/Tokyo", "label": "Tokyo", "labelFormat": "HH:mm" }
```

| Key | Default | What it does |
|---|---|---|
| `timezone` | `local` | `local` follows this machine's timezone; otherwise an IANA zone |
| `label` | derived | Display name; defaults to the zone's city (`Zürich`, `São Paulo`) |
| `showLabel` | `true` | Digital time beside the face |
| `labelFormat` | `HH:mm` | Qt format for that text, e.g. `'Zrh' HH:mm` |
| `showSeconds` | `true` | The red hand |
| `stopToGo` | `true` | Off gives a plain 60s sweep |
| `dial` | `classic` | `classic` is the white SBB dial; `theme` paints it in your bar's colors |
| `zones` | built-in list | `Europe/Zurich=Zürich, Asia/Tokyo` — the list the panel shows and right-click cycles. The local row is always added on top |

## IPC

```bash
omarchy-shell ronnie.swissclock toggle
omarchy-shell ronnie.swissclock setZone America/New_York
omarchy-shell ronnie.swissclock useLocal     # back to the system timezone
omarchy-shell ronnie.swissclock next        # also: previous
omarchy-shell ronnie.swissclock zone        # prints zone + its current time
```

## How the timezone works

QML has no timezone database, so offsets come from `date` itself: one short
`bash` call per minute resolves every zone the widget and its panel are
showing, and the clock is drawn from `now + offset`. Asking every minute is
what keeps a DST changeover from lingering — a zone that springs forward is
wrong for at most a minute. A zone name that `/usr/share/zoneinfo` does not
know stays visibly unresolved (`—`) instead of quietly rendering as UTC.

## Hacking on it

Saving a file here reloads the plugin, but the panel and the shared JS are
cached by the running shell — if an edit does not show up, run
`omarchy restart shell`.

```
manifest.json   plugin + settings schema
BarWidget.qml   the bar face, its gestures, and the IPC surface
Panel.qml       the popup: big face and location list
ClockFace.qml   the clock itself, reused at both sizes
Offsets.qml     zone name -> UTC offset, via `date`
Zones.js        zone list parsing, offset math, the stop-to-go angle
```
