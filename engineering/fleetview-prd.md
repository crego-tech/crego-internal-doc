# FleetView — Crego Platform Control Plane

**PRD · v0.1 (Draft)**
Owner: Abhishek · Status: Draft for review · Last updated: 2026-07-23
Home: `crego-internal-docs/engineering/fleetview-prd.md`

---

## 1. Summary

FleetView is a **local-first web app** that gives one person a single, trustworthy
answer to the question *"what is actually happening across Crego right now?"* — which
branch is where, which version each environment and each client tenant is running, how
many GitHub runners are live, what the last deployment was, and whether anything needs
attention.

It is a read-first **control plane** that aggregates data by driving the tools you
already run by hand — `git`, the GitHub API / `gh`, and `kubectl` — and presents it as
dashboards. A second layer adds guarded **actions** that wrap those same CLIs so routine
operations (cut a release, trigger a workflow, roll back) happen from the UI with an
audit trail. A later phase adds an **automated PR review loop** driven by Claude.

FleetView runs on the operator's machine, uses their existing local credentials
(kubeconfig, GitHub token, git checkouts), and never becomes production infrastructure.
It is a cockpit, not a new service in the critical path.

---

## 2. Problem & motivation

Crego ships one platform across five backend/frontend/infra repos into **seven
environments** (`dev-aws`, `dev-gcp`, `preprod-gcp`, `prod-aws`, `prod-gcp`, `qa1-gcp`,
`qa2-gcp`) for **multiple client tenants** (dehaat, indifi, tiger-capital, vayana, …),
each potentially on a different version and a different feature/service toggle set.

Today the answer to "what's running where" is assembled manually every time:

- `git` in five checkouts to see branches, release tags, and what's merged.
- The GitHub UI (or `gh`) to check Actions runs, runner availability, and the last
  deployment per environment.
- `kubectl` against multiple clusters to see which image tag each service is actually
  serving and whether pods are healthy.
- Scattered docs and spreadsheets to know which tenant is licensed for what and which
  version they're on.

This is slow, error-prone, and only lives in one person's head. There is no single view,
no history, and no fast path from "I see a problem" to "I ran the fix." Release and
hotfix decisions are made without a consolidated picture, which is exactly when mistakes
are most expensive.

**Why now:** the repo/environment/tenant matrix has grown past what's comfortable to hold
in your head, active client migrations (e.g. the Adani decimal/July matching work) demand
tight visibility, and the PR/review load is high enough to justify automation.

---

## 3. Goals & non-goals

### Goals

1. **One status view.** Branches, releases-per-environment, and version-per-tenant on a
   single screen, refreshed on demand and on a timer.
2. **Ground truth, not guesses.** Every number traces to a real `git` / GitHub / `kubectl`
   call, with the raw command and timestamp visible.
3. **Fast triage.** Surface drift and anomalies (env behind on version, failed run,
   unhealthy pods, tenant on an unexpected release) at a glance.
4. **Actions with a paper trail.** Common operations run from the UI via the same CLIs,
   with confirmation, dry-run, and a local audit log.
5. **Local, private, disposable.** Uses the operator's own credentials, stores nothing
   sensitive server-side, and can be thrown away and re-run without consequence.

### Non-goals (for now)

- Not a replacement for ArgoCD, GitHub, Linear, or Sentry — it *reads from* them and
  links *into* them.
- Not multi-user SaaS, not hosted, not a production dependency. No public exposure.
- Not a secrets manager — it consumes existing local credentials, never mints or stores
  long-lived secrets of its own.
- Not a CI system — it triggers and observes GitHub Actions; it does not run pipelines.
- Not automated code *authoring* or auto-merge — even the PR-review phase only comments.

---

## 4. Users & primary use cases

**Primary user — the release/platform operator (you).** Runs releases, hotfixes, and
migrations; needs the whole picture and the ability to act.

Representative jobs-to-be-done:

- *"It's release day — show me every repo's branch state and what preprod vs prod is
  running, so I can cut `release/vX.Y.Z` with confidence."*
- *"A client says something's off — which version is *their* tenant on, in which cluster,
  and is it healthy?"*
- *"Did the last deploy actually land? How many runners are busy, and did the workflow
  go green?"*
- *"Show me drift: any environment or tenant running an unexpected tag."*

**Secondary (read-only, later):** other engineers or leads who want the status view
without action permissions.

---

## 5. System context & architecture (stack-agnostic)

FleetView is a thin **backend aggregator** + **web frontend**. The stack is deliberately
left open; the requirements below constrain *what it must do*, not *what it's built in*.

```
                    ┌─────────────────────────────────────────┐
   Browser  ◀──────▶│  FleetView Web UI (dashboards + actions) │
  (localhost)       └─────────────────────────────────────────┘
                                    │  local HTTP/websocket
                                    ▼
                    ┌─────────────────────────────────────────┐
                    │  FleetView Backend (aggregator + cache)  │
                    │  - adapters over local tools             │
                    │  - short-TTL cache + refresh scheduler   │
                    │  - action runner (guarded, audited)      │
                    └─────────────────────────────────────────┘
                       │            │             │            │
                 git CLI /    GitHub API/gh   kubectl /     Linear/Sentry
                 local repos  (REST+Actions)  kubeconfigs   (read, later)
```

### Adapters (the only things that touch the outside world)

- **Git adapter** — runs read-only git against the five local checkouts under `crego/`
  (`crego-flow`, `crego-omni`, `crego-web`, `crego-infra`, plus worktrees). Reads
  branches, tags, ahead/behind, last commit, merge state. Optional `git fetch` on a
  timer.
- **GitHub adapter** — REST/GraphQL (or `gh`) for PRs, Actions runs, runner status,
  releases/tags, and last-deployment metadata. Auth via the operator's existing token.
- **Kubectl adapter** — runs read verbs (`get`, `describe`, `rollout status`) across the
  configured cluster contexts to read the deployed image tag, replica health, and rollout
  state per service per environment. Read-only by default.
- **Config/licensing source** — tenant→environment→version→entitlement mapping. v1 reads
  it from a checked-in config file (see §7.5); later phases can derive parts from cluster
  labels / infra overlays (`crego-infra/overlays/*`, `service-toggles.yaml`).
- **Linear / Sentry adapters** — read-only, introduced with the PR-review phase.

### Cross-cutting principles

- **Every adapter call is logged** with the exact command/endpoint, args, duration, and a
  timestamp; the UI can show provenance for any displayed value.
- **Reads are cached with a short TTL** (configurable, e.g. 30–60s) so dashboards are
  snappy and don't hammer clusters; a visible "refreshed Xs ago" + manual Refresh.
- **Writes are opt-in, guarded, and audited** (see §7.6). Read-only mode is the default
  and can be enforced.
- **Contexts are explicit.** The set of repos, GitHub org, cluster contexts, and
  environments is declared in one config file so nothing is hard-coded.

---

## 6. Environment & tenant model (grounded in the current repos)

FleetView's data model mirrors what already exists in the workspace so it stays truthful.

**Repositories** (`crego-flow`, `crego-omni` → prod branch `master`; `crego-web`,
`crego-infra` → prod branch `main`). Branching model per `CLAUDE.md`: `develop` →
`feature/cre-xxx-*`, `bugfix/cre-xxx-*`, `release/vX.Y.Z`,
`release/vX.Y.Z-clientname`, `hotfix/cre-xxx-*`.

**Environments** (from `crego-infra/overlays/`): `dev-aws`, `dev-gcp`, `preprod-gcp`,
`prod-aws`, `prod-gcp`, `qa1-gcp`, `qa2-gcp`. Each maps to a cluster context and an app
set under `crego-infra/apps/<env>` with per-service toggles
(`service-toggles.yaml`).

**Tenants / clients** (from `crego-internal-docs/clients/`): dehaat, indifi,
tiger-capital, vayana (extensible). Each tenant has: home environment(s), current version,
entitlements/licensed modules, and service-toggle profile.

**Versions** track the release-notes series (`v2.0.0`, `v2.1.0`, `v2.2.0`, `v2.3.0`, …)
and their release tags.

Canonical entities: **Repo**, **Branch**, **Release/Tag**, **Environment**,
**Service/Deployment**, **Tenant**, **WorkflowRun**, **Runner**, **Action** (audit
record).

---

## 7. Feature areas

MVP (Phase 1) = §7.1–§7.5. Actions layer = §7.6 (Phase 2). Auto PR review = §7.7
(Phase 3). Each feature lists what it shows, where the data comes from, and acceptance
criteria.

### 7.1 Status overview — the single pane

**What it is.** The landing dashboard that answers "what's happening right now" in one
screen: a matrix of environments × services showing the running version/tag and health,
a rail of per-repo branch state, and an attention feed of anomalies.

**Shows**
- Environment cards (one per env) with: current release tag(s) deployed, count of healthy
  vs total services, last-deploy time, and a red/amber/green rollup.
- Per-repo branch summary: current `develop` head, open `release/*` branches, latest prod
  tag, and ahead/behind vs prod.
- **Attention feed**: version drift (env or tenant not on expected tag), failed/newer
  workflow runs not yet deployed, unhealthy rollouts, release branches not yet shipped.

**Data sources.** Git adapter (branches/tags), GitHub adapter (last deploy, runs),
kubectl adapter (deployed image tag + health), licensing config (expected versions).

**Acceptance criteria**
- Renders all seven environments and all five repos without manual per-item clicks.
- Each tile shows "refreshed Xs ago" and supports manual refresh.
- Drift between *expected* (config/release) and *actual* (cluster) is visually flagged.
- Clicking any tile deep-links to the detailed view (§7.2–7.5) and/or the source
  (GitHub run, ArgoCD app).

### 7.2 Git graph & branch view

**What it is.** A cross-repo branch/release visualization — the "Branches view" from the
sketch: `develop` with `release/456`, `release/#23`, etc. branching off, per repo.

**Shows**
- Per-repo commit/branch graph focused on `develop`, active `release/*` and
  `hotfix/*` branches, and the latest prod tag, with ahead/behind counts.
- Which release branch contains which merged CRE-xxx features (from branch/commit
  history; enriched with Linear in a later phase).
- "Not yet merged back" warnings (e.g. prod not merged back to `develop` after a release,
  per the release flow in `CLAUDE.md`).
- Filter by repo; toggle to a combined multi-repo timeline.

**Data sources.** Git adapter (log/graph, `merge-base`, `branch --contains`,
`for-each-ref`), optional `git fetch`.

**Acceptance criteria**
- Shows all active `release/*` and `hotfix/*` branches per repo with base and
  ahead/behind vs `develop` and prod.
- Correctly flags a released version that has **not** been merged back to `develop`.
- Read-only; a stale-data indicator appears if the last fetch is older than a threshold.

### 7.3 GitHub / CI view — runners, runs & last deployment

**What it is.** The GitHub Actions cockpit: runner capacity, in-flight and recent runs,
and the last deployment per environment — directly answering the sketch's "how many
runners are running, what was the last deployment."

**Shows**
- **Runners**: total registered, online/offline, busy vs idle, and current queue depth
  (self-hosted runner group status where applicable).
- **Workflow runs**: recent runs per repo/branch with status (queued/running/
  success/failure), duration, trigger, and actor; live-ish updates.
- **Last deployment per environment**: which workflow/tag deployed to each env and when,
  with success/failure and a link to the run and to the resulting rollout (§7.4).
- **Open PRs** summary per repo (count, review state, checks status) as an entry point to
  the PR-review phase (§7.7).

**Data sources.** GitHub adapter (Actions runs, runners, deployments API, PR list/checks).

**Acceptance criteria**
- Runner online/busy counts match the GitHub Actions runners page.
- Each environment shows its most recent deploy (tag, time, status, link) or an explicit
  "no deploy record."
- A failed run in the last N is surfaced in the Status overview attention feed (§7.1).

### 7.4 Environment & release-tag view (pre-prod / dev / prod)

**What it is.** Per-environment detail: exactly what tag each service is running in each
cluster and whether the rollout is healthy — with pre-prod and dev called out since
that's where release validation happens.

**Shows**
- Per environment: list of services/deployments with the **actual deployed image tag**,
  replica counts (ready/desired), rollout status, and last-restart/age.
- **Expected vs actual tag** comparison (expected from the release plan/config; actual
  from the cluster) with drift highlighting.
- Service-toggle state per environment (which services are enabled) from the overlay
  config.
- Quick links: ArgoCD app, the deploy run (§7.3), and the runbook
  (`crego-infra/docs/runbooks/`).

**Data sources.** Kubectl adapter (`get deploy/pods -o`, `rollout status`, image tags,
labels), infra overlay config (`crego-infra/overlays/<env>`, `apps/<env>`), release
config.

**Acceptance criteria**
- For each of the seven environments, lists services with real deployed tags and
  ready/desired replicas.
- Flags any service whose actual tag ≠ expected tag, or whose rollout is not fully ready.
- Read verbs only by default; no mutating `kubectl` in Phase 1.
- Cluster/context for each environment is shown and configurable, never hard-coded.

### 7.5 Tenant licensing & version view

**What it is.** The per-client picture — which tenant is licensed for what, and which
version each tenant is actually running — the sketch's "Tenant Licensing."

**Shows**
- Tenant table: tenant → home environment(s) → current version/tag → licensed modules/
  entitlements → service-toggle profile → status.
- **Drift/violation flags**: tenant running a version different from what's expected, or
  a service enabled/disabled contrary to their entitlement.
- Per-tenant drill-in linking to their environment detail (§7.4) and client docs
  (`crego-internal-docs/clients/<client>/`).
- Migration status hooks (e.g. an in-flight client migration's target version) surfaced as
  a banner where relevant.

**Data sources (v1).** A checked-in licensing/tenant config (single source of truth,
e.g. `fleetview/tenants.yaml`), cross-referenced with actual deployed tags (§7.4).
Later phases can derive parts from cluster labels/namespaces and infra overlays.

**Acceptance criteria**
- Every configured tenant appears with current version and licensed modules.
- A tenant whose actual running version differs from its expected version is flagged.
- Editing the licensing config is the only way to change entitlements in v1 (no writes to
  tenants from the UI).

### 7.6 Actions layer (Phase 2) — guarded operations

**What it is.** Buttons that run the CLIs you'd otherwise type, with confirmation,
dry-run, scoping, and an audit log. The dashboards become not just observability but a
cockpit.

**Candidate actions** (each maps to an existing manual step / runbook):
- **Refresh / fetch** all repos; **`git fetch`** a specific repo.
- **Cut a release** — create `release/vX.Y.Z` from `develop` (wraps the
  `release-manager:cut-release` flow).
- **Trigger a GitHub workflow / re-run** a failed run.
- **Rollout restart / rollback** a service in an environment (`kubectl rollout restart` /
  `undo`) — highest-guard tier.
- **Merge prod back to `develop`** reminder→action after a release.

**Guardrails**
- Every action has: a **dry-run/preview** showing the exact command, an explicit
  **confirmation** (with typed environment name for prod), and a **scope** (repo/env/
  service).
- **Read-only mode** disables all writes; prod-targeting actions require an extra tier of
  confirmation.
- **Audit log**: every action records who/what/when/exact-command/result locally and is
  viewable in-app.
- Destructive/prod actions can be disabled entirely by config.

**Acceptance criteria**
- No action executes without a preview + confirmation step.
- Every executed action produces an immutable local audit entry with the exact command
  and its output/exit code.
- Read-only mode provably blocks all mutating adapter calls.

### 7.7 Automated PR review loop (Phase 3) — native feature

**What it is.** A scheduled (every ~10 min) Claude-driven reviewer that watches open PRs
across the four code repos and posts human-readable reviews to GitHub and Linear — the
right column of the sketch. Specified here as a **first-class FleetView feature**; the
existing `crego-pr-review` skill is the current reference implementation to build on.

**Behavior**
- **Trigger**: on a timer (~10 min) and on-demand from the GitHub/CI view (§7.3). Runs
  statelessly; "already reviewed" state lives in the PR via a hidden head-SHA marker so a
  PR is only re-reviewed when it gets new commits.
- **Scope**: open, non-draft PRs in `crego-omni`, `crego-web`, `crego-flow`,
  `crego-infra` whose base is `develop`, `release/*`, or (hotfix) `master`/`main`.
- **The four questions** (from the sketch), answered per PR:
  1. **What was required?** Tie the PR to its Linear CRE-xxx issue; **flag if the
     requirement is missing/unclear in Linear**.
  2. **How is it done?** Review the code/diff for correctness and tenant-safety.
  3. **Any dependencies that must merge first?** Cross-service/cross-repo ordering.
  4. **Any edge case missed?** Grounded with Sentry errors for the touched modules where
     available.
- **Where it posts**:
  - **GitHub PR**: all four sections as a human-readable review, plus inline line comments;
    a **Request-Changes** verdict when code changes are needed.
  - **Linear issue**: post items **3 and 4** (dependencies + missed edge cases) back to the
    CRE-xxx issue.
  - On any issue: add a comment and request changes.
- **Tone**: all comments must read as if written by a thoughtful human engineer — clear,
  specific, kind, no robotic boilerplate.
- **Never**: writes code, merges, deploys, or advances Linear states.

**FleetView's added value over running the skill by hand**
- A **PR-review dashboard**: queue of PRs, last-review verdict, review age, and a manual
  "review now" button.
- Schedule management and run history/audit surfaced in-app.
- Links each review back to the branch/release graph (§7.2) and CI view (§7.3).

**Dependencies**: GitHub + Linear connectors required; Sentry optional (degrade to static
edge-case reasoning, note "Sentry: unavailable").

**Acceptance criteria**
- A PR with new commits gets exactly one fresh review per new head SHA; unchanged PRs stay
  quiet.
- Each review contains all four sections; dependencies + edge cases also land on the
  Linear issue.
- Missing Linear requirement is explicitly flagged.
- No code is authored, merged, or deployed by the bot.

---

## 8. Cross-cutting requirements

**Security & privacy**
- Local-only bind (localhost) by default; no public exposure, no inbound auth surface
  beyond the machine.
- Uses the operator's existing kubeconfig contexts and GitHub token; never stores
  long-lived secrets of its own. Tokens read from the environment / existing config.
- `kubectl` defaults to read verbs; mutating verbs gated behind the actions layer +
  read-only-mode switch.
- Audit log for every action; provenance (exact command + timestamp) for every read.

**Performance & freshness**
- Short-TTL cache per adapter; background refresh scheduler; visible "refreshed Xs ago" +
  manual refresh. Cluster reads must not exceed a configurable rate.

**Reliability & degradation**
- Any adapter can be unavailable (cluster unreachable, token missing) and the app degrades
  gracefully per-tile with a clear error and last-known value + age — never a blank page.

**Configurability**
- One config file declares repos, GitHub org, cluster contexts↔environments, tenants, and
  expected versions. No environment names, tenants, or paths hard-coded.

**Observability of itself**
- The app logs its own adapter calls, errors, and action history locally.

---

## 9. Phased roadmap

| Phase | Theme | Scope | Exit criteria |
|-------|-------|-------|---------------|
| **1 — MVP** | See everything | Status overview (§7.1), Git graph (§7.2), GitHub/CI + runners + last deploy (§7.3), Env & release-tag view (§7.4), Tenant licensing (§7.5). All **read-only**. | One screen shows branches, per-env release tags, per-tenant versions, runner/last-deploy status across all 7 envs and 4 repos, with drift flags. |
| **2 — Act** | Do it from here | Actions layer (§7.6): fetch/refresh, cut-release, trigger/re-run workflow, rollout restart/rollback, with dry-run + confirmation + audit + read-only mode. | Common release/hotfix ops run from the UI with preview, confirmation, and an audit trail; prod actions double-guarded. |
| **3 — Automate review** | Quality gate | Auto PR review loop (§7.7) + PR-review dashboard, on a 10-min schedule, posting to GitHub + Linear, Sentry-grounded. | PRs auto-reviewed on new commits; four-question reviews on GitHub, deps+edge-cases on Linear; no writes/merges. |
| **4 — Later** | Depth | Linear-enriched branch graph, historical trends (deploy frequency, drift over time), migration trackers (e.g. Adani decimal/July matching), read-only shared view for the team. | — |

---

## 10. Success metrics

- **Time-to-answer** "what's running where" drops from minutes of manual CLI/UI hopping to
  a single glance (target: < 10s).
- **Drift caught before release**: number of version/tag/toggle mismatches surfaced by
  FleetView before they reach a client.
- **Release-day steps run from FleetView** vs by hand (Phase 2 adoption).
- **PR-review latency**: median time from new PR commits to a posted review (Phase 3).
- **Zero incidents** caused by FleetView itself (it stays out of the critical path).

---

## 11. Open questions

1. **Runner detail depth** — do we need self-hosted runner *group* utilization, or is
   org-level online/busy/idle enough for v1?
2. **Licensing source of truth** — start from a checked-in `tenants.yaml`, or is there an
   existing system/spreadsheet (e.g. `SCF_DF_Project_Plan.xlsx`, client onboarding sheets)
   FleetView should read from instead?
3. **Expected-tag source** — derive "expected version per env/tenant" from the release
   plan docs, from `crego-infra` overlays, or from a dedicated config?
4. **kubectl reach** — can the operator's machine reach all seven clusters directly, or do
   some (AWS prod) require a bastion/VPN the app must account for?
5. **Actions scope for v1.5** — which single action is most valuable to ship first
   (cut-release vs rollout restart vs re-run workflow)?
6. **Multi-user later** — is a read-only shared view for the team in scope for Phase 4, and
   if so does that change the local-only security posture?

---

## 12. Appendix — grounding references

- Workspace guide & branching model: `crego/CLAUDE.md`.
- Environments: `crego-infra/overlays/{dev-aws,dev-gcp,preprod-gcp,prod-aws,prod-gcp,qa1-gcp,qa2-gcp}`, app sets `crego-infra/apps/<env>`.
- Runbooks: `crego-infra/docs/runbooks/{deployment-guide,backup-recovery,troubleshooting,tenant-offboarding}.md`.
- Clients: `crego-internal-docs/clients/{dehaat,indifi,tiger-capital,vayana}`.
- Releases: `crego-internal-docs/release-notes/{v2.0.0,v2.1.0,v2.2.0,v2.3.0}`.
- Release process: `crego-internal-docs/engineering/development-process.html`.
- Existing PR-review reference implementation: `crego-pr-review` skill.
- Release/hotfix flows: `release-manager` plugin commands.
