# vmalert rules drop-in directory

This directory is mounted into the `vmalert` container at `/etc/vmalert/rules`.

`vmalert` is started with two glob patterns so consumers can structure their
rule files either way:

- `*.yml` at the top level — single-consumer or shared-no-namespace setups
- `<consumer>/*.yml` in a subdirectory — recommended for multi-consumer
  deployments where each consumer's rules should be visually grouped

## Example

```text
vmalert/rules/
├── README.md                    (this file)
├── app-a/
│   ├── recording.yml            ← app-a's recording rules
│   └── alerts.yml               ← app-a's alerts
└── app-b/
    ├── recording.yml            ← app-b's recording rules
    └── alerts.yml               ← app-b's alerts
```

Files dropped in here are read on `vmalert` startup. `docker compose restart
vmalert` after changing rule files; `vmalert` does not hot-reload by default.

## Format

Standard Prometheus / VictoriaMetrics alert-rule YAML. See
<https://docs.victoriametrics.com/vmalert/> for syntax. Recording rules and
alerts can live in the same file or be split.
