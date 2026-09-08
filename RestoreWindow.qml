import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var omackup: null

  Connections {
    target: root.omackup
    function onRestoreOpenChanged() {
      if (!window) return
      if (root.omackup && root.omackup.restoreOpen) window.visible = true
      else window.visible = false
    }
  }

  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Color.muted
  readonly property string fontFamily: Style.font.family
  readonly property bool use24Hour: omackup ? omackup.use24HourTime : true
  readonly property var selectedEntry: {
    if (!omackup) return null
    if (omackup.restoreSelected) return omackup.restoreSelected
    var list = omackup.listing || []
    if (!list.length) return null
    return list[Math.max(0, Math.min(omackup.restoreEntryIndex, list.length - 1))]
  }
  readonly property string restoreLabel: {
    var entry = selectedEntry
    if (entry && entry.name) return "Restore " + entry.name
    if (omackup && omackup.listingPath && omackup.listingPath !== "/")
      return "Restore this folder"
    return "Restore"
  }
  readonly property bool showPreviewPane: {
    if (!omackup) return false
    if (omackup.previewLoading) return true
    var selected = omackup.restoreSelected
    if (selected && selected.type && selected.type !== "dir") return true
    var kind = omackup.preview && omackup.preview.kind
    return kind === "text" || kind === "image" || kind === "unsupported"
      || kind === "binary" || kind === "too_large" || kind === "missing"
  }
  readonly property bool previewUnsupported: {
    if (!omackup || omackup.previewLoading) return false
    var kind = omackup.preview && omackup.preview.kind
    if (kind === "text") return false
    if (kind === "image") {
      if (!omackup.preview.image_path) return true
      return previewImage.status === Image.Error
    }
    return kind !== "" && kind !== "dir"
  }
  readonly property var crumbs: Model.pathCrumbs(omackup ? omackup.listingPath : "/")
  readonly property int timelineWidth: Style.font.baseSize * 15
  property int previewWidth: Style.font.baseSize * 28
  property bool previewResizeActive: false
  readonly property var shortcutHints: [
    "↑↓\u00A0select",
    "←→\u00A0pane",
    "enter\u00A0open",
    "u\u00A0up",
    "r\u00A0restore",
    "esc\u00A0close"
  ]

  function requestClose() {
    if (omackup) omackup.closeRestore()
    else window.visible = false
  }

  function moveCursor(dx, dy) {
    if (!omackup) return
    if (dx !== 0) {
      omackup.restoreFocus = dx > 0 ? "browser" : "timeline"
      return
    }
    if (dy === 0) return
    if (omackup.restoreFocus === "timeline") {
      var snaps = omackup.snapshots || []
      if (!snaps.length) return
      omackup.restoreSnapIndex = Math.max(0, Math.min(snaps.length - 1, omackup.restoreSnapIndex + dy))
      return
    }
    var list = omackup.listing || []
    if (!list.length) return
    omackup.restoreEntryIndex = Math.max(0, Math.min(list.length - 1, omackup.restoreEntryIndex + dy))
  }

  function activateCursor() {
    if (!omackup) return
    if (omackup.restoreFocus === "timeline") {
      var snaps = omackup.snapshots || []
      if (!snaps.length) return
      omackup.selectRestoreSnapshot(snaps[Math.max(0, Math.min(omackup.restoreSnapIndex, snaps.length - 1))])
      omackup.restoreFocus = "browser"
      return
    }
    var list = omackup.listing || []
    if (!list.length) return
    omackup.activateRestoreEntry(list[Math.max(0, Math.min(omackup.restoreEntryIndex, list.length - 1))], omackup.restoreEntryIndex)
  }

  function handleTextKey(t) {
    var key = String(t || "").toLowerCase()
    if (key === "r") omackup.restoreCurrent()
    else if (key === "u") omackup.goRestoreUp()
  }

  function fileUrl(path) {
    var value = String(path || "")
    if (!value) return ""
    if (value.indexOf("file:") === 0) return value
    return "file://" + encodeURI(value)
  }

  function ensureVisible(flick, item) {
    if (!flick || !item) return
    var pt = item.mapToItem(flick.contentItem, 0, 0)
    var top = pt.y
    var bottom = top + item.height
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 8
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin) flick.contentY = Math.max(0, bottom + margin - flick.height)
  }

  FloatingWindow {
    id: window
    title: omackup && omackup.restoreDestDisplay ? ("Restore · " + omackup.restoreDestDisplay) : "Restore"
    color: root.background
    implicitWidth: 1120
    implicitHeight: 740
    minimumSize: Qt.size(860, 540)
    visible: false

    onVisibleChanged: {
      if (visible) {
        Qt.callLater(function() {
          if (keyCatcher) keyCatcher.forceActiveFocus()
        })
      } else if (omackup && omackup.restoreOpen) {
        omackup.closeRestore()
      }
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        blocked: previewText.activeFocus
        onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
        onActivateRequested: root.activateCursor()
        onCloseRequested: root.requestClose()
        onTabRequested: function(direction) {
          if (!omackup) return
          omackup.restoreFocus = direction > 0
            ? (omackup.restoreFocus === "timeline" ? "browser" : "timeline")
            : (omackup.restoreFocus === "browser" ? "timeline" : "browser")
        }
        onTextKey: function(t) { root.handleTextKey(t) }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(16)
          spacing: Style.space(12)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Column {
              Layout.fillWidth: true
              spacing: Style.space(2)

              Text {
                text: "Restore"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              Text {
                text: {
                  if (!omackup) return ""
                  var dest = omackup.restoreDestDisplay || omackup.restoreDest
                  var snap = (omackup.snapshots || [])[omackup.restoreSnapIndex]
                  var when = snap ? Model.snapshotStamp(snap) : ""
                  if (dest && when) return dest + "  ·  " + when
                  return dest || ""
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Button {
              text: omackup && omackup.actionStatus && String(omackup.actionStatus).indexOf("Restor") === 0
                ? omackup.actionStatus
                : root.restoreLabel
              foreground: root.foreground
              bordered: true
              enabled: omackup && !omackup.busy
              onClicked: omackup.restoreCurrent()
            }

            Button {
              text: ""
              iconText: "×"
              tooltipText: "Close"
              foreground: root.foreground
              horizontalPadding: Style.space(8)
              onClicked: root.requestClose()
            }
          }

          Text {
            visible: omackup && omackup.lastError !== ""
            Layout.fillWidth: true
            text: omackup ? omackup.lastError : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.space(12)

            // Timeline
            ColumnLayout {
              Layout.preferredWidth: root.timelineWidth
              Layout.minimumWidth: root.timelineWidth
              Layout.maximumWidth: root.timelineWidth
              Layout.fillWidth: false
              Layout.fillHeight: true
              spacing: Style.space(8)

              Text {
                text: "Timeline"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Style.cornerRadius
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                border.width: 1

                Flickable {
                  id: timelineFlick
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  clip: true
                  contentWidth: width
                  contentHeight: timelineCol.implicitHeight
                  boundsBehavior: Flickable.StopAtBounds
                  flickableDirection: Flickable.VerticalFlick
                  interactive: contentHeight > height

                  Column {
                    id: timelineCol
                    width: timelineFlick.width
                    spacing: 2

                    Text {
                      visible: !omackup || omackup.snapshots.length === 0
                      width: parent.width
                      text: omackup && omackup.busy ? "…" : "None"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Repeater {
                      model: omackup ? omackup.snapshots : []
                      CursorSurface {
                        required property var modelData
                        required property int index
                        id: snapRow
                        width: timelineCol.width
                        implicitHeight: Style.space(28)
                        foreground: root.foreground
                        hasCursor: omackup && omackup.restoreFocus === "timeline" && omackup.restoreSnapIndex === index
                        current: omackup && String(omackup.restoreSnapshot) === String(modelData.id || modelData.full_id)
                        onHasCursorChanged: if (hasCursor) root.ensureVisible(timelineFlick, snapRow)

                        MouseArea {
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onEntered: {
                            omackup.restoreFocus = "timeline"
                            omackup.restoreSnapIndex = index
                          }
                          onClicked: omackup.selectRestoreSnapshot(modelData)
                        }

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.leftMargin: Style.space(6)
                          anchors.rightMargin: Style.space(6)
                          text: Model.snapshotStamp(modelData)
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          elide: Text.ElideNone
                          wrapMode: Text.NoWrap
                        }
                      }
                    }
                  }
                }
              }
            }

            SplitView {
              id: paneSplit
              Layout.fillWidth: true
              Layout.fillHeight: true
              orientation: Qt.Horizontal

              handle: Item {
                implicitWidth: Style.space(12)
                readonly property bool pressed: SplitView.pressed
                onPressedChanged: root.previewResizeActive = pressed
                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: parent.verticalCenter
                  width: 2
                  height: Math.max(Style.space(28), parent.height * 0.28)
                  radius: 1
                  color: parent.SplitView.pressed || parent.SplitView.hovered ? root.foreground : root.dim
                }
              }

            // Browser
            ColumnLayout {
              SplitView.fillWidth: true
              SplitView.minimumWidth: Style.font.baseSize * 16
              Layout.fillHeight: true
              spacing: Style.space(8)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(6)

                Button {
                  text: "Up"
                  foreground: root.foreground
                  enabled: omackup && omackup.listingPath !== "/" && omackup.listingPath !== ""
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(4)
                  fontSize: Style.font.caption
                  onClicked: omackup.goRestoreUp()
                }

                Flickable {
                  Layout.fillWidth: true
                  implicitHeight: crumbRow.implicitHeight
                  contentWidth: crumbRow.implicitWidth
                  contentHeight: height
                  clip: true
                  flickableDirection: Flickable.HorizontalFlick
                  boundsBehavior: Flickable.StopAtBounds

                  Row {
                    id: crumbRow
                    spacing: Style.space(4)
                    Repeater {
                      model: root.crumbs
                      Row {
                        required property var modelData
                        required property int index
                        spacing: Style.space(4)

                        Text {
                          visible: index > 0
                          text: "/"
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          text: modelData.name
                          color: index === root.crumbs.length - 1 ? root.foreground : root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.underline: crumbMouse.containsMouse
                          anchors.verticalCenter: parent.verticalCenter

                          MouseArea {
                            id: crumbMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: omackup.openRestoreFolder(modelData.path)
                          }
                        }
                      }
                    }
                  }
                }
              }

              Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Style.cornerRadius
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                border.width: 1

                ListView {
                  id: browserList
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  model: omackup ? omackup.listing : []
                  spacing: 2
                  currentIndex: omackup ? omackup.restoreEntryIndex : 0

                  Text {
                    visible: browserList.count === 0
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Style.space(10)
                    text: omackup && omackup.busy ? "Reading files…" : "This snapshot is empty here."
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                  }

                  delegate: CursorSurface {
                    required property var modelData
                    required property int index
                    width: browserList.width
                    implicitHeight: Style.space(36)
                    foreground: root.foreground
                    hasCursor: omackup && omackup.restoreFocus === "browser" && omackup.restoreEntryIndex === index
                    current: omackup && omackup.restoreSelected && String(omackup.restoreSelected.path) === String(modelData.path)
                    onHasCursorChanged: if (hasCursor) browserList.positionViewAtIndex(index, ListView.Contain)

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: {
                        omackup.restoreFocus = "browser"
                        omackup.restoreEntryIndex = index
                      }
                      onClicked: {
                        if (modelData.type === "dir") omackup.activateRestoreEntry(modelData, index)
                        else omackup.selectRestoreEntry(modelData, index)
                      }
                    }

                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(8)
                      anchors.rightMargin: Style.space(8)
                      spacing: Style.space(8)

                      Text {
                        text: Model.entryGlyph(modelData)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.icon
                        anchors.verticalCenter: parent.verticalCenter
                      }
                      Text {
                        width: parent.width - Style.space(90)
                        text: modelData.name
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                      }
                      Text {
                        visible: modelData.type !== "dir"
                        text: Model.formatBytes(modelData.size)
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }
                  }
                }
              }
            }

            // Preview — only for text and images
            ColumnLayout {
              id: previewPane
              visible: root.showPreviewPane
              SplitView.preferredWidth: root.previewWidth
              SplitView.minimumWidth: Style.font.baseSize * 12
              Layout.fillHeight: true
              spacing: Style.space(8)
              onWidthChanged: {
                if (!visible || width <= 0 || !root.previewResizeActive) return
                var next = Math.round(width)
                if (next !== root.previewWidth) root.previewWidth = next
              }

              Text {
                text: "Preview"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Style.cornerRadius
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                border.width: 1
                clip: true

                Text {
                  visible: omackup && omackup.previewLoading
                  anchors.fill: parent
                  anchors.margins: Style.space(12)
                  text: "Loading…"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  verticalAlignment: Text.AlignVCenter
                  horizontalAlignment: Text.AlignHCenter
                }

                Image {
                  id: previewImage
                  visible: omackup && !omackup.previewLoading && omackup.preview.kind === "image" && previewImage.status !== Image.Error
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  source: omackup && omackup.preview.kind === "image" && omackup.preview.image_path ? root.fileUrl(omackup.preview.image_path) : ""
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  cache: false
                  smooth: true
                }

                Text {
                  visible: root.previewUnsupported
                  anchors.fill: parent
                  anchors.margins: Style.space(16)
                  text: "preview for this file not supported"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  verticalAlignment: Text.AlignVCenter
                  horizontalAlignment: Text.AlignHCenter
                }

                ScrollView {
                  visible: omackup && !omackup.previewLoading && omackup.preview.kind === "text"
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  clip: true
                  ScrollBar.horizontal.policy: ScrollBar.AsNeeded

                  TextEdit {
                    id: previewText
                    width: parent.width
                    readOnly: true
                    wrapMode: TextEdit.Wrap
                    text: omackup ? String(omackup.preview.text || "") : ""
                    color: root.foreground
                    font.family: "monospace"
                    font.pixelSize: Style.font.bodySmall
                    selectByMouse: true
                    persistentSelection: true
                  }
                }
              }
            }
            }
          }

          Flow {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Repeater {
              model: root.shortcutHints
              Text {
                required property string modelData
                text: modelData
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
