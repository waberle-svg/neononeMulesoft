#!/bin/zsh
# 07-cloudhub-check.sh — ping the three apps running on CloudHub 2.0 (Sandbox, Shared Space) with the caller headers.
#
# Usage:   demo/07-cloudhub-check.sh            ping all three: expects 401 without headers and "ok" with headers
#          demo/07-cloudhub-check.sh --sweep    additionally run the instance-ready sweep on prc
#                                               (that one WRITES: it patches registry rows in the Dev sandbox)
#
# The secret comes from .mule-local.env (INTER_APP_SECRET) via demo-env.sh and is never printed.
# Hosts are the public endpoints shown in Runtime Manager ▸ app ▸ Public Endpoint. They only change if an app is
# deleted and redeployed; override with JIRA_HOST= / SF_HOST= / PRC_HOST= in front of the command if that happens.
set -u
source "${${(%):-%x}:A:h}/demo-env.sh"

JIRA_HOST="${JIRA_HOST:-jira-sys-api-dev-7e6zq2.5sc6y6-2.usa-e2.cloudhub.io}"
SF_HOST="${SF_HOST:-salesforce-sys-api-dev-7e6zq2.5sc6y6-4.usa-e2.cloudhub.io}"
PRC_HOST="${PRC_HOST:-provisioning-prc-api-dev-7e6zq2.5sc6y6-4.usa-e2.cloudhub.io}"
: "${INTER_APP_SECRET:?INTER_APP_SECRET is missing from .mule-local.env}"
AUTH=(-H "X-Client-Id: manual" -H "X-Client-Secret: $INTER_APP_SECRET")

check() {  # <display name> <host>
  local name=$1 host=$2 noauth body summary
  noauth=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "https://$host/api/v1/ping")
  body=$(curl -s --max-time 30 "${AUTH[@]}" "https://$host/api/v1/ping")
  summary=$(print -r -- "$body" | python3 -c '
import sys, json
raw = sys.stdin.read()
try:
    d = json.loads(raw); print(d.get("status", "?"), d.get("app", "?"), d.get("version", "?"), d.get("env", "?"))
except Exception:
    print("not JSON:", raw[:80].replace("\n", " ") or "(empty — app stopped or host wrong)")
')
  printf '%-26s without headers: %s   with headers: %s\n' "$name" "${noauth:-000}" "$summary"
}

echo "CloudHub 2.0 Sandbox — caller-header ping  ($(date '+%Y-%m-%d %H:%M:%S'))"
check jira-sys-api-dev "$JIRA_HOST"
check salesforce-sys-api-dev "$SF_HOST"
check provisioning-prc-api-dev "$PRC_HOST"
echo "expected on every line: without headers 401, with headers 'ok <app> 1.0.0 dev'. 000 or 'not JSON' = app stopped or host changed."

if [[ "${1:-}" == "--sweep" ]]; then
  echo
  echo "Running the instance-ready sweep on prc (patches changed registry rows in the Dev sandbox)..."
  curl -s --max-time 180 -X POST "${AUTH[@]}" -H "Content-Type: application/json" -d '{}' \
    "https://$PRC_HOST/api/v1/sweeps/instance-ready"
  echo
  echo "expected: JSON with checked/updated/unchanged/errors; errors=1 is the old row INT-000000 (fake key NSSU-0) until it is deleted."
fi
