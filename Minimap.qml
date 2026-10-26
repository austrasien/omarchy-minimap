import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs.Commons
import "Model.js" as Model

// A round, game-style minimap pinned to a screen corner. What the disc
// shows is a map plugin, one folder per map under maps/ (weather radar and
// workspace terrain built in); the clock lists them.
// The rim is a 24 h day/night dial; the battery marks the hour it lasts until.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/minimap.json"
  readonly property string locationPath: home + "/.local/state/omarchy/settings/weather.json"

  // ------------------------------------------------------------ config

  property var rawConfig: ({})
  readonly property var cfg: Model.normalizeConfig(rawConfig)
  readonly property bool shown: rawConfig.visible !== false

  function saveConfig(patch) {
    var next = ({})
    for (var k in rawConfig) next[k] = rawConfig[k]
    for (var p in patch) next[p] = patch[p]
    rawConfig = next
    configFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.rawConfig = JSON.parse(text() || "{}") } catch (e) { console.warn("minimap: bad config", e) }
    }
  }

  // --------------------------------------------------------------- clock

  property var now: new Date()
  readonly property real nowSec: now.getTime() / 1000

  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  // ------------------------------------------------------------- battery

  readonly property var battery: UPower.displayDevice
  readonly property int batteryPercent: battery && battery.isPresent ? Math.round(Number(battery.percentage || 0) * 100) : -1
  readonly property bool charging: battery && battery.isPresent && !UPower.onBattery
    && battery.state === UPowerDeviceState.Charging
  // The dial shows the battery as one stripe from now, then a dashed one
  // after it. On battery: solid to the estimated empty time. Charging:
  // orange to full, then dashed for how long a full charge would last.
  // Plugged in and full: dashed for how long it would last from now. The
  // dashed runtimes use the median discharge rate of the last week
  // (UPower's rate history).
  readonly property string batteryMode: !battery || !battery.isPresent ? ""
    : (UPower.onBattery ? "discharging" : (charging ? "charging" : "estimate"))
  readonly property real batterySeconds: {
    if (batteryMode === "discharging") return Number(battery.timeToEmpty || 0)
    if (batteryMode === "charging") return Number(battery.timeToFull || 0)
    return 0
  }
  readonly property real batteryAfterSeconds: {
    if (dischargeWatts <= 0) return 0
    if (batteryMode === "charging") return Number(battery.energyCapacity || battery.energy || 0) / dischargeWatts * 3600
    if (batteryMode === "estimate") return Number(battery.energy || 0) / dischargeWatts * 3600
    return 0
  }
  property real dischargeWatts: 0

  Process {
    id: rateProc
    command: ["sh", "-c", "gdbus call --system --dest org.freedesktop.UPower"
      + " --object-path \"$(upower -e | grep -m1 /battery_)\""
      + " --method org.freedesktop.UPower.Device.GetHistory rate 604800 4000"]
    stdout: StdioCollector {
      onStreamFinished: {
        var w = Model.dischargeRate(text, Date.now() / 1000, 7)
        if (w > 0) root.dischargeWatts = w
      }
    }
  }

  Timer {
    interval: 600000
    running: root.shown && (root.batteryMode === "estimate" || root.batteryMode === "charging")
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!rateProc.running) rateProc.running = true
  }

  // ------------------------------------------------------------- weather

  property var location: null
  property string radarHost: ""
  property var radarFrames: []
  property var forecast: null
  property real radarFetchedAt: 0

  FileView {
    path: root.locationPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.location = Model.parseLocation(text())
      root.fetchForecast()
    }
  }

  // The shell does not use Qt's network stack; everything goes through curl
  // like the other plugins.
  Process {
    id: radarProc
    command: ["curl", "-fsS", "--max-time", "10", "https://api.rainviewer.com/public/weather-maps.json"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parsed = Model.parseRadarFrames(text)
        if (parsed.frames.length === 0) return
        root.radarHost = parsed.host
        root.radarFrames = parsed.frames
        root.radarFetchedAt = Date.now() / 1000
      }
    }
  }

  Process {
    id: forecastProc
    stdout: StdioCollector {
      onStreamFinished: {
        var f = Model.parseForecast(text)
        if (f) root.forecast = f
      }
    }
  }

  function fetchRadar() {
    if (!radarProc.running) radarProc.running = true
  }

  function fetchForecast() {
    if (!location || forecastProc.running) return
    forecastProc.command = ["curl", "-fsS", "--max-time", "10",
      "https://api.open-meteo.com/v1/forecast?latitude=" + location.lat + "&longitude=" + location.lon
      + "&minutely_15=precipitation&forecast_minutely_15=8&daily=sunrise,sunset"
      + "&timezone=auto&forecast_days=1&timeformat=unixtime"]
    forecastProc.running = true
  }

  // ------------------------------------------------------------ tile cache

  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/austraz-minimap"
  readonly property string fetchTiles: Qt.resolvedUrl("bin/fetch-tiles").toString().replace(/^[a-z]+:\/\//, "")
  property var tilesReady: ({})
  property var tileQueue: []
  property var tileBatch: ({})

  function requestTiles(list) {
    var queued = tileQueue.slice()
    var seen = ({})
    for (var i = 0; i < queued.length; i++) seen[queued[i].file] = true
    for (var j = 0; j < list.length; j++) {
      var t = list[j]
      if (tilesReady[t.file] || seen[t.file]) continue
      seen[t.file] = true
      queued.push(t)
    }
    tileQueue = queued
    pumpTiles()
  }

  function pumpTiles() {
    if (tileProc.running || tileQueue.length === 0) return
    var batch = tileQueue.slice(0, 64)
    tileQueue = tileQueue.slice(64)
    var args = [fetchTiles, cacheDir]
    for (var i = 0; i < batch.length; i++) args.push(batch[i].url, batch[i].file)
    tileBatch = ({})
    tileProc.command = args
    tileProc.running = true
  }

  Process {
    id: tileProc
    stdout: SplitParser {
      onRead: function(line) { root.tileBatch[line] = true }
    }
    onExited: {
      var next = ({})
      for (var k in root.tilesReady) next[k] = true
      for (var f in root.tileBatch) next[f] = true
      root.tilesReady = next
      root.pumpTiles()
    }
  }

  readonly property bool weatherActive: shown && shownMap === "weather"
  onWeatherActiveChanged: if (weatherActive && nowSec - radarFetchedAt > 300) fetchRadar()

  Timer {
    interval: 300000
    running: root.weatherActive
    repeat: true
    triggeredOnStart: true
    onTriggered: root.fetchRadar()
  }

  // Sunrise/sunset feed the dial whatever the map, so this one always runs;
  // more often while the rain alert watches the forecast.
  Timer {
    interval: root.cfg.rainAlert > 0 ? 300000 : 600000
    running: root.shown
    repeat: true
    onTriggered: root.fetchForecast()
  }

  // ------------------------------------------------------ workspace terrain

  property int revision: 0
  property var lastFocus: ({})
  // { session: { state, pids, address } }, fed by the `agent` IPC call.
  property var agents: ({})
  // Windows Hyprland flagged urgent, by normalized address.
  property var urgentAddresses: ({})

  function normalizeAddress(a) { return Model.normalizeAddress(a) }

  function ipcWindow(tl) {
    var ipc = tl.lastIpcObject || {}
    return {
      address: normalizeAddress(tl.address),
      appId: tl.wayland && tl.wayland.appId ? tl.wayland.appId : String(ipc["class"] || ""),
      title: String(tl.title || ""),
      // Right after a shell restart activeToplevel is unset until focus
      // moves; fall back to the Wayland activated flag like Spaces does.
      focused: Hyprland.activeToplevel ? Hyprland.activeToplevel === tl : !!(tl.wayland && tl.wayland.activated),
      floating: ipc.floating === true,
      at: ipc.at && ipc.at.length === 2 ? ipc.at : null,
      size: ipc.size && ipc.size.length === 2 ? ipc.size : null,
      pid: Number(ipc.pid) || 0,
      workspace: ipc.workspace ? Number(ipc.workspace.id) : (tl.workspace ? tl.workspace.id : 0),
      scratchpad: !!(ipc.workspace && ipc.workspace.name === "special:scratchpad")
    }
  }

  readonly property var allWindows: {
    root.revision
    var out = []
    var values = Hyprland.toplevels.values
    for (var i = 0; i < values.length; i++) out.push(ipcWindow(values[i]))
    return out
  }

  readonly property int currentWorkspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

  // When each workspace was last left (epoch seconds), so the arcs of
  // desks not visited for a while darken. Desks not seen since the shell
  // started count from then.
  property var deskVisits: ({})
  property int previousWorkspace: -1
  onCurrentWorkspaceChanged: {
    var next = ({})
    for (var k in deskVisits) next[k] = deskVisits[k]
    var t = Date.now() / 1000
    if (previousWorkspace !== -1) next[previousWorkspace] = t
    next[currentWorkspace] = t
    deskVisits = next
    previousWorkspace = currentWorkspace
    if (deskVisitsFile.loaded) deskVisitsFile.setText(JSON.stringify(next) + "\n")
    Qt.callLater(acknowledgeAgents)
  }

  // Kept across shell restarts.
  FileView {
    id: deskVisitsFile
    property bool loaded: false
    path: root.home + "/.local/state/austraz-minimap/desks.json"
    printErrors: false
    atomicWrites: true
    onLoaded: {
      var saved = ({})
      try { saved = JSON.parse(text() || "{}") || ({}) } catch (e) {}
      for (var k in root.deskVisits) saved[k] = root.deskVisits[k]
      root.deskVisits = saved
      loaded = true
    }
    onLoadFailed: loaded = true
  }

  readonly property var monitorRect: {
    root.revision
    var mon = Hyprland.focusedMonitor
    if (!mon) return null
    var ipc = mon.lastIpcObject || {}
    var scale = Number(mon.scale) || 1
    var w = mon.width / scale
    var h = mon.height / scale
    if (Number(ipc.transform) % 2 === 1) { var t = w; w = h; h = t }
    return { x: mon.x, y: mon.y, width: w, height: h }
  }

  readonly property real terrainSize: cfg.size - 2 * ringWidth - 2 * (bandWidth + bandGap)
  readonly property int bandWidth: 18
  readonly property int bandGap: 3

  readonly property var terrain: {
    var here = []
    for (var i = 0; i < allWindows.length; i++)
      if (allWindows[i].workspace === currentWorkspace) here.push(allWindows[i])
    var tiles = Model.discLayout(here, terrainSize, monitorRect)
    for (var j = 0; j < tiles.length; j++) tiles[j].icon = windowIcon(tiles[j])
    return { id: currentWorkspace, windows: tiles }
  }

  // App icon for a window class, resolved the way Spaces does it so both
  // show the same picture: desktop entry by id candidates, by
  // StartupWMClass, by Exec address for web apps, then Quickshell's
  // heuristic; the icon name goes through
  // an index of the icon files on disk (Qt's theme lookup misses
  // ~/.local/share/icons), then Quickshell. Cached per class.
  property var iconCache: ({})
  property var iconIndex: ({})
  property var pendingIconIndex: ({})

  function desktopEntryFor(appId) {
    var ids = Model.appIdCandidates(appId)
    for (var c = 0; c < ids.length; c++) {
      var byId = DesktopEntries.byId(ids[c])
      if (byId) return byId
    }
    var apps = DesktopEntries.applications.values
    for (var i = 0; i < apps.length; i++)
      if (String(apps[i].startupClass || "") === appId) return apps[i]
    // Web apps: the launcher whose Exec opens the window's address.
    var hint = Model.webAppHint(appId)
    if (hint) {
      var execs = []
      for (var j = 0; j < apps.length; j++) {
        var cmd = apps[j].command || []
        execs.push([String(apps[j].execString || "")].concat(Array.prototype.slice.call(cmd).map(String)).join(" "))
      }
      var at = Model.bestWebAppExecIndex(execs, hint)
      return at >= 0 ? apps[at] : null
    }
    return DesktopEntries.heuristicLookup(appId)
  }

  function iconUrl(name) {
    var value = String(name || "")
    if (value === "") return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    if (iconIndex[value]) return "file://" + iconIndex[value]
    return Quickshell.iconPath(value, true)
  }

  function appIcon(appId) {
    if (!appId) return ""
    if (iconCache[appId] !== undefined) return iconCache[appId]
    // Per-class icons from the config win (e.g. two accounts of one web app).
    var forced = cfg.iconOverrides[appId]
    if (forced) return iconCache[appId] = iconUrl(forced)
    var entry = desktopEntryFor(appId)
    var url = iconUrl(entry && entry.icon ? entry.icon : appId)
    if (!url) url = iconUrl(appId.split(".").pop().toLowerCase())
    iconCache[appId] = url || ""
    return iconCache[appId]
  }

  Process {
    id: iconScan
    command: ["bash", "-c", [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for base in $dirs; do [[ -d $base ]] && find "$base" -path "*/apps/*" \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null; done;',
      'find /usr/share/pixmaps -maxdepth 1 \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null'
    ].join(" ")]
    stdout: SplitParser {
      onRead: function(line) {
        var path = String(line || "").trim()
        if (!path) return
        var name = Model.iconNameFromPath(path)
        var have = root.pendingIconIndex[name]
        if (!have || Model.iconPathScore(path) > Model.iconPathScore(have)) root.pendingIconIndex[name] = path
      }
    }
    onStarted: root.pendingIconIndex = ({})
    onExited: {
      root.iconIndex = root.pendingIconIndex
      root.iconCache = ({})
      root.revision++
    }
  }

  // Browser windows: the current tab's favicon (bin/favicons.py, from
  // Spaces), else the app icon.
  property var faviconMap: ({})
  property int faviconMisses: 0

  function windowIcon(win) {
    if (Model.isBrowserWindow(win.appId)) {
      var fav = faviconMap[win.address]
      if (fav && fav.source) return iconUrl(fav.source)
    }
    return appIcon(win.appId)
  }

  Process {
    id: faviconQuery
    command: ["python3", Qt.resolvedUrl("bin/favicons.py").toString().replace(/^[a-z]+:\/\//, "")]
    stdout: StdioCollector {
      onStreamFinished: {
        var data = ({})
        try { data = JSON.parse(String(text || "{}")) || ({}) } catch (e) {}
        root.faviconMap = data
        root.revision++
        // Chromium writes the favicon a moment after the title: retry a few
        // times while some browser window still has none.
        var expected = 0, got = 0
        for (var i = 0; i < root.allWindows.length; i++) if (Model.isBrowserWindow(root.allWindows[i].appId)) expected++
        for (var k in data) if (data[k] && data[k].source) got++
        if (got < expected && root.faviconMisses < 3) { root.faviconMisses++; faviconRetry.restart() }
        else root.faviconMisses = 0
      }
    }
  }

  function startFaviconQuery() { if (!faviconQuery.running) faviconQuery.running = true }

  Timer { id: faviconDebounce; interval: 180; onTriggered: { root.faviconMisses = 0; root.startFaviconQuery() } }
  Timer { id: faviconRetry; interval: 2000; onTriggered: root.startFaviconQuery() }
  Timer { interval: 400; running: true; onTriggered: root.startFaviconQuery() }

  Component.onCompleted: iconScan.running = true

  Connections {
    target: DesktopEntries
    function onApplicationsChanged() { iconRescan.restart() }
  }

  Timer {
    id: iconRescan
    interval: 1500
    onTriggered: if (!iconScan.running) iconScan.running = true
  }

  // Agents, the same way Spaces tracks them (see Model.js, agents).
  readonly property real startedAt: Date.now() / 1000
  readonly property var markers: {
    var m = Model.agentWindowStates(agents, allWindows)
    // A finished turn always blinks a few times, even when it is seen at
    // once (in view, or acknowledged right away).
    var now = flashClock
    for (var address in doneFlashes)
      if (doneFlashes[address] > now && !m[address]) m[address] = "done"
    return m
  }

  // address → time (ms) until which a finished turn keeps blinking: three
  // quick blinks (0.7 s each, see WorkspaceMap.donePulse).
  readonly property int doneFlashMs: 3 * 700
  property var doneFlashes: ({})
  property real flashClock: Date.now()
  Timer {
    interval: 250
    running: Object.keys(root.doneFlashes).length > 0
    repeat: true
    onTriggered: {
      root.flashClock = Date.now()
      var next = ({}), left = false
      for (var a in root.doneFlashes) if (root.doneFlashes[a] > root.flashClock) { next[a] = root.doneFlashes[a]; left = true }
      if (Object.keys(next).length !== Object.keys(root.doneFlashes).length) root.doneFlashes = next
    }
  }

  function flashDone(agent) {
    var addresses = Model.agentAddresses(agent, Model.agentWindowsByPid(allWindows))
    if (!addresses.length) return
    var next = ({})
    for (var a in doneFlashes) next[a] = doneFlashes[a]
    var until = Date.now() + doneFlashMs
    for (var i = 0; i < addresses.length; i++) next[addresses[i]] = until
    flashClock = Date.now()
    doneFlashes = next
  }

  function activeAddress() {
    return Hyprland.activeToplevel ? normalizeAddress(Hyprland.activeToplevel.address) : ""
  }

  // An agent is in view when one of its windows is focused or on the
  // workspace on screen.
  function agentInView(agent) {
    var addresses = Model.agentAddresses(agent, Model.agentWindowsByPid(allWindows))
    if (!addresses.length) return false
    var active = activeAddress()
    for (var i = 0; i < addresses.length; i++) {
      if (addresses[i] === active) return true
      for (var w = 0; w < allWindows.length; w++) {
        var win = allWindows[w]
        if (win.address !== addresses[i]) continue
        if (win.workspace === currentWorkspace || (win.scratchpad && scratchpadShown)) return true
      }
    }
    return false
  }

  property string lastActiveEvent: ""

  // The scratchpad (special:scratchpad) is on screen.
  property bool scratchpadShown: false
  onScratchpadShownChanged: Qt.callLater(acknowledgeAgents)

  // Desk of an agent's window: the smallest numbered one, the scratchpad
  // (negative id) only if nothing else, as in Spaces.
  function smallerDesk(a, b) {
    if (!a) return b
    if (!b) return a
    if (a > 0 && b > 0) return a < b ? a : b
    if (a > 0) return a
    if (b > 0) return b
    return a > b ? a : b
  }

  function deskForAgent(agent) {
    var addresses = Model.agentAddresses(agent, Model.agentWindowsByPid(allWindows))
    var best = 0
    for (var i = 0; i < addresses.length; i++)
      for (var w = 0; w < allWindows.length; w++)
        if (allWindows[w].address === addresses[i] && allWindows[w].workspace !== 0) best = smallerDesk(best, allWindows[w].workspace)
    return best
  }

  // Alerts not in view: waiting first, then done. Drives the LEDs and
  // Super+Caps Lock (focusAlert).
  function alertDesk() {
    var waiting = 0, done = 0
    for (var k in agents) {
      var agent = agents[k]
      if (!agent || agentInView(agent)) continue
      var ws = deskForAgent(agent)
      if (!ws) continue
      if (agent.state === "waiting") waiting = smallerDesk(waiting, ws)
      else if (agent.state === "done") done = smallerDesk(done, ws)
    }
    return waiting || done
  }

  function focusWorkspace(id) {
    // Hyprland here takes Lua dispatches (hl.dsp.*), as Spaces sends them;
    // the classic "workspace N" form is rejected.
    var target = id < 0 ? "special:scratchpad" : String(id)
    Hyprland.dispatch('hl.dsp.focus({ workspace = "' + target + '" })')
  }

  function focusAlert() {
    var id = alertDesk()
    if (!id) return false
    focusWorkspace(id)
    return true
  }

  // Caps Lock and the fingerprint ring: blink while a waiting agent is out
  // of view, stay lit while a done one is, off otherwise.
  readonly property string ledMode: {
    root.revision
    var waiting = false, done = false
    for (var k in agents) {
      var agent = agents[k]
      if (!agent) continue
      if (!Model.agentAddresses(agent, Model.agentWindowsByPid(allWindows)).length) continue
      if (agentInView(agent)) continue
      if (agent.state === "waiting") waiting = true
      else if (agent.state === "done") done = true
    }
    return waiting ? "blink" : (done ? "on" : "off")
  }
  // Each call to alert-leds writes the wanted mode, and calls launched in
  // the same instant may land in any order; so changes are coalesced and only
  // the settled mode is sent. Also sent once at start to fix a stale LED.
  onLedModeChanged: ledSync.restart()
  Timer {
    id: ledSync
    interval: 150
    running: true
    onTriggered: Quickshell.execDetached([Qt.resolvedUrl("bin/alert-leds").toString().replace(/^[a-z]+:\/\//, ""), root.ledMode])
  }

  // Workspace numbers while Super is held (bound like Spaces' showNumbers).
  property bool numbersShown: false

  function applyAgent(session, state, pidsCsv) {
    var next = ({})
    for (var k in agents) if (k !== session) next[k] = agents[k]
    if (state === "end") { agents = next; return }
    var reported = Model.normalizeAgentState(state)
    if (!reported) return
    var pids = Model.parsePids(pidsCsv)
    var prev = agents[session]
    // Keep the window the agent was pinned to while it still exists, so a
    // single-instance terminal does not spill the badge onto its siblings.
    var address = prev && prev.address ? prev.address : ""
    if (address && !allWindows.some(function(w) { return w.address === address })) address = ""
    if (!address) address = Model.agentPinAddress(pids, allWindows, activeAddress())
    var agent = { state: reported, pids: pids, address: address }
    // Finishing on the desk you are looking at needs no done blink.
    if (reported === "done" && !(prev && prev.state === "done")) flashDone(agent)
    if (reported === "done" && agentInView(agent)) agent.state = "idle"
    next[session] = agent
    agents = next
  }

  // Seeing a finished agent's window or desk clears its blink.
  function acknowledgeAgents() {
    var changed = false, next = ({})
    for (var k in agents) {
      var agent = agents[k]
      if (agent.state === "done" && agentInView(agent)) {
        agent = { state: "idle", pids: agent.pids, address: agent.address }
        changed = true
      }
      next[k] = agent
    }
    if (changed) agents = next
  }

  function setUrgent(address, urgent) {
    var key = normalizeAddress(address)
    if (key === "" || (!!urgentAddresses[key]) === urgent) return
    var next = ({})
    for (var k in urgentAddresses) if (k !== key) next[k] = true
    if (urgent) next[key] = true
    urgentAddresses = next
  }

  // A crashed reporter never sends "end": once a minute, drop working or
  // waiting claims whose agent process is gone.
  property var liveAgentPids: ({})
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      var pids = Model.agentProcessIds(root.agents)
      if (!pids.length || agentProbe.running) return
      root.liveAgentPids = ({})
      agentProbe.command = ["sh", "-c", "for p in \"$@\"; do [ -d /proc/$p ] && echo $p; done; echo probed", "sh"].concat(pids.map(String))
      agentProbe.running = true
    }
  }
  Process {
    id: agentProbe
    stdout: SplitParser {
      onRead: function(line) {
        var text = String(line || "").trim()
        if (text === "probed") root.agents = Model.pruneDeadAgents(root.agents, Object.keys(root.liveAgentPids))
        else if (Number(text) > 1) root.liveAgentPids[text] = true
      }
    }
  }

  // The other occupied workspaces, as arcs around the disc (the current one
  // is the disc itself).
  readonly property var workspaceArcs: {
    root.revision
    var byId = ({})
    for (var i = 0; i < allWindows.length; i++) {
      var w = allWindows[i]
      if (w.workspace === 0 || w.workspace === currentWorkspace) continue
      if (w.workspace < 0 && !w.scratchpad) continue
      if (!byId[w.workspace]) byId[w.workspace] = { id: w.workspace, apps: [], addresses: [], icons: [] }
      byId[w.workspace].apps.push(w.appId.split(".").pop())
      byId[w.workspace].addresses.push(w.address)
      // One icon per app, in window order.
      var icon = windowIcon(w)
      if (icon && byId[w.workspace].icons.indexOf(icon) === -1) byId[w.workspace].icons.push(icon)
    }
    var list = []
    for (var id in byId) {
      var ws = byId[id]
      // Like Spaces: a waiting agent or a Hyprland-urgent window makes the
      // desk urgent (red), a finished agent makes it done (accent).
      var st = Model.strongestState(ws.addresses, markers)
      if (st !== "waiting" && ws.addresses.some(function(a) { return root.urgentAddresses[a] })) st = "waiting"
      list.push({ id: ws.id, current: ws.id === currentWorkspace, count: ws.addresses.length,
        apps: ws.apps, icons: ws.icons, state: st })
    }
    // Numbered desks in order, the scratchpad last.
    list.sort(function(a, b) { return (a.id < 0) - (b.id < 0) || a.id - b.id })
    return Model.workspaceArcs(list, 4)
  }

  // Sends a window to another workspace without following it; the
  // scratchpad arc (negative id) is the special workspace.
  function moveWindow(address, workspace) {
    var target = workspace < 0 ? '"special:scratchpad"' : String(workspace)
    Hyprland.dispatch("hl.dsp.window.move({ workspace = " + target + ', window = "address:0x'
      + normalizeAddress(address) + '", follow = false })')
    refreshDebounce.restart()
  }

  function focusWindow(address) {
    Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + normalizeAddress(address) + '" })')
  }

  function noteFocus() {
    var active = Hyprland.activeToplevel
    if (!active) return
    var next = ({})
    for (var k in lastFocus) next[k] = lastFocus[k]
    next[normalizeAddress(active.address)] = Date.now() / 1000
    lastFocus = next
  }

  Timer {
    id: refreshDebounce
    interval: 120
    onTriggered: {
      Hyprland.refreshToplevels()
      Hyprland.refreshMonitors()
      root.revision++
    }
  }

  // ------------------------------------------------------- auto compact
  //
  // With autoCompact on, a gap between workspaces (a desk emptied, a window
  // moved away) renumbers them 1..n, like Super+Shift+Backspace on an empty
  // desk. Two passes through temporary ids so no change hits a used id.

  Timer {
    id: compactDebounce
    interval: 400
    onTriggered: if (root.cfg.autoCompact && !compactQuery.running) compactQuery.running = true
  }

  Process {
    id: compactQuery
    command: ["hyprctl", "workspaces", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        var list = []
        try { list = JSON.parse(String(text || "[]")) } catch (e) { return }
        if (!root.cfg.autoCompact) return
        var plan = Model.compactionPlan(list)
        if (!plan.length) return
        var i
        for (i = 0; i < plan.length; i++)
          Hyprland.dispatch("hl.dsp.workspace.change_id({ workspace = " + plan[i].from + ", id = " + (10000 + plan[i].from) + " })")
        for (i = 0; i < plan.length; i++)
          Hyprland.dispatch("hl.dsp.workspace.change_id({ workspace = " + (10000 + plan[i].from) + ", id = " + plan[i].to + " })")
        // Desk visit times follow their desk to its new number.
        var visits = ({})
        for (var k in root.deskVisits) visits[k] = root.deskVisits[k]
        for (i = 0; i < plan.length; i++) delete visits[plan[i].to]
        for (i = 0; i < plan.length; i++)
          if (root.deskVisits[plan[i].from] !== undefined) visits[plan[i].to] = root.deskVisits[plan[i].from]
        root.deskVisits = visits
        refreshDebounce.restart()
      }
    }
  }
  onCfgChanged: if (cfg.autoCompact) compactDebounce.restart()

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() { root.noteFocus(); Qt.callLater(root.acknowledgeAgents) }
    function onRawEvent(event) {
      if (root.cfg.autoCompact && ["closewindow", "movewindow", "movewindowv2", "destroyworkspace",
          "destroyworkspacev2", "workspace", "workspacev2"].indexOf(event.name) !== -1)
        compactDebounce.restart()
      switch (event.name) {
      case "urgent":
        root.setUrgent(event.data, true)
        break
      case "activewindowv2":
        // Hyprland re-sends this on every title change of the focused
        // window, so only a real focus change hides held numbers.
        if (event.data !== root.lastActiveEvent) root.numbersShown = false
        root.lastActiveEvent = event.data
        root.setUrgent(event.data, false)
        refreshDebounce.restart()
        break
      case "activespecial":
      case "activespecialv2":
        root.scratchpadShown = String(event.data).indexOf("special:scratchpad") !== -1
        refreshDebounce.restart()
        break
      case "closewindow":
        root.numbersShown = false
        root.setUrgent(event.data, false)
        refreshDebounce.restart()
        faviconDebounce.restart()
        break
      case "windowtitle":
      case "windowtitlev2":
        faviconDebounce.restart()
        break
      case "openwindow":
        root.numbersShown = false
        faviconDebounce.restart()
        refreshDebounce.restart()
        break
      case "openlayer":
        // Like Spaces: anything that moves the view drops held numbers, as the
        // Super release may never reach us after a Super+key chord.
        root.numbersShown = false
        break
      case "fullscreen":
        Hyprland.refreshWorkspaces()
        refreshDebounce.restart()
        break
      case "workspace":
      case "workspacev2":
        root.numbersShown = false
        refreshDebounce.restart()
        break
      case "movewindow":
      case "movewindowv2":
      case "changefloatingmode":
      case "focusedmon":
      case "fullscreen":
        refreshDebounce.restart()
        break
      }
    }
  }

  // The workspace map stays on screen around every other map.
  readonly property bool workspaceActive: shown && hasWorkspaceMap

  // Tiles resize without a dedicated event (a neighbour opens, a split
  // moves), so poll while the terrain is on screen.
  Timer {
    interval: 2000
    running: root.workspaceActive
    repeat: true
    triggeredOnStart: true
    onTriggered: refreshDebounce.restart()
  }

  // --------------------------------------------------------------- window

  readonly property int ringWidth: 22   // dial 8 + gap 3 + battery 8 + gap 3
  readonly property var targetScreen: {
    var screens = Quickshell.screens
    var want = cfg.monitor || (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
    for (var i = 0; i < screens.length; i++) if (screens[i].name === want) return screens[i]
    return screens.length ? screens[0] : null
  }

  // ------------------------------------------------------------- maps
  //
  // Each folder under maps/ holding a map.json is a map: its entry QML is
  // loaded into the disc with `minimap` (this object) as its only required
  // property. bin/list-maps reads them; rescanned whenever the list opens.

  property var maps: []
  readonly property bool hovered: hover.hovered
  // The configured map, or the first one when it is not installed.
  readonly property string mapId: {
    for (var i = 0; i < maps.length; i++) if (maps[i].id === cfg.map) return cfg.map
    return maps.length ? maps[0].id : cfg.map
  }

  Process {
    id: mapScan
    command: ["python3", "-I", Qt.resolvedUrl("bin/list-maps").toString().replace(/^[a-z]+:\/\//, "")]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var list = JSON.parse(String(text || "[]"))
          if (Array.isArray(list) && JSON.stringify(list) !== JSON.stringify(root.maps)) root.maps = list
        } catch (e) { console.warn("minimap: bad map list", e) }
      }
    }
  }
  function scanMaps() { if (!mapScan.running) mapScan.running = true }

  // ------------------------------------------------------ notifications
  //
  // A map calls minimap.notify(this, duration, persistent) to be shown
  // over the chosen one.
  // - Temporary: shown for `duration` (default 5 s), in turn; while others
  //   wait behind it, 2 s. Asked again while showing, its time restarts.
  // - Persistent: it waits for the user and stays until the map calls
  //   release(this). They pile up: the latest is shown; once released, the
  //   one under it comes back, and so on. Temporaries show over them, all
  //   of them, then the top persistent one comes back.
  // Every change of what the disc shows turns it over like a coin: right
  // to left in a right corner, left to right in a left one, and the other
  // way when it comes back to the chosen map.

  property var tempQueue: []       // [{ id, duration }], the first on screen
  property var persistStack: []    // map ids, the latest last
  property real tempStart: 0
  readonly property string notifyingId: tempQueue.length ? tempQueue[0].id
    : (persistStack.length ? persistStack[persistStack.length - 1] : "")
  readonly property string targetMap: notifyingId !== "" ? notifyingId : mapId
  property string shownMap: ""
  property real flip: 0
  property int flipDir: 1

  function mapIdOf(source) {
    if (typeof source === "string") return source
    for (var i = 0; i < mapLoaders.count; i++) {
      var l = mapLoaders.itemAt(i)
      if (l && l.item === source) return l.modelData.id
    }
    return ""
  }

  function notify(source, duration, persistent) {
    var id = mapIdOf(source)
    if (id === "" || !shown) return
    if (persistent) {
      persistStack = persistStack.filter(function(x) { return x !== id }).concat([id])
      return
    }
    var d = duration > 0 ? duration : 5000
    var q = tempQueue.slice()
    for (var i = 0; i < q.length; i++) {
      if (q[i].id !== id) continue
      q[i] = { id: id, duration: d }
      tempQueue = q
      if (i === 0) tempStart = Date.now()
      return
    }
    if (!q.length) tempStart = Date.now()
    tempQueue = q.concat([{ id: id, duration: d }])
  }

  // The map's persistent notification is settled.
  function release(source) {
    var id = mapIdOf(source)
    persistStack = persistStack.filter(function(x) { return x !== id })
  }

  Timer {
    interval: 100
    running: root.tempQueue.length > 0
    repeat: true
    onTriggered: {
      var q = root.tempQueue
      if (Date.now() - root.tempStart < (q.length > 1 ? 2000 : q[0].duration)) return
      root.tempQueue = q.slice(1)
      root.tempStart = Date.now()
    }
  }

  onTargetMapChanged: {
    if (shownMap === "") { shownMap = targetMap; return }
    // Towards the screen's interior going out, back the other way.
    var out = cornerRight ? -1 : 1
    flipDir = notifyingId !== "" ? out : -out
    if (!flipAnim.running) flipAnim.start()
  }

  SequentialAnimation {
    id: flipAnim
    NumberAnimation { target: root; property: "flip"; from: 0; to: 90; duration: 230; easing.type: Easing.InQuad }
    ScriptAction { script: root.shownMap = root.targetMap }
    NumberAnimation { target: root; property: "flip"; from: -90; to: 0; duration: 230; easing.type: Easing.OutQuad }
    onFinished: if (root.shownMap !== root.targetMap) flipAnim.start()
  }

  readonly property bool hasWorkspaceMap: {
    for (var i = 0; i < maps.length; i++) if (maps[i].id === "workspace") return true
    return false
  }

  function setMap(name) {
    for (var i = 0; i < maps.length; i++) if (maps[i].id === name) { saveConfig({ map: name }); return }
  }
  function setZoom(z) { saveConfig({ zoom: Math.max(Model.MIN_ZOOM, Math.min(Model.MAX_ZOOM, z)) }) }

  // ------------------------------------------------------------- cutout
  //
  // The minimap does not sit on the window under it: a ring as wide as
  // Hyprland's gaps_out shows the wallpaper around the disc, as if the disc
  // were cut out of that window, and the disc keeps that same distance from
  // the screen edges.

  property int gapsOut: 10
  property int borderSize: 2
  property color activeBorder: "#7aa2f7"
  property color inactiveBorder: "#aa595959"
  property string wallpaper: ""
  readonly property int ring: cfg.cutout ? gapsOut : 0
  readonly property int discMargin: cfg.margin < 0 ? gapsOut : cfg.margin
  readonly property int windowMargin: Math.max(0, discMargin - ring)
  // Radius of the cut: the disc plus the wallpaper ring. The window's
  // border is drawn just outside it, so the window gets that much room on
  // its inner sides.
  readonly property real cutR: cfg.size / 2 + ring
  readonly property int borderRoom: ring > 0 ? borderSize : 0
  readonly property int windowSize: cfg.size + 2 * ring + borderRoom
  readonly property bool cornerRight: cfg.corner.indexOf("right") !== -1
  readonly property bool cornerBottom: cfg.corner.indexOf("bottom") === 0
  // Disc centre in window coordinates: cutR from the anchored edges.
  readonly property real cx: cornerRight ? windowSize - cutR : cutR
  readonly property real cy: cornerBottom ? windowSize - cutR : cutR

  // Hyprland's outer gap and window borders: "css" gives the gap per side,
  // borders are "AARRGGBB ... angle" gradients (the first colour is used).
  Process {
    id: gapsQuery
    command: ["sh", "-c", "for o in general:gaps_out general:border_size general:col.active_border general:col.inactive_border; do hyprctl getoption \"$o\" -j | tr -d '\\n'; echo; done"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var o = JSON.parse(line)
          if (o.option === "general:gaps_out") {
            var v = o.css !== undefined ? parseInt(String(o.css), 10) : parseInt(o.int, 10)
            if (!isNaN(v) && v >= 0) root.gapsOut = v
          } else if (o.option === "general:border_size") {
            if (o.int >= 0) root.borderSize = o.int
          } else if (o.gradient) {
            var hex = String(o.gradient).split(" ")[0]
            if (/^[0-9a-fA-F]{8}$/.test(hex)) {
              if (o.option === "general:col.active_border") root.activeBorder = "#" + hex
              else root.inactiveBorder = "#" + hex
            }
          }
        } catch (e) {}
      }
    }
  }

  // The window the minimap is cut out of: the one under the disc centre on
  // the current workspace, the focused one first.
  readonly property var underWindow: {
    var o = windowOrigin
    var px = o.mx + o.x + cx, py = o.my + o.y + cy
    var best = null
    for (var i = 0; i < allWindows.length; i++) {
      var w = allWindows[i]
      if (w.workspace !== currentWorkspace || !w.at || !w.size) continue
      if (px < w.at[0] || py < w.at[1] || px > w.at[0] + w.size[0] || py > w.at[1] + w.size[1]) continue
      if (!best || w.focused) best = w
    }
    return best
  }

  // Follows Omarchy's current background (a symlink that theme and
  // background switches repoint).
  Process {
    id: wallpaperQuery
    command: ["readlink", "-f", root.home + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector { onStreamFinished: { var p = text.trim(); if (p) root.wallpaper = "file://" + p } }
  }
  Timer {
    interval: 10000
    running: root.shown && root.cfg.cutout
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!wallpaperQuery.running) wallpaperQuery.running = true
  }

  // Over the bar the minimap lives on the overlay layer, which also covers
  // fullscreen windows: it steps aside while the workspace has one.
  readonly property bool fullscreenHere: {
    root.revision
    var ws = Hyprland.focusedWorkspace
    if (!ws) return false
    if (ws.hasFullscreen !== undefined) return ws.hasFullscreen
    return !!(ws.lastIpcObject && ws.lastIpcObject.hasfullscreen)
  }

  // Where the window sits on its screen, to line the wallpaper up with the
  // real one: anchored edges, minus the zones other layers reserve (bar),
  // unless it sits over the bar.
  readonly property var windowOrigin: {
    root.revision
    var scr = targetScreen
    if (!scr) return { x: 0, y: 0, w: 0, h: 0 }
    var reserved = [0, 0, 0, 0]
    var mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++) {
      if (mons[i].name !== scr.name) continue
      var r = mons[i].lastIpcObject ? mons[i].lastIpcObject.reserved : null
      if (r && r.length === 4 && !cfg.overBar) reserved = r
    }
    var left = cfg.corner.indexOf("left") !== -1
    var top = cfg.corner.indexOf("top") === 0
    var mx = 0, my = 0
    for (var j = 0; j < mons.length; j++) if (mons[j].name === scr.name) { mx = mons[j].x; my = mons[j].y }
    return {
      x: left ? reserved[0] + windowMargin : scr.width - reserved[2] - windowMargin - windowSize,
      y: top ? reserved[1] + windowMargin : scr.height - reserved[3] - windowMargin - windowSize,
      w: scr.width, h: scr.height, mx: mx, my: my
    }
  }

  // ------------------------------------------------------------- peek
  //
  // System OSDs (volume, brightness, microphone…) forwarded by the audio
  // plugin: shown over the middle circle, without turning the coin, while
  // the disc is on screen. Otherwise the answer is "off" and the OSD shows
  // its own card.
  property var osd: ({})            // { icon, message, value, max, hasProgress, duration }
  property bool osdOpen: false
  function showOsd(json) {
    if (!win.visible || peeking) return false
    try { osd = JSON.parse(json || "{}") } catch (e) { return false }
    osdOpen = true
    var d = osd.duration === undefined ? 1200 : Number(osd.duration)
    if (d > 0) { osdTimer.interval = d; osdTimer.restart() }
    else osdTimer.stop()
    return true
  }
  Timer { id: osdTimer; onTriggered: root.osdOpen = false }

  // Shift while hovering hides the minimap (input passes straight through,
  // the picture fades out) so the corner of the window under it can be
  // clicked. It comes back once the pointer leaves its square; with no
  // input the panel cannot see that, so the cursor is polled meanwhile.

  property bool peeking: false
  property real veil: peeking ? 0 : 1
  Behavior on veil { NumberAnimation { duration: 320; easing.type: Easing.InOutCubic } }

  function peek() {
    mapMenu.open = false
    settingsPop.open = false
    peeking = true
  }

  // The panel has no keyboard focus, so Qt never sees Shift: ask Hyprland
  // (xkb keycodes 50 and 62, the two Shifts) while the pointer is over it.
  Timer {
    interval: 120
    running: root.hovered && !root.peeking
    repeat: true
    onTriggered: if (!shiftQuery.running) shiftQuery.running = true
  }
  Process {
    id: shiftQuery
    command: ["hyprctl", "repl", "return hl.is_key_down(50) or hl.is_key_down(62)"]
    stdout: StdioCollector {
      onStreamFinished: if (String(text).trim() === "true" && root.hovered) root.peek()
    }
  }

  Timer {
    interval: 150
    running: root.peeking
    repeat: true
    onTriggered: if (!cursorQuery.running) cursorQuery.running = true
  }
  Process {
    id: cursorQuery
    command: ["hyprctl", "cursorpos", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var c = JSON.parse(String(text || "{}"))
          var o = root.windowOrigin
          var x = c.x - o.mx - o.x, y = c.y - o.my - o.y
          if (x < 0 || y < 0 || x > root.windowSize || y > root.windowSize) root.peeking = false
        } catch (e) {}
      }
    }
  }

  PanelWindow {
    id: win
    screen: root.targetScreen
    visible: root.shown && root.targetScreen !== null && !(root.cfg.overBar && root.fullscreenHere)
    color: "transparent"
    implicitWidth: root.windowSize
    implicitHeight: root.windowSize

    anchors {
      top: root.cfg.corner.indexOf("top") === 0
      bottom: root.cfg.corner.indexOf("bottom") === 0
      left: root.cfg.corner.indexOf("left") !== -1
      right: root.cfg.corner.indexOf("right") !== -1
    }
    margins {
      top: root.windowMargin
      bottom: root.windowMargin
      left: root.windowMargin
      right: root.windowMargin
    }

    WlrLayershell.namespace: "austraz-minimap"
    WlrLayershell.layer: root.cfg.overBar ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: root.cfg.overBar ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: 0

    // Only the disc and the selector take input; the rest stays click-through.
    // While peeking under it, nothing takes input.
    mask: Region {
      item: root.peeking ? null : disc
      shape: RegionShape.Ellipse
    }

    // Iris: peeking closes the whole minimap into its centre and opening
    // grows it back out, with a thin accent ring on the moving edge.
    Item {
      id: iris
      anchors.fill: parent
      readonly property real radius: (root.cutR + root.borderSize + 1) * root.veil
      layer.enabled: root.veil < 1
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: irisMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }

      // The wallpaper ring, under the disc.
      Item {
        id: cutout
        visible: root.ring > 0 && root.wallpaper !== ""
        anchors.fill: parent
        layer.enabled: visible
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: cutoutMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1.0
        }

        Image {
          x: -root.windowOrigin.x
          y: -root.windowOrigin.y
          width: root.windowOrigin.w
          height: root.windowOrigin.h
          source: root.wallpaper
          fillMode: Image.PreserveAspectCrop
          sourceSize.width: root.windowOrigin.w * (root.targetScreen ? root.targetScreen.devicePixelRatio : 1)
          asynchronous: true
          cache: true
          smooth: true
        }
      }

      // The cut: the disc plus the ring, and the window's corner on the side
      // the minimap sits, from the disc centre out to that corner.
      Item {
        id: cutoutMask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle {
          x: root.cx - root.cutR; y: root.cy - root.cutR
          width: 2 * root.cutR; height: width
          radius: width / 2
          color: "black"
        }
        Rectangle {
          x: root.cornerRight ? root.cx : 0
          y: root.cornerBottom ? root.cy : 0
          width: root.cornerRight ? parent.width - root.cx : root.cx
          height: root.cornerBottom ? parent.height - root.cy : root.cy
          color: "black"
        }
      }

      // The cut window's border, carried around the cut: active colour when
      // it has focus, inactive otherwise, only where that window really is
      // (its border box) and not across the masked corner.
      Item {
        id: cutBorder
        readonly property var w: root.underWindow
        visible: root.ring > 0 && w !== null
        x: w ? w.at[0] - root.borderSize - root.windowOrigin.mx - root.windowOrigin.x : 0
        y: w ? w.at[1] - root.borderSize - root.windowOrigin.my - root.windowOrigin.y : 0
        width: w ? w.size[0] + 2 * root.borderSize : 0
        height: w ? w.size[1] + 2 * root.borderSize : 0
        clip: true

        Shape {
          x: -cutBorder.x; y: -cutBorder.y
          width: win.width; height: win.height
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeColor: cutBorder.w && cutBorder.w.focused ? root.activeBorder : root.inactiveBorder
            strokeWidth: root.borderSize
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathAngleArc {
              centerX: root.cx; centerY: root.cy
              radiusX: root.cutR + root.borderSize / 2; radiusY: radiusX
              // Skip the quarter facing the screen corner (masked).
              startAngle: root.cornerRight ? (root.cornerBottom ? 90 : 0) : (root.cornerBottom ? 180 : 270)
              sweepAngle: 270
            }
          }
        }
      }

      Item {
        id: disc
        x: root.cx - width / 2
        y: root.cy - height / 2
        width: root.cfg.size
        height: root.cfg.size
        opacity: (hover.hovered || mapMenu.open || settingsPop.open ? 1 : root.cfg.opacity)

        Behavior on opacity { enabled: !root.peeking; NumberAnimation { duration: 200 } }

        HoverHandler { id: hover }

        // Right-click anywhere on the minimap opens its settings.
        TapHandler {
          acceptedButtons: Qt.RightButton
          onTapped: { mapMenu.open = false; settingsPop.toggle() }
        }

        readonly property real mapSize: width - 2 * root.ringWidth

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: Color.background
        }

        Item {
          id: content
          x: root.ringWidth
          y: root.ringWidth
          width: disc.mapSize
          height: disc.mapSize
          layer.enabled: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: circleMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
          }

          // Every map stays loaded so it can watch things and ask for a
          // notification. The workspace map is always there on the whole
          // disc, so the other desks stay in view around whatever is shown;
          // any other map is drawn over it in the middle circle, inside the
          // band, and that circle is what turns over like a coin.
          Repeater {
            id: mapLoaders
            model: root.maps
            delegate: Loader {
              id: mapLoader
              required property var modelData
              readonly property bool band: modelData.id === "workspace"
              readonly property real inset: band || !root.hasWorkspaceMap ? 0 : root.bandWidth + root.bandGap
              x: inset; y: inset
              width: content.width - 2 * inset
              height: width
              z: band ? 0 : 1
              visible: band || root.shownMap === modelData.id
              transform: Rotation {
                origin.x: mapLoader.width / 2
                origin.y: mapLoader.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: mapLoader.band && root.hasWorkspaceMap ? 0 : root.flip * root.flipDir
              }
              layer.enabled: !band
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: innerMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
              }
              Component.onCompleted: setSource(modelData.url, { minimap: root })
              onStatusChanged: if (status === Loader.Error) console.warn("minimap: map failed to load:", modelData.url)
            }
          }

          // The coin's shading: the face turning away darkens.
          Rectangle {
            readonly property real inset: root.hasWorkspaceMap && root.shownMap !== "workspace"
              ? root.bandWidth + root.bandGap : 0
            z: 2
            x: inset; y: inset
            width: content.width - 2 * inset
            height: width
            radius: width / 2
            color: "black"
            // The workspace map itself never turns: nothing to shade then.
            visible: !(root.hasWorkspaceMap && root.shownMap === "workspace")
            opacity: 0.55 * Math.sin(Math.abs(root.flip) * Math.PI / 180)
          }


          // A system OSD on the middle circle: the level as a ring with a
          // big readout, or a glyph over a message.
          Item {
            id: osdFace
            readonly property real inset: root.hasWorkspaceMap ? root.bandWidth + root.bandGap : 0
            readonly property real max: Math.max(1, Number(root.osd.max) || 100)
            readonly property real value: Number(root.osd.value) || 0
            readonly property bool progress: !!root.osd.hasProgress
            readonly property bool overdriven: progress && max > 100 && value > 100
            property real level: progress ? Math.max(0, Math.min(1, value / max)) : 0
            Behavior on level { enabled: osdFace.opacity === 1; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            z: 3
            x: inset; y: inset
            width: content.width - 2 * inset
            height: width
            opacity: root.osdOpen ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 140 } }

            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: Color.background
            }

            Shape {
              anchors.fill: parent
              visible: osdFace.progress
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                strokeColor: Qt.alpha(Color.foreground, 0.15)
                strokeWidth: 8
                fillColor: "transparent"
                PathAngleArc {
                  centerX: osdFace.width / 2; centerY: osdFace.height / 2
                  radiusX: osdFace.width / 2 - 4; radiusY: radiusX
                  startAngle: -90; sweepAngle: 360
                }
              }
              ShapePath {
                strokeColor: osdFace.overdriven ? Color.urgent : Color.accent
                strokeWidth: 8
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathAngleArc {
                  centerX: osdFace.width / 2; centerY: osdFace.height / 2
                  radiusX: osdFace.width / 2 - 4; radiusY: radiusX
                  startAngle: -90; sweepAngle: 360 * osdFace.level
                }
              }
              // The real 100 % when the scale goes past it (volume overdrive).
              ShapePath {
                strokeColor: osdFace.max > 100 ? Color.foreground : "transparent"
                strokeWidth: 12
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathAngleArc {
                  centerX: osdFace.width / 2; centerY: osdFace.height / 2
                  radiusX: osdFace.width / 2 - 4; radiusY: radiusX
                  startAngle: -90 + 360 * 100 / osdFace.max - 1; sweepAngle: 2
                }
              }
            }

            Column {
              anchors.centerIn: parent
              width: parent.width * 0.7
              spacing: osdFace.width * 0.02
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: root.osd.icon || ""
                color: Color.foreground
                font.family: Style.fontFamily
                font.pixelSize: osdFace.width * (osdFace.progress ? 0.2 : 0.26)
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                visible: text !== ""
                text: root.osd.message || ""
                color: Color.foreground
                font.family: Style.fontFamily
                font.bold: true
                font.pixelSize: osdFace.width * (osdFace.progress ? 0.17 : 0.09)
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }
            }
          }

          Item {
            id: innerMask
            width: content.width - 2 * (root.hasWorkspaceMap ? root.bandWidth + root.bandGap : 0)
            height: width
            layer.enabled: true
            visible: false
            Rectangle { anchors.fill: parent; radius: width / 2; color: "black" }
          }
        }

        Item {
          id: circleMask
          width: content.width
          height: content.height
          layer.enabled: true
          visible: false
          Rectangle { anchors.fill: parent; radius: width / 2; color: "black" }
        }

        Rectangle {
          x: content.x - 0.5; y: content.y - 0.5
          width: content.width + 1; height: content.height + 1
          radius: width / 2
          color: "transparent"
          border.width: 1
          border.color: Qt.alpha(Color.foreground, 0.25)
        }

        Rim {
          anchors.fill: parent
          ringWidth: root.ringWidth
          now: root.now
          daylight: root.forecast ? Model.daylightArc(root.forecast.sunrise, root.forecast.sunset) : null
          daytime: Model.isDaytime(root.nowSec, root.forecast ? root.forecast.sunrise : 0, root.forecast ? root.forecast.sunset : 0)
          battery: root.batteryPercent
          batterySeconds: root.batterySeconds
          batteryAfterSeconds: root.batteryAfterSeconds
          batteryMode: root.batteryMode
        }

        // Clock, WoW-style, on the bottom of the ring. Hidden in the
        // settings, it still comes up on hover: it opens the map list.
        Rectangle {
          opacity: root.cfg.clock || hover.hovered || mapMenu.open ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: 150 } }
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          width: clock.implicitWidth + 12
          height: clock.implicitHeight + 2
          radius: height / 2
          color: Color.background
          border.width: 1
          border.color: mapMenu.open ? Color.accent : Qt.alpha(Color.foreground, 0.25)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { settingsPop.open = false; mapMenu.toggle() }
          }

          Text {
            id: clock
            anchors.centerIn: parent
            // On battery the level is always there; hovering adds the times.
            text: {
              var t = Model.clockText(root.now)
              if (root.batteryPercent < 0) return t
              if (!hover.hovered) return root.batteryMode === "discharging" ? t + " · " + root.batteryPercent + "%" : t
              var out = t + " · " + root.batteryPercent + "%"
              if (root.batteryMode === "discharging" && root.batterySeconds > 0) out += " " + Model.durationText(root.batterySeconds)
              if (root.batteryMode === "charging" && root.batterySeconds > 0) out += " ↑" + Model.durationText(root.batterySeconds)
              if (root.batteryAfterSeconds > 0) out += " ~" + Model.durationText(root.batteryAfterSeconds)
              return out
            }
            color: Color.foreground
            font.family: Style.fontFamily
            font.pixelSize: 11
            font.bold: true
          }
        }
      }
    }

    Item {
      id: irisMask
      anchors.fill: parent
      layer.enabled: true
      visible: false
      Rectangle {
        x: root.cx - iris.radius; y: root.cy - iris.radius
        width: 2 * iris.radius; height: width
        radius: width / 2
        color: "black"
      }
    }

    Rectangle {
      visible: root.veil > 0.02 && root.veil < 0.98
      x: root.cx - iris.radius; y: root.cy - iris.radius
      width: 2 * iris.radius; height: width
      radius: width / 2
      color: "transparent"
      border.width: 2
      border.color: Color.accent
      opacity: Math.sin(Math.PI * root.veil)
    }
  }

  // The list of maps, from the clock: under the disc (above it in a bottom
  // corner), on the screen's side.
  Popover {
    id: mapMenu
    target: disc
    onOpenChanged: if (open) root.scanMaps()
    cornerRight: root.cornerRight
    cornerBottom: root.cornerBottom
    padding: 4

    Column {
      Repeater {
        model: root.maps
        delegate: Rectangle {
          id: row
          required property var modelData
          readonly property bool current: root.mapId === modelData.id
          width: 150
          height: 28
          color: rowHover.hovered ? Qt.alpha(Color.accent, 0.18) : "transparent"
          radius: Style.cornerRadius

          HoverHandler { id: rowHover }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 8
            spacing: 10
            Image {
              visible: row.modelData.image !== ""
              width: 16; height: 16
              source: row.modelData.image
              sourceSize.width: 32; sourceSize.height: 32
            }
            Text {
              visible: row.modelData.image === ""
              width: 16
              text: row.modelData.glyph
              color: row.current ? Color.accent : Color.popups.text
              font.family: Style.fontFamily
              font.pixelSize: 14
            }
            Text {
              text: row.modelData.name
              color: row.current ? Color.accent : Color.popups.text
              font.family: Style.fontFamily
              font.pixelSize: 12
              font.bold: row.current
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.setMap(row.modelData.id); mapMenu.open = false }
          }
        }
      }
    }
  }

  // Settings, from a right-click: beside the disc, on the screen's side.
  Popover {
    id: settingsPop
    target: disc
    beside: true
    cornerRight: root.cornerRight
    cornerBottom: root.cornerBottom

    Settings {
      cfg: root.cfg
      onSave: function(patch) { root.saveConfig(patch) }
    }
  }

  IpcHandler {
    target: "austraz.minimap"

    function show(): void { root.saveConfig({ visible: true }) }
    function hide(): void { root.saveConfig({ visible: false }) }
    function toggle(): void { root.saveConfig({ visible: !root.shown }) }
    function next(): void { root.setMap(Model.nextMap(root.maps, root.mapId, 1)) }
    function settings(): void { mapMenu.open = false; settingsPop.toggle() }
    function peek(): void { root.peek() }
    function notify(map: string): void { root.notify(map) }
    // A system OSD (see showOsd): "ok" when shown here, else "off".
    function osd(payload: string): string { return root.showOsd(payload) ? "ok" : "off" }
    function closeOsd(): void { root.osdOpen = false }
    // A map's own demo, when it has one: `demo prometheus legendary`.
    function demo(map: string, arg: string): void {
      for (var i = 0; i < mapLoaders.count; i++) {
        var l = mapLoaders.itemAt(i)
        if (l && l.modelData.id === map && l.item && l.item.demo) l.item.demo(arg)
      }
    }
    // The weather map as a notification, playing the end of the radar loop.
    function radar(): void {
      for (var i = 0; i < mapLoaders.count; i++) {
        var l = mapLoaders.itemAt(i)
        if (l && l.modelData.id === "weather" && l.item && l.item.playRadar) l.item.playRadar()
      }
    }
    function maps(): void { settingsPop.open = false; mapMenu.toggle() }
    function map(name: string): void { root.setMap(name) }
    function corner(name: string): void { root.saveConfig({ corner: name }) }
    function zoomIn(): void { root.setZoom(root.cfg.zoom + 1) }
    function zoomOut(): void { root.setZoom(root.cfg.zoom - 1) }
    function refresh(): void { root.fetchRadar(); root.fetchForecast() }
    // Render the disc to a PNG, for checking the look without a screen grab.
    // Jump to the desk the LEDs are signalling (bound to Super+Caps Lock).
    function focusAlert(): string { return root.focusAlert() ? "ok" : "none" }
    // What the minimap knows about agents and alerts, for diagnosis.
    function alerts(): string { return JSON.stringify({ leds: root.ledMode, desk: root.alertDesk(), agents: root.agents }) }
    function showNumbers(): void { root.numbersShown = true }
    function hideNumbers(): void { root.numbersShown = false }
    // Same call as Spaces' IPC, sent by the agent reporters to both.
    function agent(session: string, state: string, pids: string): void { root.applyAgent(session, state, pids) }
    function snapshot(path: string): void { disc.grabToImage(function(r) { r.saveToFile(path) }) }
  }
}
