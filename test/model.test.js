// Checks for Model.js, the minimap's pure helpers: node --test test/*.test.js
const test = require("node:test")
const assert = require("node:assert/strict")

// Qt's value-type constructors, as QML gives them to Model.js.
global.Qt = {
  size: (width, height) => ({ width, height }),
  rect: (x, y, width, height) => ({ x, y, width, height })
}
const Model = require("../Model.js")

test("normalizeConfig: defaults, and size kept to 300..480", () => {
  const c = Model.normalizeConfig({})
  assert.equal(c.size, 300)
  assert.equal(c.corner, "bottom-right")
  assert.equal(c.cardinals, true)
  assert.deepEqual(c.disabledBands, [])
  assert.equal(Model.normalizeConfig({ size: 250 }).size, 300)
  assert.equal(Model.normalizeConfig({ size: 900 }).size, 480)
  assert.equal(Model.normalizeConfig({ corner: "middle" }).corner, "bottom-right")
  assert.deepEqual(Model.normalizeConfig({ disabledBands: ["ai", 3] }).disabledBands, ["ai", "3"])
})

test("deskDarkness: grey for 2 min, black at 1 h, quick at first", () => {
  assert.equal(Model.deskDarkness(0), 0)
  assert.equal(Model.deskDarkness(120), 0)
  assert.equal(Model.deskDarkness(3600), 1)
  assert.equal(Model.deskDarkness(9999), 1)
  const half = Model.deskDarkness(120 + 3480 / 2)
  assert.ok(half > 0.6 && half < 0.7, "past the middle by mid-time: " + half)
  assert.ok(Model.deskDarkness(600) < Model.deskDarkness(1800))
})

test("deskOrder: the scratchpad first, then the desks in order", () => {
  const ids = [3, -98, 1, 10, 2].map(id => ({ id }))
  assert.deepEqual(ids.sort(Model.deskOrder).map(w => w.id), [-98, 1, 2, 3, 10])
})

test("workspaceArcs: equal arcs from the top, gaps between them", () => {
  assert.deepEqual(Model.workspaceArcs([]), [])
  const one = Model.workspaceArcs([{ id: 1 }])
  assert.equal(one[0].sweep, 360)
  const arcs = Model.workspaceArcs([{ id: 1 }, { id: 2 }, { id: 3 }, { id: 4 }], 4)
  assert.deepEqual(arcs.map(a => a.mid), [0, 90, 180, 270])
  assert.ok(arcs.every(a => a.sweep === 86))
  assert.equal(arcs[0].start, 317)          // centred on noon: 360 - 45 + 2
})

test("compactionPlan: closes the gaps, keeps order", () => {
  const ws = id => ({ id, windows: 1, name: String(id) })
  assert.deepEqual(Model.compactionPlan([ws(1), ws(2), ws(3)]), [])
  assert.deepEqual(Model.compactionPlan([ws(1), ws(3), ws(5)]), [{ from: 3, to: 2 }, { from: 5, to: 3 }])
})

test("dialAngle: midnight at the bottom, noon at the top", () => {
  assert.equal(Model.dialAngle(0), 180)
  assert.equal(Model.dialAngle(12 * 3600), 0)
  assert.equal(Model.dialAngle(18 * 3600), 90)
})

test("batterySweep and durationText", () => {
  assert.equal(Model.batterySweep(0), 0)
  assert.equal(Model.batterySweep(6 * 3600), 90)
  assert.equal(Model.batterySweep(48 * 3600), 355)   // never closes the ring
  assert.equal(Model.durationText(0), "")
  assert.equal(Model.durationText(45 * 60), "45 min")
  assert.equal(Model.durationText(125 * 60), "2 h 05")
})

test("dischargeRate: median of discharging samples in the window", () => {
  const now = 1000000
  const text = "([(uint32 999000, 10.0, uint32 2), (uint32 999100, 30.0, uint32 2), (uint32 999200, 20.0, uint32 2),"
    + " (uint32 999300, 50.0, uint32 1), (uint32 1, 99.0, uint32 2)],)"
  assert.equal(Model.dischargeRate(text, now, 7), 20)
  assert.equal(Model.dischargeRate("", now, 7), 0)
})

test("wallpaperCrop: the corner as the screen shows it", () => {
  // 8192x4608 on a 2304x1536 screen at 1.25: covers 2880x1920, centred.
  const c = Model.wallpaperCrop(8192, 4608, 2304, 1536, 1.25, { x: 2032, y: 0, width: 272, height: 272 })
  assert.deepEqual(c.sourceSize, { width: 3413, height: 1920 })
  assert.deepEqual(c.clip, { x: 2807, y: 0, width: 340, height: 340 })   // 266.5 + 2540, rounded
  assert.equal(Model.wallpaperCrop(0, 0, 2304, 1536, 1, { x: 0, y: 0, width: 10, height: 10 }), null)
})

test("sunTimes: Paris on 27 Oct 2026 (CET)", () => {
  const t = Model.sunTimes(Date.UTC(2026, 9, 27, 11), 48.8566, 2.3522)
  const hm = s => new Date(s * 1000).toISOString().slice(11, 16)   // UTC
  // Open-Meteo for that day: sunrise 06:29 UTC, sunset 16:38 UTC.
  const near = (s, h, m) => Math.abs(s - Date.UTC(2026, 9, 27, h, m) / 1000) < 240
  assert.ok(near(t.sunrise, 6, 29), "sunrise " + hm(t.sunrise))
  assert.ok(near(t.sunset, 16, 38), "sunset " + hm(t.sunset))
  assert.ok(t.goldenEnd > t.sunrise && t.goldenEnd - t.sunrise < 5400)
  assert.ok(t.goldenStart < t.sunset && t.sunset - t.goldenStart < 5400)
  // Twilight steps outwards: civil, nautical, astronomical.
  assert.ok(t.civilDawn < t.sunrise && t.nauticalDawn < t.civilDawn && t.astroDawn < t.nauticalDawn)
  assert.ok(t.civilDusk > t.sunset && t.nauticalDusk > t.civilDusk && t.astroDusk > t.nauticalDusk)
  assert.equal(Model.twilightArcs(t.sunrise, t.sunset, t).length, 6)
  // Within 2 h of the evening bands only; none in the middle of the night.
  assert.equal(Model.twilightArcs(t.sunrise, t.sunset, t, t.sunset, 7200).length, 3)
  assert.equal(Model.twilightArcs(t.sunrise, t.sunset, t, t.astroDusk + 4 * 3600, 7200).length, 0)
  const polar = Model.sunTimes(Date.UTC(2026, 11, 21, 12), 80, 0)   // polar night
  assert.equal(polar.sunrise, 0)
  assert.equal(polar.sunset, 0)
})
