// Presentation helpers for Lachesis forecast states. The service owns the
// estimate; this file only turns an explicit state into short UI copy.
function timestampMs(value) {
  if (value === null || value === undefined || value === "") return NaN
  var timestamp = new Date(value).getTime()
  return isFinite(timestamp) ? timestamp : NaN
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

function activeAccount(accounts, provider, providerAccountUuid) {
  var matches = []
  var active = []
  var uuidMatches = []
  accounts = accounts || []
  for (var i = 0; i < accounts.length; i++) {
    var account = accounts[i]
    if (account.provider !== provider) continue
    matches.push(account)
    if (provider === "claude" && providerAccountUuid &&
        account.provider_account_uuid === providerAccountUuid) uuidMatches.push(account)
    if (provider !== "claude" && account.active === true) active.push(account)
  }
  if (provider === "claude") {
    return providerAccountUuid && uuidMatches.length === 1 ? uuidMatches[0] : null
  }
  if (active.length === 1) return active[0]
  return matches.length > 0 ? matches[0] : null
}

function otherProviderAccounts(accounts) {
  var out = []
  accounts = accounts || []
  for (var i = 0; i < accounts.length; i++) {
    var account = accounts[i]
    var provider = account && typeof account.provider === "string" ? account.provider : ""
    if (provider !== "codex" && provider !== "claude") out.push(account)
  }
  return out
}

function providerAccentRole(provider) {
  if (provider === "claude") return "accent"
  if (provider === "codex") return "foreground"
  return "neutral"
}

function runwayIsUrgent(kind) {
  return kind === "exhausted" || kind === "stale" || kind === "unavailable" || kind === "elapsed"
}

function estimateDate(forecast) {
  return forecast ? timestampMs(forecast.exhaustion_at) : NaN
}

function resetDate(window) {
  return window ? timestampMs(window.resets_at) : NaN
}

function statusLabel(forecast, usageStatus) {
  if (!forecast) {
    if (usageStatus === "error" || usageStatus === "unavailable") return "Unavailable"
    return "No forecast"
  }
  var status = String(forecast.status || "")
  var accountStatus = String(forecast.account_status || "")
  if (status === "reauth_required" || accountStatus === "reauth_required") return "Sign in required"
  if (status === "stale") return "Stale estimate"
  if (status === "exhausted") return "Exhausted"
  if (status === "awaiting_update") return "Awaiting update"
  if (status === "resets_before_exhaustion") return "Resets before depletion"
  if (status === "zero_burn") return "No observed burn"
  if (status === "unknown_reset") return "Unknown reset"
  if (status === "gapped_history") return "History gap"
  if (status === "insufficient_history" || status === "windows_missing") return "Collecting history"
  if (status === "history_persistence_error") return "History unavailable"
  if (status === "incomplete") return "Incomplete estimate"
  if (status === "estimate_out_of_range") return "No finite estimate"
  if (status === "estimated_qualified") return "Qualified estimate"
  if (status === "account_degraded" || accountStatus === "degraded") return "Account unavailable"
  if (status === "steady" || status === "estimated") return "Estimated"
  if (status === "unavailable") return "Unavailable"
  return status || "No forecast"
}

function runway(forecast, nowMs, usageStatus) {
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  var label = statusLabel(forecast, usageStatus)
  if (!forecast) return {kind: "unavailable", label: label, detail: "Forecast unavailable"}

  var status = String(forecast.status || "")
  var exhaustion = estimateDate(forecast)
  var windows = forecast.windows || []
  var hasResetBeforeDepletion = false
  var hasExhaustedWindow = false
  var resetPassed = false
  for (var i = 0; i < windows.length; i++) {
    if (String(windows[i].status || "") === "resets_before_exhaustion") hasResetBeforeDepletion = true
    else if (String(windows[i].status || "") === "exhausted") hasExhaustedWindow = true
    if (isFinite(resetDate(windows[i])) && resetDate(windows[i]) <= now) resetPassed = true
  }
  if (status === "stale") return {kind: "stale", label: label, detail: "History is too old to trust"}
  if (status === "reauth_required" || String(forecast.account_status || "") === "reauth_required")
    return {kind: "unavailable", label: label, detail: "Reconnect this account"}
  if (usageStatus === "error" || usageStatus === "unavailable")
    return {kind: "unavailable", label: "Unavailable", detail: "Lachesis could not read this account"}
  if (String(forecast.account_status || "") === "degraded")
    return {kind: "unavailable", label: "Account unavailable", detail: "Lachesis could not use this account"}
  if (forecast.history_error)
    return {kind: "unavailable", label: "History unavailable", detail: "Saved history is unavailable"}
  if (resetPassed)
    return {kind: "pending", label: "Awaiting update", detail: "The limit reset; waiting for fresh usage"}
  if (hasExhaustedWindow)
    return {kind: "exhausted", label: "Exhausted", detail: "Allowance is spent"}
  if (status === "exhausted" || (isFinite(exhaustion) && exhaustion <= now))
    return status === "exhausted" || hasExhaustedWindow
      ? {kind: "exhausted", label: "Exhausted", detail: "Allowance is spent"}
      : {kind: "elapsed", label: "Estimate elapsed", detail: "Refresh before trusting this projection"}
  if (status === "resets_before_exhaustion")
    return {kind: "reset", label: "Resets before depletion", detail: "The limit resets first"}
  if (status === "estimated" && !isFinite(exhaustion) && hasResetBeforeDepletion)
    return {kind: "reset", label: "Resets before depletion", detail: "The limit resets first"}
  if (status === "zero_burn")
    return {kind: "idle", label: "No observed burn", detail: "Need demand to project runway"}
  if (isFinite(exhaustion) && exhaustion > now &&
      (status === "estimated" || status === "steady" || status === "estimated_qualified")) {
    var detail = "Runs out in " + formatDuration(exhaustion - now)
    if (status === "estimated_qualified" && forecast.qualification)
      detail += " · " + String(forecast.qualification)
    return {kind: "estimate", label: "~" + formatDuration(exhaustion - now) + " left", detail: detail}
  }
  if (status === "unknown_reset") return {kind: "unknown", label: "Unknown reset", detail: "A reset was observed without a marker"}
  if (status === "gapped_history") return {kind: "unknown", label: "History gap", detail: "Waiting for a continuous sample"}
  if (status === "insufficient_history" || status === "windows_missing")
    return {kind: "collecting", label: "Collecting history", detail: "Runway appears after an hour of samples"}
  if (status === "history_persistence_error") return {kind: "unavailable", label: "History unavailable", detail: "Could not read saved samples"}
  if (status === "estimate_out_of_range") return {kind: "unknown", label: "No finite estimate", detail: "Observed burn is too small to project"}
  if (status === "incomplete") return {kind: "unknown", label: "Incomplete estimate", detail: "Some compatible capacity has no measured rate"}
  if (status === "account_degraded")
    return {kind: "unavailable", label: "Account unavailable", detail: "Lachesis could not use this account"}
  if (status === "steady" || status === "estimated") return {kind: "unknown", label: "No estimate", detail: "Waiting for a finite exhaustion time"}
  return {kind: "unavailable", label: label, detail: "Forecast unavailable"}
}

function windowRunway(window, nowMs) {
  if (!window) return {kind: "unavailable", label: "No window", detail: "No usage window"}
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  var status = String(window.status || "")
  var exhaustion = estimateDate(window)
  var reset = resetDate(window)
  if (status === "stale") return {kind: "stale", label: "Stale", detail: "History is too old to trust"}
  if (isFinite(reset) && reset <= now) return {kind: "pending", label: "Awaiting update", detail: "The limit reset; waiting for fresh usage"}
  if (status === "exhausted") return {kind: "exhausted", label: "Exhausted", detail: "Allowance is spent"}
  if (isFinite(exhaustion) && exhaustion <= now)
    return {kind: "elapsed", label: "Estimate elapsed", detail: "Refresh before trusting this projection"}
  if (status === "resets_before_exhaustion") return {kind: "reset", label: "Resets first", detail: "The limit resets before depletion"}
  if (status === "zero_burn") return {kind: "idle", label: "No observed burn", detail: "Need demand to project runway"}
  if (isFinite(exhaustion) && exhaustion > now &&
      (status === "steady" || status === "estimated" || status === "estimated_qualified"))
    return {kind: "estimate", label: "~" + formatDuration(exhaustion - now) + " left", detail: "Estimated exhaustion"}
  if (status === "unknown_reset") return {kind: "unknown", label: "Unknown reset", detail: "Reset marker is missing"}
  if (status === "gapped_history") return {kind: "unknown", label: "History gap", detail: "Waiting for a continuous sample"}
  if (status === "insufficient_history") return {kind: "collecting", label: "Collecting history", detail: "Need more samples"}
  if (status === "estimate_out_of_range") return {kind: "unknown", label: "No finite estimate", detail: "Observed burn is too small to project"}
  return {kind: "unknown", label: status || "No estimate", detail: "No finite exhaustion time"}
}

// One answer per harness: if work moves to another account as each one runs
// out, does the combined allowance last until an account gets allowance back?
// Every account's allowance counts the same, whatever its plan.
var HARNESS_WINDOWS = {codex: ["primary"], claude: ["five_hour", "seven_day"]}

function harnessWindow(forecasts, windowId, now) {
  var remaining = 0
  var rate = 0
  var nextReset = NaN
  var members = 0
  for (var i = 0; i < forecasts.length; i++) {
    var windows = forecasts[i].windows || []
    var window = null
    for (var j = 0; j < windows.length; j++) if (windows[j].id === windowId) window = windows[j]
    if (!window) continue
    var left = Number(window.remaining_percent)
    if (!isFinite(left)) continue
    members++
    var reset = resetDate(window)
    // A reset that already passed has given the allowance back.
    if (isFinite(reset) && reset <= now) left = 100
    remaining += left
    var accountRate = Number(window.rate_percent_per_hour)
    if (accountRate > 0 && isFinite(accountRate)) rate += accountRate
    if (left < 100 && isFinite(reset) && reset > now && !(reset >= nextReset)) nextReset = reset
  }
  if (members === 0) return null
  var runsOut = rate > 0 ? now + remaining / rate * 3600000 : NaN
  var lasts = !isFinite(runsOut) || !isFinite(nextReset) || runsOut >= nextReset
  return {windowId: windowId, lasts: lasts, runsOut: runsOut, nextReset: nextReset, remaining: remaining}
}

function accountPlanCaveat(account, forecast) {
  if (!account || account.provider !== "claude") return ""
  var plan = forecast ? forecast.plan : account.plan
  return String(plan || "").trim() ? "" : "Plan unknown; kept separate from Combined"
}

function comparableClaudeWindowStatus(status) {
  return status === "steady" || status === "resets_before_exhaustion" ||
    status === "zero_burn" || status === "exhausted"
}

function comparableClaudeWindow(forecast, id) {
  var windows = forecast ? forecast.windows || [] : []
  for (var i = 0; i < windows.length; i++) {
    var window = windows[i]
    var seconds = Number(window.window_seconds)
    if (window.id === id && comparableClaudeWindowStatus(String(window.status || "")) &&
        seconds > 0 && isFinite(seconds) && isFinite(Number(window.remaining_percent))) return window
  }
  return null
}

function unavailableClaudeRunway(detail, label) {
  return {
    kind: "unavailable",
    runsOut: NaN,
    nextReset: NaN,
    label: label || "No Combined estimate",
    detail: detail
  }
}

function claudeHarnessRunway(accounts, now) {
  accounts = accounts || []
  var hasClaude = false
  for (var i = 0; i < accounts.length; i++) if (accounts[i].provider === "claude") hasClaude = true
  if (!hasClaude) return {kind: "unavailable", runsOut: NaN, nextReset: NaN}

  var candidates = []
  var planNames = []
  var excluded = false
  var sawForecast = false
  var unknownPlan = false
  var expectedWindows = HARNESS_WINDOWS.claude || []
  for (var j = 0; j < accounts.length; j++) {
    if (accounts[j].provider !== "claude") continue
    var forecast = accounts[j].forecast
    if (!forecast) {
      excluded = true
      continue
    }
    sawForecast = true
    if (forecast.status === "stale" || forecast.status === "reauth_required" ||
        forecast.account_status === "reauth_required" || forecast.history_error) {
      excluded = true
      continue
    }
    var plan = String(forecast.plan || "")
    if (!plan.trim()) {
      unknownPlan = true
      excluded = true
      continue
    }
    var hasComparableWindow = false
    for (var k = 0; k < expectedWindows.length; k++)
      if (comparableClaudeWindow(forecast, expectedWindows[k])) hasComparableWindow = true
    if (!hasComparableWindow) {
      excluded = true
      continue
    }
    if (planNames.indexOf(plan) < 0) planNames.push(plan)
    candidates.push(forecast)
  }

  if (planNames.length === 0) {
    if (!sawForecast)
      return unavailableClaudeRunway("No current forecast is available; per-account rows remain visible.", "Runway unavailable")
    if (unknownPlan)
      return unavailableClaudeRunway("Plan unknown; account runways remain separate below.")
    return unavailableClaudeRunway("No current comparable Claude data; per-account states remain below.")
  }
  if (planNames.length > 1)
    return unavailableClaudeRunway("Claude plans differ; see the per-account runways below.")

  var results = []
  for (var windowIndex = 0; windowIndex < expectedWindows.length; windowIndex++) {
    var windowId = expectedWindows[windowIndex]
    var durations = []
    var matchingForecasts = []
    var allExhausted = true
    for (var matchingIndex = 0; matchingIndex < candidates.length; matchingIndex++) {
      var candidateForecast = candidates[matchingIndex]
      var window = comparableClaudeWindow(candidateForecast, windowId)
      if (!window) {
        excluded = true
        continue
      }
      var duration = Number(window.window_seconds)
      if (durations.indexOf(duration) < 0) durations.push(duration)
      var forecastCopy = {}
      for (var forecastKey in candidateForecast) forecastCopy[forecastKey] = candidateForecast[forecastKey]
      forecastCopy.windows = [window]
      matchingForecasts.push(forecastCopy)
      if (window.status !== "exhausted") allExhausted = false
    }
    if (durations.length === 0) continue
    if (durations.length > 1) {
      excluded = true
      continue
    }
    var windowResult = allExhausted
      ? {windowId: windowId, lasts: false, runsOut: now, nextReset: NaN, exhausted: true}
      : harnessWindow(matchingForecasts, windowId, now)
    results.push(windowResult)
  }

  if (results.length === 0)
    return unavailableClaudeRunway("No matching plan and window data can be combined; see the per-account runways below.")
  var short = null
  for (var resultIndex = 0; resultIndex < results.length; resultIndex++)
    if (!results[resultIndex].lasts && (!short || results[resultIndex].runsOut < short.runsOut)) short = results[resultIndex]
  var summary
  if (short) summary = short.exhausted
    ? {kind: "exhausted", runsOut: short.runsOut, nextReset: short.nextReset}
    : {kind: "short", runsOut: short.runsOut, nextReset: short.nextReset}
  else {
    var longest = results[results.length - 1]
    summary = !isFinite(longest.runsOut)
      ? {kind: "idle", runsOut: NaN, nextReset: longest.nextReset}
      : {kind: "lasts", runsOut: longest.runsOut, nextReset: longest.nextReset}
  }
  if (excluded) summary.qualified = true
  return summary
}

function harnessRunway(accounts, provider, nowMs) {
  var now = Number(nowMs)
  if (!isFinite(now)) now = Date.now()
  if (provider === "claude") return claudeHarnessRunway(accounts, now)
  var forecasts = []
  accounts = accounts || []
  for (var i = 0; i < accounts.length; i++) {
    var forecast = accounts[i].forecast
    // A failed refresh (degraded) still leaves a recent sample worth counting.
    if (accounts[i].provider === provider && forecast && forecast.status !== "stale" &&
        forecast.account_status !== "reauth_required") forecasts.push(forecast)
  }
  var ids = HARNESS_WINDOWS[provider] || []
  var results = []
  for (var k = 0; k < ids.length; k++) {
    var result = harnessWindow(forecasts, ids[k], now)
    if (result) results.push(result)
  }
  if (results.length === 0) return {kind: "unavailable", runsOut: NaN, nextReset: NaN}
  var short = null
  for (var m = 0; m < results.length; m++)
    if (!results[m].lasts && (!short || results[m].runsOut < short.runsOut)) short = results[m]
  if (short) return {kind: "short", runsOut: short.runsOut, nextReset: short.nextReset}
  // Everything lasts; report against the longest window, the one that matters most.
  var longest = results[results.length - 1]
  if (!isFinite(longest.runsOut)) return {kind: "idle", runsOut: NaN, nextReset: longest.nextReset}
  return {kind: "lasts", runsOut: longest.runsOut, nextReset: longest.nextReset}
}

function coverageText(hours) {
  var value = Number(hours)
  if (!(value > 0) || !isFinite(value)) return "No sample coverage"
  if (value < 1) return Math.round(value * 60) + "m sample coverage"
  if (value < 10) return value.toFixed(1) + "h sample coverage"
  return Math.round(value) + "h sample coverage"
}

if (typeof module !== "undefined") {
  module.exports = {
    timestampMs: timestampMs,
    formatDuration: formatDuration,
    activeAccount: activeAccount,
    otherProviderAccounts: otherProviderAccounts,
    providerAccentRole: providerAccentRole,
    runwayIsUrgent: runwayIsUrgent,
    statusLabel: statusLabel,
    runway: runway,
    windowRunway: windowRunway,
    harnessRunway: harnessRunway,
    accountPlanCaveat: accountPlanCaveat,
    coverageText: coverageText
  }
}
