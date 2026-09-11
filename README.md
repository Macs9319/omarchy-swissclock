# Swiss Railway Clock

Hans Hilfiker's 1944 Bahnhofsuhr as an [Omarchy](https://omarchy.org) bar
widget — a station clock that can be pointed at another place.

![Omarchy Swiss Clock — the wall of city clocks and the location panel](preview.png)

Out of the box it shows **your own time**, whatever this machine's timezone
is. Point it somewhere else and it stays there: an office in another country,
a market open, someone you keep calling.

## What it draws

- The SBB dial — white face, black bezel, twelve bar markers, and sixty
  minute ticks once the face is big enough to carry them.
- Blunt black hands. The minute hand does not creep: it is held and then
  snaps, the way a slave clock waits for the master clock's impulse.
- The red paddle second hand in **stop-to-go** — a full turn in 58.5 seconds,
  then a wait at 12 for the next minute. That pause is the character of the
  design, so it is the default.

At bar size the face drops its minute ticks and thickens its hands, the same
trade the small platform clocks make against the big concourse ones.

Left click opens the panel: the same clock drawn big, the date there, how far
ahead or behind you it runs, and every location you can send it to with the
time in each.

## The wall

Middle-click the widget (or press `w` in the panel) for every location at
once, the way a newsroom hangs them — red bezels, city plates, and the offset
from you under each dial. `Esc`, a click, or middle-click again dismisses it.

Columns are chosen by trying every split and keeping the one that makes the
faces biggest, so a wall of five and a wall of thirteen are both laid out to
fill the screen. Every dial reads the same instant off one timer. Behind them,
twenty-four faint bands — one per hour of longitude, which is all the world
map behind a clock wall was ever really saying.

Bind it to a key, in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + ALT + C", "World clock wall", "omarchy-shell ronnie.swissclock toggleWall")
```

That modifier is where Omarchy keeps its other display toggles (`SUPER + CTRL
+ ALT + T` shows the time, `+ W` the weather). Check a combo is free before
taking it — `SUPER + W`, the obvious one, is already Close window:

```bash
omarchy menu keybindings --print          # or: hyprctl binds
```

## Install

```bash
omarchy plugin add <this-repo-url> --enable --yes
omarchy bar move ronnie.swissclock --before omarchy.clock
```

Or by hand, without git:

```bash
cp -r . ~/.config/omarchy/plugins/ronnie.swissclock
omarchy-shell shell rescanPlugins
omarchy plugin enable ronnie.swissclock
omarchy bar move ronnie.swissclock --before omarchy.clock
```

Needs Omarchy's Quickshell shell (`omarchy-shell`) — plugin `schemaVersion 1`.
Nothing else: timezones come from `date` and the dial is drawn in QML.

## Using it

| Gesture | Effect |
|---|---|
| left click | the panel — big face, date, and the location list |
| right click | next location |
| middle click | the fullscreen clock wall |
| scroll | previous / next location |

In the panel, `↑`/`↓` (or `k`/`j`) move and `Enter` picks, `w` opens the wall,
`Esc` closes. The
first row is always where you actually are, marked `(local)`, so coming back
to your own time is one click rather than a timezone you have to remember the
name of. A pick is written to `shell.json` and survives restarts.

## Settings

Set these in Setup › Plugins, or inline in the widget's `shell.json` entry:

```json
{ "id": "ronnie.swissclock", "timezone": "Asia/Tokyo", "label": "Tokyo", "labelFormat": "HH:mm" }
```

| Key | Default | What it does |
|---|---|---|
| `timezone` | `local` | `local` follows this machine's timezone; otherwise an IANA zone |
| `label` | derived | Display name; defaults to the zone's city (`Zürich`, `São Paulo`) |
| `faceScale` | `72` | Dial size as a percentage of the bar's height. Below ~55% the dial keeps only the quarter markers |
| `labelFormat` | `HH:mm` | Qt format for that text, e.g. `'Zrh' HH:mm` |
| `showSeconds` | `true` | The red hand |
| `stopToGo` | `true` | Off gives a plain 60s sweep |
| `dial` | `classic` | `classic` is the white SBB dial; `theme` paints it in your bar's colors |
| `wallRim` | `red` | Bezel on the wall's clocks: `red`, `black`, or `theme` |
| `showLabel` | `true` | Digital time beside the face — the setting the middle click used to toggle |
| `zones` | built-in list | `Europe/Zurich=Zürich, Asia/Tokyo` — what the panel lists and right-click cycles. The local row is always added on top |

Because `timezone` stores the sentinel `local` rather than a resolved zone
name, a clock left on local keeps following the system timezone if that later
changes — a laptop that travels, a `timedatectl set-timezone`.

## IPC

```bash
omarchy-shell ronnie.swissclock toggle
omarchy-shell ronnie.swissclock setZone America/New_York
omarchy-shell ronnie.swissclock useLocal     # back to the system timezone
omarchy-shell ronnie.swissclock next         # also: previous
omarchy-shell ronnie.swissclock zone         # prints the zone and its current time
omarchy-shell ronnie.swissclock toggleWall   # the wall; also wall / closeWall
```

## How it works

**Timezones.** QML has no timezone database, so offsets come from `date`
itself: one short `bash` call a minute resolves every zone the widget and its
panel are showing, and the clock is drawn from `now + offset`. Asking every
minute is what keeps a DST changeover from lingering — a zone that springs
forward is wrong for at most a minute. Offsets that are not whole hours work
the same way (Mumbai at `-2:30` above, Chatham at `+12:45`). A zone name that
`/usr/share/zoneinfo` does not know stays visibly unresolved (`—`) instead of
quietly rendering as UTC.

**Drawing.** The dial is a supersampled `Canvas` painted once per size and
colour change; the hands are rotated rectangles. So the sweeping second hand
costs a transform per frame and never a repaint — this thing ticks all day in
a bar. The sweep itself runs at 25fps, which is plenty for a hand this slow
and keeps the widget off the 60fps treadmill.

## Repo layout

```
manifest.json   plugin declaration + settings schema
BarWidget.qml   the bar face, its gestures, and the IPC surface
Panel.qml       the popup: big face and location list
Wall.qml        the fullscreen overlay: every location at once
ClockFace.qml   the clock itself, reused at both sizes
Offsets.qml     zone name -> UTC offset, via `date`
Zones.js        zone list parsing, offset math, the stop-to-go angle
```

Saving a file under `~/.config/omarchy/plugins/` reloads the plugin, but the
running shell caches the panel QML and the shared JS — if an edit does not
show up, `omarchy restart shell`.

## Credits

The design is Hans Hilfiker's, made for the Swiss Federal Railways in 1944 and
still theirs; this is only a drawing of it. Not affiliated with SBB CFF FFS or
Mondaine.

MIT — see [LICENSE](LICENSE).
