# victoriana self-monitoring dashboards

Provisioned into the Grafana folder `victoriana`. All query the
`victoriametrics` datasource, fed by [../../../victoriametrics/scrape.yml](../../../victoriametrics/scrape.yml).

- `victoriana-overview.json` - victoriana's own: is the stack healthy (scrape
  health, firing alerts, cert expiry, OTLP edge, collector, storage).
- Upstream, unmodified (Apache-2.0, (c) VictoriaMetrics):
  - `victoriametrics.json`, `vmalert.json` - [VictoriaMetrics v1.155.0](https://github.com/VictoriaMetrics/VictoriaMetrics/tree/v1.155.0/dashboards)
  - `victorialogs.json` - [VictoriaLogs v1.53.0](https://github.com/VictoriaMetrics/VictoriaLogs/tree/v1.53.0/dashboards)
  - `victoriatraces.json` - [VictoriaTraces v0.12.1](https://github.com/VictoriaMetrics/VictoriaTraces/tree/v0.12.1/dashboards)

  To refresh, re-download from the matching tags when bumping an image.
