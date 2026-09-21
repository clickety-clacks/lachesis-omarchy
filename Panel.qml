import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "mike.lachesis-usage"
  ipcTarget: "mike.lachesis-usage"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var accounts: []
  property string generatedAt: ""
  property string errorText: ""
  property bool refreshing: false
  property double nowMs: Date.now()

  readonly property var codexAccounts: accountsFor("codex")
  readonly property var claudeAccounts: accountsFor("claude")
  readonly property var activeCodex: activeFor("codex")
  readonly property var activeClaude: activeFor("claude")
  readonly property int codexPercent: headlinePercent(activeCodex)
  readonly property int claudePercent: headlinePercent(activeClaude)
  readonly property bool alarming: codexPercent >= 90 || claudePercent >= 90

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function clamp(value, low, high) { return Math.max(low, Math.min(high, value)) }
  function alpha(color, opacity) { return Qt.rgba(color.r, color.g, color.b, opacity) }

  function accountsFor(provider) {
    var out = []
    for (var i = 0; i < accounts.length; i++)
      if (accounts[i].provider === provider) out.push(accounts[i])
    out.sort(function(a, b) {
      if (a.active !== b.active) return a.active ? -1 : 1
      return headlinePercent(a) - headlinePercent(b)
    })
    return out
  }

  function activeFor(provider) {
    var list = accountsFor(provider)
    for (var i = 0; i < list.length; i++) if (list[i].active) return list[i]
    return list.length > 0 ? list[0] : null
  }

  function headlineWindow(account) {
    if (!account) return null
    var windows = account.windows || []
    var preferred = null
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      if (account.provider === "codex" && w.id === "primary") return w
      if (account.provider === "claude" && w.id === "seven_day") return w
      if (!preferred || Number(w.used_percent) > Number(preferred.used_percent)) preferred = w
    }
    return preferred
  }

  function headlinePercent(account) {
    var window = headlineWindow(account)
    return window ? Math.round(Number(window.used_percent)) : -1
  }

  function displayWindows(account) {
    if (!account) return []
    var windows = account.windows || []
    if (account.provider !== "codex") return windows
    var primary = []
    for (var i = 0; i < windows.length; i++)
      if (windows[i].id === "primary") primary.push(windows[i])
    return primary
  }

  function providerName(provider) { return provider === "codex" ? "Codex" : "Claude" }

  function shortLabel(account) {
    if (!account) return "Not connected"
    var label = String(account.label || "")
    var prefix = account.provider + "-"
    return label.indexOf(prefix) === 0 ? label.slice(prefix.length) : label
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  function resetText(window) {
    if (!window || !window.resets_at) return ""
    var timestamp = new Date(window.resets_at).getTime()
    if (!isFinite(timestamp)) return ""
    return "Resets in " + formatDuration(timestamp - nowMs)
  }

  function ageText(account) {
    if (!account) return ""
    var age = Math.max(0, Number(account.age_seconds || 0) * 1000 + (nowMs - new Date(account.observed_at).getTime()))
    if (!isFinite(age)) return ""
    return "Updated " + formatDuration(age) + " ago"
  }

  function refreshNow() {
    if (fetchProcess.running) return
    refreshing = true
    errorText = ""
    fetchProcess.command = [Qt.resolvedUrl("fetch.sh").toString().replace("file://", ""),
                            String(setting("host", "gibson")), String(setting("user", "mike"))]
    fetchProcess.running = true
  }

  function applyPayload(text) {
    try {
      var payload = JSON.parse(String(text || ""))
      accounts = payload.accounts || []
      generatedAt = String(payload.generated_at || "")
      errorText = ""
    } catch (error) {
      errorText = "Lachesis returned unreadable data"
    }
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refreshNow()
  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    refreshNow()
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    interval: Math.max(30, Number(root.setting("refreshIntervalSec", 300))) * 1000
    running: true
    repeat: true
    onTriggered: root.refreshNow()
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Process {
    id: fetchProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPayload(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "")
        root.errorText = "Cannot reach Lachesis on " + root.setting("host", "gibson")
    }
    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode !== 0 && root.errorText === "") root.errorText = "Lachesis refresh failed"
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: usageRow.implicitWidth + Style.space(24)
    horizontalMargin: 0
    verticalPadding: 8.75
    tooltipText: "Active Codex and Claude allowance used"
    active: root.alarming
    useActiveColor: false
    foreground: root.alarming
      ? root.urgent
      : root.foreground

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      radius: Style.cornerRadius
      color: "transparent"
      z: -1
    }

    Row {
      id: usageRow
      anchors.centerIn: parent
      spacing: Style.space(8)

      ProviderStat {
        iconSource: "file:///usr/share/omarchy/shell/plugins/agents/assets/codex.svg"
        iconName: "Codex"
        percent: root.codexPercent
      }

      Rectangle {
        width: Math.max(1, Style.space(1))
        height: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        color: root.alpha(button.foreground, 0.35)
      }

      ProviderStat {
        iconSource: "file:///usr/share/omarchy/shell/plugins/agents/assets/claude.svg"
        iconName: "Claude"
        percent: root.claudePercent
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refreshNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { if (text === "r" || text === "R") root.refreshNow() }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: panelFlick.width
          spacing: Style.space(14)

          PanelHero {
            width: parent.width
            title: "AI account usage"
            meta: root.refreshing ? "Refreshing from Gibson…" : "Lachesis · " + root.accounts.length + " accounts"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󱚣"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          BorderSurface {
            visible: root.errorText !== ""
            width: parent.width
            implicitHeight: errorLabel.implicitHeight + Style.space(24)
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: errorLabel
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: root.errorText
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            PanelSectionHeader {
              width: parent.width
              text: "ACTIVE NOW"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            ActiveCard { width: parent.width; account: root.activeCodex }
            ActiveCard { width: parent.width; account: root.activeClaude }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          ProviderSection {
            width: parent.width
            provider: "codex"
            model: root.codexAccounts
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          ProviderSection {
            width: parent.width
            provider: "claude"
            model: root.claudeAccounts
          }

          Text {
            width: parent.width
            text: "R refreshes · percentages are allowance used"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component Meter: Item {
    id: meter
    property real value: 0
    property bool alarming: false
    implicitHeight: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
    Rectangle { anchors.fill: parent; radius: height / 2; color: root.track }
    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      width: parent.width * root.clamp(meter.value, 0, 1)
      radius: height / 2
      color: meter.alarming ? root.urgent : root.foreground
      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
  }

  component ProviderStat: Row {
    id: providerStat
    property url iconSource: ""
    property string iconName: ""
    property int percent: -1
    spacing: Style.space(5)

    Rectangle {
      width: Style.space(17)
      height: Style.space(17)
      radius: Style.space(4)
      color: root.bar ? root.bar.background : Color.background
      anchors.verticalCenter: parent.verticalCenter

      Image {
        anchors.fill: parent
        anchors.margins: Style.space(3)
        source: providerStat.iconSource
        sourceSize.width: Style.space(22)
        sourceSize.height: Style.space(22)
        fillMode: Image.PreserveAspectFit
        smooth: true
      }
    }

    Text {
      text: providerStat.percent >= 0 ? providerStat.percent + "%" : "—"
      color: button.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      renderType: Text.NativeRendering
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  component ActiveCard: BorderSurface {
    id: card
    property var account: null
    readonly property int percent: root.headlinePercent(account)
    readonly property var window: root.headlineWindow(account)
    implicitHeight: activeContent.implicitHeight + Style.space(24)
    color: root.alpha(root.foreground, 0.035)
    borderSpec: Border.flat(root.alpha(root.foreground, 0.16), 1)
    radius: Style.cornerRadius

    Column {
      id: activeContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(12)
      spacing: Style.space(7)

      Item {
        width: parent.width
        implicitHeight: Math.max(activeTitle.implicitHeight, activeValue.implicitHeight)
        Text {
          id: activeTitle
          text: card.account ? root.providerName(card.account.provider) + " · " + root.shortLabel(card.account) : "Not connected"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          anchors.left: parent.left
          anchors.right: activeValue.left
          anchors.rightMargin: Style.space(10)
          elide: Text.ElideRight
        }
        Text {
          id: activeValue
          text: card.percent >= 0 ? card.percent + "%" : "—"
          color: card.percent >= 90 ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          anchors.right: parent.right
        }
      }
      Meter { width: parent.width; value: card.percent / 100; alarming: card.percent >= 90 }
      Text {
        width: parent.width
        text: card.window ? card.window.name + " · " + root.resetText(card.window) : "No usage window"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  component ProviderSection: Column {
    id: section
    property string provider: ""
    property var model: []
    spacing: Style.space(10)

    PanelSectionHeader {
      width: parent.width
      text: root.providerName(section.provider).toUpperCase() + " · " + section.model.length
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      visible: section.model.length === 0
      width: parent.width
      text: "No registered " + root.providerName(section.provider) + " accounts"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: section.model
      AccountCard {
        required property var modelData
        width: section.width
        account: modelData
      }
    }
  }

  component AccountCard: Column {
    id: accountCard
    property var account: null
    spacing: Style.space(7)

    Item {
      width: parent.width
      implicitHeight: Math.max(accountName.implicitHeight, accountState.implicitHeight)
      Text {
        id: accountName
        text: (accountCard.account && accountCard.account.active ? "●  " : "") + root.shortLabel(accountCard.account)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: accountCard.account && accountCard.account.active
        anchors.left: parent.left
        anchors.right: accountState.left
        anchors.rightMargin: Style.space(10)
        elide: Text.ElideRight
      }
      Text {
        id: accountState
        text: accountCard.account && accountCard.account.active ? "ACTIVE" : root.ageText(accountCard.account)
        color: accountCard.account && accountCard.account.active ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
      }
    }

    Repeater {
      model: root.displayWindows(accountCard.account)
      Column {
        required property var modelData
        width: accountCard.width
        spacing: Style.space(4)
        Item {
          width: parent.width
          implicitHeight: Math.max(windowName.implicitHeight, windowValue.implicitHeight)
          Text {
            id: windowName
            text: modelData.name
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.left: parent.left
            anchors.right: windowValue.left
            anchors.rightMargin: Style.space(8)
            elide: Text.ElideRight
          }
          Text {
            id: windowValue
            text: Math.round(Number(modelData.used_percent)) + "% · " + root.resetText(modelData)
            color: Number(modelData.used_percent) >= 90 ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.right: parent.right
          }
        }
        Meter {
          width: parent.width
          value: Number(modelData.used_percent) / 100
          alarming: Number(modelData.used_percent) >= 90
        }
      }
    }
  }
}
