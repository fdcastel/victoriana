# victoriana self-monitoring dashboards

Provisioned into the Grafana folder `victoriana`. All query the
`victoriametrics` datasource, fed by [../../../victoriametrics/scrape.yml](../../../victoriametrics/scrape.yml).

- `victoriana-overview.json` - victoriana's own: is the stack healthy (scrape
  health, firing alerts, cert expiry, OTLP edge, collector, storage).
- Upstream (Apache-2.0, (c) VictoriaMetrics):
  - `victoriametrics.json`, `vmalert.json` - [VictoriaMetrics v1.155.0](https://github.com/VictoriaMetrics/VictoriaMetrics/tree/v1.155.0/dashboards)
  - `victorialogs.json` - [VictoriaLogs v1.53.0](https://github.com/VictoriaMetrics/VictoriaLogs/tree/v1.53.0/dashboards)
  - `victoriatraces.json` - [VictoriaTraces v0.12.1](https://github.com/VictoriaMetrics/VictoriaTraces/tree/v0.12.1/dashboards)

  One local change: upstream ships them with a datasource variable whose
  default is a uid from their own Grafana (and, for `victorialogs.json`, the
  `__inputs` of an "export for sharing"). Both are rewritten so the variable
  defaults to `victoriametrics`.

  Don't edit these by hand: [../../../scripts/vendor-upstream.sh](../../../scripts/vendor-upstream.sh)
  re-downloads them from the tags pinned in `docker-compose.yml` and reapplies
  the change. Run it after bumping `VM_VERSION`, `VL_VERSION` or `VT_VERSION`
  there, and commit the result.
