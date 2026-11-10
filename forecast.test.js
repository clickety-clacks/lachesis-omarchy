#!/usr/bin/env node
"use strict"

const assert = require("assert")
const forecast = require("./forecast.js")

const now = Date.parse("2026-09-21T12:00:00Z")

function check(name, actual, expected) {
  assert.deepStrictEqual(actual, expected, name)
}

check("future estimate formats hours", forecast.runway({
  status: "estimated",
  exhaustion_at: "2026-09-21T15:30:00Z",
  account_status: "ready"
}, now), {
  kind: "estimate",
  label: "~3h 30m left",
  detail: "Runs out in 3h 30m"
})

check("qualified finite runway keeps its qualification", forecast.runway({
  status: "estimated_qualified",
  exhaustion_at: "2026-09-21T15:30:00Z",
  account_status: "ready",
  qualification: "Plan unknown"
}, now), {
  kind: "estimate",
  label: "~3h 30m left",
  detail: "Runs out in 3h 30m · Plan unknown"
})

check("unknown-plan qualification is context, not runway urgency", [
  forecast.runwayIsUrgent(forecast.runway({
    status: "estimated_qualified",
    exhaustion_at: "2026-09-21T15:30:00Z",
    account_status: "ready",
    qualification: "Plan unknown"
  }, now).kind),
  forecast.runwayIsUrgent("reset"),
  forecast.runwayIsUrgent("exhausted")
], [false, false, true])

check("unknown Claude plan stays account-only", forecast.accountPlanCaveat(
  {provider: "claude"}, {plan: null}
), "Plan unknown; kept separate from Combined")

check("known Claude plan has no unknown-plan caveat", forecast.accountPlanCaveat(
  {provider: "claude"}, {plan: "synthetic-plan-a"}
), "")

const unknownPlanForecast = {
  plan: null,
  status: "estimated",
  exhaustion_at: "2026-09-21T15:30:00Z",
  account_status: "ready"
}
const unknownPlanRunway = forecast.runway(unknownPlanForecast, now)
check("unknown-plan per-account ETA remains visible with its qualification", [
  unknownPlanRunway.kind,
  unknownPlanRunway.label,
  forecast.accountPlanCaveat({provider: "claude"}, unknownPlanForecast)
], ["estimate", "~3h 30m left", "Plan unknown; kept separate from Combined"])

check("Claude active account matches the provider UUID, independent of usage", forecast.activeAccount([
  {provider: "claude", id: "higher-usage", provider_account_uuid: "uuid-other", used_percent: 95},
  {provider: "claude", id: "active", provider_account_uuid: "uuid-current", used_percent: 5}
], "claude", "uuid-current"), {
  provider: "claude", id: "active", provider_account_uuid: "uuid-current", used_percent: 5
})

check("Claude active account stays unknown without a local UUID", forecast.activeAccount([
  {provider: "claude", id: "first", provider_account_uuid: "uuid-first", active: true},
  {provider: "claude", id: "second", provider_account_uuid: "uuid-second"}
], "claude", ""), null)

check("Claude active account stays unknown without a registered UUID", forecast.activeAccount([
  {provider: "claude", id: "only", provider_account_uuid: null}
], "claude", "uuid-current"), null)

check("Claude active account stays unknown when local UUID is not registered", forecast.activeAccount([
  {provider: "claude", id: "first", provider_account_uuid: "uuid-first"},
  {provider: "claude", id: "second", provider_account_uuid: "uuid-second"}
], "claude", "uuid-unmatched"), null)

check("duplicate registered Claude UUIDs remain ambiguous", forecast.activeAccount([
  {provider: "claude", id: "first", provider_account_uuid: "uuid-current"},
  {provider: "claude", id: "second", provider_account_uuid: "uuid-current"}
], "claude", "uuid-current"), null)

check("Codex fallback behavior remains unchanged", forecast.activeAccount([
  {provider: "codex", id: "first"},
  {provider: "codex", id: "second", active: false}
], "codex"), {provider: "codex", id: "first"})

check("provider accent roles distinguish the known providers and keep a neutral fallback", [
  forecast.providerAccentRole("claude"),
  forecast.providerAccentRole("codex"),
  forecast.providerAccentRole("unknown"),
  forecast.providerAccentRole("")
], ["accent", "foreground", "neutral", "neutral"])

const unknownProvider = {provider: "unknown", label: "Unknown account"}
const missingProvider = {label: "Missing provider"}
check("missing and unmapped provider accounts remain in the renderable fallback group",
  forecast.otherProviderAccounts([
    {provider: "claude", label: "Claude account"},
    {provider: "codex", label: "Codex account"},
    unknownProvider,
    missingProvider
  ]), [unknownProvider, missingProvider])

check("stale estimate cannot look current", forecast.runway({
  status: "stale",
  exhaustion_at: "2026-09-21T15:30:00Z",
  account_status: "ready"
}, now), {
  kind: "stale",
  label: "Stale estimate",
  detail: "History is too old to trust"
})

check("unknown reset stays qualified", forecast.runway({
  status: "unknown_reset",
  exhaustion_at: null,
  account_status: "ready"
}, now), {
  kind: "unknown",
  label: "Unknown reset",
  detail: "A reset was observed without a marker"
})

check("reset before depletion is explicit", forecast.windowRunway({
  status: "resets_before_exhaustion",
  exhaustion_at: null,
  resets_at: "2026-09-21T16:00:00Z"
}, now), {
  kind: "reset",
  label: "Resets first",
  detail: "The limit resets before depletion"
})

check("account reset status comes from its windows", forecast.runway({
  status: "estimated",
  exhaustion_at: null,
  account_status: "ready",
  windows: [{status: "resets_before_exhaustion"}]
}, now), {
  kind: "reset",
  label: "Resets before depletion",
  detail: "The limit resets first"
})

check("invalid date never becomes an ETA", forecast.runway({
  status: "estimated",
  exhaustion_at: "not-a-date",
  account_status: "ready"
}, now), {
  kind: "unknown",
  label: "No estimate",
  detail: "Waiting for a finite exhaustion time"
})

check("unavailable account stays in the panel", forecast.runway({
  status: "insufficient_history",
  account_status: "degraded"
}, now, "error"), {
  kind: "unavailable",
  label: "Unavailable",
  detail: "Lachesis could not read this account"
})

check("missing forecast remains unavailable", forecast.runway(null, now, "unavailable"), {
  kind: "unavailable",
  label: "Unavailable",
  detail: "Forecast unavailable"
})

check("past estimate is not observed exhaustion", forecast.runway({
  status: "estimated",
  exhaustion_at: "2026-09-21T11:59:59Z",
  account_status: "ready"
}, now), {
  kind: "elapsed",
  label: "Estimate elapsed",
  detail: "Refresh before trusting this projection"
})

check("exhausted window confirms exhaustion", forecast.runway({
  status: "estimated_qualified",
  exhaustion_at: "2026-09-21T11:59:59Z",
  account_status: "ready",
  windows: [{status: "exhausted"}]
}, now), {
  kind: "exhausted",
  label: "Exhausted",
  detail: "Allowance is spent"
})

const exhaustedRunway = forecast.runway({
  status: "exhausted",
  account_status: "ready"
}, now)
check("account-level exhaustion stays explicit and urgent", [
  exhaustedRunway,
  forecast.runwayIsUrgent(exhaustedRunway.kind)
], [{
  kind: "exhausted",
  label: "Exhausted",
  detail: "Allowance is spent"
}, true])

check("history error blocks a numeric estimate", forecast.runway({
  status: "estimated_qualified",
  exhaustion_at: "2026-09-21T15:30:00Z",
  history_error: "saved samples unavailable",
  account_status: "ready"
}, now), {
  kind: "unavailable",
  label: "History unavailable",
  detail: "Saved history is unavailable"
})

check("incomplete pool cannot use a date", forecast.runway({
  status: "incomplete",
  exhaustion_at: "2026-09-21T15:30:00Z",
  account_status: "ready"
}, now), {
  kind: "unknown",
  label: "Incomplete estimate",
  detail: "Some compatible capacity has no measured rate"
})

const hour = 3600000
const fiveHourSeconds = 5 * 60 * 60
const sevenDaySeconds = 7 * 24 * 60 * 60
function account(provider, windows, status, id, plan) {
  return {id: id || "synthetic-account", provider: provider, plan: plan,
    forecast: {plan: plan, account_status: status || "ready", windows: windows}}
}
function iso(ms) { return new Date(ms).toISOString() }
function claudeWindow(id, remaining, rate, reset, seconds, status) {
  return {id: id, status: status || "steady", remaining_percent: remaining,
    rate_percent_per_hour: rate, resets_at: reset, window_seconds: seconds}
}

check("rotation lasts when the combined allowance outlasts the next reset", forecast.harnessRunway([
  account("codex", [{id: "primary", remaining_percent: 20, rate_percent_per_hour: 2, resets_at: iso(now + 30 * hour)}]),
  account("codex", [{id: "primary", remaining_percent: 100, resets_at: iso(now + 100 * hour)}]),
  account("claude", [{id: "seven_day", remaining_percent: 0, rate_percent_per_hour: 50, resets_at: iso(now + hour)}])
], "codex", now), {kind: "lasts", runsOut: now + 60 * hour, nextReset: now + 30 * hour})

check("rotation falls short when the allowance runs out before the next reset", forecast.harnessRunway([
  account("codex", [{id: "primary", remaining_percent: 10, rate_percent_per_hour: 3, resets_at: iso(now + 80 * hour)}]),
  account("codex", [{id: "primary", remaining_percent: 50, rate_percent_per_hour: 1, resets_at: iso(now + 90 * hour)}])
], "codex", now), {kind: "short", runsOut: now + 15 * hour, nextReset: now + 80 * hour})

check("an untouched account's reset gives nothing back", forecast.harnessRunway([
  account("codex", [{id: "primary", remaining_percent: 40, rate_percent_per_hour: 2, resets_at: iso(now + 50 * hour)}]),
  account("codex", [{id: "primary", remaining_percent: 100, resets_at: iso(now + 5 * hour)}])
], "codex", now), {kind: "lasts", runsOut: now + 70 * hour, nextReset: now + 50 * hour})

check("a spent account's burn moves to the accounts that are left", forecast.harnessRunway([
  account("claude", [
    claudeWindow("five_hour", 100, 0, iso(now + 60 * hour), fiveHourSeconds, "zero_burn"),
    claudeWindow("seven_day", 0, 2, iso(now + 60 * hour), sevenDaySeconds)
  ], "ready", "claude-a", "synthetic-plan-a"),
  account("claude", [
    claudeWindow("five_hour", 90, 1, iso(now + 2 * hour), fiveHourSeconds),
    claudeWindow("seven_day", 90, 1, iso(now + 150 * hour), sevenDaySeconds)
  ], "ready", "claude-b", "synthetic-plan-a")
], "claude", now), {kind: "short", runsOut: now + 30 * hour, nextReset: now + 60 * hour})

check("a passed reset counts the account as full again", forecast.harnessRunway([
  account("codex", [{id: "primary", remaining_percent: 0, rate_percent_per_hour: 1, resets_at: iso(now - hour)}])
], "codex", now).kind, "lasts")

check("no recent use cannot run out", forecast.harnessRunway([
  account("codex", [{id: "primary", remaining_percent: 70, resets_at: iso(now + 10 * hour)}])
], "codex", now).kind, "idle")

check("a rate-limited account still counts its recent sample", forecast.harnessRunway([
  account("claude", [claudeWindow("seven_day", 50, 1, iso(now + 10 * hour), sevenDaySeconds)],
    "degraded", "claude-limited", "synthetic-plan-a")
], "claude", now).kind, "lasts")

const missingClaudeForecast = forecast.harnessRunway([
  {provider: "claude", plan: "synthetic-plan-a", forecast: null}
], "claude", now)
check("missing Claude forecast stays unavailable rather than implying unknown plan", [
  missingClaudeForecast.label,
  missingClaudeForecast.detail
], ["Runway unavailable", "No current forecast is available; per-account rows remain visible."])

const unknownPlanCombined = forecast.harnessRunway([
  account("claude", [claudeWindow("five_hour", 50, 5, iso(now + 24 * hour), fiveHourSeconds)],
    "ready", "known-plan-account", "synthetic-plan-a"),
  account("claude", [claudeWindow("five_hour", 100, 0, iso(now + 24 * hour), fiveHourSeconds, "zero_burn")],
    "ready", "unknown-plan-account", "")
], "claude", now)
check("unknown-plan Claude capacity is excluded from Combined", [
  unknownPlanCombined.kind,
  unknownPlanCombined.runsOut,
  unknownPlanCombined.qualified
], ["short", now + 10 * hour, true])

const differentPlanCombined = forecast.harnessRunway([
  account("claude", [claudeWindow("five_hour", 50, 5, iso(now + 24 * hour), fiveHourSeconds)],
    "ready", "plan-a-account", "synthetic-plan-a"),
  account("claude", [claudeWindow("five_hour", 50, 5, iso(now + 24 * hour), fiveHourSeconds)],
    "ready", "plan-b-account", "synthetic-plan-b")
], "claude", now)
check("different known Claude plans are not combined", [
  differentPlanCombined.kind,
  differentPlanCombined.label,
  differentPlanCombined.detail
], ["unavailable", "No Combined estimate", "Claude plans differ; see the per-account runways below."])

const incompatibleWindowCombined = forecast.harnessRunway([
  account("claude", [claudeWindow("five_hour", 50, 5, iso(now + 24 * hour), fiveHourSeconds)],
    "ready", "five-hour-account", "synthetic-plan-a"),
  account("claude", [claudeWindow("five_hour", 50, 5, iso(now + 24 * hour), fiveHourSeconds * 2)],
    "ready", "different-window-account", "synthetic-plan-a")
], "claude", now)
check("Claude windows with different durations are not combined", [
  incompatibleWindowCombined.kind,
  incompatibleWindowCombined.label
], ["unavailable", "No Combined estimate"])

const exhaustedCombined = forecast.harnessRunway([
  account("claude", [claudeWindow("five_hour", 0, null, iso(now + hour), fiveHourSeconds, "exhausted")],
    "ready", "exhausted-account", "synthetic-plan-a")
], "claude", now)
check("a fully spent comparable Claude group stays exhausted", exhaustedCombined.kind, "exhausted")

check("accounts that need sign-in are left out", forecast.harnessRunway([
  account("codex", [{id: "primary", remaining_percent: 70, rate_percent_per_hour: 1}], "reauth_required")
], "codex", now).kind, "unavailable")

check("reauth is actionable", forecast.runway({
  status: "reauth_required",
  account_status: "reauth_required"
}, now), {
  kind: "unavailable",
  label: "Sign in required",
  detail: "Reconnect this account"
})

check("a passed reset invalidates cached exhaustion", forecast.runway({
  status: "estimated_qualified",
  exhaustion_at: "2026-09-21T12:30:00Z",
  account_status: "ready",
  windows: [{status: "exhausted", resets_at: "2026-09-21T11:59:00Z"}]
}, now), {
  kind: "pending",
  label: "Awaiting update",
  detail: "The limit reset; waiting for fresh usage"
})

check("a passed reset invalidates a cached finite ETA", forecast.runway({
  status: "estimated",
  exhaustion_at: "2026-09-21T15:30:00Z",
  account_status: "ready",
  windows: [{status: "steady", resets_at: "2026-09-21T11:59:00Z"}]
}, now), {
  kind: "pending",
  label: "Awaiting update",
  detail: "The limit reset; waiting for fresh usage"
})

console.log("forecast presentation tests passed")
