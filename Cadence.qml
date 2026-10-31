import QtQuick

// A cheap clock for looping animations. While `active`, `phase` runs
// smoothly from 0 to 1 for the first `smoothCycles` cycles, so a state
// change is noticed, then jumps through `steps` evenly spaced positions on a
// timer: a running animation redraws the shell on every frame (~60 Hz), a
// step only a few times per cycle. Inactive, `phase` rests at 0. Users map
// the phase to what they draw (a blink, a widening ring).
Item {
  id: cadence
  visible: false

  property bool active: false
  property int duration: 1000      // one cycle, ms
  property int smoothCycles: 3
  property int steps: 2
  property real phase: 0

  // Also call it to replay the smooth part, e.g. when a new agent starts.
  function restart() {
    smooth.stop()
    stepper.stop()
    cadence.phase = 0
    if (cadence.active) smooth.start()
  }

  onActiveChanged: restart()
  Component.onCompleted: restart()

  NumberAnimation {
    id: smooth
    target: cadence
    property: "phase"
    from: 0; to: 1
    duration: cadence.duration
    loops: Math.max(1, cadence.smoothCycles)
    // finished() comes only from a natural end, never from stop().
    onFinished: {
      cadence.phase = 0
      if (cadence.active) stepper.start()
    }
  }

  Timer {
    id: stepper
    interval: Math.max(16, cadence.duration / cadence.steps)
    repeat: true
    onTriggered: cadence.phase = ((Math.round(cadence.phase * cadence.steps) + 1) % cadence.steps) / cadence.steps
  }

  // A blink between 1 and `low` from the phase: a cosine, so the smooth part
  // eases like InOutSine and two steps land on 1 and `low`.
  function blink(low) {
    return low + (1 - low) * (Math.cos(2 * Math.PI * cadence.phase) + 1) / 2
  }
}
