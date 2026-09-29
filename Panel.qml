import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Uptime label, nothing else.
//
// The bar shows how long the machine has been up, in one of eight formats.
// Right-click the label opens a menu: pick the format, the suffix, or whether
// the clock icon is drawn. Left-click is deliberately left to the bar, so the
// label never eats a drag or a click you meant for something else.
//
// Formats (the `from` and `count` arguments to formatLadder):
//   0  days / hours / minutes        "12d 3h 45m"
//   1  hours / minutes               "291h 27m"
//   2  weeks / days / hours / mins   "1w 5d 3h 45m"
//   3  the two largest units         "1w 5d"
//   4  total hours                   "6,955h"
//   5  total minutes                 "417,271m"
//   6  total seconds                 "25,036,263s"
//   7  total milliseconds            "25,036,263,000ms"
//
// Uptime comes from /proc/uptime, which is read once a minute and
// interpolated in between, so a fast-ticking display costs a timer rather
// than a process per frame. Choices persist to
// ~/.config/omarchy/bar/uptime-counter-settings.json.

Panel {
  id: root
  moduleName: "robbie.uptime-counter"
  ipcTarget: "robbie.uptime-counter"

  // ---- uptime state ----
  // baseSeconds/baseTimeMs is the last reading from /proc/uptime and when it
  // was taken; the displayed value is interpolated from that pair.
  property real baseSeconds: 0
  property double baseTimeMs: 0

  // The bar's text, written by tick() only when it actually changes so a
  // format that ticks once a minute does not re-layout sixty times a second.
  property string labelText: ""

  // The value the menu rows preview. Only advanced while the menu is open,
  // and only once a second, because every format the menu offers reads in
  // whole units and the millisecond format would otherwise rebuild all eight
  // preview strings twenty times a second.
  property real previewSeconds: 0

  // ---- display choices ----
  property int format: 0
  property int suffix: 0
  property bool showIcon: true

  readonly property string settingsFilePath: Quickshell.env("HOME") + "/.config/omarchy/bar/uptime-counter-settings.json"

  readonly property var formats: [
    { label: "D H:M",   tip: "Days, hours and minutes" },
    { label: "H:M",     tip: "Hours and minutes" },
    { label: "W D H:M", tip: "Weeks, days, hours and minutes" },
    { label: "Short",   tip: "The two largest units" },
    { label: "Hours",   tip: "Total hours" },
    { label: "Min",     tip: "Total minutes" },
    { label: "Sec",     tip: "Total seconds" },
    { label: "ms",      tip: "Total milliseconds, ticking live", subSecond: true }
  ]
  readonly property int formatCount: root.formats.length

  // `label` is what the menu row shows; `text` is what goes on the bar, which
  // is empty for "Icon only" so the bar draws no suffix at all.
  readonly property var suffixes: [
    { label: "UT:",       text: "UT:",     tip: "Label reads \u201cUT: 12d 3h 45m\u201d" },
    { label: "Uptime:",   text: "Uptime:", tip: "Label reads \u201cUptime: 12d 3h 45m\u201d" },
    { label: "Icon only", text: "",        tip: "No suffix, just the clock icon and the value" }
  ]
  readonly property int suffixCount: root.suffixes.length

  // Only the millisecond format can show a change between whole seconds, so
  // it is the only one that pays for a fast timer.
  readonly property bool subSecond: !!(root.formats[root.format] && root.formats[root.format].subSecond)

  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int captionPx: Style.font.caption
  readonly property int bodyPx: Style.font.body

  // ---- formatting ----

  // Unit ladder, largest first.
  readonly property var ladder: [[604800, "w"], [86400, "d"], [3600, "h"], [60, "m"]]

  // Renders the ladder from index `from`, skipping leading zero units and
  // stopping at the first zero once something has been printed, so an hour-old
  // machine reads "3h 45m" rather than "0d 3h 45m". `count` caps how many
  // units are shown; anything still left over is dropped. Seconds are the
  // floor: an uptime under a minute still reads as something.
  function formatLadder(seconds, from, count) {
    var t = Math.max(0, Math.floor(Number(seconds) || 0))
    var parts = []
    for (var i = from; i < root.ladder.length; i++) {
      if (count > 0 && parts.length >= count) break
      var size = root.ladder[i][0]
      var n = Math.floor(t / size)
      t -= n * size
      if (n === 0) {
        if (parts.length > 0) break
        continue
      }
      parts.push(n + root.ladder[i][1])
    }
    return parts.length > 0 ? parts.join(" ") : t + "s"
  }

  // Thousands separators, for the total-count formats.
  function groupDigits(n) {
    var s = String(Math.max(0, Math.floor(Number(n) || 0)))
    var out = ""
    for (var i = 0; i < s.length; i++) {
      var r = s.length - i
      if (i > 0 && r % 3 === 0) out += ","
      out += s[i]
    }
    return out
  }

  // `which` renders a format explicitly, which is how the menu previews show
  // a format that is not the selected one; it defaults to the selection.
  function formatValue(seconds, which) {
    var s = Number(seconds) || 0
    switch (which === undefined ? root.format : which) {
      case 0: return root.formatLadder(s, 1)
      case 1: return root.formatLadder(s, 2)
      case 2: return root.formatLadder(s, 0)
      case 3: return root.formatLadder(s, 0, 2)
      case 4: return root.groupDigits(s / 3600) + "h"
      case 5: return root.groupDigits(s / 60) + "m"
      case 6: return root.groupDigits(s) + "s"
      // Rounded, not floored: the interpolated seconds carry a fractional
      // part, and flooring one can drop a whole millisecond off the end.
      case 7: return root.groupDigits(Math.round(s * 1000)) + "ms"
    }
    return ""
  }

  function suffixText() {
    return root.suffixes[root.suffix] ? root.suffixes[root.suffix].text : ""
  }

  function tooltipBody() {
    var s = root.uptimeSeconds()
    return [
      "Uptime \u00b7 right-click for the format menu",
      root.formatLadder(s, 0),
      "",
      root.groupDigits(Math.floor(s / 3600)) + " total hours",
      root.groupDigits(Math.floor(s / 60)) + " total minutes",
      root.groupDigits(Math.floor(s)) + " total seconds"
    ].join("\n")
  }

  // ---- ticking ----

  // Uptime as of now, interpolated from the last /proc/uptime reading.
  function uptimeSeconds() {
    return root.baseSeconds + (Date.now() - root.baseTimeMs) / 1000
  }

  // Rewrites the bar's text only when the formatted value actually differs,
  // so a format that ticks once a minute does not re-layout sixty times a
  // second.
  function tickLabel() {
    var text = root.formatValue(root.uptimeSeconds())
    if (text !== root.labelText) root.labelText = text
  }

  // Menu previews advance once a second, and only while the menu is open:
  // every format on offer reads in whole units, and the millisecond format
  // would otherwise rebuild all eight preview strings twenty times a second.
  function tickPreview() {
    if (root.opened) root.previewSeconds = root.uptimeSeconds()
  }

  function chooseFormat(i) {
    root.format = root.modIndex(i, root.formatCount)
    root.tickLabel()
    root.tickPreview()
    root.scheduleSettingsSave()
  }

  function chooseSuffix(i) {
    root.suffix = root.modIndex(i, root.suffixCount)
    root.scheduleSettingsSave()
  }

  function toggleIcon() {
    root.showIcon = !root.showIcon
    root.scheduleSettingsSave()
  }

  // ---- uptime reading ----

  function refreshUptime() {
    if (!uptimeReadProc.running) uptimeReadProc.running = true
  }

  // ---- settings (uptime-counter-settings.json) ----

  function modIndex(i, n) {
    var v = Math.round(Number(i))
    if (!isFinite(v)) v = 0
    return ((v % n) + n) % n
  }

  function loadSettings(raw) {
    var data = {}
    try { data = JSON.parse(raw || "{}") } catch (err) { data = {} }
    if (data.format !== undefined) root.format = root.modIndex(data.format, root.formatCount)
    if (data.suffix !== undefined) root.suffix = root.modIndex(data.suffix, root.suffixCount)
    if (data.icon !== undefined) root.showIcon = !!data.icon
    root.tickLabel()
    root.tickPreview()
    // Whatever is on disk right now needs no rewrite.
    root.lastSavedJson = root.settingsJson()
  }

  function settingsJson() {
    return JSON.stringify({
      version: 1,
      format: root.format,
      suffix: root.suffix,
      icon: root.showIcon
    }, null, 2) + "\n"
  }

  function scheduleSettingsSave() { saveSettingsTimer.restart() }

  // The last JSON handed to the file. Re-clicking the selected row in the menu
  // leaves the settings alone rather than writing an identical file.
  property string lastSavedJson: ""

  FileView {
    id: settingsFile
    path: root.settingsFilePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.loadSettings("")
  }

  // Running through the menu should land as one write, not one per click.
  Timer {
    id: saveSettingsTimer
    interval: 150
    repeat: false
    onTriggered: {
      var json = root.settingsJson()
      if (json === root.lastSavedJson) return
      root.lastSavedJson = json
      settingsFile.setText(json)
    }
  }

  // ---- bar label ----

  implicitWidth: Math.max(12, labelRow.implicitWidth + 16)
  implicitHeight: bar ? bar.barSize : 24

  Row {
    id: labelRow
    anchors.centerIn: parent
    spacing: 8
    leftPadding: 10

    Text {
      text: "\uf06e"
      visible: root.showIcon
      color: bar ? bar.barForeground : Color.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.bar.iconFont
      renderType: Text.NativeRendering
    }

    Text {
      text: root.suffixText()
      visible: text !== ""
      color: bar ? bar.barForeground : Color.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.bar.iconFont
      renderType: Text.NativeRendering
    }

    Text {
      text: root.labelText
      color: bar ? bar.barForeground : Color.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.bar.iconFont
      renderType: Text.NativeRendering
    }
  }

  // Right-click only: the left button belongs to the bar, so the label stays
  // out of the way of anything the bar itself does with a click or a drag.
  MouseArea {
    anchors.fill: parent
    z: 5
    acceptedButtons: Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggle()
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipBody())
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // ---- data sources ----

  Process {
    id: uptimeReadProc
    command: ["cat", "/proc/uptime"]
    stdout: SplitParser {
      onRead: function(line) {
        var up = Math.floor(parseFloat(line) * 1000) / 1000
        if (isNaN(up)) return
        root.baseSeconds = up
        root.baseTimeMs = Date.now()
        root.tickLabel()
        root.tickPreview()
      }
    }
  }

  // Once a minute is plenty: the value between readings is interpolated, so
  // the widget stays accurate without a process per tick.
  Timer {
    id: rebaseTimer
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshUptime()
  }

  // One format per second for every format except the millisecond one, where
  // the fast timer already owns the label and this timer only keeps the menu
  // previews moving.
  Timer {
    id: secondTimer
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!root.subSecond) root.tickLabel()
      root.tickPreview()
    }
  }

  // Only runs for the millisecond format, and off the second timer rather
  // than alongside it.
  Timer {
    id: fastTimer
    interval: 50
    running: root.subSecond
    repeat: true
    onTriggered: root.tickLabel()
  }

  // The menu's preview column starts on the live value rather than zero, so
  // opening it never shows a column of "0m" for a frame.
  onOpenedChanged: if (root.opened) { root.tickLabel(); root.tickPreview() }

  // ---- format menu ----
  //
  // A PopupCard, not a KeyboardPanel: there is nothing to type in here, and
  // the menu must not take keyboard focus away from whatever was being typed
  // when the bar was right-clicked.

  PopupCard {
    id: menu
    anchorItem: labelRow
    owner: root
    bar: root.bar
    open: root.opened
    padding: Style.spacing.popupPadding
    contentWidth: menu.fittedContentWidth(Style.space(300))
    contentHeight: menu.cappedContentHeight(menuColumn.implicitHeight)

    Column {
      id: menuColumn
      width: parent.width
      spacing: Style.spacing.xs

      PanelHero {
        width: parent.width
        title: "Uptime"
        meta: "Pick how the bar label reads"
        foreground: Color.popups.text
        fontFamily: root.fontFamily
        iconComponent: Component {
          Text {
            text: "\uf06e"
            color: Color.popups.text
            font.family: root.fontFamily
            font.pixelSize: root.captionPx
          }
        }
      }

      SectionLabel { text: "FORMAT" }

      Repeater {
        model: root.formats

        MenuRow {
          required property var modelData
          required property int index

          label: modelData.label
          tip: modelData.tip
          selected: index === root.format
          value: root.formatValue(root.previewSeconds, index)
          onPicked: root.chooseFormat(index)
        }
      }

      PanelSeparator { foreground: Color.popups.text }

      SectionLabel { text: "SUFFIX" }

      Repeater {
        model: root.suffixes

        MenuRow {
          required property var modelData
          required property int index

          label: modelData.label
          tip: modelData.tip
          selected: index === root.suffix
          onPicked: root.chooseSuffix(index)
        }
      }

      PanelSeparator { foreground: Color.popups.text }

      SectionLabel { text: "DISPLAY" }

      MenuRow {
        label: "Clock icon"
        tip: root.showIcon ? "Hide the clock icon" : "Show the clock icon"
        selected: root.showIcon
        onPicked: root.toggleIcon()
      }
    }
  }

  // One selectable row: a check mark for the active choice, the choice's
  // label, and an optional right-aligned preview of what the bar would read.
  // The check slot keeps its width either way, so labels do not shuffle when
  // the selection moves.
  component MenuRow: Item {
    id: row
    required property string label
    property string tip: ""
    property bool selected: false
    property string value: ""
    signal picked()

    implicitWidth: parent ? parent.width : 0
    width: implicitWidth
    height: Math.max(Style.spacing.controlHeight, labelText.implicitHeight)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: hover.containsMouse ? Util.alpha(Color.popups.text, 0.08) : "transparent"
    }

    Item {
      id: markSlot
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.xs
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(14)
      height: parent.height

      Text {
        anchors.centerIn: parent
        visible: row.selected
        text: "\uf00c"
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: root.captionPx
      }
    }

    Text {
      id: labelText
      anchors.left: markSlot.right
      anchors.leftMargin: Style.spacing.sm
      anchors.right: parent.right
      anchors.rightMargin: row.value !== "" ? 0 : Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      text: row.label
      elide: Text.ElideRight
      color: row.selected ? Color.accent : Color.popups.text
      font.family: root.fontFamily
      font.pixelSize: root.bodyPx
    }

    Text {
      id: valueText
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.xs
      anchors.verticalCenter: parent.verticalCenter
      visible: row.value !== ""
      text: row.value
      color: Util.alpha(Color.popups.text, row.selected ? 0.95 : 0.55)
      font.family: root.fontFamily
      font.pixelSize: root.captionPx
    }

    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.picked()
    }

    PanelToolTip {
      visible: hover.containsMouse
      text: row.tip
      fontFamily: root.fontFamily
    }
  }

  component SectionLabel: Text {
    width: parent ? parent.width : 0
    text: ""
    color: Util.alpha(Color.popups.text, 0.6)
    font.family: root.fontFamily
    font.pixelSize: root.captionPx
    font.letterSpacing: 1
    font.bold: true
    horizontalAlignment: Text.AlignLeft
    leftPadding: Style.spacing.xs
  }
}
