# Minimap

A round, game-style minimap pinned to a screen corner of the Omarchy shell.

- **Weather map**: Esri dark/light gray basemap, RainViewer radar (latest
  scan at rest, the last two hours looped while hovered), place names on top,
  you in the middle, and an Open-Meteo nowcast line ("pluie dans 20 min",
  "sec 2 h"). Wheel zooms (4–10; radar tiles stop at 7 and are scaled up).
- **Workspace map**: the focused workspace stretched onto the disc, each
  window drawn as its rectangle cut to the circle (one window fills it, two
  side by side make two half discs). The other occupied workspaces are equal
  arcs around it, in order clockwise from the top; hover names a
  workspace's apps, click switches to it. Every window shows
  its app icon in the middle of its visible part (desktop entry, StartupWMClass for web apps) and windows
  untouched for a while fade out. Coding agents show the same way on
  their window and on their workspace's arc, no markers: a fast red blink
  when blocked on a permission prompt, a slow theme-accent blink when a turn
  is done (at least three blinks, then cleared once you see it), slow theme-accent rings spreading
  from the icon (or the arc's middle) for as long as they work. Click a window to focus it.
  Switching workspace animates: the one you leave shrinks into the arc
  that opens for it on the band (in the theme accent, fading to its own
  colour as the switch ends), while the one you go to grows out of its
  arc, which closes in the theme accent; the other arcs slide into place.
- **Rim**: a 24 h dial (noon at the top, midnight at the bottom). By day the
  arc from the real sunrise to sunset is yellow, with the sun on the current
  time; by night the arc from sunset to sunrise is blue, with the moon drawn
  in its real phase (mean lunation, waxing lit on the right). Between the
  map's edge and the dial, a band of its own carries the battery: on
  battery a stripe from now to the estimated empty time (level shown next to
  the clock); charging, an orange stripe to full followed by a green one for
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
- **Scratchpad**: an arc reading "0" while it holds windows; click toggles
  it, and its agents count as seen while it is shown.

The minimap does not sit on the window under it: a ring as wide as
Hyprland's `gaps_out` shows the wallpaper around the disc (lined up with the
real one, from `~/.local/state/omarchy/current/background`), as if the disc
were cut out of that window, and the disc keeps that same distance from the
screen edges. The window's corner on the minimap's side is masked too, and
that window's Hyprland border (active colour when it has focus, inactive
otherwise, same width) is carried around the cut.

The button in the corner facing the screen shows the current map; clicking
it lists the maps to pick from. Right-click on the disc cycles them.
Clicking the clock opens the settings (corner, monitor, size, opacity,
cutout, weather zoom and basemap), written to the config straight away.

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
  "size": 210,
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
`iconOverrides`: `{ "<window class>": "<icon name or path>" }`, for windows
whose launcher cannot be told apart (two accounts of the same web app).
`corner`: `bottom-right`, `bottom-left`, `top-right`, `top-left`.
`basemap`: `auto` follows the theme background, or `dark` / `light`.
`monitor`: a connector name such as `eDP-1`; empty follows the focused monitor.

## IPC

```bash
omarchy-shell austraz.minimap toggle        # show / hide
omarchy-shell austraz.minimap next          # cycle maps
omarchy-shell austraz.minimap maps          # open / close the map list
omarchy-shell austraz.minimap settings      # open / close the settings
omarchy-shell austraz.minimap map workspace
omarchy-shell austraz.minimap corner top-left
omarchy-shell austraz.minimap zoomIn
omarchy-shell austraz.minimap refresh       # refetch radar + forecast
omarchy-shell austraz.minimap snapshot /tmp/minimap.png
omarchy-shell austraz.minimap agent <session> <working|waiting|done|idle|end> <pid,pid,...>
omarchy-shell austraz.minimap focusAlert    # Super+Caps Lock
omarchy-shell austraz.minimap showNumbers   # held Super (hideNumbers on release)
```

## Install

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable austraz.minimap
omarchy-restart-shell   # the panel is keepLoaded: QML edits need a restart
```
