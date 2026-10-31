#!/usr/bin/env bash
# Re-vendor VictoriaMetrics' upstream dashboards and alert rules from the tags
# pinned in docker-compose.yml, then apply victoriana's patches:
#
#   - Alert rules: job-filter the VictoriaMetrics files' unfiltered selectors,
#     which would otherwise also match VictoriaLogs/VictoriaTraces (whose own
#     files carry the same alert names, job-filtered) and fire twice.
#   - Dashboards: drop the "export for sharing" `__inputs` and point every
#     Prometheus datasource variable at our `victoriametrics` uid, since file
#     provisioning never fills inputs in (grafana/dashboards/README.md).
#
#   scripts/vendor-upstream.sh
#
# Run after bumping VM_VERSION, VL_VERSION or VT_VERSION in docker-compose.yml
# and commit the result. With unchanged pins it produces no diff (CI checks).
# Needs curl, jq and perl.
set -euo pipefail

cd "$(dirname "$0")/.."

pin() {  # default of ${NAME:-...} in docker-compose.yml
  local v
  v=$(grep -oE "\\\$\\{$1:-[^}]+\\}" docker-compose.yml | head -n1 | sed -E 's/.*:-(.*)\}/\1/')
  [ -n "$v" ] || { echo "no default for $1 in docker-compose.yml" >&2; exit 1; }
  printf '%s' "$v"
}

VM=$(pin VM_VERSION)
VL=$(pin VL_VERSION)
VT=$(pin VT_VERSION)
VMALERT=$(pin VMALERT_VERSION)
[ "$VM" = "$VMALERT" ] || echo "warning: VMALERT_VERSION ($VMALERT) != VM_VERSION ($VM); vmalert rules follow VM_VERSION" >&2

RULES=vmalert/rules/victoriana
DASH=grafana/dashboards/victoriana
RAW=https://raw.githubusercontent.com/VictoriaMetrics

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fetch() {  # fetch REPO TAG PATH DEST
  echo "$4  <-  $1@$2:$3"
  curl -fsSL --retry 3 "$RAW/$1/$2/$3" -o "$TMP/$(basename "$4")"
}

fetch VictoriaMetrics "$VM" deployment/docker/rules/alerts-health.yml      "$RULES/upstream-vm-health.yml"
fetch VictoriaMetrics "$VM" deployment/docker/rules/alerts-single-node.yml "$RULES/upstream-vmsingle.yml"
fetch VictoriaMetrics "$VM" deployment/docker/rules/alerts-vmalert.yml     "$RULES/upstream-vmalert.yml"
fetch VictoriaLogs    "$VL" deployment/docker/rules/alerts-health.yml      "$RULES/upstream-vl-health.yml"
fetch VictoriaLogs    "$VL" deployment/docker/rules/alerts-vlogs.yml       "$RULES/upstream-vlogs.yml"
fetch VictoriaTraces  "$VT" deployment/docker/rules/alerts-health.yml      "$RULES/upstream-vt-health.yml"
fetch VictoriaTraces  "$VT" deployment/docker/rules/alerts-vtraces.yml     "$RULES/upstream-vtraces.yml"
fetch VictoriaMetrics "$VM" dashboards/victoriametrics.json "$DASH/victoriametrics.json"
fetch VictoriaMetrics "$VM" dashboards/vmalert.json         "$DASH/vmalert.json"
fetch VictoriaLogs    "$VL" dashboards/victorialogs.json    "$DASH/victorialogs.json"
fetch VictoriaTraces  "$VT" dashboards/victoriatraces.json  "$DASH/victoriatraces.json"

# --- Rules: job-filter the VictoriaMetrics files -----------------------------
# The regex is the one upstream already uses on this file's filtered rules.
# Only single-line `expr:` lines are touched (not annotations that quote
# queries). Metrics already carrying a label set get the filter prepended.
export VM_JOBS='.*(victoriametrics|vmselect|vminsert|vmstorage|vmagent|vmalert|vmsingle|vmalertmanager|vmauth).*'
export VM_METRICS='process_max_fds|process_open_fds|process_resident_memory_anon_bytes|vm_available_memory_bytes|process_cpu_seconds_total|process_cpu_cores_available|vm_concurrent_insert_current|vm_concurrent_insert_capacity|vm_concurrent_select_limit_timeout_total|vm_rows_ignored_total|vm_snapshots|vm_http_request_errors_total'
for f in upstream-vm-health.yml upstream-vmsingle.yml; do
  perl -i -pe '
    if (/^\s*expr:/) {
      s/\b($ENV{VM_METRICS})\b(?=[^{_]|$)/$1\{job=~"$ENV{VM_JOBS}"\}/g;
      s/\bvm_log_messages_total\{/vm_log_messages_total\{job=~"$ENV{VM_JOBS}",/g;
    }' "$TMP/$f"
done
# Fail loudly if upstream changed shape: in vm-health every single-line expr
# but UncleanShutdown's (no VL/VT counterpart, so it stays global) must now be
# filtered, and so must vmsingle's RequestErrorsToAPI.
unfiltered=$(grep -E '^\s*expr: .+' "$TMP/upstream-vm-health.yml" | grep -vc 'job=~' || true)
[ "$unfiltered" = 1 ] && grep -q '^\s*expr: vm_app_prev_shutdown_unclean' "$TMP/upstream-vm-health.yml" \
  || { echo "upstream-vm-health.yml: expected only UncleanShutdown unfiltered, got $unfiltered; review the patch" >&2; exit 1; }
grep -q 'vm_http_request_errors_total{job=~' "$TMP/upstream-vmsingle.yml" \
  || { echo "upstream-vmsingle.yml: RequestErrorsToAPI not filtered; review the patch" >&2; exit 1; }

# --- Dashboards: provisionable datasource ------------------------------------
for f in victoriametrics.json vmalert.json victorialogs.json victoriatraces.json; do
  jq --indent 2 '
    del(.__inputs, .__elements, .__requires)
    | .templating.list |= map(
        if .type == "datasource" and .query == "prometheus"
        then .current = {"text": "VictoriaMetrics", "value": "victoriametrics"}
        else . end)' "$TMP/$f" > "$TMP/$f.new"
  mv "$TMP/$f.new" "$TMP/$f"
  if grep -q '\${DS_' "$TMP/$f" || [ "$(jq '[.templating.list[] | select(.type == "datasource")] | length' "$TMP/$f")" = 0 ]; then
    echo "$f: unexpected datasource wiring upstream; review the patch" >&2; exit 1
  fi
done

for f in "$TMP"/*.yml; do mv "$f" "$RULES/"; done
for f in "$TMP"/*.json; do mv "$f" "$DASH/"; done

echo "vendored VM $VM, VL $VL, VT $VT"
git status --short -- "$RULES" "$DASH"
