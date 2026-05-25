# Grafana dashboards drop-in directory

This directory is mounted into the `grafana` container at
`/var/lib/grafana/dashboards`. The file provider configured at
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

## Format

Standard Grafana dashboard JSON. Export from the Grafana UI (Share → Export
→ "Export for sharing externally") or hand-author. Files are detected and
loaded on `updateIntervalSeconds`; no Grafana restart needed for new
dashboards or changes.

`allowUiUpdates: false` is set, so changes made through the Grafana UI to a
provisioned dashboard are saved as a copy and don't affect the JSON on disk.
This keeps the on-disk dashboards as source of truth.
