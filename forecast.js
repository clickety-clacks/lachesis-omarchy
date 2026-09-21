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

function poolRunway(pool, nowMs) {
  if (!pool) return runway(null, nowMs, "unavailable")
  var members = pool.members || []
  var memberWindows = []
  for (var i = 0; i < members.length; i++)
    memberWindows.push({resets_at: members[i].resets_at || ""})
  return runway({
    status: String(pool.status || ""),
    exhaustion_at: pool.exhaustion_at || null,
    account_status: "ready",
    windows: memberWindows
  }, nowMs, "ready")
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
    statusLabel: statusLabel,
    runway: runway,
    windowRunway: windowRunway,
    poolRunway: poolRunway,
    coverageText: coverageText
  }
}
