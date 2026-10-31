#!/usr/bin/env bash
set -euo pipefail

host="${1:-localhost}"
user="${2:-$(id -un)}"
active_codex=""
active_claude_uuid=""

if [[ -r "${HOME}/.codex/auth.json" ]]; then
  active_codex=$(jq -r '.tokens.account_id // .account_id // empty' "${HOME}/.codex/auth.json" 2>/dev/null || true)
fi
if [[ -r "${HOME}/.claude.json" ]]; then
  active_claude_uuid=$(jq -r '.oauthAccount.accountUuid // empty' "${HOME}/.claude.json" 2>/dev/null || true)
fi

fetch_remote() {
  local path="$1"
  if [[ "$host" == "localhost" || "$host" == "127.0.0.1" ]]; then
    curl -fsS --max-time 15 "http://127.0.0.1:7843${path}"
    return
  fi
  ssh -o BatchMode=yes -o ConnectTimeout=5 "${user}@${host}" \
    "curl -fsS --max-time 15 'http://127.0.0.1:7843${path}'"
}

# Usage is the primary read. Keep it available when the history-backed
# forecast endpoint is temporarily unavailable.
usage_json=""
if ! usage_json="$(fetch_remote '/api/v1/usage?refresh=background')"; then
  echo "Cannot read Lachesis usage on ${host}" >&2
  exit 1
fi
if ! jq -e 'type == "object" and ((.results // []) | type == "array")' >/dev/null 2>&1 <<<"$usage_json"; then
  echo "Lachesis returned unreadable usage data on ${host}" >&2
  exit 1
fi

forecast_json="null"
forecast_fetch_error="false"
forecast_candidate=""
if forecast_candidate="$(fetch_remote '/api/v1/usage/forecast' 2>/dev/null)" && \
   jq -e 'type == "object" and ((.accounts // []) | type == "array") and ((.pools // []) | type == "array")' >/dev/null 2>&1 <<<"$forecast_candidate"; then
  forecast_json="$forecast_candidate"
else
  forecast_json="null"
  forecast_fetch_error="true"
fi

# Account metadata has no provider credentials. It lets the widget keep a
# registered account visible when its provider returned no usage sample.
registry_json='{"accounts":[]}'
if metadata_json="$(fetch_remote '/api/v1/accounts' 2>/dev/null)" && \
   jq -e 'type == "object" and ((.accounts // []) | type == "array")' >/dev/null 2>&1 <<<"$metadata_json"; then
  registry_json="$metadata_json"
fi

jq -cn \
  --argjson usage "$usage_json" \
  --argjson forecast "$forecast_json" \
  --argjson registry "$registry_json" \
  --arg active_codex "$active_codex" \
  --arg active_claude_uuid "$active_claude_uuid" \
  --arg forecast_fetch_error "$forecast_fetch_error" '
  ($usage.results // []) as $usage_rows |
  ($forecast.accounts // []) as $forecast_rows |
  ($registry.accounts // []) as $registry_rows |
  ([
    ($registry_rows[]?.id),
    ($usage_rows[]?.account_id),
    ($forecast_rows[]?.account_id)
  ] | map(select(. != null and . != "")) | unique) as $ids |
  {
    generated_at: ($usage.generated_at // ""),
    forecast_generated_at: ($forecast.generated_at // ""),
    forecast_fetch_error: ($forecast_fetch_error == "true"),
    forecast: $forecast,
    pools: ($forecast.pools // []),
    forecast_status: ($forecast.status // "unavailable"),
    forecast_diagnostics: ($forecast.diagnostics // []),
    active_claude_uuid: $active_claude_uuid,
    accounts: [
      $ids[] as $id |
      (first($registry_rows[]? | select(.id == $id)) // {}) as $meta |
      (first($usage_rows[]? | select(.account_id == $id)) // {}) as $usage_row |
      (first($forecast_rows[]? | select(.account_id == $id)) // {}) as $forecast_row |
      ($usage_row.sample // {}) as $sample |
      ($sample.provider // $meta.provider // $forecast_row.provider // "unknown") as $provider |
      {
        id: $id,
        provider: $provider,
        provider_account_uuid: (if $provider == "claude" then ($meta.provider_account_uuid // null) else null end),
        label: ($sample.label // $meta.label // (($provider | tostring | ascii_upcase) + " account")),
        email: (if ($meta.email | type) == "string" then $meta.email else "" end),
        plan: ($sample.plan // $forecast_row.plan // ""),
        active: (
          if $provider == "codex" then
            (($id == $active_codex or ($sample.raw.account_id // "") == $active_codex) and $active_codex != "")
          else false end
        ),
        status: ($meta.status // $forecast_row.account_status // "unknown"),
        usage_status: ($usage_row.status // (if $usage_row.sample != null then "ready" else "unavailable" end)),
        observed_at: ($sample.observed_at // null),
        age_seconds: ($sample.age_seconds // null),
        error: (
          if ($usage_row.error | type) == "object" then ($usage_row.error.message // "")
          else ($usage_row.error // "") end
        ),
        windows: [
          $sample.windows[]? |
          {
            id,
            name,
            used_percent: (.used_percent // 0),
            resets_at: (.resets_at // ""),
            window_seconds: (.window_seconds // 0)
          }
        ],
        forecast: (if ($forecast_row | length) > 0 then $forecast_row else null end)
      }
    ]
  }
 '
