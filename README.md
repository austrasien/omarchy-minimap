# Minimap

A round, game-style minimap pinned to a screen corner of the Omarchy shell.

- **Switching maps**: the wheel over the disc turns the middle circle to the
  previous (up) or next (down) map, as a coin; a trackpad flick turns it
  once. Maps with nothing to show (media with no player, notifications with
  none on screen) are skipped, and stand aside while empty.
- **Weather map**: Esri dark/light gray basemap, RainViewer radar (latest
  scan at rest, the last two hours looped while hovered), place names on top,
  you in the middle, and an Open-Meteo nowcast line ("pluie dans 20 min",
  "sec 2 h"). Ctrl+wheel zooms (4–10; radar tiles stop at 7 and are scaled up).
- **Workspace map**: the focused workspace stretched onto the disc, each
  window drawn as its rectangle cut to the circle (one window fills it, two
  side by side make two half discs). The other occupied workspaces are equal
  arcs around it, in order clockwise from the top, each showing its apps'
  icons along the band ("+n" when they do not fit; holding Super shows the
  desk numbers instead). An arc darkens from grey to black the longer its
  desk goes unvisited (from 2 min, black at 1 h; kept in
  `~/.local/state/austraz-minimap/desks.json`). Click switches to it; drag a window from the disc onto an arc to send it
  to that workspace (you stay where you are). Every window shows
  its app icon in the middle of its visible part (desktop entry, StartupWMClass for web apps) and windows
  untouched for a while fade out. Coding agents show the same way on
  their window and on their workspace's arc, no markers: a fast red blink
  when blocked on a permission prompt, a slow theme-accent blink when a turn
  is done (three quick blinks on the current desk, then cleared once you see it), slow theme-accent rings spreading
  from the icon (or the arc's middle) for as long as they work. Click a window to focus it.
  Switching workspace animates: the one you leave shrinks into the arc
  that opens for it on the band (in the theme accent, fading to its own
  colour as the switch ends), while the one you go to grows out of its
  arc, which closes in the theme accent; the other arcs slide into place.
- **Rim details on hover**: the rim explains itself in the middle circle,
  over the map without turning it, gone when the pointer leaves.
  - The day/night dial: the sun's path as a wide arch from eight o'clock
    (sunrise) over the top to four o'clock (sunset), the sun where it is
    now, the golden hours in orange at both ends (sunrise until the sun is
    6° up, 6° until sunset, computed for your location), and large inside:
    the day's length, the golden hour under way or next, sunrise and
    sunset. The golden hours are also drawn warmer on the dial.
  - The battery band: austraz.power's TOP CPU bar bent into a ring (the five
    busiest apps, a share each, same colours, each named along its arc when the
    name fits) and, in the middle, the watts
    now and its CHARGE RATE chart for the last 15 minutes (read from the
    history austraz.power keeps), with the level and time left. A click
    still opens austraz.power.
  - A desk's arc: its number, how many windows, its apps (desktop entry
    names) and when you last went there.
- **System OSDs**: volume, brightness and microphone OSDs show in the
  middle circle instead of the shell's card, when an OSD that asks first is
  installed (austraz.audio does: `osd` answers "ok" only while the disc is
  on screen, so the card comes back whenever it is not). Volume reads on a
  0–200 % ring with 100 % at six o'clock and turns red past it. The face
  pops out of the centre, the ring springs to each value behind a glowing
  head, every step sends a ripple out (louder) or in (softer) and rolls the
  readout like a counter, and crossing 100 % flashes red.
- **Dictation**: while voxtype or a tool writing its state file
  (`$XDG_RUNTIME_DIR/voxtype/state`) records, a ring of bars carries the
  microphone as a wave flowing from noon down both sides, around a
  microphone that swells with the voice and a breathing red rim; while it
  transcribes, a comet circles the shortened bars under a writing pencil.
  Levels come from `$XDG_RUNTIME_DIR/nemotron/levels.ndjson`. A dictation
  HUD can ask `dictation` and stand aside on "ok".
- **Rim**: a 24 h dial (noon at the top, midnight at the bottom). By day the
  arc from the real sunrise to sunset is yellow, with the sun on the current
  time; by night the arc from sunset to sunrise is blue, with the moon drawn
  in its real phase (mean lunation, waxing lit on the right). Twilight shades
  the dial on both sides of the night: civil (down to 6° below the horizon)
  in pink, nautical (12°) in purple, astronomical (18°) in light blue, and the
  sun stays on the dial through civil twilight. The golden hours and each
  twilight band only show from 2 h before them until 2 h after. Outside the
  dial, a band of its own carries the battery, with the wallpaper showing
  through around its stripe: on
  battery a stripe from now to the estimated empty time (level shown next to
  the clock), green at 100 % shading to red at 0 %, blinking under 10 %; charging, an orange stripe to full followed by a green one for
  how long that charge would last; plugged in and full, the green runtime
  from now. Runtimes use the median discharge rate of the last week (UPower
  rate history over D-Bus). Hovering adds the figures to the clock.

Agents and alerts follow Omarchy Spaces' agent model, so the minimap can
replace it. Any reporter that speaks Spaces' agent IPC works: point it at
`austraz.minimap` (or at both plugins) with
`omarchy-shell austraz.minimap agent <session> <state> <pids>`, e.g. from a
Claude Code, Cursor or other coding-agent hook. Same rules as Spaces: an
agent is pinned to its window, a turn that ends while its window or desk is
in view needs no blink and seeing it later clears the blink, and working or
waiting claims whose agent process died are dropped every minute. A
Hyprland "urgent" window turns its desk red like a waiting agent.

Also taken over from Spaces:

- **Alert LEDs**: Caps Lock and the Framework fingerprint ring blink while a
  waiting agent is out of view and stay lit while a finished one is
  (`bin/alert-leds`, from Spaces' `spaces-caps-blink`; same lock and want
  files, so the two plugins never fight over the LEDs).
- **Super+Caps Lock** (`focusAlert`): jumps to the desk being signalled,
  waiting first, smallest number first, the scratchpad last.
- **Held Super** (`showNumbers` / `hideNumbers`): the current workspace's
  number over the disc.
- **Scratchpad**: the first arc, reading "0", while it holds windows; click toggles
  it, and its agents count as seen while it is shown.

The minimap does not sit on the window under it: a ring as wide as
Hyprland's `gaps_out` shows the wallpaper around the disc (lined up with the
real one, from `~/.local/state/omarchy/current/background`), as if the disc
were cut out of that window, and the disc keeps that same distance from the
screen edges. The window's corner on the minimap's side is masked too, and
that window's Hyprland border (active colour when it has focus, inactive
otherwise, same width) is carried around the cut. A video background (OWE)
plays in the ring too, kept on OWE's clock (`owe render-status`) and paused
while OWE is paused (`WallpaperVideo.qml`): `bin/wallpaper-video-corner` cuts
the piece under the window once into `~/.cache` (VA-API decode, never above
the source's resolution), and QtMultimedia decodes only that, muted; the
whole video plays clipped for the few seconds the cut takes.

Clicking the clock lists the maps to pick from. Right-clicking anywhere on
the minimap opens its settings (clock, corner, monitor, size, opacity, over the
bar, workspace compaction, cutout, weather zoom, rain alert and basemap), written to the config straight away.
Hovering with Shift held closes the minimap like an iris and lets clicks through to
the window under it; it comes back once the pointer leaves its corner.

## Maps

Each map is a plugin of its own: a folder under `maps/` holding a
`map.json` and a QML entry point. Weather (`maps/weather/`), workspace
(`maps/workspace/`), media (`maps/media/`) and notifications
(`maps/notifications/`) are built in; add as many folders as you like next to
them and they show up in the clock's list (rescanned each time it opens).
Folders other than the built-in ones are ignored by git, so
`omarchy plugin update` leaves them alone.
A map folder may be a symlink: a plugin can ship its own map and link it
here (Prometheus does: `maps/prometheus`); its relative imports resolve
from its real location.

```json
{
  "id": "hello",
  "name": "Hello",
  "icon": "󰥔",
  "entry": "Map.qml",
  "order": 50
}
```

`id` defaults to the folder name, `entry` to `Map.qml`, `order` to 100
(the list is sorted by order, then name). `icon` is a Nerd Font glyph or a
`.svg` / `.png` file in the folder.

The entry fills the inner disc (clipped round) and gets the minimap as its
one required property:

```qml
import QtQuick
import qs.Commons

Item {
  required property var minimap
  Text {
    anchors.centerIn: parent
    text: Qt.formatTime(minimap.now, "HH:mm:ss")
    color: Color.accent
  }
}
```

Useful members of `minimap`: `now`, `nowSec`, `hovered`, `cfg` (the
config), `location`, `forecast`, `allWindows`, `currentWorkspace`,
`terrain`, `workspaceArcs`, `agents`, `markers`, `numbersShown`, `home`,
`cacheDir`; and `focusWindow(address)`, `focusWorkspace(id)`,
`setMap(id)`, `saveConfig(patch)`, `notify(this, durationMs)`,
`iconUrl(name)`, `appIcon(appId)`. Every map stays loaded
in the background; `minimap.shownMap` is the id on screen. After editing a
map's QML, run `omarchy-restart-shell`. A map with nothing to show can say
so with `readonly property bool empty`; the wheel, `next` and the map list
skip it then. The
shell has no Qt network access: fetch with `Process` and curl.

### Notifications

A map calls `minimap.notify(this, durationMs, persistent)` to be shown over
the chosen one.

- **Temporary**: shown for `durationMs` (default 5 s), in turn; while
  others wait behind it, 2 s. Asked again while showing, its time restarts.
- **Persistent**: it waits for the user and stays until the map calls
  `minimap.release(this)`. They pile up: the latest is shown; once
  released, the one under it comes back, and so on. Temporaries show over
  them, all of them, then the top persistent one comes back.

Whenever what the disc shows changes it turns over like a coin, right to
left in a right corner, left to right in a left one, and back the other
way when it returns to the chosen map. The workspace map always stays on
the whole disc: any other map is drawn over its middle, inside the band of
workspace arcs, so the other desks stay in view. `omarchy-shell
austraz.minimap notify <map id>` shows a map for a moment from a script.

### Notifications map

Catches Omarchy's notifications from the files the notification daemon
keeps for its toasts (`~/.local/state/omarchy/notifications/`, watched with
`inotifywait`). Each one is shown as a notification: its icon in the middle
(attached image, app icon or desktop entry), its title and body running
once around the inner edge, fading in at noon and going clockwise, upright
at 6 o'clock, until they fade out back at noon. Several wait their turn; an urgent one (critical urgency, e.g. a
suggestion waiting for "Voir") stays until clicked or closed by the daemon.
Clicking it while it shows fires the notification's default action, as
clicking its toast would (through `omarchy-shell notifications invoke <id>`,
provided by the `austraz.notifications` clone).
With `hideToasts` (on by default) a notification daemon that reads
`minimap.json`, such as the `austraz.notifications` clone, keeps its own
toasts hidden: the minimap shows them instead.

### Media

What is playing (MPRIS: Spotify, browsers, mpv…): the album cover fills the
disc, a red ring grows clockwise from noon along its edge as the track
plays; paused, the cover dims under a white pause sign. Click plays or
pauses. It notifies on pause, on a skip (a white << or >> over the cover;
back to the previous track or restarting one reads <<) and 2.5 s before a
track ends, so the old cover shows 2.5 s and the new one 2.5 s. Remote
covers are fetched with curl into
`~/.cache/austraz-minimap/covers/`.

## Rim bands

A band is a ring of its own on the rim, inside the day/night dial: the map
shrinks to make room. Like maps, each is a folder, under `bands/`, holding a
`band.json` (`id`, `name`, `entry` defaulting to `Band.qml`, `order`) and
usually linked from the plugin that ships it; `bands/` is ignored by git.
The first band in order sits outermost. Each one gets a switch under its
name in the settings (`disabledBands` in the config); turned off, it takes no
room.

The entry fills the whole disc and gets `minimap`, then `radius` (the band's
centre line) and `thickness`, kept up to date as the size changes. It draws
its own arcs there and handles its own pointer (a `containmentMask` on the
ring keeps the rest of the disc free). To explain itself it can use the OSD
face in the middle circle: `minimap.holdOsd(osd)` while the pointer rests on
something (no timer; `quiet: true` fades it in), `minimap.releaseOsd()`
when it leaves, and `minimap.flashOsd(osd, ms)` for an alert. Besides the
system OSD fields (`icon`, `message`, `value`, `maxValue`, `hasProgress`),
the face takes `color` (ring tint), `ghost` (0..1, a pale arc on from the
level, such as a forecast) and `detail` (small lines under the readout). A
system OSD (volume) over a held one hands back to it when it ends.

My Agents ships the **AI usage** band (`bands/ai`): Claude's 5-hour
session, week and Fable week as three gauges, see its README.

## Data

| What | Source |
| --- | --- |
| Location | `~/.local/state/omarchy/settings/weather.json` (`omarchy-weather-location`) |
| Radar | `api.rainviewer.com` + `tilecache.rainviewer.com` |
| Basemap | `server.arcgisonline.com` Canvas World Dark/Light Gray (© Esri, HERE, Garmin, © OpenStreetMap contributors) |
| Nowcast, sunrise/sunset | `api.open-meteo.com` |
| Agents | `omarchy-shell austraz.minimap agent <session> <state> <pids>`, the same call Spaces takes, sent by every reporter (see below) |
| Tab favicons | `bin/favicons.py` (from Omarchy Spaces, MIT, © Tornike Gomareli), cached in `~/.cache/austraz-minimap/favicons` |

The shell does not use Qt's network stack, so tiles are fetched by
`bin/fetch-tiles` (curl, parallel) into `~/.cache/austraz-minimap/`;
radar frames older than three hours are pruned.

## Config

`~/.config/omarchy/minimap.json`, reloaded on save. The selector, the settings
and IPC write back to it.

```json
{
  "corner": "bottom-right",
  "size": 300,
  "margin": -1,
  "map": "weather",
  "zoom": 7,
  "opacity": 1,
  "basemap": "auto",
  "monitor": "",
  "visible": true
}
```

`margin`: distance from the disc to the screen edges; `-1` (default) uses
Hyprland's `gaps_out`. `cutout`: `false` drops the wallpaper ring.
`overBar`: `true` puts the minimap in the screen corner over the bar (overlay
layer, ignoring the zone the bar reserves); it then hides while the
workspace has a fullscreen window.
`autoCompact`: `true` renumbers the workspaces 1..n whenever a gap appears
(a desk emptied, a window moved away): occupied desks keep their order,
persistent ones keep their id, an empty desk still on screen goes last.
`clock`: `false` hides the clock, which then only shows while the minimap
is hovered (it opens the map list).
`cardinals`: `false` drops the pilot's bezel (a triangle at noon, E, S and W)
for plain ticks at those four hours.
`rainAlert`: minutes (0–30, default 10, 0 = off) before the forecast rain
starts to show the weather map as a notification (playing the end of the
radar loop), once per dry spell. The
forecast comes in 15 min steps, so the start time is that precise at best.
`iconOverrides`: `{ "<window class>": "<icon name or path>" }`, for windows
whose launcher cannot be told apart (two accounts of the same web app).
`corner`: `bottom-right`, `bottom-left`, `top-right`, `top-left`.
`basemap`: `auto` follows the theme background, or `dark` / `light`.
`disabledBands`: ids of the rim bands turned off (see Rim bands).
`monitor`: a connector name such as `eDP-1`; empty follows the focused monitor.

## IPC

```bash
omarchy-shell austraz.minimap toggle        # show / hide
omarchy-shell austraz.minimap next          # next map in the list
omarchy-shell austraz.minimap maps          # open / close the map list
omarchy-shell austraz.minimap settings      # open / close the settings
omarchy-shell austraz.minimap peek          # hide until the pointer leaves the corner
omarchy-shell austraz.minimap notify media  # show a map for a moment, queued
omarchy-shell austraz.minimap radar         # weather map as a notification, end of the radar loop
omarchy-shell austraz.minimap osd '{"iconKey":"volume","icon":"","value":130,"maxValue":200,"hasProgress":true,"message":"130%"}'  # "ok" when shown
omarchy-shell austraz.minimap dictation     # "ok" while the disc can show dictation
omarchy-shell austraz.minimap demo prometheus legendary  # a map's own demo, if it has one
omarchy-shell austraz.minimap map workspace  # any map id
omarchy-shell austraz.minimap corner top-left
omarchy-shell austraz.minimap zoomIn
omarchy-shell austraz.minimap refresh       # refetch radar + forecast
omarchy-shell austraz.minimap snapshot /tmp/minimap.png
omarchy-shell austraz.minimap agent <session> <working|waiting|done|idle|end> <pid,pid,...>
omarchy-shell austraz.minimap focusAlert    # Super+Caps Lock
omarchy-shell austraz.minimap showNumbers   # held Super (hideNumbers on release)
```

## Tests

The pure helpers in `Model.js` (config, desk order and darkening, arcs,
dial, battery, wallpaper crop) have checks for Node's test runner:

```sh
node --test test/*.test.js
```

## Install

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable austraz.minimap
omarchy-restart-shell   # the panel is keepLoaded: QML edits need a restart
```
