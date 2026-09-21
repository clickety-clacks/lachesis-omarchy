#!/usr/bin/env bash
set -euo pipefail

host="${1:-gibson}"
user="${2:-mike}"
active_codex=""

if [[ -r "${HOME}/.codex/auth.json" ]]; then
  active_codex=$(jq -r '.tokens.account_id // .account_id // empty' "${HOME}/.codex/auth.json" 2>/dev/null || true)
fi

ssh -o BatchMode=yes -o ConnectTimeout=5 "${user}@${host}" \
  'curl -fsS --max-time 15 "http://127.0.0.1:7843/api/v1/usage?refresh=background"' |
  jq -c --arg active_codex "$active_codex" '
    .results as $results |
    {
      generated_at,
      accounts: [
        $results[] |
        select(.sample != null) |
        .sample as $sample |
        {
          id: .account_id,
          provider: $sample.provider,
          label: $sample.label,
          plan: ($sample.plan // ""),
          active: (
            if $sample.provider == "codex" then
              (($sample.raw.account_id // "") == $active_codex and $active_codex != "")
            else
              ([ $results[] | select(.sample.provider == "claude") ] | length) == 1
            end
          ),
          status: .status,
          observed_at: $sample.observed_at,
          age_seconds: ($sample.age_seconds // 0),
          error: (.error.message // .error // ""),
          windows: [
            $sample.windows[]? |
            {
              id,
              name,
              used_percent: (.used_percent // 0),
              resets_at: (.resets_at // ""),
              window_seconds: (.window_seconds // 0)
            }
          ]
        }
      ]
    }
  '
