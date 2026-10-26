// Pure helpers for the minimap: slippy-map tile math, the 24 h dial,
// the rain nowcast line, and the workspace terrain layout. No QML here so
// the logic can be checked with node.

var TILE = 256
// RainViewer's free tiles stop at zoom 7 (zoom 8 returns a
// "Zoom Level Not Supported" picture), so the radar layer is drawn at
// min(zoom, 7) and scaled up under the basemap.
var RADAR_MAX_ZOOM = 7
var MIN_ZOOM = 4
var MAX_ZOOM = 10

var CORNERS = ["bottom-right", "bottom-left", "top-right", "top-left"]
var MAPS = ["weather", "workspace"]
// What the map menu lists, in MAPS order. Glyphs are Nerd Font icons.
var MAP_INFO = [
  { name: "weather", label: "Météo", glyph: String.fromCodePoint(0xF0595) },
  { name: "workspace", label: "Bureaux", glyph: String.fromCodePoint(0xF0379) }
]

function mapInfo(name) {
  for (var i = 0; i < MAP_INFO.length; i++) if (MAP_INFO[i].name === name) return MAP_INFO[i]
  return MAP_INFO[0]
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// ---------------------------------------------------------------- config

function normalizeConfig(raw) {
  var c = raw && typeof raw === "object" ? raw : {}
  var corner = CORNERS.indexOf(String(c.corner)) !== -1 ? String(c.corner) : "bottom-right"
  var map = MAPS.indexOf(String(c.map)) !== -1 ? String(c.map) : "weather"
  var size = parseInt(c.size, 10)
  var margin = parseInt(c.margin, 10)
  var zoom = parseInt(c.zoom, 10)
  var opacity = parseFloat(c.opacity)
  return {
    corner: corner,
    map: map,
    size: isNaN(size) ? 210 : clamp(size, 120, 480),
    // -1 = automatic: Hyprland's gaps_out, like a window's distance to the edge.
    margin: isNaN(margin) ? -1 : clamp(margin, 0, 200),
    cutout: c.cutout !== false,
    iconOverrides: c.iconOverrides && typeof c.iconOverrides === "object" ? c.iconOverrides : {},
    zoom: isNaN(zoom) ? 7 : clamp(zoom, MIN_ZOOM, MAX_ZOOM),
    opacity: isNaN(opacity) ? 1 : clamp(opacity, 0.2, 1),
    monitor: c.monitor ? String(c.monitor) : "",
    basemap: c.basemap === "light" || c.basemap === "dark" ? c.basemap : "auto"
  }
}

// weather.json is owned by omarchy-weather-location: {name, latitude, longitude}.
function parseLocation(text) {
  try {
    var d = JSON.parse(text || "{}")
    var lat = parseFloat(d.latitude)
    var lon = parseFloat(d.longitude)
    if (isNaN(lat) || isNaN(lon)) return null
    return { name: String(d.name || ""), lat: lat, lon: lon }
  } catch (e) {
    return null
  }
}

function nextMap(current, step) {
  var i = MAPS.indexOf(current)
  if (i === -1) i = 0
  var n = MAPS.length
  return MAPS[((i + (step || 1)) % n + n) % n]
}

// Selector buttons sit on the rim facing the screen interior, so they are
// never pushed against the screen edge. Angles in degrees, 0 = up, clockwise.
function selectorAngle(corner) {
  switch (corner) {
  case "bottom-left": return 45
  case "top-right": return 225
  case "top-left": return 135
  default: return 315
  }
}

// ------------------------------------------------------------ tile math

function worldPixel(lat, lon, zoom) {
  var scale = TILE * Math.pow(2, zoom)
  var latR = clamp(lat, -85.0511, 85.0511) * Math.PI / 180
  return {
    x: (lon + 180) / 360 * scale,
    y: (1 - Math.log(Math.tan(latR) + 1 / Math.cos(latR)) / Math.PI) / 2 * scale
  }
}

// Tiles of zoom `tileZoom` covering a `size` x `size` view centred on
// world pixel (cx, cy) at display zoom `zoom`. Each tile is drawn at
// TILE * 2^(zoom - tileZoom) px. Returns [{z, x, y, left, top, size}].
function tilesFor(cx, cy, zoom, tileZoom, size) {
  var s = Math.pow(2, zoom - tileZoom)
  var drawn = TILE * s
  var cxT = cx / s
  var cyT = cy / s
  var half = size / 2 / s
  var n = Math.pow(2, tileZoom)
  var x0 = Math.floor((cxT - half) / TILE)
  var x1 = Math.floor((cxT + half) / TILE)
  var y0 = Math.max(0, Math.floor((cyT - half) / TILE))
  var y1 = Math.min(n - 1, Math.floor((cyT + half) / TILE))
  var out = []
  for (var ty = y0; ty <= y1; ty++) {
    for (var tx = x0; tx <= x1; tx++) {
      out.push({
        z: tileZoom,
        x: ((tx % n) + n) % n,
        y: ty,
        left: (tx * TILE - cxT) * s + size / 2,
        top: (ty * TILE - cyT) * s + size / 2,
        size: drawn
      })
    }
  }
  return out
}

// Esri Canvas basemaps (no key needed): the base under the radar, the
// reference layer (place names, borders) on top of it. Esri orders z/y/x.
function basemapUrl(style, layer, t) {
  var name = "World_" + (style === "light" ? "Light" : "Dark") + "_Gray_" + (layer === "labels" ? "Reference" : "Base")
  return "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/" + name + "/MapServer/tile/" + t.z + "/" + t.y + "/" + t.x
}

// Colour scheme 2 = Universal Blue, options 1_1 = smoothed + snow shown.
function radarUrl(host, path, t) {
  return host + path + "/256/" + t.z + "/" + t.x + "/" + t.y + "/2/1_1.png"
}

// Where a tile lives in the on-disk cache (fetch-tiles fills it with curl;
// Qt's own network stack is not used by the shell).
function basemapFile(cache, style, layer, t) {
  var ext = layer === "labels" ? ".png" : ".jpg"
  return cache + "/basemap/" + style + "-" + layer + "/" + t.z + "/" + t.x + "/" + t.y + ext
}

function radarFile(cache, path, t) {
  var frame = String(path).split("/").pop()
  return cache + "/radar/" + frame + "/" + t.z + "/" + t.x + "/" + t.y + ".png"
}

// weather-maps.json → past frames, oldest first: [{time, path}]
function parseRadarFrames(text) {
  try {
    var d = JSON.parse(text)
    var past = d && d.radar && Array.isArray(d.radar.past) ? d.radar.past : []
    var frames = []
    for (var i = 0; i < past.length; i++) {
      if (past[i] && past[i].path) frames.push({ time: Number(past[i].time) || 0, path: String(past[i].path) })
    }
    return { host: String(d.host || "https://tilecache.rainviewer.com"), frames: frames }
  } catch (e) {
    return { host: "", frames: [] }
  }
}

function isLightColor(c) {
  if (!c) return false
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b > 0.5
}

// ------------------------------------------------------------ the dial

// Seconds since local midnight → angle on a 24 h dial with noon at the top.
function dialAngle(secondsOfDay) {
  return ((secondsOfDay / 86400) * 360 + 180) % 360
}

function secondsOfDay(date) {
  return date.getHours() * 3600 + date.getMinutes() * 60 + date.getSeconds()
}

// Open-Meteo forecast → {sunrise, sunset (epoch s), rain: [{time, mm}]}
function parseForecast(text) {
  try {
    var d = JSON.parse(text)
    var m = d.minutely_15 || {}
    var times = m.time || []
    var mm = m.precipitation || []
    var rain = []
    for (var i = 0; i < times.length; i++) rain.push({ time: Number(times[i]), mm: Number(mm[i]) || 0 })
    var daily = d.daily || {}
    return {
      sunrise: daily.sunrise && daily.sunrise.length ? Number(daily.sunrise[0]) : 0,
      sunset: daily.sunset && daily.sunset.length ? Number(daily.sunset[0]) : 0,
      rain: rain
    }
  } catch (e) {
    return null
  }
}

// Sunrise/sunset epochs → dial angles of the daylight arc.
function daylightArc(sunrise, sunset) {
  if (!sunrise || !sunset) return null
  var a = dialAngle(secondsOfDay(new Date(sunrise * 1000)))
  var b = dialAngle(secondsOfDay(new Date(sunset * 1000)))
  return { start: a, end: b }
}

function isDaytime(nowSec, sunrise, sunset) {
  if (!sunrise || !sunset) {
    var h = new Date(nowSec * 1000).getHours()
    return h >= 7 && h < 19
  }
  return nowSec >= sunrise && nowSec < sunset
}

// Moon phase as a fraction of the synodic month: 0 new, 0.25 first
// quarter, 0.5 full, 0.75 last quarter. Mean lunation from the new moon of
// 2000-01-06 18:14 UTC, good to within a few hours.
var SYNODIC_DAYS = 29.530588853
var NEW_MOON_2000 = Date.UTC(2000, 0, 6, 18, 14) / 1000

function moonPhase(epochSeconds) {
  var days = (epochSeconds - NEW_MOON_2000) / 86400
  var p = (days / SYNODIC_DAYS) % 1
  return p < 0 ? p + 1 : p
}

// Outline of the lit part of the moon for a disc of radius r centred at
// (r, r): down the limb on the lit side (right while waxing, as seen from
// the northern hemisphere), back up the terminator, a half ellipse at
// x = cos(2π·phase)·r·√(1 − y²) on the same side.
function moonOutline(phase, r) {
  var side = phase < 0.5 ? 1 : -1
  var k = Math.cos(2 * Math.PI * phase)
  var pts = [], n = 24, i, y, w
  for (i = 0; i <= n; i++) {
    y = -1 + 2 * i / n
    w = Math.sqrt(Math.max(0, 1 - y * y))
    pts.push({ x: r + side * r * w, y: r + y * r })
  }
  for (i = n; i >= 0; i--) {
    y = -1 + 2 * i / n
    w = Math.sqrt(Math.max(0, 1 - y * y))
    pts.push({ x: r + side * k * r * w, y: r + y * r })
  }
  return pts
}

// Minimum rain worth announcing, mm per 15 min.
var RAIN_MM = 0.1

// One short line for the bottom of the weather map.
function nowcastLine(rain, nowSec) {
  if (!rain || rain.length === 0) return ""
  var upcoming = []
  for (var i = 0; i < rain.length; i++) {
    if (rain[i].time + 900 > nowSec) upcoming.push(rain[i])
  }
  if (upcoming.length === 0) return ""
  var raining = upcoming[0].mm >= RAIN_MM
  for (var j = 1; j < upcoming.length; j++) {
    var wet = upcoming[j].mm >= RAIN_MM
    if (wet !== raining) {
      var mins = Math.max(5, Math.round((upcoming[j].time - nowSec) / 300) * 5)
      return raining ? "fin dans " + mins + " min" : "pluie dans " + mins + " min"
    }
  }
  var span = Math.round((upcoming[upcoming.length - 1].time + 900 - nowSec) / 3600)
  return raining ? "pluie " + span + " h+" : "sec " + span + " h"
}

function pad2(n) { return n < 10 ? "0" + n : String(n) }

function clockText(date) {
  return pad2(date.getHours()) + ":" + pad2(date.getMinutes())
}

function frameAge(frameTime, nowSec) {
  if (!frameTime) return ""
  var m = Math.max(0, Math.round((nowSec - frameTime) / 60))
  return m < 1 ? "maintenant" : "-" + m + " min"
}

// ------------------------------------------------------- workspace terrain

// ------------------------------------------------------------ agents
//
// Same model as Omarchy Spaces, so the minimap can replace it: reporters
// (coding-agent hooks and the like) send `agent <session> <state> <pids>`
// over IPC; pids run from the agent process up to init, and the nearest
// one that owns a window is the agent's window.

var AGENT_REPORT_STATES = { working: true, waiting: true, done: true, idle: true }
var AGENT_LIVE_STATES = { working: true, waiting: true }

function normalizeAddress(address) {
  return String(address || "").toLowerCase().replace(/^0x/, "")
}

function normalizeAgentState(state) {
  var value = String(state || "")
  return AGENT_REPORT_STATES[value] ? value : ""
}

function parsePids(csv) {
  return String(csv || "").split(",").map(function(v) { return Number(v) }).filter(function(n) { return n > 1 })
}

function agentWindowsByPid(windows) {
  var byPid = {}
  for (var w = 0; w < (windows || []).length; w++) {
    var pid = Number(windows[w].pid)
    if (!pid) continue
    if (!byPid[pid]) byPid[pid] = []
    byPid[pid].push(normalizeAddress(windows[w].address))
  }
  return byPid
}

// Windows showing an agent: its pinned window, or every window of its
// nearest ancestor pid when that is ambiguous (one terminal server, many
// windows).
function agentAddresses(agent, byPid) {
  var candidates = null
  for (var i = 0; i < agent.pids.length; i++) {
    if (byPid[agent.pids[i]]) { candidates = byPid[agent.pids[i]]; break }
  }
  if (!candidates) return []
  var pinned = normalizeAddress(agent.address)
  if (pinned && candidates.indexOf(pinned) !== -1) return [pinned]
  return candidates
}

function agentPinAddress(pids, windows, activeAddress) {
  var addresses = agentAddresses({ pids: pids }, agentWindowsByPid(windows))
  if (addresses.length === 1) return addresses[0]
  var active = normalizeAddress(activeAddress)
  return active && addresses.indexOf(active) !== -1 ? active : ""
}

// Strongest marker wins when several agents share one window.
var STATE_RANK = { waiting: 3, done: 2, working: 1 }

// { session: {state, pids, address} } → { normalizedAddress: state }
function agentWindowStates(agents, windows) {
  var byPid = agentWindowsByPid(windows)
  var out = {}
  for (var session in agents) {
    var agent = agents[session]
    var rank = STATE_RANK[agent.state] || 0
    if (!rank) continue
    var addresses = agentAddresses(agent, byPid)
    for (var c = 0; c < addresses.length; c++) {
      var address = addresses[c]
      if (!out[address] || STATE_RANK[out[address]] < rank) out[address] = agent.state
    }
  }
  return out
}

// Agent processes to check while they claim to be working or waiting.
function agentProcessIds(agents) {
  var out = []
  for (var session in agents) {
    var agent = agents[session]
    if (!agent || !AGENT_LIVE_STATES[agent.state]) continue
    var pid = Number(agent.pids && agent.pids[0])
    if (pid > 1 && out.indexOf(pid) === -1) out.push(pid)
  }
  return out.sort(function(a, b) { return a - b })
}

// A crashed reporter never sends "end": drop live claims whose agent died.
function pruneDeadAgents(agents, alivePids) {
  var alive = {}
  for (var i = 0; i < (alivePids || []).length; i++) alive[String(Number(alivePids[i]))] = true
  var pruned = false, out = {}
  for (var session in agents) {
    var agent = agents[session]
    var pid = Number(agent && agent.pids && agent.pids[0])
    if (agent && AGENT_LIVE_STATES[agent.state] && pid > 1 && !alive[String(pid)]) { pruned = true; continue }
    out[session] = agent
  }
  return pruned ? out : agents
}

// Stretch the workspace onto the whole disc: the box around the tiled
// windows becomes the disc's square, so one window fills the circle and
// two side by side make two half discs. Floating windows map into the
// same box. `fallback` (the monitor) is used when nothing is tiled.
function discLayout(windows, size, fallback) {
  var box = null
  for (var i = 0; i < windows.length; i++) {
    var w = windows[i]
    if (w.floating || !w.at || !w.size) continue
    var x1 = w.at[0] + w.size[0], y1 = w.at[1] + w.size[1]
    if (!box) box = { x0: w.at[0], y0: w.at[1], x1: x1, y1: y1 }
    else {
      box.x0 = Math.min(box.x0, w.at[0]); box.y0 = Math.min(box.y0, w.at[1])
      box.x1 = Math.max(box.x1, x1); box.y1 = Math.max(box.y1, y1)
    }
  }
  if (!box && fallback) box = { x0: fallback.x, y0: fallback.y, x1: fallback.x + fallback.width, y1: fallback.y + fallback.height }
  if (!box || box.x1 <= box.x0 || box.y1 <= box.y0) return []
  var sx = size / (box.x1 - box.x0)
  var sy = size / (box.y1 - box.y0)
  var out = []
  for (var j = 0; j < windows.length; j++) {
    var win = windows[j]
    if (!win.at || !win.size) continue
    var left = clamp((win.at[0] - box.x0) * sx, 0, size)
    var top = clamp((win.at[1] - box.y0) * sy, 0, size)
    var right = clamp((win.at[0] + win.size[0] - box.x0) * sx, 0, size)
    var bottom = clamp((win.at[1] + win.size[1] - box.y0) * sy, 0, size)
    if (right - left < 2 || bottom - top < 2) continue
    out.push({
      address: win.address, appId: win.appId, title: win.title,
      focused: win.focused, floating: win.floating,
      x: left, y: top, w: right - left, h: bottom - top
    })
  }
  return out
}

// Occupied workspaces as equal arcs around the disc, in id order,
// clockwise, the first one centred at the top. Angles in dial degrees.
function workspaceArcs(workspaces, gap) {
  var n = workspaces.length
  if (n === 0) return []
  var span = 360 / n
  var g = n > 1 ? (gap || 4) : 0
  var out = []
  for (var i = 0; i < n; i++) {
    var ws = workspaces[i]
    var mid = i * span
    out.push({
      id: ws.id, current: ws.current, state: ws.state, apps: ws.apps, icons: ws.icons || [], count: ws.count,
      start: ((mid - span / 2 + g / 2) % 360 + 360) % 360, sweep: span - g, mid: mid
    })
  }
  return out
}

// Where an arc's icons go: as many as fit along it, `step` px apart at
// radius r, centred on its middle; when they do not all fit, the last slot
// shows "+n". Returns [{ angle, icon }] or [{ angle, more }].
function arcIconSlots(arc, r, step, margin) {
  var icons = arc && arc.icons ? arc.icons : []
  if (!icons.length || r <= 0) return []
  var stepDeg = step / r * 180 / Math.PI
  var fit = Math.floor((arc.sweep - 2 * (margin || 0)) / stepDeg)
  if (fit < 1) return []
  var shown = icons.length <= fit ? icons.length : fit - 1
  var n = icons.length <= fit ? shown : fit
  var out = []
  for (var i = 0; i < n; i++) {
    var angle = arc.mid + (i - (n - 1) / 2) * stepDeg
    if (i < shown) out.push({ angle: angle, icon: icons[i] })
    else out.push({ angle: angle, more: icons.length - shown })
  }
  return out
}

// Arcs halfway between two layouts, for the switch animation (t from 0 to
// 1). An arc in both slides and resizes; one only in `from` (the workspace
// you go to) closes on its middle; one only in `to` (the workspace you
// leave) opens from its middle.
function blendArcs(from, to, t) {
  var byId = {}, ids = [], i, id
  for (i = 0; i < from.length; i++) { byId[from[i].id] = { f: from[i] }; ids.push(from[i].id) }
  for (i = 0; i < to.length; i++) {
    id = to[i].id
    if (!byId[id]) { byId[id] = {}; ids.push(id) }
    byId[id].g = to[i]
  }
  var out = []
  for (i = 0; i < ids.length; i++) {
    var e = byId[ids[i]], f = e.f, g = e.g, start, sweep
    if (f && g) {
      var d = ((g.start - f.start) % 360 + 540) % 360 - 180
      start = f.start + d * t
      sweep = f.sweep + (g.sweep - f.sweep) * t
    } else if (f) {
      sweep = f.sweep * (1 - t)
      start = f.start + (f.sweep - sweep) / 2
    } else {
      sweep = g.sweep * t
      start = g.mid - sweep / 2
    }
    var src = g || f
    out.push({ id: src.id, current: src.current, state: src.state, apps: src.apps, icons: src.icons || [], count: src.count,
      arriving: !!f && !g, leaving: !f && !!g, start: (start % 360 + 360) % 360, sweep: sweep, mid: ((start + sweep / 2) % 360 + 360) % 360 })
  }
  return out
}

// Centre of mass and area of a closed polygon ([{x, y}], last = first):
// where a tile's icon goes, so it sits in the middle of what is visible of
// the window once cut to the circle.
function polygonCentroid(pts) {
  var a = 0, cx = 0, cy = 0
  for (var i = 0; i + 1 < pts.length; i++) {
    var p = pts[i], q = pts[i + 1]
    var cross = p.x * q.y - q.x * p.y
    a += cross
    cx += (p.x + q.x) * cross
    cy += (p.y + q.y) * cross
  }
  if (Math.abs(a) < 1e-6) return { x: pts.length ? pts[0].x : 0, y: pts.length ? pts[0].y : 0, area: 0 }
  return { x: cx / (3 * a), y: cy / (3 * a), area: Math.abs(a) / 2 }
}

// Desktop-entry ids to try for a window class, most specific first, as
// Spaces does: reverse-DNS ids often ship a file named after the last part.
function appIdCandidates(appId) {
  var id = String(appId || "")
  if (id === "") return []
  var out = [id]
  function add(v) { if (v && out.indexOf(v) === -1) out.push(v) }
  add(id.toLowerCase())
  add(id + ".desktop")
  add(id.toLowerCase() + ".desktop")
  var dot = id.lastIndexOf(".")
  if (dot > 0 && dot < id.length - 1) {
    add(id.slice(dot + 1))
    add(id.slice(dot + 1).toLowerCase())
  }
  return out
}

// Chromium-family --app windows use classes like
// "brave-chat.google.com__u_1_app_home-Default": host and path, so the
// launcher whose Exec opens that address can be found (as Spaces does).
function webAppHint(appId) {
  var m = /^(?:chrome|chromium|brave|msedge|vivaldi|helium|opera)-([^_]+?)__(.*?)-(?:Default|Profile_\d+)$/i.exec(String(appId || ""))
  if (!m) return null
  return { host: m[1], path: String(m[2] || "").replace(/_/g, "/").replace(/^\/+|\/+$/g, "") }
}

function scoreWebAppExec(exec, hint) {
  var text = String(exec || "")
  var needle = "//" + hint.host
  var at = text.indexOf(needle)
  if (at === -1) return -1
  var execPath = text.slice(at + needle.length).replace(/[?"'\s].*$/, "").replace(/^\/+/, "").replace(/\/+$/, "")
  if (hint.path) {
    if (execPath === hint.path || execPath.indexOf(hint.path + "/") === 0) return 1000 + execPath.length
    return -1
  }
  return 100 - Math.min(99, execPath.length)
}

// Index of the best launcher: same path first (keeps two accounts apart),
// else any launcher for the host, shorter paths first. -1 when none.
function bestWebAppExecIndex(execs, hint) {
  if (!hint || !execs || execs.length === 0) return -1
  function pick(h) {
    var best = -1, bestScore = -1
    for (var i = 0; i < execs.length; i++) {
      var score = scoreWebAppExec(execs[i], h)
      if (score > bestScore) { bestScore = score; best = i }
    }
    return bestScore >= 0 ? best : -1
  }
  var found = pick(hint)
  return found >= 0 || !hint.path ? found : pick({ host: hint.host, path: "" })
}

// Ordinary browser windows (not --app web apps) all share one class, so
// they show the current tab's favicon instead, as in Spaces.
var BROWSER_APP_IDS = {
  "brave-origin": true, "brave-browser": true, "brave-browser-stable": true, "brave": true,
  "chromium": true, "chromium-browser": true, "google-chrome": true, "google-chrome-stable": true,
  "helium": true
}

function isBrowserWindow(appId) {
  return !!BROWSER_APP_IDS[String(appId || "").toLowerCase()]
}

// Icon index helpers: an SVG beats any PNG, a bigger PNG beats a smaller.
function iconPathScore(path) {
  var p = String(path || "")
  if (/\.svg$/i.test(p)) return 100000
  var m = /\/(\d+)x\d+\//.exec(p)
  if (m) return Number(m[1])
  return /\/pixmaps\//.test(p) ? 48 : 1
}

function iconNameFromPath(path) {
  var value = String(path || "")
  var file = value.slice(value.lastIndexOf("/") + 1)
  var dot = file.lastIndexOf(".")
  return dot > 0 ? file.slice(0, dot) : file
}

// Outline of a window rectangle cut to the disc of diameter `size`: walk
// the rectangle's edges and pull every point that falls outside the
// circle back onto it, so the tile's outer edge follows the circle. Edges
// on the disc's bounding box are pushed well outside first (an edge tangent
// to the circle would otherwise cut a flat chord at the cardinal points),
// and only edges shared with a neighbour are inset by `gap`.
function tileOutline(x, y, w, h, size, gap) {
  var c = size / 2, r = size / 2, g = gap || 0, far = size
  var x0 = x <= 0.5 ? -far : x + g
  var y0 = y <= 0.5 ? -far : y + g
  var x1 = x + w >= size - 0.5 ? size + far : x + w - g
  var y1 = y + h >= size - 0.5 ? size + far : y + h - g
  var corners = [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
  var pts = []
  for (var e = 0; e < 4; e++) {
    var a = corners[e], b = corners[(e + 1) % 4]
    var len = Math.max(Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]))
    var steps = Math.max(1, Math.ceil(len / (len > size ? 6 : 1)))
    for (var k = 0; k < steps; k++) {
      var px = a[0] + (b[0] - a[0]) * k / steps
      var py = a[1] + (b[1] - a[1]) * k / steps
      var dx = px - c, dy = py - c
      var d = Math.sqrt(dx * dx + dy * dy)
      if (d > r) { px = c + dx * r / d; py = c + dy * r / d }
      var last = pts[pts.length - 1]
      if (!last || Math.abs(last.x - px) > 0.05 || Math.abs(last.y - py) > 0.05) pts.push({ x: px, y: py })
    }
  }
  pts.push(pts[0])
  return pts
}

// Pointer position in a square of `size` → dial angle in degrees.
function pointAngle(x, y, size) {
  var a = Math.atan2(x - size / 2, size / 2 - y) * 180 / Math.PI
  return (a + 360) % 360
}

function arcAt(arcs, angle) {
  for (var i = 0; i < arcs.length; i++) {
    var d = ((angle - arcs[i].start) % 360 + 360) % 360
    if (d <= arcs[i].sweep) return arcs[i]
  }
  return null
}

// Strongest agent state across a set of window addresses.
function strongestState(addresses, markers) {
  var best = ""
  for (var i = 0; i < addresses.length; i++) {
    var st = markers[addresses[i]]
    if (st && (!best || STATE_RANK[st] > STATE_RANK[best])) best = st
  }
  return best
}

// Battery time on the dial: from now to the estimated empty (or full)
// time, capped just short of a full turn.
function batterySweep(seconds) {
  if (!(seconds > 0)) return 0
  return Math.min(355, seconds / 86400 * 360)
}

// UPower GetHistory("rate") as printed by gdbus: (time, watts, state)
// tuples, state 2 = discharging. Median discharge rate over the last
// `days`, in watts, or 0 when there is nothing to go on.
function dischargeRate(text, nowSec, days) {
  var re = /\((?:uint32 )?(\d+), ([\d.]+), (?:uint32 )?(\d+)\)/g
  var rates = [], m
  var since = nowSec - (days || 7) * 86400
  while ((m = re.exec(String(text || ""))) !== null) {
    var t = Number(m[1]), w = Number(m[2]), st = Number(m[3])
    if (st === 2 && t >= since && w > 0.5) rates.push(w)
  }
  if (rates.length === 0) return 0
  rates.sort(function(a, b) { return a - b })
  return rates[Math.floor(rates.length / 2)]
}

function durationText(seconds) {
  if (!(seconds > 0)) return ""
  var m = Math.round(seconds / 60)
  return m < 60 ? m + " min" : Math.floor(m / 60) + " h " + pad2(m % 60)
}

// Fog of war: windows untouched for a while fade out, never below `floor`.
function fogOpacity(lastFocused, nowSec, floor) {
  if (!lastFocused) return floor
  var idle = nowSec - lastFocused
  if (idle < 600) return 1
  if (idle > 3600) return floor
  return 1 - (1 - floor) * (idle - 600) / 3000
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeConfig: normalizeConfig,
    parseLocation: parseLocation,
    nextMap: nextMap,
    mapInfo: mapInfo,
    MAP_INFO: MAP_INFO,
    selectorAngle: selectorAngle,
    worldPixel: worldPixel,
    tilesFor: tilesFor,
    basemapUrl: basemapUrl,
    radarUrl: radarUrl,
    basemapFile: basemapFile,
    radarFile: radarFile,
    parseRadarFrames: parseRadarFrames,
    dialAngle: dialAngle,
    secondsOfDay: secondsOfDay,
    parseForecast: parseForecast,
    daylightArc: daylightArc,
    isDaytime: isDaytime,
    nowcastLine: nowcastLine,
    moonPhase: moonPhase,
    moonOutline: moonOutline,
    clockText: clockText,
    frameAge: frameAge,
    discLayout: discLayout,
    workspaceArcs: workspaceArcs,
    blendArcs: blendArcs,
    arcIconSlots: arcIconSlots,
    polygonCentroid: polygonCentroid,
    appIdCandidates: appIdCandidates,
    webAppHint: webAppHint,
    isBrowserWindow: isBrowserWindow,
    bestWebAppExecIndex: bestWebAppExecIndex,
    iconPathScore: iconPathScore,
    iconNameFromPath: iconNameFromPath,
    pointAngle: pointAngle,
    arcAt: arcAt,
    strongestState: strongestState,
    normalizeAddress: normalizeAddress,
    normalizeAgentState: normalizeAgentState,
    parsePids: parsePids,
    agentAddresses: agentAddresses,
    agentWindowsByPid: agentWindowsByPid,
    agentPinAddress: agentPinAddress,
    agentWindowStates: agentWindowStates,
    agentProcessIds: agentProcessIds,
    pruneDeadAgents: pruneDeadAgents,
    batterySweep: batterySweep,
    dischargeRate: dischargeRate,
    tileOutline: tileOutline,
    durationText: durationText,
    fogOpacity: fogOpacity,
    RADAR_MAX_ZOOM: RADAR_MAX_ZOOM,
    MIN_ZOOM: MIN_ZOOM,
    MAX_ZOOM: MAX_ZOOM
  }
}
