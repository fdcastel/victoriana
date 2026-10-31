# victoriana self-monitoring rules

- `victoriana.yml` - victoriana's own alerts: Traefik, the collector, Grafana,
  and TLS certificate expiry.
- `upstream-*.yml` - VictoriaMetrics' published alert rules:
  - `upstream-vm-health.yml`, `upstream-vmsingle.yml`, `upstream-vmalert.yml` -
    [VictoriaMetrics v1.155.0](https://github.com/VictoriaMetrics/VictoriaMetrics/tree/v1.155.0/deployment/docker/rules)
    (`alerts-health.yml`, `alerts-single-node.yml`, `alerts-vmalert.yml`)
  - `upstream-vl-health.yml`, `upstream-vlogs.yml` -
    [VictoriaLogs v1.53.0](https://github.com/VictoriaMetrics/VictoriaLogs/tree/v1.53.0/deployment/docker/rules)
    (`alerts-health.yml`, `alerts-vlogs.yml`)
  - `upstream-vt-health.yml`, `upstream-vtraces.yml` -
    [VictoriaTraces v0.12.1](https://github.com/VictoriaMetrics/VictoriaTraces/tree/v0.12.1/deployment/docker/rules)
    (`alerts-health.yml`, `alerts-vtraces.yml`)

  Apache-2.0, (c) VictoriaMetrics. They select on the job names in
  [../../../victoriametrics/scrape.yml](../../../victoriametrics/scrape.yml).

  One local change: the VictoriaMetrics files are the only ones whose
  selectors upstream leaves unfiltered, so a VictoriaLogs or VictoriaTraces
  incident would also fire the VM copy of the same alert. Every single-line
  `expr:` in `upstream-vm-health.yml` (except `UncleanShutdown`, which has no
  VL/VT counterpart) and `RequestErrorsToAPI` in `upstream-vmsingle.yml` get the
  file's own `job=~".*(victoriametrics|...).*"` filter, so each product's
  alerts come from its own file only.
  To refresh, re-download from the matching tags when bumping an image.
