# Alloy collects everything notefeed-1 reports

2026-10-25 · small change · approved: _pending_

## Why

notefeed-1's monitoring data took two ways to Prometheus: Alloy on the server pushed the logs and the machine's numbers,
while Prometheus on the monitoring server fetched notefeed's `/metrics` itself (infra-ansible's `scrape_jobs`). New sources
(Caddy #40, PostgreSQL notefeed/ansible#21, healthchecks infra-stacks#46) should not add a third. Alloy is needed anyway,
because Loki only receives logs that are pushed, so it carries everything.

## Goals

- One way: Alloy on notefeed-1 collects every source and sends logs to Loki, numbers to Prometheus.
- What is collected is described in notefeed's own repos: `collectors/alloy/config.alloy` here, the secrets in
  notefeed-ansible's vault. infra-ansible holds nothing about notefeed's monitoring.
- The dashboards keep working unchanged: `job="notefeed"` stays.

## Non-goals

- Creem (revenue, plans): it has no Prometheus address and would need a translating service. A decision of its own (notefeed/notefeed#233).
- Per-query PostgreSQL statistics (`pg_stat_statements`): needs a database restart.
- The monitoring server's own collection (infra-stacks `collectors/`): unchanged.

## Approaches

- **A. Prometheus fetches every source directly**, each a job in infra-ansible. One hop, like notefeed today. But logs
  still need Alloy, so it stays two ways; secrets would move or be copied into infra-ansible's vault; Caddy and the
  PostgreSQL exporter would listen on the private address.
- **B. Alloy collects everything (chosen).** One way for logs and numbers; the secrets stay where they are; Caddy and
  the exporter listen on 127.0.0.1 only. Costs: Alloy must restart to read a changed config (notefeed/ansible#22 does);
  Prometheus no longer records "notefeed unreachable" itself (no alert used it; see below).

## Sources, all in `config.alloy`, all through `prometheus.relabel "host"` (adds host, product, instance)

| Source | Where | Login | Job |
|---|---|---|---|
| Machine (unchanged) | host /proc, /sys, D-Bus | none | as today |
| notefeed | `PRIVATE_IP:3000/metrics` | bearer, `vault_notefeed_metrics_token` → collectors `.env` | `notefeed` |
| Caddy | admin endpoint 127.0.0.1:2019 | none | `caddy` (host → site, totals only) |
| PostgreSQL | exporter 127.0.0.1:9187 (profile `postgres`) | login `monitor`, `vault_postgres_monitor_password` | `postgres` |
| healthchecks | `healthchecks.io/projects/<id>/metrics/<key>` | `vault_healthchecks_api_key` (notefeed's project, full-access key) | `healthchecks` |

healthchecks is off until notefeed's project id is known (`healthchecks_notefeed_project` in notefeed-ansible's vars.yml,
not a secret). Whether its metrics address accepts a full-access key is checked then; if not, a read-only key goes into
the vault in its place.

## Outages

When notefeed-1 is down, numbers stop arriving. Uptime Kuma (site, every 60 s, ntfy), healthchecks (missed backup ping)
and Beszel already say so. "notefeed: operator" gets one tile, "Last data from notefeed-1", the age of the newest sample
Alloy sent.

## Changes

- notefeed/stacks #41: Caddy `metrics { per_host }` stays on the admin endpoint; Alloy blocks for notefeed and healthchecks
  added; `prometheus.scrape` for Caddy as is. #42 unchanged (exporter on 127.0.0.1, Alloy scrape).
- notefeed/ansible #22: collectors `.env` gets `NOTEFEED_METRICS_TOKEN`, `HEALTHCHECKS_PROJECT`, `HEALTHCHECKS_KEY`.
- infra-ansible: the `notefeed` entry leaves `scrape_jobs`; #27 closed.
- infra-stacks #47: the "Last data from notefeed-1" tile. #48's panel reads `job="healthchecks"`.

## Order

1. infra-ansible: drop the `notefeed` job first, so no moment has the numbers twice (a gap of minutes instead).
2. notefeed-ansible with stacks #41/#42 merged: Alloy starts sending `job="notefeed"`, Caddy, PostgreSQL.
3. infra-ansible for infra-stacks #47–#49 (dashboards, Loki rule).

## Left to the builder (my calls)

- Scrape intervals: notefeed 30 s (as Prometheus did), Caddy 60 s, PostgreSQL 30 s, healthchecks 60 s.
- Alloy's `job_name` set per block, so job labels match today's.
- The "Last data" tile: `time() - max(last_over_time(timestamp(up{host="notefeed-1"})[1d:1m]))`, so the age keeps
  growing during an outage instead of turning into "No data"; orange at 5 min, red at 15.
