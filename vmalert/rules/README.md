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

Consumer subdirectories are gitignored: each consumer deploys its own folder
out-of-band, and a `git pull` of victoriana never touches them. The exception
is `victoriana/`, victoriana's own self-monitoring rules (tracked).

vmalert re-reads this directory every 60s (`-configCheckInterval`), so new or
changed files take effect within a minute, no restart. A file that fails to
parse is reported in `docker compose logs vmalert` and the previous rules stay
active.

Alerts are delivered only if `VMALERT_NOTIFIER_URL` is set in `.env`;
otherwise they are evaluated and shown (vmalert UI, Grafana) but discarded.

## Format

Standard Prometheus / VictoriaMetrics alert-rule YAML. See
<https://docs.victoriametrics.com/vmalert/> for syntax. Recording rules and
alerts can live in the same file or be split.
