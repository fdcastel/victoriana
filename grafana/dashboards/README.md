# Grafana dashboards drop-in directory

This directory is mounted into the `grafana` container at
`/etc/grafana/dashboards`. The file provider configured at
[../provisioning/dashboards/dashboards.yaml](../provisioning/dashboards/dashboards.yaml)
scans this path on startup and every 60s afterwards.

## Layout

`foldersFromFilesStructure: true` is set on the provisioner, so subdirectories
become Grafana UI folders. For multi-consumer deployments, namespace by
consumer:

```text
grafana/dashboards/
├── README.md                   (this file)
├── app-a/
│   ├── overview.json           ← appears in Grafana folder "app-a"
│   └── latency.json
└── app-b/
    ├── throughput.json         ← appears in Grafana folder "app-b"
    └── errors.json
```

Consumer subdirectories are gitignored: each consumer deploys its own folder
out-of-band, and a `git pull` of victoriana never touches them.

## Format

Standard Grafana dashboard JSON. Export from the Grafana UI (Share → Export
→ "Export for sharing externally") or hand-author. Files are detected and
loaded on `updateIntervalSeconds`; no Grafana restart needed for new
dashboards or changes.

`allowUiUpdates: false` is set, so changes made through the Grafana UI to a
provisioned dashboard are saved as a copy and don't affect the JSON on disk.
This keeps the on-disk dashboards as source of truth.

## Datasources

Reference datasources by these stable uids (provisioned in
[../provisioning/datasources/victoria.yaml](../provisioning/datasources/victoria.yaml)):

| uid | Type | Use for |
|-----|------|---------|
| `victoriametrics` | Prometheus (MetricsQL) | metrics; Prometheus naming (`foo_bar`, `_total`) |
| `victorialogs` | VictoriaLogs (LogsQL) | logs |
| `victoriatraces` | Jaeger | trace search, trace-ID lookup, the trace waterfall, service dependency graph |
| `victoriatraces_logs` | VictoriaLogs (LogsQL) | spans as rows: `stats by`, `quantile`, `sort by`, span attributes as table columns - anything the Jaeger search API can't express |

Both VictoriaTraces entries query the same server; pick the surface by what the
panel needs, not by the data.
