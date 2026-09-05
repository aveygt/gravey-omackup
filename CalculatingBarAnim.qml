import QtQuick

// Calculating-bar flicker. Edit the TWEAK section, save, and the plugin reloads.
Item {
  id: root

  property int blockCount: 20
  property color tone: "#ffffff"
  property color emptyColor: Qt.rgba(1, 1, 1, 0.14)
  property bool colorful: true
  property bool active: false

  // ============================================================
  // TWEAK — fade speed, how many blocks, randomness, color
  // ============================================================

  // How many blocks are fading at once.
  property int concurrentFades: 60

  // Fade-in and fade-out time, in milliseconds. Lower = snappier.
  property int fadeInMs: 300
  property int fadeOutMs: 600

  // How long lit blocks take to fade away when calculating ends.
  // 0 = use fadeOutMs.
  property int exitFadeMs: 0

  // Hold at full brightness before fading out. 0 = none.
  property int fadeHoldMs: 100

  // Pause after a fade-out before that spark picks a new block.
  property int pauseMinMs: 10
  property int pauseMaxMs: 90

  // Stagger the first start so sparks don't all kick off together.
  property int staggerMs: 50
  property int staggerJitterMs: 100

  // 0 = walk the bar in order. 1 = pick any block at random.
  property real blockRandomness: 1.0

  // Prefer a block that isn't already lit. Falls back if the bar is crowded.
  property bool uniqueBlocks: true

  // 0 = always use the bar's foreground color. 1 = fully random hues.
  property real colorRandomness: 1.0
  property real hueMin: 0.0
  property real hueMax: 1.0
  property real minSaturation: 0.78
  property real maxSaturation: 1.0
  property real minLightness: 0.46
  property real maxLightness: 0.62
  property real peakOpacity: 1.0

  // Easing.InOutSine, Easing.Linear, Easing.InOutQuad, Easing.OutCubic, …
  property int fadeEasing: Easing.InOutSine

  // ============================================================

  readonly property real blockWidth: width / Math.max(1, blockCount)
  readonly property int settleDurationMs: Math.max(1, exitFadeMs > 0 ? exitFadeMs : fadeOutMs)
  property int walkIndex: 0
  property bool settling: false
  visible: active || settling
  clip: true

  function randomBetween(minValue, maxValue) {
    var lo = Math.min(minValue, maxValue)
    var hi = Math.max(minValue, maxValue)
    return lo + Math.floor(Math.random() * (hi - lo + 1))
  }

  function isOccupied(blockIndex, self) {
    var i
    var item
    for (i = 0; i < sparkRepeater.count; i++) {
      item = sparkRepeater.itemAt(i)
      if (!item || item === self) continue
      if (item.blockIndex === blockIndex && item.opacity > 0.08) return true
    }
    return false
  }

  function pickBlock(self) {
    var count = Math.max(1, blockCount)
    if (Math.random() > Math.max(0, Math.min(1, blockRandomness))) {
      walkIndex = (walkIndex + 1) % count
      return walkIndex
    }
    var pick = Math.floor(Math.random() * count)
    if (!uniqueBlocks || concurrentFades >= count) return pick
    var tries = count
    while (tries > 0 && isOccupied(pick, self)) {
      pick = Math.floor(Math.random() * count)
      tries -= 1
    }
    return pick
  }

  function pickColor() {
    var variance = Math.max(0, Math.min(1, colorRandomness))
    if (!colorful || variance <= 0) return tone
    var hueSpan = hueMax - hueMin
    var hue = hueMin + Math.random() * hueSpan
    if (variance < 1) hue = hueMin + hueSpan * 0.5 + (hue - (hueMin + hueSpan * 0.5)) * variance
    if (hue < 0) hue += 1
    hue = hue % 1.0
    var sat = minSaturation + Math.random() * Math.max(0, maxSaturation - minSaturation)
    var lit = minLightness + Math.random() * Math.max(0, maxLightness - minLightness)
    sat = minSaturation + (sat - minSaturation) * variance
    return Qt.hsla(hue, sat, lit, 1)
  }

  function armAll() {
    var i
    var item
    for (i = 0; i < sparkRepeater.count; i++) {
      item = sparkRepeater.itemAt(i)
      if (item) item.arm(i)
    }
  }

  function haltAll() {
    var i
    var item
    for (i = 0; i < sparkRepeater.count; i++) {
      item = sparkRepeater.itemAt(i)
      if (item) item.halt()
    }
    settling = false
  }

  function settleAll() {
    var i
    var item
    var anyLit = false
    settling = true
    for (i = 0; i < sparkRepeater.count; i++) {
      item = sparkRepeater.itemAt(i)
      if (!item) continue
      if (item.settle()) anyLit = true
    }
    if (!anyLit) settling = false
  }

  function sparkSettled() {
    var i
    var item
    for (i = 0; i < sparkRepeater.count; i++) {
      item = sparkRepeater.itemAt(i)
      if (item && item.opacity > 0.01) return
    }
    settling = false
  }

  onActiveChanged: {
    if (active) {
      settling = false
      Qt.callLater(armAll)
    } else {
      settleAll()
    }
  }

  onConcurrentFadesChanged: {
    if (active) Qt.callLater(armAll)
  }

  Component.onCompleted: if (active) Qt.callLater(armAll)

  Row {
    id: emptyTrack
    anchors.fill: parent
    spacing: 0
    opacity: root.active ? 1 : 0

    Behavior on opacity {
      NumberAnimation {
        duration: root.settleDurationMs
        easing.type: root.fadeEasing
      }
    }

    Repeater {
      model: Math.max(1, root.blockCount)
      Rectangle {
        required property int index
        width: root.blockWidth
        height: parent.height
        color: root.emptyColor
      }
    }
  }

  Repeater {
    id: sparkRepeater
    model: Math.max(1, root.concurrentFades)

    Rectangle {
      id: spark
      required property int index
      property int blockIndex: 0
      property bool exiting: false

      width: root.blockWidth
      height: root.height
      x: blockIndex * root.blockWidth
      y: 0
      color: root.tone
      opacity: 0
      visible: root.active || root.settling || opacity > 0.01

      NumberAnimation {
        id: fadeIn
        target: spark
        property: "opacity"
        from: 0
        to: root.peakOpacity
        duration: Math.max(1, root.fadeInMs)
        easing.type: root.fadeEasing
        onFinished: {
          if (!root.active || spark.exiting) return
          if (root.fadeHoldMs > 0) holdTimer.start()
          else fadeOut.start()
        }
      }

      NumberAnimation {
        id: fadeOut
        target: spark
        property: "opacity"
        to: 0
        duration: spark.exiting ? root.settleDurationMs : Math.max(1, root.fadeOutMs)
        easing.type: root.fadeEasing
        onFinished: {
          if (spark.exiting || !root.active) {
            spark.exiting = false
            root.sparkSettled()
            return
          }
          pauseTimer.interval = root.randomBetween(root.pauseMinMs, root.pauseMaxMs)
          pauseTimer.start()
        }
      }

      Timer {
        id: holdTimer
        interval: Math.max(1, root.fadeHoldMs)
        repeat: false
        onTriggered: {
          if (root.active) fadeOut.start()
        }
      }

      Timer {
        id: pauseTimer
        interval: 1
        repeat: false
        onTriggered: {
          if (root.active) spark.beginCycle()
        }
      }

      Timer {
        id: startDelay
        interval: 1
        repeat: false
        onTriggered: {
          if (root.active) spark.beginCycle()
        }
      }

      function beginCycle() {
        if (!root.active || spark.exiting) return
        fadeIn.stop()
        fadeOut.stop()
        holdTimer.stop()
        opacity = 0
        blockIndex = root.pickBlock(spark)
        color = root.pickColor()
        fadeIn.start()
      }

      function settle() {
        startDelay.stop()
        pauseTimer.stop()
        holdTimer.stop()
        fadeIn.stop()
        fadeOut.stop()
        if (opacity <= 0.01) {
          opacity = 0
          exiting = false
          return false
        }
        exiting = true
        fadeOut.start()
        return true
      }

      function arm(order) {
        halt()
        startDelay.interval = Math.max(0, order * root.staggerMs + root.randomBetween(0, root.staggerJitterMs))
        startDelay.start()
      }

      function halt() {
        startDelay.stop()
        pauseTimer.stop()
        holdTimer.stop()
        fadeIn.stop()
        fadeOut.stop()
        exiting = false
        opacity = 0
      }
    }
  }
}
