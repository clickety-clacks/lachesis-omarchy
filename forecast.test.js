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

check("Claude active account matches the provider UUID, independent of usage", forecast.activeAccount([
  {provider: "claude", id: "higher-usage", accountUuid: "uuid-other", used_percent: 95},
  {provider: "claude", id: "active", accountUuid: "uuid-current", used_percent: 5}
], "claude", "uuid-current"), {
  provider: "claude", id: "active", accountUuid: "uuid-current", used_percent: 5
})

check("Claude active account stays unknown without a local UUID", forecast.activeAccount([
  {provider: "claude", id: "first", accountUuid: "uuid-first", active: true},
  {provider: "claude", id: "second", accountUuid: "uuid-second"}
], "claude", ""), null)

check("Claude active account stays unknown without a registered UUID", forecast.activeAccount([
  {provider: "claude", id: "only", accountUuid: null}
], "claude", "uuid-current"), null)

check("Claude active account stays unknown when local UUID is not registered", forecast.activeAccount([
  {provider: "claude", id: "first", accountUuid: "uuid-first"},
  {provider: "claude", id: "second", accountUuid: "uuid-second"}
], "claude", "uuid-unmatched"), null)

check("duplicate registered Claude UUIDs remain ambiguous", forecast.activeAccount([
  {provider: "claude", id: "first", accountUuid: "uuid-current"},
  {provider: "claude", id: "second", accountUuid: "uuid-current"}
], "claude", "uuid-current"), null)

check("Codex fallback behavior remains unchanged", forecast.activeAccount([
  {provider: "codex", id: "first"},
  {provider: "codex", id: "second", active: false}
], "codex"), {provider: "codex", id: "first"})

const knownPool = {id: "known", comparable: true}
check("only explicitly comparable pools appear in combined runway", forecast.compatiblePools([
  knownPool,
  {id: "unknown-plan", comparable: false},
  {id: "missing-comparability"}
]), [knownPool])

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

check("one exhausted member does not exhaust a mixed pool", forecast.poolRunway({
  status: "incomplete",
  exhaustion_at: null,
  members: [
    {status: "exhausted", resets_at: "2026-09-26T08:00:00Z"},
    {status: "steady", resets_at: "2026-09-28T08:00:00Z"}
  ]
}, now), {
  kind: "unknown",
  label: "Incomplete estimate",
  detail: "Some compatible capacity has no measured rate"
})

check("a mixed pool can keep its finite aggregate estimate", forecast.poolRunway({
  status: "estimated",
  exhaustion_at: "2026-09-21T15:30:00Z",
  members: [
    {status: "exhausted", resets_at: "2026-09-26T08:00:00Z"},
    {status: "steady", resets_at: "2026-09-28T08:00:00Z"}
  ]
}, now), {
  kind: "estimate",
  label: "~3h 30m left",
  detail: "Runs out in 3h 30m"
})

check("a pool waits after its earliest member reset", forecast.poolRunway({
  status: "estimated",
  exhaustion_at: "2026-09-21T15:30:00Z",
  members: [
    {status: "exhausted", resets_at: "2026-09-21T11:59:00Z"},
    {status: "steady", resets_at: "2026-09-28T08:00:00Z"}
  ]
}, now), {
  kind: "pending",
  label: "Awaiting update",
  detail: "The limit reset; waiting for fresh usage"
})

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
