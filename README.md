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

operator  --HTTP-->  Traefik :80 (web) -->  grafana  -->  all three datasources
                     (off by default;       (pre-provisioned; dashboards from
                      see GRAFANA_HTTP_BIND)  ./grafana/dashboards/)

                                                          vmalert --> victoriametrics
                                                          (rules from ./vmalert/rules/)
```

**Traefik is the only edge.** Every network-reachable service sits behind it;
nothing is published directly:
- `:4318` (`otlp` entrypoint) -> the OTLP collector. Bearer-authenticated.
- `:80` (`web` entrypoint) -> Grafana. **Off the network by default** (bound to
  loopback; reach via SSH tunnel) - set `GRAFANA_HTTP_BIND` to expose it.

Whether an endpoint is plain HTTP, Let's Encrypt TLS, or your own certificate is
**purely Traefik configuration** (`./traefik/`) - the compose file, the ports,
and everything downstream are identical in every mode. VictoriaMetrics/Logs/
Traces and vmalert stay on loopback (SSH tunnel); the collector and Grafana are
never published directly.

## Quick start (no-TLS)

```sh
cp .env.example .env
$EDITOR .env                       # set OTLP_TOKEN  (openssl rand -hex 32)

mkdir -p data/grafana && sudo chown 472:472 data/grafana   # Grafana runs as uid 472

docker compose up -d
docker compose ps                  # wait for "healthy"
```

Smoke test:

```sh
TOKEN="$(grep ^OTLP_TOKEN= .env | cut -d= -f2-)"
curl -s -o /dev/null -w '%{http_code}\n' \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -X POST "http://localhost:4318/v1/metrics" \
     -d '{"resourceMetrics":[{"scopeMetrics":[{"metrics":[{"name":"smoke","gauge":{"dataPoints":[{"asInt":"1","timeUnixNano":"1"}]}}]}]}]}'
# Expect 200 (with token) and 401 (without).
```

## TLS modes (Traefik config, no compose changes)

The endpoint stays `:4318` in every mode; only `./traefik/` and the client's
`http`/`https` change. Only `./traefik/dynamic/` hot-reloads - **static
`traefik.yml` changes need `docker compose up -d --force-recreate traefik`.**

| Mode | How |
|------|-----|
| **no-TLS** (default) | Ships as-is. Plain HTTP on `:4318`, bearer enforced at the collector. Good for a trusted LAN / behind another proxy. |
| **ACME (Let's Encrypt)** | `cp traefik/examples/traefik.acme.yml traefik/traefik.yml` (edit the email) and `cp traefik/examples/otlp.acme.yml traefik/dynamic/otlp.yml` (edit the `Host`). Set your DNS-provider token (Cloudflare: `CLOUDFLARE_API_TOKEN` in `.env`). Then `docker compose up -d --force-recreate traefik`. |
| **bring-your-own-cert** | `cp traefik/examples/otlp.byocert.yml traefik/dynamic/otlp.yml`, drop `tls.crt`/`tls.key` into `./certs/`, then `docker compose restart traefik`. |

ACME uses the DNS-01 challenge (works for endpoints not reachable on :80/:443).
The example uses Cloudflare; any [Traefik DNS provider](https://doc.traefik.io/traefik/https/acme/#providers)
works - set its credentials per the Traefik docs.

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
  (subdirectories become Grafana folders; scanned every 60s, no restart). The
  three Victoria datasources are pre-provisioned with stable uids
  (`victoriametrics`, `victorialogs`, `victoriatraces`). See
  [grafana/dashboards/README.md](grafana/dashboards/README.md).
- **Rules:** drop alert/recording rule YAML into `vmalert/rules/` (or a
  per-consumer subdirectory), then `docker compose restart vmalert`. See
  [vmalert/rules/README.md](vmalert/rules/README.md). No notifier is wired by
  default - recording rules still write back to VictoriaMetrics so dashboards
  see them; add `-notifier.url=...` for alert delivery.

## Web UIs

By default everything but the OTLP port is on `127.0.0.1`. **Grafana** is served
by Traefik's `web` entrypoint, bound to loopback by default; the Victoria
services and vmalert bind to loopback directly. Reach them over SSH:

```sh
ssh -L 8080:localhost:80 \
    -L 8428:localhost:8428 -L 9428:localhost:9428 -L 10428:localhost:10428 \
    -L 8880:localhost:8880 user@<host>
```

- `http://localhost:8080/` - Grafana via Traefik (the three datasources come pre-provisioned)
- `http://localhost:8428/vmui/` - VictoriaMetrics
- `http://localhost:9428/select/vmui/` - VictoriaLogs
- `http://localhost:10428/select/vmui/` - VictoriaTraces
- `http://localhost:8880/vmalert/` - vmalert

To expose Grafana on a network instead of tunnelling, set `GRAFANA_HTTP_BIND` in
`.env` (e.g. `0.0.0.0:80`, or `<lan-ip>:80` for one interface) - this binds
Traefik's `web` entrypoint, not Grafana itself. Only do this on a trusted
network: Grafana ships anonymous-Admin (see [Security model](#security-model)).

## Configuration

Image versions and retention are env-driven with sane defaults baked into
`docker-compose.yml`; override in `.env` (see `.env.example`).

| Image | Default | | Retention var | Default |
|-------|---------|-|---------------|---------|
| `traefik` | `v3.6` | | `VM_RETENTION_PERIOD` | `30d` |
| `victoriametrics/victoria-metrics` | `v1.142.0` | | `VL_RETENTION_PERIOD` | `30d` |
| `victoriametrics/victoria-logs` | `v1.50.0` | | `VT_RETENTION_PERIOD` | `7d` |
| `victoriametrics/victoria-traces` | `v0.8.2` | | | |
| `victoriametrics/vmalert` | `v1.142.0` | | | |
| `grafana/grafana` | `11.4.0` | | | |
| `otel/opentelemetry-collector-contrib` | `0.151.0` | | | |

VictoriaMetrics runs with `-opentelemetry.usePrometheusNaming=true` so OTLP
metrics are stored under standard Prometheus names (`foo.bar` -> `foo_bar`,
`_total` on counters). Dashboards/PromQL should assume Prometheus naming.

## Security model

- **Traefik is the only edge** - the collector and Grafana are never published
  directly; everything reachable goes through it.
- By default the only network-exposed port is `:4318` (OTLP), protected by the
  **bearer token**. Grafana's `web` entrypoint and the other UIs bind to
  loopback until you set `GRAFANA_HTTP_BIND`.
- In **no-TLS** mode the bearer token travels unencrypted - fine on a trusted
  network or behind another TLS proxy; otherwise enable a TLS mode above.
- **Grafana ships with anonymous Admin and no login** (`GF_AUTH_ANONYMOUS_*`),
  convenient behind the loopback/SSH-tunnel boundary. Before exposing it
  (`GRAFANA_HTTP_BIND`), consider removing those env vars and provisioning real
  users - otherwise anyone who reaches the port is Admin.

## Operations

- **Rotate the bearer token:** edit `OTLP_TOKEN` in `.env`, then
  `docker compose up -d otel-collector`.
- **Bump an image:** edit the `*_VERSION` in `.env`, then
  `docker compose up -d <service>`.
- **Reload rules:** drop files in `vmalert/rules/`, `docker compose restart vmalert`.
- **Reload dashboards:** drop files in `grafana/dashboards/` (picked up in ~60s).
- **Reset stored data:** `docker compose down && rm -rf data/vm data/vl data/vt && docker compose up -d`
  (keep `data/traefik/` to preserve any ACME cert).
- **Logs:** `docker compose logs -f otel-collector` / `... traefik`.

## Layout

```
docker-compose.yml          stack definition (Traefik always-on -> collector -> VM/VL/VT)
otel-collector-config.yaml  collector pipelines + bearer-token auth
traefik/
  traefik.yml               static config (no-TLS default)
  dynamic/otlp.yml          active router (no-TLS default)
  examples/                 ACME + bring-your-own-cert variants (copy over the defaults)
certs/                      bring-your-own-cert files (gitignored)
grafana/
  provisioning/             datasources (stable uids) + dashboard provider
  dashboards/               drop-in dashboard JSON (per-consumer subdirs)
vmalert/rules/              drop-in alert/recording rule YAML
.env.example                copy to .env
```

## License

[MIT](LICENSE) (c) 2026 F. D. Castel.
