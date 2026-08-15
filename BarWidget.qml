import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A row of fixed timezones on the bar, rendered as flag emoji + 24h time:
// "🇨🇱 14:05 · 🇨🇦 12:05 · 🇯🇵 02:05".
//
// Zones and their emojis come from the `zones` setting on the widget's
// shell.json layout entry — an array of { flag, tz } — edited by clicking
// the label, which runs the bundled dst-clocks-menu.sh (Omarchy menu flow:
// add clock / remove clock / change emoji).
//
// Qt's QML runtime has no Intl, so the zone math is delegated to the
// system tzdata via `env TZ=<zone> date` once a minute — each country's
// DST rules stay correct with no hand-maintained offsets or rules.
BarWidget {
  id: root
  moduleName: "alvarosaavedra.dst-clocks"

  // The clocks the label renders. `zones` on the layout entry is canonical;
  // the older zone1Flag/zone1Tz/zone2Flag/zone2Tz keys are still read as a
  // fallback so a hand-written config keeps working until the first menu
  // edit, which writes the merged list back as `zones`.
  readonly property var zones: {
    var list = setting("zones", null)
    if (Array.isArray(list) && list.length > 0) return list
    return [
      { flag: String(setting("zone1Flag", "🇨🇱")), tz: String(setting("zone1Tz", "America/Santiago")) },
      { flag: String(setting("zone2Flag", "🇨🇦")), tz: String(setting("zone2Tz", "America/Toronto")) }
    ]
  }

  // Last reading per zone, keyed by IANA name. Filled asynchronously by the
  // date process; a zone shows "--:--" until its first reading lands.
  property var zoneTimes: ({})

  readonly property string displayText: {
    var parts = []
    for (var i = 0; i < zones.length; i++) {
      var z = zones[i]
      if (!z || z.tz === undefined || z.tz === null) continue
      var tz = String(z.tz)
      parts.push(String((z.flag === undefined || z.flag === null) ? "🕐" : z.flag) + " " + (zoneTimes[tz] || "--:--"))
    }
    return parts.join(" · ")
  }

  readonly property string tooltipText: {
    var parts = []
    for (var i = 0; i < zones.length; i++) {
      var z = zones[i]
      if (z && z.tz) parts.push(String(z.flag || "") + " " + String(z.tz))
    }
    return parts.join(" · ") + " — click to edit"
  }

  // Property change handlers can fire before children exist, so only the
  // completed widget may reach the process.
  property bool ready: false

  function refresh() {
    var quoted = []
    for (var i = 0; i < zones.length; i++) {
      var z = zones[i]
      if (z && z.tz !== undefined && z.tz !== null)
        quoted.push("env TZ=" + Util.shellQuote(String(z.tz)) + " date +%H:%M")
    }
    if (quoted.length === 0) {
      zoneTimes = ({})
      return
    }
    proc.command = ["sh", "-c", quoted.join("; ")]
    proc.running = true
  }

  function openMenu() {
    if (!root.bar) return
    var script = String(Qt.resolvedUrl("dst-clocks-menu.sh")).replace(/^file:\/\//, "")
    root.bar.run("sh " + Util.shellQuote(script))
  }

  Component.onCompleted: {
    ready = true
    refresh()
  }

  // A shell.json edit lands here as a new settings object; fetch the new
  // zones immediately instead of waiting for the next minute tick.
  onZonesChanged: if (ready) refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    // The tick fires just before the minute rolls over, so a `date` call made
    // on the tick samples the outgoing minute. Delay the read slightly and
    // the process always sees the new one.
    onDateChanged: settleTimer.restart()
  }

  Timer {
    id: settleTimer
    interval: 2500
    onTriggered: root.refresh()
  }

  Process {
    id: proc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var zs = root.zones
        var lines = text.trim().split("\n")
        var times = {}
        var tzIndex = 0
        for (var i = 0; i < zs.length; i++) {
          var z = zs[i]
          if (!z || z.tz === undefined || z.tz === null) continue
          if (tzIndex < lines.length) times[String(z.tz)] = lines[tzIndex].trim()
          tzIndex++
        }
        root.zoneTimes = times
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    tooltipText: root.tooltipText
    onPressed: root.openMenu()
  }
}
