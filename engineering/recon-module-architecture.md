# Reconciliation Module — Architecture & Design

**Status:** Approved design, pre-implementation
**Date:** 2026-08-01
**Related:** CRE-6057 (LMS & GL Reconciliation report), omni PR #1387, web PR #922
**Repos:** crego-omni (new `recon` app), crego-web (new `recon` module)

---

## 1. Purpose

A reconciliation module with two levels of functionality, run within a specified
date window, surfaced on a dedicated dashboard:

1. **Report matching & reconciliation** — reconcile the GL module against the LMS
   module (ledgers, portfolio, excess payment, upfront interest, trial balance),
   and later bank statements (UTR matching) as a third layer.
2. **Daily sanity checks** — background invariant checks that run automatically
   every day and flag problems (payment allocation, loan status vs outstanding,
   closure integrity, disbursement principal, upfront deduction).

Industry-standard shape (Blackline / Duco / IntelliMatch model): an
**exception-management engine**. Checks run on a schedule, results and breaks
are *persisted records with a lifecycle*, and reports/dashboards are views over
them. The product of a reconciliation is not a report — it is a **break**: a
persisted, deduplicated exception that ages and gets resolved.

## 2. Decisions (locked)

| Decision | Choice | Rationale |
|---|---|---|
| Engine vs report module | Own `recon` app + Celery tasks; the Excel report handler becomes a read-only **exporter** of persisted runs | `reports.tasks.generate_report` deliberately has `autoretry_for=()`, `max_retries=0`; its product is a file, not queryable state |
| Daily sanity trigger | **New `EODTask` member** (`run_recon_sanity`, step 6) | Guaranteed ordering after `update_transaction_summaries`; progress visible in Day Rollover UI; per-step failure isolation already built |
| Report-recon cadence | **Daily**, enqueued async by the EOD step (not inline) | Freshness without extending the EOD window; reuses just-materialized EOD summaries |
| UI placement | **Standalone module** `/recon` in omni-web | Scope spans payments, loans, GL, future bank — bigger than the GL addon. PR #922's screen stays as the GL report export form |
| Break lifecycle v1 | **Read-only**: `open` / `auto_resolved` only | Model keeps `status` CharField so ack/resolve/assignment can be added in v2 without migration pain |
| PR #1387 disposition | Keep the compute engine (`gl/reconciliation.py`, `build_mapping_lookup`); repackage handler as exporter; fix 3 defects (below) | ~80% of the engine survives unchanged |

## 3. Architecture

```
            ┌────────────── Layer 1: Sources (adapters) ──────────────┐
            │  LedgerSource      GLSource        SummarySource        │
            │  ReportSource(handler.generate_data)     BankSource*    │
            │        * Phase 4 — bank statement / UTR                 │
            └───────────────────────┬─────────────────────────────────┘
                                    │ normalized rows: (grain key, Decimal)
            ┌───────────────────────▼─────────────────────────────────┐
            │  Layer 2: Check framework   @ReconCheckRegistry.register│
            │  BaseReconCheck: code, level, severity, tolerance       │
            │      run(ctx) -> Findings                               │
            │  level = sanity (EOD inline) | report_recon (async)     │
            └───────────┬─────────────────────────┬───────────────────┘
     EOD step 6 (inline │ sanity; enqueue recon)  │ on-demand (API "Run now")
            ┌───────────▼─────────────────────────▼───────────────────┐
            │  Layer 3: Persistence                                   │
            │  ReconCheck (seeded) · ReconRun ─▶ ReconCheckResult     │
            │                              └──▶ ReconBreak            │
            │  breaks fingerprinted: dedup across runs, aging,        │
            │  auto-resolve when they stop appearing                  │
            └───────┬──────────────────┬──────────────┬───────────────┘
                    │                  │              │
             Dashboard API      Excel export      Notification rule
             (omni-web /recon)  (report handler   (new critical break →
                                 reads last run,   event, correlation_id
                                 schedulable,      = fingerprint)
                                 emailable later)
```

Date semantics — one rule:
- **Balance checks** (tie-outs, outstanding, closing balances): as-of `end_date`.
- **Movement checks** (payment allocation, disbursements, GL movement): `[start_date, end_date]`.
- Daily runs use `start = end = the day just closed`. Everything on `value_date`;
  `txn_date` drift is an info metric only.

## 4. Backend design (crego-omni)

### 4.1 App layout

```
project/apps/recon/
├── apps.py                      # post_migrate → seed_recon_checks (mirrors reports)
├── constants.py                 # ReconRunType, ReconRunStatus, CheckLevel,
│                                # CheckSeverity, BreakStatus
├── models.py                    # ReconCheck, ReconRun, ReconCheckResult, ReconBreak
├── serializers.py               # Read/List serializers (read-only v1)
├── filters.py
├── services/
│   ├── runner.py                # ReconRunnerService — orchestrates a run
│   └── runs.py                  # ReconRunService — history, stats, trigger
├── checks/
│   ├── __init__.py              # explicit imports → registration
│   ├── base.py                  # BaseReconCheck + Finding + ReconContext
│   ├── registry.py              # ReconCheckRegistry
│   ├── sanity/
│   │   ├── payment_allocation.py
│   │   ├── loan_status_outstanding.py
│   │   ├── closure_integrity.py
│   │   ├── disbursement_principal.py
│   │   └── upfront_identity.py
│   └── report_recon/
│       ├── gl_tieout.py         # wraps gl.reconciliation (unchanged)
│       ├── portfolio_gl_control.py   # Tier-4: portfolio ↔ GL control account
│       └── report_vs_report.py  # portfolio↔outstanding, excess↔ledger, upfront↔summary
├── sources/
│   ├── base.py                  # ReconSource → normalized [(key, Decimal)] rows
│   └── report_source.py         # wraps handler.generate_data(), display→Decimal
├── tasks.py                     # run_report_recon, sweep_stuck_recon_runs
├── views.py / urls.py / admin.py
├── management/commands/
│   ├── seed_recon_checks.py
│   └── run_recon.py             # CLI: --suite sanity --start --end --checks a,b
└── tests/
```

**Placement rule:** domain compute stays in the domain app. `gl/reconciliation.py`
does not move; recon checks import and wrap it. The `recon` app owns
orchestration, persistence, and presentation only.

### 4.2 Models

```
ReconCheck (seeded from registry — admin-tunable, like Report)
  code (unique) · name · description · level · default_severity
  tolerance Decimal(=0.01) · status active/inactive · config JSON

ReconRun
  run_type: daily_sanity | report_recon      trigger: eod | manual | scheduled
  run_date (business date) · start_date · end_date
  status: pending → running → completed | completed_with_breaks | error
  stats JSON: {checks, passed, warning, failed, error,
               new_breaks, reopened, auto_resolved, per_check_ms}
  started_at · completed_at
  UniqueConstraint(run_date, run_type) WHERE trigger='eod'   ← idempotency key #1

ReconCheckResult
  run FK · check_code · status: passed|warning|failed|error|skipped
  expected · actual · difference (Decimal, nullable) · breaks_count
  duration_ms · detail JSON
  unique(run, check_code)                                    ← idempotency key #2

ReconBreak
  fingerprint = sha256(check_code|entity_type|entity_id|dimension)  (unique) ← key #3
  check_code · severity · entity_type · entity_id · entity_ref (loan ref_id/UTR/txn ref)
  amount_difference · detail JSON
  first_seen_run FK · last_seen_run FK
  status: open | auto_resolved            (v1; ack/resolved reserved for v2)
  Indexes: (status, check_code) · (entity_type, entity_id) · (status, severity)
```

### 4.3 Check interface

```python
@ReconCheckRegistry.register
class PaymentAllocationCheck(BaseReconCheck):
    code = "payment_fully_allocated"
    level = CheckLevel.sanity
    default_severity = CheckSeverity.critical

    def run(self, ctx):   # ctx: start_date, end_date, tolerance, config, heartbeat()
        # set-based queries only; yields Finding(entity_type, entity_id,
        # entity_ref, dimension, amount, detail)
```

The **runner** (not the check) owns: result row creation, finding→break upsert
in batches of 500, tolerance filtering, per-check try/except (a crashing check
gets `status=error`, run continues — mirrors EOD `_run()` isolation), heartbeat,
and the auto-resolve pass.

### 4.4 Check catalog

**Sanity (daily, EOD-inline, whole suite < 3 min):**

| Check | Assertion | Query shape / budget |
|---|---|---|
| payment_fully_allocated | `Payment.amount == Σ settled ledgers + excess − refunded` per payment, window-scoped | 1 grouped Payment↔Ledger join, <5s |
| disbursement_principal | disbursed txn ⇒ principal ledger/demand == disbursed amount | window-scoped join, <5s |
| loan_status_vs_outstanding | outstanding>0 ⇒ active; ==0 ⇒ closed. Reads **EOD TransactionSummary** (materialized in EOD step 3 — never recompute) | full book, <30s |
| closure_integrity | closed/foreclosed/settled_off ⇒ `AccountProps[loan_closure_value_date]` present + closing txn exists | anti-joins, <10s |
| upfront_identity | `available = hold − accrued − excess_raw` (correct formula, see §7.1) from EOD summary `upfront_interest_details` | dict math, <30s |
| demand_outstanding_identity (candidate) | `Demand.outstanding == amount − (settled+waived+refunded+excess+paid+accrued+tax_outstanding)` — denorm vs its own components | full book aggregate |

**Report recon (daily, async post-EOD, report-class limits):**

| Comparison | Source A | Source B |
|---|---|---|
| LMS ledger ↔ GL posted | `GLReconciliationService` tiers 1–3 from PR #1387, as-is | — |
| Portfolio ↔ GL control (Tier 4) | Σ `outstanding_details.total` (EOD summary) | GL loan-control closing balance |
| Portfolio report ↔ Outstanding report | `portfolio_handler.generate_data()` | `outstanding_report.generate_data()` |
| Upfront report ↔ summary | handler output | `upfront_interest_details` |
| Excess report ↔ ledger | handler output | direct ledger aggregate |
| TB ↔ GL balances | TB generator | opening + movement |
| *(Phase 4)* Payments ↔ bank | payment UTRs | `BankStatementLine` (exact UTR → amount+date fuzzy → unmatched break) |

Report-vs-report comparisons call `handler.generate_data()` directly (never via
Excel). Where handler output is too display-formatted, the source adapter
duplicates extraction — *controlled duplication is the point*: an independent
second computation is what makes it a reconciliation.

### 4.5 Execution flow

```
EOD 01:00  run_day_rollover  (core/tasks.py:26; EODTask enum product/constants.py:220)
├─ 1 settle_excess_payments
├─ 2 update_demand_dpds
├─ 3 update_transaction_summaries     ← summaries fresh
├─ 4 update_system_date
├─ 5 scan_due_reminders
└─ 6 run_recon_sanity  (NEW)
      ├─ ReconRunnerService.run(daily_sanity, run_date=closed day)  # inline, <3 min
      └─ TaskService.invoke(recon.tasks.run_report_recon, run_date) # async, heavy
Step "succeeds" if the engine ran; breaks are data-health, not pipeline failure.

On-demand: POST /recon-runs/ {run_type, start_date, end_date, checks?}
           → TaskService.invoke → same runner.

Export: LmsGlReconciliationHandler refactored to read the persisted run →
        keeps report-module scheduling + future email delivery for free.
```

## 5. Speed, retries, idempotency

### 5.1 Retry layers

| Layer | Mechanism | Grounding |
|---|---|---|
| Infra failure | `RobustTask` autoretry: 3×, exp backoff 180→600s, 25% jitter | tasks/base_task.py:42-57 |
| Final failure | DLQ publish (`{service}-dlx`) + `on_failure` marks `ReconRun.status=error` | base_task.py:220; mirrors `_ReportGenerateTask.on_failure` |
| One check crashes | runner catches → `ReconCheckResult.status=error`, run continues | recon runner |
| Stuck run | `sweep_stuck_recon_runs`: running + `updated_at` >30 min → error | copies `sweep_stuck_reports` (reports/tasks.py:296) + heartbeat pattern |
| EOD step failure | `DayRolloverRun.status=partial` — engine broke ≠ data broke | existing EOD semantics |

### 5.2 Idempotent resume (why autoretry is safe here)

```
retry/re-invoke (run_date=D)
→ get_or_create ReconRun(D, run_type, trigger=eod)          # unique constraint
→ skip checks whose ReconCheckResult has terminal status     # resume, not reject
→ break upsert by fingerprint: reprocessing is a no-op
  (first_seen preserved, last_seen bumped)
→ auto-resolve ONLY over checks that COMPLETED this run
  (an errored check cannot mass-auto-resolve its old breaks)
→ notification correlation_id = f"recon-break:{fingerprint}" # alert once, ever
```

Checks are read-only — no partial-write hazard inside a check.

### 5.3 Performance rules

- No per-loan Python loops; set-based aggregates only (anti-join style like
  `unposted_transactions_qs`).
- Sanity checks read EOD-materialized `TransactionSummary`, never recompute.
- Long stages chunk + call `heartbeat()` (30-min sweeper threshold).
- Report-recon: own task, `soft_time_limit≈6000s` (report class), never in EOD.
- Ledger indexes today: `(value_date, posting_type)`, `(component, posting_type)`,
  `(transaction, posting_type)`. If per-account sums get slow, consider
  `(account, value_date)` — decide from EXPLAIN during implementation.

## 6. UI design (crego-web / omni-web)

Standalone module at `/recon`, sidebar entry gated by `view_reconrun`.
PR #922's screen remains the GL report export form under gl-config.

```
/recon
┌─ Last run: today 01:42 · 2m 11s ──────────────────────┐
│  ✓ 8 passed  ⚠ 1 warn  ✗ 1 fail                       │
│  Open breaks 14 (3 new, 2 aged >7d)                    │
│                        [Run now ▾] [Export ⬇]          │
└────────────────────────────────────────────────────────┘
Tabs: Overview · Breaks · Runs · Checks

Breaks: filters check/severity/status/entity ·
  columns: Check | Entity | Ref | Δ Amount | Age | Status
  row click → read-only drawer: detail JSON + run history of this break
Runs: date · type · ✓/⚠/✗ counts · new breaks · duration
  row click → per-check results (expected/actual/difference)
Checks: registry list · tolerance · enabled (admin)
```

Files (following the Reports module shape):
`modules/recon/{index,router,list,detail,queries,types}` +
`services/reconApi.ts` + nav entry in `shared/constants/nav/default.ts` +
permission codes `view_reconrun` (v1 is read-only; no change permission needed
until v2 workflow). Standard `DataTable`, react-query, server-side pagination.

## 7. Known defects & gaps to fix while folding in PR #1387

### 7.1 Upfront identity formula (bug)

Branch asserts `available == deducted − accrued − refunded − settled`
(gl/reconciliation.py:822). Actual computation
(ctm/services/transaction_summary.py `_upfront_aggregate_to_details`):
`available = hold − accrued − excess_raw`. They agree only when unrefunded
upfront excess is zero → permanent false "failed" on tenants with live upfront
excess. Fix the check to the real identity.

### 7.2 Other fixes

- `_current_balance_drift_count()` ignores `as_of_date` (all-time) — scope it.
- `build_lms_report_totals()` runs even for trial-balance-only selections — skip.
- Float drift: `upfront_interest_details` values are floats; portfolio-wide sums
  manufacture penny mismatches → per-check tolerance (default 0.01) everywhere.
- `lms_report_amount_for_row` returns the ledger amount verbatim for the excess
  section (tautology) — replace with genuine excess-report source comparison.

### 7.3 Structural gaps the module closes

```
Ledger ──▶ GL          ✅ PR #1387 (posting fidelity)
Ledger ──▶ Portfolio   ➕ sanity checks
Portfolio ──▶ GL       ➕ Tier-4 control-account check   ← the CFO question
```

### 7.4 Data-model facts that shaped checks

- `Account` has no denormalized outstanding; use EOD summary or Σ`Demand.outstanding`.
- Payment DB constraint `amount = excess + used − refund − tds`
  (transfer/models.py:262) ties Payment's own columns only; the recon check ties
  them to **ledger truth** — not redundant.
- Closure date lives in `AccountProps["loan_closure_value_date"]`
  (product/services/closure_dates.py); a terminal-status account missing the
  prop is itself a break.

## 8. Risks

1. **Break-storm on first run** — historical data will light up hundreds of
   breaks. First run per tenant runs in "baseline" mode: bulk-tag existing
   breaks so the page starts actionable, not archaeological.
2. **False breaks from float/rounding** — every check has a tolerance; noisy
   checks kill recon-system credibility fastest.
3. **Daily report-recon cost on large tenants** — mitigated by async post-EOD
   execution + EOD-summary reuse; monitor per-check `duration_ms` in run stats
   and demote to weekly per-tenant via `ReconCheck.config` if needed.

## 9. Phasing

| Phase | Scope | Repo |
|---|---|---|
| 1 | `recon` app: models, registry, runner, 5–6 sanity checks, EOD step 6, sweeper, notification event, read-only API | crego-omni |
| 2 | Report-recon pack: fold PR #1387 engine, fix §7 defects, Tier-4 check, report-vs-report sources, daily async enqueue, Excel exporter refactor | crego-omni |
| 3 | Dashboard UI: `/recon` module (Overview/Breaks/Runs/Checks) | crego-web |
| 4 | Bank layer: `BankStatementLine` ingest + UTR matcher check pack | crego-omni |
| v2 | Break workflow: ack/resolve/assignment, maker-checker | both |
