#!/usr/bin/env bash
# End-to-end smoke test: sends one metric, one log and one span through the
# OTLP endpoint and asserts that each lands in its store.
#
#   scripts/smoke.sh [ENDPOINT]
#
# ENDPOINT defaults from .env: http://localhost:4318 (OTLP_TLS_MODE=none),
# https://$OTLP_HOSTNAME:4318 (acme), https://localhost:4318 (byocert; trust
# your cert with CURL_CA_BUNDLE=certs/tls.crt if it isn't publicly signed).
# The token is $OTLP_TOKEN, else OTLP_TOKEN from .env. The stores are queried
# on their loopback ports; override with VM_URL / VL_URL / VT_URL.
set -euo pipefail

cd "$(dirname "$0")/.."

envval() {  # value of $1 from the environment, else from .env
  if [ -n "${!1:-}" ]; then printf '%s' "${!1}"
  elif [ -f .env ]; then grep -E "^$1=" .env | tail -n1 | cut -d= -f2- || true
  fi
}

TOKEN="$(envval OTLP_TOKEN)"
[ -n "$TOKEN" ] || { echo "OTLP_TOKEN not set (environment or .env)" >&2; exit 2; }

if [ $# -ge 1 ]; then
  ENDPOINT="$1"
else
  case "$(envval OTLP_TLS_MODE)" in
    acme)     ENDPOINT="https://$(envval OTLP_HOSTNAME):4318" ;;
    byocert)  ENDPOINT="https://localhost:4318" ;;
    *)        ENDPOINT="http://localhost:4318" ;;
  esac
fi
ENDPOINT="${ENDPOINT%/}"
VM_URL="${VM_URL:-http://localhost:8428}"
VL_URL="${VL_URL:-http://localhost:9428}"
VT_URL="${VT_URL:-http://localhost:10428}"

RUN="smoke$(date +%s)$$"
NOW_NS="$(date +%s%N)"
TRACE_ID="$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')"
SPAN_ID="$(od -An -tx1 -N8 /dev/urandom | tr -d ' \n')"
fail=0

echo "endpoint: $ENDPOINT   run: $RUN"

post() {  # post SIGNAL JSON [auth=yes|no] -> prints HTTP status
  local auth=()
  [ "${3:-yes}" = yes ] && auth=(-H "Authorization: Bearer $TOKEN")
  curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${auth[@]}" \
       -H "Content-Type: application/json" -X POST "$ENDPOINT/v1/$1" -d "$2"
}

expect() {  # expect WHAT WANT GOT
  if [ "$3" = "$2" ]; then echo "ok    $1 -> $3"; else echo "FAIL  $1 -> $3 (want $2)"; fail=1; fi
}

wait_for() {  # wait_for WHAT URL PATTERN : poll up to 60s for PATTERN in URL's body
  local i
  for i in $(seq 1 30); do
    if curl -s --max-time 5 "$2" | grep -q "$3"; then echo "ok    $1"; return 0; fi
    sleep 2
  done
  echo "FAIL  $1 (not found after 60s)"; fail=1
}

RESOURCE='"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"victoriana-smoke"}}]}'

METRIC='{"resourceMetrics":[{'"$RESOURCE"',"scopeMetrics":[{"metrics":[{"name":"victoriana_smoke","gauge":{"dataPoints":[{"asInt":"1","timeUnixNano":"'"$NOW_NS"'","attributes":[{"key":"smoke_run","value":{"stringValue":"'"$RUN"'"}}]}]}}]}]}]}'
LOG='{"resourceLogs":[{'"$RESOURCE"',"scopeLogs":[{"logRecords":[{"timeUnixNano":"'"$NOW_NS"'","severityText":"INFO","body":{"stringValue":"victoriana smoke '"$RUN"'"}}]}]}]}'
SPAN='{"resourceSpans":[{'"$RESOURCE"',"scopeSpans":[{"spans":[{"traceId":"'"$TRACE_ID"'","spanId":"'"$SPAN_ID"'","name":"'"$RUN"'","kind":1,"startTimeUnixNano":"'"$NOW_NS"'","endTimeUnixNano":"'"$((NOW_NS + 1000000))"'"}]}]}]}'

expect "POST /v1/metrics without token" 401 "$(post metrics '{}' no)"
expect "POST /v1/metrics" 200 "$(post metrics "$METRIC")"
expect "POST /v1/logs"    200 "$(post logs "$LOG")"
expect "POST /v1/traces"  200 "$(post traces "$SPAN")"

wait_for "metric in VictoriaMetrics" \
  "$VM_URL/api/v1/query?query=victoriana_smoke%7Bsmoke_run%3D%22$RUN%22%7D" "\"$RUN\""
wait_for "log in VictoriaLogs" \
  "$VL_URL/select/logsql/query?query=_time%3A10m%20%22$RUN%22" "$RUN"
wait_for "span in VictoriaTraces" \
  "$VT_URL/select/jaeger/api/traces/$TRACE_ID" "\"$RUN\""

[ "$fail" = 0 ] && echo "smoke: PASS" || { echo "smoke: FAIL"; exit 1; }
