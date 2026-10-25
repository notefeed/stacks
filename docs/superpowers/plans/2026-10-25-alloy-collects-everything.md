# Alloy collects everything notefeed-1 reports: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** notefeed-1's Alloy fetches notefeed's `/metrics` and healthchecks too, so Prometheus fetches nothing from notefeed itself.

**Architecture:** Two new blocks in `collectors/alloy/config.alloy` (notefeed with bearer token, healthchecks with targets as JSON from the environment), fed by notefeed-ansible through the collectors' `.env`. infra-ansible stops scraping notefeed. One dashboard tile shows the age of notefeed-1's newest data.

**Tech Stack:** Grafana Alloy v1.20.1, Prometheus v3.15.0, Grafana 13.2.3, Ansible (ansible-core 2.21), Docker Compose.

**Spec:** `docs/superpowers/specs/2026-10-25-alloy-collects-everything-design.md` (this repo)

## Global Constraints

- Every secret lives in the repo's `inventory/group_vars/all/vault.yml`; no side files, no inline `!vault`, never printed.
- Job labels as today: `notefeed`, `caddy`, `postgres`, plus `healthchecks`. Dashboards keep `job="notefeed"`.
- Every block forwards to `prometheus.relabel.host.receiver` (adds host, product, instance).
- Scrape intervals: notefeed 30s, Caddy 60s, PostgreSQL 30s, healthchecks 60s.
- healthchecks stays off while `healthchecks_notefeed_project` is empty.
- No merge, no deploy; push to the existing PR branches, open one new infra-ansible PR, close #27.

## Review Focus

- healthchecks project unset → Alloy must start and scrape nothing (empty target list), not fail. Pinned in Task 1 step 2.
- Overlap at deploy: Prometheus and Alloy both scraping notefeed doubles every `sum()`. Pinned by the order in Task 5 and the PR text.
- The old `notefeed.generated.yaml` left on the monitoring server would keep Prometheus scraping. Pinned in Task 3 step 2.
- notefeed-1 down → the tile must show a growing age, not "No data". Pinned in Task 4 step 2.
- Token with characters special to `.env` quoting → Alloy reads it intact. Pinned in Task 2 step 2 (quoted like `KUMA_PASSWORD`).

---

### Task 1: Alloy blocks for notefeed and healthchecks (notefeed/stacks, branch `caddy-metrics`, PR #41)

**Files:** Modify `collectors/alloy/config.alloy`, `collectors/compose.yaml` (environment), `README.md` (collectors row).

**Interfaces:**
- Produces env vars read by Alloy: `PRIVATE_IP` (already in `.env`), `NOTEFEED_METRICS_TOKEN`, `HEALTHCHECKS_TARGETS` (JSON array, `[]` when off).

- [ ] **Step 1:** Add `prometheus.scrape "notefeed"`: target `sys.env("PRIVATE_IP") + ":3000"`, `job_name = "notefeed"`, `scrape_interval = "30s"`, `bearer_token = sys.env("NOTEFEED_METRICS_TOKEN")`. Add `prometheus.scrape "healthchecks"`: `targets = encoding.from_json(sys.env("HEALTHCHECKS_TARGETS"))`, `job_name = "healthchecks"`, `scrape_interval = "60s"`. Both forward to `prometheus.relabel.host.receiver`. In compose, pass `PRIVATE_IP`, `NOTEFEED_METRICS_TOKEN: ${NOTEFEED_METRICS_TOKEN:?…}`, `HEALTHCHECKS_TARGETS: ${HEALTHCHECKS_TARGETS:-[]}` to the alloy service.
- [ ] **Step 2: Verify locally.** Mock notefeed `/metrics` (requires `Authorization: Bearer t0k"en'`) and healthchecks (`/projects/p/metrics/k`, text with `hc_check_up`) with a small Python server; run Alloy from this config against local Prometheus. Expected: `up{job="notefeed"}=1`, a notefeed sample with `host="notefeed-1"`; with `HEALTHCHECKS_TARGETS=[]` Alloy starts, no `job="healthchecks"` series; with the target set, `hc_check_up{job="healthchecks"}` present. `alloy fmt` clean.
- [ ] **Step 3:** Commit "Alloy fetches notefeed's /metrics and healthchecks too (design 2026-10-25)", push; rebase/merge into `postgres-exporter` (#42) and push.

### Task 2: notefeed-ansible feeds them (branch `postgres-monitor`, PR #22)

**Files:** Modify `inventory/group_vars/all/vars.yml`, `roles/stacks/templates/collectors.env.j2`.

**Interfaces:** Consumes Task 1's env names. Produces `healthchecks_notefeed_project: ""` (vars.yml, not secret), `healthchecks_api_key: "{{ vault_healthchecks_api_key | default('') }}"`.

- [ ] **Step 1:** `.env` gets `NOTEFEED_METRICS_TOKEN='{{ notefeed_metrics_token }}'` and `HEALTHCHECKS_TARGETS='{{ ([{"__address__": "healthchecks.io", "__scheme__": "https", "__metrics_path__": "/projects/" ~ healthchecks_notefeed_project ~ "/metrics/" ~ healthchecks_api_key}] if (healthchecks_notefeed_project and healthchecks_api_key) else []) | to_json }}'`.
- [ ] **Step 2: Verify.** Render the template locally with a token containing a space and a quote and with project empty/set; source it with `docker compose config` and check the values reach the alloy service intact. `ansible-playbook site.yml --check` on notefeed-1: failed=0, changed only collectors `.env` and the collectors.
- [ ] **Step 3:** Commit, push.

### Task 3: infra-ansible stops scraping notefeed (new branch `notefeed-scrape-via-alloy` from main; close #27)

**Files:** Modify `inventory/group_vars/all/vars.yml` (`scrape_jobs: []`, comment says notefeed is pushed by its Alloy), `roles/stacks/tasks/main.yml`.

- [ ] **Step 1:** Remove the `notefeed` entry from `scrape_jobs`; keep the template/loop for future products.
- [ ] **Step 2:** Add task "Scrape files of products no longer listed are gone": `find` `*.generated.yaml` in `monitoring/prometheus/scrape/`, `file: state=absent` for names not in `scrape_jobs`; register and add to Prometheus's `recreate` condition.
- [ ] **Step 3: Verify.** `--check` on monitor-1: the notefeed file reported removed, Prometheus recreate, failed=0. `vault_notefeed_metrics_token` left in the vault, noted in the PR as removable later.
- [ ] **Step 4:** Commit, push, open PR; close #27 with a comment linking the design; delete its branch.

### Task 4: Dashboards (infra-stacks, branches #47 → #48 → #49)

**Files:** Modify `monitoring/grafana/dashboards/notefeed/operator.json`.

- [ ] **Step 1 (#47):** Stat "Last data from notefeed-1" in the "Now" row, `time() - max(last_over_time(timestamp(up{host="notefeed-1"})[1d:1m]))`, unit s, thresholds green / orange 300 / red 900. Make room by narrowing the existing row's tiles or adding it to the second line (keep ids unique).
- [ ] **Step 2: Verify** with jq and local Grafana: value ~30–60 s while Alloy runs; stop Alloy for 6 minutes, value keeps growing (not "No data").
- [ ] **Step 3 (#48):** "Backup checks" query `job="healthchecks"`; description names `healthchecks_notefeed_project` and `vault_healthchecks_api_key` in notefeed-ansible. Verify against the Task 1 mock.
- [ ] **Step 4:** Commit each on its branch, merge #47 → #48 → #49 forward, push.

### Task 5: PR texts and order

- [ ] **Step 1:** Update the descriptions of stacks #41/#42, notefeed/ansible #22, infra-stacks #47/#48, the new infra-ansible PR: what moved to Alloy, and the deploy order: (1) infra-ansible without the notefeed job, (2) notefeed-ansible after stacks #41/#42 are merged, (3) infra-ansible for infra-stacks #47–#49.
- [ ] **Step 2:** Report to Marcel: PRs, what was verified, what waits (project id).
