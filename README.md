# victoriana

A small, batteries-included **OpenTelemetry observability stack** you can run
with `docker compose up`. It accepts OTLP at a single bearer-authenticated
endpoint and stores it across **VictoriaMetrics** (metrics), **VictoriaLogs**
(logs), and **VictoriaTraces** (traces), with **Grafana** for dashboards and
**vmalert** for recording rules and alerts.

It is **project-agnostic**: point any app's OTLP exporter at it, and drop your
own dashboards and alert rules into `grafana/dashboards/` and `vmalert/rules/`.

## Architecture

```
app       --OTLP/HTTP + bearer-->  Traefik :4318  -->  otel-collector  -->  victoriametrics (metrics)
                                   (TLS optional)        (bearer-auth,        victorialogs    (logs)
                                                          batches, fans out)  victoriatraces  (traces)

operator  --HTTP-->  Traefik :80 (web) -->  grafana  -->  all three stores
                     (off by default;       (pre-provisioned; dashboards from
                      see TRAEFIK_WEB_BIND)  ./grafana/dashboards/)

                                                          vmalert --> victoriametrics
                                                          (rules from ./vmalert/rules/)
```

**Traefik is the only edge.** Every network-reachable service sits behind it;
nothing is published directly:
- `:4318` (`otlp` entrypoint) -> the OTLP collector. Bearer-authenticated.
- `:80` (`web` entrypoint) -> Grafana. **Off the network by default** (bound to
  loopback; reach via SSH tunnel) - set `TRAEFIK_WEB_BIND` to expose it.

Whether an endpoint is plain HTTP, Let's Encrypt TLS, or your own certificate is
**purely Traefik configuration** (`./traefik/`) - the compose file, the ports,
and everything downstream are identical in every mode. VictoriaMetrics/Logs/
Traces and vmalert stay on loopback (SSH tunnel); the collector and Grafana are
never published directly.

## Quick start (no-TLS)

```sh
cp .env.example .env
$EDITOR .env                       # set OTLP_TOKEN  (openssl rand -hex 32)

docker compose up -d
docker compose ps                  # wait for "healthy"
```

Smoke test (the same script CI runs):

```sh
scripts/smoke.sh
```

It checks that `:4318` rejects a request without the token, then sends one
metric, one log and one span and waits until each is queryable in
VictoriaMetrics, VictoriaLogs and VictoriaTraces. It reads `OTLP_TOKEN` and the
TLS mode from `.env` to pick the endpoint; pass one explicitly to override
(`scripts/smoke.sh https://otlp.example.com:4318`).

## TLS modes (`.env` only)

Set `OTLP_TLS_MODE` in `.env` and run `docker compose up -d traefik`. The
endpoint stays `:4318` in every mode; only the client's `http`/`https` changes.
No file in the repo is edited, so a deployed checkout stays clean.

| `OTLP_TLS_MODE` | Also set in `.env` | Serves |
|-----------------|--------------------|--------|
| `none` (default) | - | Plain HTTP, any Host. Bearer enforced at the collector. Good for a trusted LAN / behind another proxy. |
| `acme` | `OTLP_HOSTNAME`, `ACME_EMAIL`, `CLOUDFLARE_API_TOKEN` | Let's Encrypt cert, only for `Host(OTLP_HOSTNAME)`. |
| `byocert` | - (drop `tls.crt` + `tls.key` into `./certs/`) | Your cert, any Host. |

An unknown mode, or `acme` without `OTLP_HOSTNAME`, disables the OTLP router
(every request gets 404) and Traefik logs why; it never falls back to plain
HTTP. The router is the template [traefik/dynamic/otlp.yml](traefik/dynamic/otlp.yml);
Traefik's static config is the `command:` of the `traefik` service in
`docker-compose.yml`.

ACME uses the DNS-01 challenge (works for endpoints not reachable on :80/:443)
via Cloudflare; the cert and account persist in `./data/traefik/acme.json`.
Another [Traefik DNS provider](https://doc.traefik.io/traefik/https/acme/#providers)
needs `dnsChallenge.provider` and its credential variables changed on the
`traefik` service in `docker-compose.yml`.

## Sending OTLP from an app

```sh
OTEL_EXPORTER_OTLP_ENDPOINT=http://<host>:4318       # or https://<host>:4318 with TLS
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer <OTLP_TOKEN>"
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

OTLP SDKs append `/v1/{traces,metrics,logs}` per signal automatically - the same
two settings cover all three.

## Dashboards & alert rules (drop-in)

- **Dashboards:** drop Grafana dashboard JSON into `grafana/dashboards/`
  (subdirectories become Grafana folders; scanned every 60s, no restart). Four
  datasources are pre-provisioned with stable uids: `victoriametrics`,
  `victorialogs`, and VictoriaTraces twice - `victoriatraces` (Jaeger API) and
  `victoriatraces_logs` (LogsQL over spans). See
  [grafana/dashboards/README.md](grafana/dashboards/README.md).
- **Rules:** drop alert/recording rule YAML into `vmalert/rules/` (or a
  per-consumer subdirectory); vmalert re-reads them every 60s, no restart. See
  [vmalert/rules/README.md](vmalert/rules/README.md). Recording rules write
  back to VictoriaMetrics. Alerts are evaluated and visible in the vmalert UI
  and Grafana, but delivered nowhere until you set `VMALERT_NOTIFIER_URL` (an
  Alertmanager, e.g. `http://alertmanager:9093`) in `.env` and run
  `docker compose up -d vmalert`.

## Self-monitoring

victoriana watches itself. VictoriaMetrics scrapes every component
([victoriametrics/scrape.yml](victoriametrics/scrape.yml): the three stores,
vmalert, Traefik, the collector, Grafana), and two drop-in directories ship
pre-filled:

- `grafana/dashboards/victoriana/` - **victoriana - stack overview** (is it
  healthy: scrape health, firing alerts, TLS cert expiry, OTLP status codes,
  collector throughput and refusals, storage), plus VictoriaMetrics' upstream
  dashboards for VictoriaMetrics, VictoriaLogs, VictoriaTraces and vmalert.
- `vmalert/rules/victoriana/` - VictoriaMetrics' upstream alert rules for each
  Victoria component, plus `victoriana.yml` for the edge, the collector,
  Grafana and certificate expiry.

Firing alerts show in the overview dashboard and the vmalert UI; see
[Dashboards & alert rules](#dashboards--alert-rules-drop-in) for delivery.

## Web UIs

By default everything but the OTLP port is on `127.0.0.1`. **Grafana** is served
by Traefik's `web` entrypoint, bound to loopback by default; the Victoria
services and vmalert bind to loopback directly. Reach them over SSH:

```sh
ssh -L 8080:localhost:80 \
    -L 8428:localhost:8428 -L 9428:localhost:9428 -L 10428:localhost:10428 \
    -L 8880:localhost:8880 user@<host>
```

- `http://localhost:8080/` - Grafana via Traefik (the four datasources come pre-provisioned)
- `http://localhost:8428/vmui/` - VictoriaMetrics
- `http://localhost:9428/select/vmui/` - VictoriaLogs
- `http://localhost:10428/select/vmui/` - VictoriaTraces
- `http://localhost:8880/vmalert/` - vmalert

To expose Grafana on a network instead of tunnelling, set `TRAEFIK_WEB_BIND` in
`.env` (e.g. `0.0.0.0:80`, or `<lan-ip>:80` for one interface) - this binds
Traefik's `web` entrypoint, not Grafana itself. Grafana ships anonymous-Admin
(see [Security model](#security-model)), so before exposing it set either or
both of:

- `GRAFANA_BASIC_AUTH_USERS` - htpasswd lines (comma-separated, single-quoted
  in `.env`); Traefik then requires a login before anything reaches Grafana.
- `GRAFANA_HOSTNAME` - serve Grafana only for that Host, over HTTPS with a
  Let's Encrypt cert (same `ACME_EMAIL`/`CLOUDFLARE_API_TOKEN` as the OTLP
  endpoint). Plain HTTP then gets 404; e.g. `TRAEFIK_WEB_BIND=0.0.0.0:443`.

Apply with `docker compose up -d traefik`.

## Configuration

Image versions and retention are env-driven with sane defaults baked into
`docker-compose.yml`; override in `.env` (see `.env.example`).

| Image | Default | | Retention var | Default |
|-------|---------|-|---------------|---------|
| `traefik` | `v3.7.17` | | `VM_RETENTION_PERIOD` | `30d` |
| `victoriametrics/victoria-metrics` | `v1.155.0` | | `VL_RETENTION_PERIOD` | `30d` |
| `victoriametrics/victoria-logs` | `v1.53.0` | | `VT_RETENTION_PERIOD` | `7d` |
| `victoriametrics/victoria-traces` | `v0.12.1` | | | |
| `victoriametrics/vmalert` | `v1.155.0` | | | |
| `grafana/grafana` | `13.3.0` | | | |
| `otel/opentelemetry-collector-contrib` | `0.164.0` | | | |
| `victoriametrics-logs-datasource` (Grafana plugin, `VL_PLUGIN_VERSION`) | `0.33.1` | | | |

**Disk guards.** Retention is time-based, plus two guards on the filesystem
holding `./data` (shared by all three stores): VictoriaLogs and VictoriaTraces
drop their oldest days once it is 80% full (`VL_/VT_MAX_DISK_USAGE_PERCENT`),
and every store stops accepting writes below 1 GiB free (`VM_/VL_/VT_MIN_FREE_DISK`).
Metrics are never deleted early, so on a disk filled by something else
VictoriaMetrics stops ingesting rather than losing history.

VictoriaMetrics runs with `-opentelemetry.usePrometheusNaming=true` so OTLP
metrics are stored under standard Prometheus names (`foo.bar` -> `foo_bar`,
`_total` on counters). Dashboards/PromQL should assume Prometheus naming.

## Security model

- **Traefik is the only edge** - the collector and Grafana are never published
  directly; everything reachable goes through it.
- By default the only network-exposed port is `:4318` (OTLP), protected by the
  **bearer token**. Grafana's `web` entrypoint and the other UIs bind to
  loopback until you set `TRAEFIK_WEB_BIND`.
- In **no-TLS** mode the bearer token travels unencrypted - fine on a trusted
  network or behind another TLS proxy; otherwise enable a TLS mode above.
- **Grafana ships with anonymous Admin and no login** (`GF_AUTH_ANONYMOUS_*`),
  convenient behind the loopback/SSH-tunnel boundary. Before exposing it
  (`TRAEFIK_WEB_BIND`), set `GRAFANA_BASIC_AUTH_USERS` (and ideally
  `GRAFANA_HOSTNAME` for TLS) - otherwise anyone who reaches the port is Admin.
  Everyone who passes the basicAuth login is still Grafana Admin; for per-user
  roles, remove the anonymous env vars and provision real Grafana users.

## Operations

How each kind of change takes effect:

| You changed | Apply with |
|-------------|-----------|
| `.env`, `docker-compose.yml` | `docker compose up -d` (recreates only the affected services) |
| `otel-collector-config.yaml` | `docker compose restart otel-collector` (`up -d` doesn't notice a bind-mounted file) |
| `grafana/provisioning/` | `docker compose restart grafana` |
| `./certs/tls.crt`, `tls.key` | `docker compose restart traefik` |
| `traefik/dynamic/`, `victoriametrics/scrape.yml`, `grafana/dashboards/`, `vmalert/rules/` | nothing - re-read automatically (Traefik at once, the rest within ~60s) |

- **Rotate the bearer token** (no flag day): set `OTLP_TOKEN_NEXT` to the new
  token in `.env` and `docker compose up -d otel-collector` - both are now
  accepted. Move every producer to the new token, then set `OTLP_TOKEN` to it,
  remove `OTLP_TOKEN_NEXT`, and `docker compose up -d otel-collector` again.
- **Bump an image:** edit the `*_VERSION` in `.env`, then
  `docker compose up -d <service>`.
- **Reset stored data:** `docker compose down && rm -rf data/vm data/vl data/vt && docker compose up -d`
  (keep `data/traefik/` to preserve any ACME cert). Grafana's state lives in the
  `grafana-data` named volume and holds nothing that isn't re-provisioned;
  `docker compose down -v` discards it.
- **Back up:** the irreplaceable state is `./data/vm`, `./data/vl`, `./data/vt`,
  `./data/traefik/acme.json` and your `.env` (secrets: store it securely);
  Grafana and all config are re-provisioned from the repo. Copying a running
  store's files is not consistent - copy a snapshot instead (each store's
  `/storage` is `./data/<store>` on the host):
  - VictoriaMetrics: `curl http://localhost:8428/snapshot/create` returns a
    name; copy `./data/vm/snapshots/<name>/` off-host (rsync/rclone), then
    `curl 'http://localhost:8428/snapshot/delete?snapshot=<name>'`. Or use
    [`vmbackup`](https://docs.victoriametrics.com/vmbackup/).
  - VictoriaLogs (`:9428`) / VictoriaTraces (`:10428`): data is in per-day
    partitions; snapshot one with
    `curl -X POST 'http://localhost:9428/internal/partition/snapshot/create?partition_prefix=YYYYMMDD'`,
    rsync the returned path, then delete the snapshot (also `POST`). Details and restore:
    [VictoriaLogs backup docs](https://docs.victoriametrics.com/victorialogs/#backup-and-restore)
    (VictoriaTraces works the same way).
- **Logs:** `docker compose logs -f otel-collector` / `... traefik`.

## Layout

```
docker-compose.yml          stack definition (Traefik always-on -> collector -> VM/VL/VT)
otel-collector-config.yaml  collector pipelines + bearer-token auth
victoriametrics/scrape.yml  self-monitoring scrape targets
scripts/smoke.sh            end-to-end test (README + CI)
traefik/
  dynamic/otlp.yml          OTLP router; a template rendered from OTLP_TLS_MODE
  dynamic/grafana.yml       Grafana router (web entrypoint)
certs/                      bring-your-own-cert files (gitignored)
grafana/
  provisioning/             datasources (stable uids) + dashboard provider
  dashboards/               drop-in dashboard JSON (per-consumer subdirs, gitignored)
    victoriana/             self-monitoring dashboards (tracked)
vmalert/rules/              drop-in alert/recording rule YAML (per-consumer subdirs, gitignored)
  victoriana/               self-monitoring alert rules (tracked)
.env.example                copy to .env
```

## License

[MIT](LICENSE) (c) 2026 F. D. Castel.
