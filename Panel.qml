import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "forecast.js" as Forecast

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
  property var pools: []
  property var aggregateForecast: null
  property string generatedAt: ""
  property string forecastGeneratedAt: ""
  property string forecastStatus: "unavailable"
  property string errorText: ""
  property bool refreshing: false
  property double nowMs: Date.now()

  readonly property var compatiblePools: pools.filter(function(pool) { return pool.comparable === true })
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

  function forecastFor(account) {
    if (!account || !account.forecast) return null
    var forecast = account.forecast
    var generated = Forecast.timestampMs(forecast.generated_at || forecastGeneratedAt)
    var ttl = Math.max(60000, Number(setting("refreshIntervalSec", 300)) * 2000)
    if (!isFinite(generated) || nowMs - generated > ttl) return null
    return forecast
  }

  function runwayFor(account) {
    return Forecast.runway(forecastFor(account), nowMs,
                           account ? String(account.usage_status || "") : "unavailable")
  }

  function poolRunway(pool) {
    if (!pool) return Forecast.runway(null, nowMs, "unavailable")
    var generated = Forecast.timestampMs(aggregateForecast && aggregateForecast.generated_at
      ? aggregateForecast.generated_at : forecastGeneratedAt)
    var ttl = Math.max(60000, Number(setting("refreshIntervalSec", 300)) * 2000)
    if (!isFinite(generated) || nowMs - generated > ttl)
      return Forecast.runway(null, nowMs, "unavailable")
    return Forecast.poolRunway(pool, nowMs)
  }

  function compactStat(account) {
    var percent = headlinePercent(account)
    return percent >= 0 ? percent + "%" : "—"
  }

  function stateColor(kind) {
    if (kind === "exhausted" || kind === "stale" || kind === "unavailable" || kind === "elapsed") return root.urgent
    if (kind === "estimate") return root.foreground
    return root.dim
  }

  function hasDiagnostic(list, code) {
    list = list || []
    for (var i = 0; i < list.length; i++) if (String(list[i].code || "") === code) return true
    return false
  }

  function poolTitle(pool) {
    if (!pool) return "Quota pool"
    var title = root.providerName(pool.provider) + " · " + String(pool.window_name || pool.window_id || "quota")
    if (!pool.comparable && pool.members && pool.members.length === 1)
      title += " · " + String(pool.members[0].label || "account")
    return title
  }

  function poolCaveat(pool) {
    if (!pool) return ""
    if (hasDiagnostic(pool.diagnostics, "POOL_CAPPED_DEMAND_CENSORED")) return "100% cap hides demand"
    if (hasDiagnostic(pool.diagnostics, "POOL_MISSING_BURN")) return "Missing recent burn on one or more accounts"
    if (hasDiagnostic(pool.diagnostics, "POOL_ACCOUNT_QUALIFIED")) return "One account has another unestimated window"
    if ((pool.diagnostics || []).length > 0) return "Estimate has limitations"
    return ""
  }

  function accountCaveat(account) {
    var forecast = forecastFor(account)
    if (!forecast) return ""
    if (forecast.qualification || forecast.status === "estimated_qualified") return "Qualified"
    if ((forecast.diagnostics || []).length > 0) return "Limited estimate"
    return ""
  }

  function usageNote(account) {
    if (!account) return ""
    var status = String(account.usage_status || "")
    if (status === "stale") return "Stale usage"
    if (status === "error" || status === "unavailable") return "Usage unavailable"
    if (status === "cache") return "Cached usage"
    return ""
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

  function forecastWindow(account, id) {
    var forecast = forecastFor(account)
    if (!forecast || forecast.history_error || String(forecast.status || "") === "stale" ||
        String(forecast.status || "") === "reauth_required" ||
        String(forecast.account_status || "") !== "ready" ||
        String(account.usage_status || "") === "error" ||
        String(account.usage_status || "") === "unavailable") return null
    var windows = forecast ? (forecast.windows || []) : []
    for (var i = 0; i < windows.length; i++) if (windows[i].id === id) return windows[i]
    return null
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
    var observed = Forecast.timestampMs(account.observed_at)
    if (isFinite(observed)) return "Updated " + formatDuration(nowMs - observed) + " ago"
    var reportedAge = Number(account.age_seconds)
    if (reportedAge > 0 && isFinite(reportedAge)) return "Observed " + formatDuration(reportedAge * 1000) + " ago"
    return "No usage sample"
  }

  function clearForecasts() {
    var current = []
    for (var i = 0; i < accounts.length; i++) {
      var copy = {}
      for (var key in accounts[i]) copy[key] = accounts[i][key]
      copy.forecast = null
      current.push(copy)
    }
    accounts = current
    pools = []
    aggregateForecast = null
    forecastGeneratedAt = ""
    forecastStatus = "unavailable"
  }

  function refreshNow() {
    if (fetchProcess.running) return
    clearForecasts()
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
      pools = payload.pools || []
      aggregateForecast = payload.forecast || null
      nowMs = Date.now()
      generatedAt = String(payload.generated_at || "")
      forecastGeneratedAt = String(payload.forecast_generated_at || "")
      forecastStatus = String(payload.forecast_status || "unavailable")
      errorText = ""
    } catch (error) {
      errorText = "Lachesis returned unreadable data"
      clearForecasts()
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
    running: true
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
    tooltipText: "Active account usage and runway"
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
        account: root.activeCodex
        valueText: root.compactStat(root.activeCodex)
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
        account: root.activeClaude
        valueText: root.compactStat(root.activeClaude)
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(600))

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
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: panelFlick.width
          spacing: Style.space(12)

          Column {
            width: parent.width
            spacing: Style.space(3)
            Text {
              text: "AI account usage"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              text: root.refreshing ? "Refreshing…" : root.accounts.length + " accounts · Lachesis"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
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
            visible: root.compatiblePools.length > 0
            width: parent.width
            spacing: Style.space(6)
            Text {
              text: "Combined runway · if switching accounts"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Repeater {
              model: root.compatiblePools
              PoolCard {
                required property var modelData
                width: panelFlick.width
                pool: modelData
              }
            }
          }

          Text {
            visible: root.compatiblePools.length === 0
            width: parent.width
            text: root.refreshing ? "Loading runway estimates…" :
              root.forecastStatus === "unavailable" ? "Runway estimates unavailable" : "No compatible account pools"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

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
            text: "R refreshes · select an account for details"
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
    property var account: null
    property string valueText: "—"
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
      text: providerStat.valueText
      color: button.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      renderType: Text.NativeRendering
      anchors.verticalCenter: parent.verticalCenter
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
    property bool expanded: false
    readonly property var runway: root.runwayFor(account)
    readonly property var windows: root.displayWindows(account)
    readonly property var forecast: root.forecastFor(account)
    readonly property string caveat: root.accountCaveat(account)
    spacing: Style.space(6)

    Controls.Button {
      width: parent.width
      padding: 0
      hoverEnabled: true
      background: Rectangle {
        color: parent.hovered || parent.activeFocus ? root.alpha(root.foreground, 0.05) : "transparent"
        radius: Style.cornerRadius
      }
      onClicked: accountCard.expanded = !accountCard.expanded
      Accessible.name: root.shortLabel(accountCard.account) + ", " +
        (root.headlinePercent(accountCard.account) >= 0 ? root.headlinePercent(accountCard.account) + " percent used, " : "") +
        accountCard.runway.label + (accountCard.caveat ? ", " + accountCard.caveat : "") +
        (accountCard.expanded ? ", collapse details" : ", expand details")

      contentItem: Column {
        spacing: Style.space(4)
        Item {
          width: parent.width
          implicitHeight: Math.max(accountName.implicitHeight, accountValue.implicitHeight)
          Text {
            id: accountName
            text: (accountCard.account && accountCard.account.active ? "● " : "") + root.shortLabel(accountCard.account)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: accountCard.account && accountCard.account.active
            anchors.left: parent.left
            anchors.right: accountValue.left
            anchors.rightMargin: Style.space(10)
            elide: Text.ElideRight
          }
          Text {
            id: accountValue
            text: (root.headlinePercent(accountCard.account) >= 0 ? root.headlinePercent(accountCard.account) + "% used" : "Unavailable") +
              (accountCard.expanded ? "  ▴" : "  ▾")
            color: root.headlinePercent(accountCard.account) >= 90 ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            anchors.right: parent.right
          }
        }

        Text {
          width: parent.width
          text: accountCard.runway.label + (accountCard.caveat ? " · " + accountCard.caveat : "")
          color: accountCard.caveat ? root.urgent : root.stateColor(accountCard.runway.kind)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: accountCard.windows
          Column {
            id: usageRow
            required property var modelData
            required property int index
            width: parent.width
            spacing: Style.space(3)
            Text {
              visible: accountCard.windows.length > 1
              width: parent.width
              text: modelData.name + " · " + Math.round(Number(modelData.used_percent)) + "% used"
              color: Number(modelData.used_percent) >= 90 ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Meter {
              width: parent.width
              value: Number(usageRow.modelData.used_percent) / 100
              alarming: Number(usageRow.modelData.used_percent) >= 90
            }
            Text {
              width: parent.width
              text: (accountCard.windows.length === 1 ? usageRow.modelData.name + " · " : "") +
                root.resetText(usageRow.modelData) +
                (usageRow.index === 0 && root.usageNote(accountCard.account) ? " · " + root.usageNote(accountCard.account) : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }

    Column {
      visible: accountCard.expanded
      width: parent.width
      spacing: Style.space(5)
      Text {
        width: parent.width
        text: root.shortLabel(accountCard.account) +
          (accountCard.account && accountCard.account.active ? " · Active account" : "") +
          (accountCard.account && accountCard.account.plan ? " · " + accountCard.account.plan : "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
      Text {
        width: parent.width
        text: accountCard.runway.detail
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
      Text {
        width: parent.width
        text: root.ageText(accountCard.account) +
          (accountCard.forecast ? " · " + Forecast.coverageText(accountCard.forecast.coverage_hours) : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
      Repeater {
        model: accountCard.windows
        Text {
          required property var modelData
          readonly property var windowForecast: root.forecastWindow(accountCard.account, modelData.id)
          width: parent.width
          visible: windowForecast !== null
          text: modelData.name + ": " + Forecast.windowRunway(windowForecast, root.nowMs).label +
            (windowForecast ? " · " + Forecast.coverageText(windowForecast.coverage_48h_hours) : "") +
            (windowForecast && root.hasDiagnostic(windowForecast.diagnostics, "USAGE_CAPPED_DEMAND_CENSORED") ? " · 100% cap hides demand" : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  component PoolCard: BorderSurface {
    id: poolCard
    property var pool: null
    property bool expanded: false
    readonly property var runway: root.poolRunway(pool)
    implicitHeight: poolContent.implicitHeight + Style.space(16)
    color: root.alpha(root.foreground, 0.035)
    borderSpec: Border.flat(root.alpha(root.foreground, 0.16), 1)
    radius: Style.cornerRadius

    Column {
      id: poolContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(8)
      spacing: Style.space(6)

      Controls.Button {
        width: parent.width
        padding: 0
        hoverEnabled: true
        background: Rectangle {
          color: parent.hovered || parent.activeFocus ? root.alpha(root.foreground, 0.05) : "transparent"
          radius: Style.cornerRadius
        }
        onClicked: poolCard.expanded = !poolCard.expanded
        Accessible.name: root.poolTitle(poolCard.pool) + ", " + poolCard.runway.label +
          (root.poolCaveat(poolCard.pool) ? ", qualified" : "") +
          (poolCard.expanded ? ", collapse details" : ", expand details")
        contentItem: Column {
          spacing: Style.space(3)
          Item {
            width: parent.width
            implicitHeight: Math.max(poolTitle.implicitHeight, poolValue.implicitHeight)
            Text {
              id: poolTitle
              text: root.poolTitle(poolCard.pool)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.left: parent.left
              anchors.right: poolValue.left
              anchors.rightMargin: Style.space(8)
              elide: Text.ElideRight
            }
            Text {
              id: poolValue
              text: poolCard.runway.label
              color: root.stateColor(poolCard.runway.kind)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
            }
          }
          Text {
            width: parent.width
            text: {
              if (!poolCard.pool) return ""
              var plan = poolCard.pool.plan_known && poolCard.pool.plan ? String(poolCard.pool.plan) : "Plan unknown"
              return plan + " · " + Number(poolCard.pool.capacity_member_count || 0) + " accounts" +
                (root.poolCaveat(poolCard.pool) ? " · Qualified" : "") +
                (poolCard.expanded ? "  ▴" : "  ▾")
            }
            color: root.poolCaveat(poolCard.pool) ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }

      Column {
        visible: poolCard.expanded
        width: parent.width
        spacing: Style.space(5)
        Text {
          width: parent.width
          text: poolCard.pool ? (poolCard.pool.members || []).map(function(member) { return member.label }).join(" · ") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          text: "Assumes work can switch between accounts with matching provider, plan and quota window."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          text: poolCard.runway.detail +
            (poolCard.pool ? " · " + Forecast.coverageText(poolCard.pool.coverage_hours) : "") +
            (root.poolCaveat(poolCard.pool) ? " · " + root.poolCaveat(poolCard.pool) : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          text: poolCard.pool ? (Number(poolCard.pool.remaining_percent_points || 0) / 100).toFixed(1) +
            " account allowances remaining" : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
