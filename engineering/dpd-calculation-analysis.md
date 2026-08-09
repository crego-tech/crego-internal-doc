# DPD Calculation in Omni — How It Works End to End

**Date:** 2026-07-28
**Repo:** `crego-omni` (verified against source, branch `develop`)
**Scope:** Demand-level DPD, loan-level roll-up, group/aggregate roll-up, trigger points,
and behaviour when an overdue demand is settled.

---

## The headline: there are **two** DPD systems, not one

They live side by side, are computed differently, and only one of them is a `max()` of
`Demand.dpd`.

| | **System A — Stored DPD** | **System B — Derived DPD** |
|---|---|---|
| Lives on | `Demand.dpd`, `Demand.peak_dpd` (int cols) | `TransactionSummary.due_details["current_dpd"]` |
| Written by | EOD batch + payment settlement | Nothing — recomputed at every summary build |
| Behaviour | **Ratchet** — `max(new, old)`, never falls | **Point-in-time** — can drop to 0 instantly |
| Basis | Demand row status | Ledger **outstanding** as of date |
| Feeds | NPA trigger, dashboards, collections queue | Asset classification, reports, group roll-up |

> **Common misconception:** when building a `TransactionSummary`, we do **not** take
> `max(Demand.dpd)`. `current_dpd` is re-derived from scratch off outstanding balances.
> The only thing read from the `Demand` table is `peak_dpd`.

---

## 1. Demand level — where the number is born

`project/apps/product/handlers/eod.py:144` → `update_demand_dpds()` (EOD step 2 of 5)

```
     ┌──────────────────────────────────────────────┐
     │ WHO gets re-aged each EOD                    │
     ├──────────────────────────────────────────────┤
     │ due_date <= as_of_date                       │  ← not yet due → skipped
     │ AND status in unpaid_choices()               │  ← paid/waived/cancelled → skipped
     │   (pending, due, partially_paid,             │
     │    partially_settled)                        │
     │ AND component.code in dpd.component_codes    │  ← default [principal, interest, penal]
     └──────────────────────────────────────────────┘
                          │
                          ▼
        dpd = (as_of_date − due_date).days  + 1 if EOD product   (eod.py:192-195)
                                            + 0 if SOD product
                          │
                          ▼
        demand.dpd      = max(dpd, demand.dpd)        ← RATCHET  (eod.py:197)
        demand.peak_dpd = max(dpd, demand.peak_dpd)   ← RATCHET  (eod.py:198)
```

Note the `+1` on EOD products: a demand due today is already **DPD 1** at tonight's EOD,
not 0.

Persisted via `Demand.objects.bulk_update([...], ["dpd", "peak_dpd", "updated_by"])`
at `eod.py:216`.

---

### Residual-due guard (added 2026-07-28)

The status filter is not sufficient on its own. `Demand.status` and the demand amounts are
maintained by *separate branches* of the same `if/elif` chain, so they can drift:

```python
# base.py:655-664 — order matters
if   paid + tax_paid >= amount:            status = paid
elif paid + tax_paid  > 0:                 status = partially_paid   ◀── catches it first
elif waived + tax_waived == amount:        status = waived
```

A demand of ₹10,000 cleared as **₹6,000 paid + ₹4,000 waived** hits the second branch →
`partially_paid`, which **is** in `unpaid_choices()`. Meanwhile
`outstanding = amount − (paid + waived) = 0`. EOD then ages a demand that owes nothing, and
because `Demand.dpd` is a ratchet, that number never comes back down — and it feeds the NPA
trigger.

`eod.py` now gates on the money as well as the status:

```python
residual_due = demand.outstanding + demand.tax
if residual_due <= DPD_RESIDUAL_DUE_THRESHOLD:   # Decimal("0.01")
    cleared_demand_ids.append(str(demand.id))
    continue
```

Two properties worth noting:

- The threshold `Decimal("0.01")` is deliberately the **same constant** the summary builder
  uses for its outstanding gate, so System A and System B now agree on which demands are
  delinquent.
- Skipped demands are collected and emitted as a `logger.warning` after the bulk update. The
  skip fixes the DPD; the warning surfaces the underlying status-update gap so it gets fixed
  at the write path instead of being silently absorbed by EOD forever.

`hold` is excluded from `residual_due` — per the model comment,
`amount = outstanding + hold + tax`, and `hold` is not yet payable.

Tests: `project/apps/product/tests/test_eod_demand_dpd_guard.py`.

---

## 2. What happens when that demand gets paid

Two different code paths write it, **and they disagree**.

```
                       PAYMENT FULLY SETTLES A DEMAND
                                    │
              ┌─────────────────────┴─────────────────────┐
              ▼                                           ▼
    repayment.py:372-381                          base.py:654-658
    (normal repayment handler)                    (generic ledger→demand sync)

    dpd      = 0                    ← ZEROED      dpd      = max(last_paid_at − due_date, 0)
    peak_dpd = last_paid_at                       peak_dpd = max(dpd, peak_dpd)
               − due_date                                    ← RETAINED, non-zero
    status   = paid                               status   = paid
```

Either way, `status = paid` ⇒ the demand **leaves** `unpaid_choices()` ⇒ EOD never touches
it again. The values **freeze** at whatever that path wrote.

### Why does `base.py` use `max(0, last_paid_at − due_date)`?

It isn't a deliberate design choice — **it is the pre-CRE-5369 semantics that survived
because the fix was only applied to one of the two call sites.** Git history:

| Date | Commit | What happened |
|---|---|---|
| 2026-01-08 | `197c41cb6` (PR #554) | `_update_demand_amount_and_status_by_ledger` centralised in `base.py`. `dpd` meant *"the DPD at which this demand settled"* — a final delinquency stamp. `dpd = days_late`, `peak_dpd = max(dpd, peak_dpd)`. |
| 2026-01-16 | `ede59abb9` | Same expression present in `repayment.py`, plus a `due_date` null guard. |
| 2026-04-27 | `e90f6d40d` (PR #1020, CRE-5369) | *"resetting demand DPD and updating peak DPD calculation"* — `repayment.py` changed to `dpd = 0` and the days-late expression **moved onto** `peak_dpd`. |

The CRE-5369 diff is literally a two-line move:

```diff
-                        demand.dpd = (
+                        demand.dpd = 0
+                        demand.peak_dpd = (
                             max((demand.last_paid_at - demand.due_date).days, 0)
                             ...
                         )
-                        demand.peak_dpd = max(demand.dpd, demand.peak_dpd)
```

That commit established the semantics we use today: **`dpd` = current delinquency (0 once
settled), `peak_dpd` = historical worst.** `base.py:657` was never updated to match, so it
still writes the January meaning of `dpd` into a field that has had the April meaning
everywhere else for three months.

The `max(..., 0)` clamp itself is unrelated and correct in both files — it stops an *early*
settlement (paid before `due_date`) producing a negative DPD.

**Recommendation:** backport CRE-5369 to `base.py:657` so both settlement paths write
`dpd = 0`. This also removes the NPA false-positive described in the risks section, since a
paid demand would no longer carry a ≥91 `dpd`. Needs a data check first — see below.

### Timeline — demand ₹10,000, due 01-Jun, paid in full 25-Jun (EOD product)

```
 date    01 ─── 05 ─── 10 ─── 15 ─── 20 ─── 24 │ 25 ─── 30 ──▶
                                               │ PAID
 ─────────────────────────────────────────────────────────────
 Demand.dpd        1     5    10    15    20  24 │  0   0   0   ← repayment.py path
                  ▁▂▃▄▅▆▇█████████████████████  │  ╳ cliff to zero
 ─────────────────────────────────────────────────────────────
 Demand.peak_dpd   1     5    10    15    20  24 │ 24  24  24   ← holds forever
                  ▁▂▃▄▅▆▇█████████████████████████████████████
 ─────────────────────────────────────────────────────────────
 outstanding    10000 10000 10000 10000 10000 10000│  0   0   0
 ─────────────────────────────────────────────────────────────
 summary
 current_dpd       1     5    10    15    20  24 │  0   0   0   ← recomputed, mirrors outstanding
 summary
 peak_dpd          1     5    10    15    20  24 │ 24  24  24
```

### The rule, stated precisely

| Demand state | `current_dpd` contribution | `peak_dpd` contribution |
|---|---|---|
| Overdue, outstanding > 0.01 | `(as_of − due_date).days [+1]` | same, ratcheted |
| **Was overdue, now settled** | **0** — drops out of the max entirely | **retains** the days-late high-water mark |
| Never overdue (due_date > as_of) | 0 | 0 |
| Component not in `dpd.component_codes` | excluded | excluded |

**Answer to "overdue but now settled":** `current_dpd` → **0** (the loan is clean today).
`peak_dpd` → **24** (it stays dirty in history). Asset classification follows `current_dpd`,
so the loan drops straight back to Regular the moment the last rupee lands.

---

## 3. Loan level — the first `max()`

`project/apps/ctm/services/transaction_summary.py:369-418`

This is **not** `Max(Demand.dpd)`. It walks schedules and re-derives:

```
current_dpd = 0
for each schedule in loan:
      run accrual projection (in-memory, not saved)
      for each (component_code, demand) in schedule:

          ├─ component_code not in dpd.component_codes ?  ──▶ skip
          │
          ├─ outstanding_after_accrual <= 0.01 ?          ──▶ skip   ★ settled demands
          │                                                          drop out here
          ├─ due_date > as_of_date ?                      ──▶ skip
          │
          └─ demand_dpd = (as_of_date − due_date).days [+1 if EOD]
             current_dpd = max(current_dpd, demand_dpd)      ◀── MAX #1
```

The `> 0.01` outstanding gate is the whole mechanism: **a settled demand simply stops being
a candidate for the max.** No reset logic needed.

### Peak, computed separately (`:420-453`)

```
peak_dpd_from_demand = Max(Demand.peak_dpd)  over this account,
                       filtered to dpd.component_codes         ◀── the only
                                                                   Demand-table read
peak_dpd = max(current_dpd, peak_dpd_from_demand)
```

Batched builds read it from `build_ctx.peak_dpd_by_account`; unbatched builds hit the DB
directly. Same result.

### Worked example — one loan, 5 demands, as-of 30-Jun

```
                     due_date   outstanding   in dpd codes?   demand_dpd   counted?
 principal 01-Jun     01-Jun       ₹0          yes              —          ✗ settled
 interest  01-Jun     01-Jun       ₹450        yes              30         ✓
 fee       10-Jun     10-Jun       ₹200        NO (not in cfg)  —          ✗ component
 principal 15-Jun     15-Jun       ₹8,000      yes              16         ✓
 principal 15-Jul     15-Jul       ₹8,000      yes              —          ✗ not due
                                                            ────────────
                                     current_dpd = max(30, 16)  =  30
                                     peak_dpd    = max(30, Demand.peak_dpd=47) = 47
```

The loan's *oldest unpaid* demand wins — as it should. A paid-late demand contributed
**47** to peak and **nothing** to current.

---

## 4. Group / aggregate level — the second `max()`

`transaction_summary.py:2335-2359`, stored at `:2452-2457`
(`_aggregate_account_summaries_batch()`)

This one *does* read stored values — but from the **child summaries**, not from demands.

```
                    ┌─────────────────────────┐
                    │  GROUP / PARENT ACCOUNT │
                    │  current_dpd = 30       │◀── max of children
                    │  peak_dpd    = 62       │◀── max of children (independent max!)
                    │  asset_category ← computed from max_dpd,
                    │                  using the CONFIG OF THE
                    │                  HIGHEST-DPD CHILD  (:2358)
                    └───────────┬─────────────┘
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                 ▼
        ┌───────────┐     ┌───────────┐     ┌───────────┐
        │  Loan A   │     │  Loan B   │     │  Loan C   │
        │ cur   30  │     │ cur    0  │     │ cur   12  │
        │ peak  30  │     │ peak  62  │     │ peak  12  │
        └───────────┘     └───────────┘     └───────────┘
                            ↑ fully caught up today,
                              but still drags peak to 62
```

Two independent maxes — the group's `peak_dpd` can come from a **different loan** than its
`current_dpd`.

RBI category has an extra rule (`:2353`): if **any** child is NPA, the parent is NPA —
that's an OR, not a max.

Customer-level RBI NPA (`transaction_summary.py:45-118`) is a third variant: it maxes
`(as_of_date − due_date).days` over unpaid demands across all *related* loans (same contact
or parent). The code comment at `:95` is explicit that it deliberately avoids live
`Demand.dpd` so backdated summaries use historical DPD.

Same aggregation function is reused for program and product levels.

---

## 5. Asset classification bands

Driven by `current_dpd` against `config.dpd.npa_dpd_threshold`
(seeded in `addon/migrations/0013_add_dpd_config_to_non_template_configs.py`):

| DPD | RBI category |
|---|---|
| ≤ 0 | STD / Regular |
| 1 – 30 | SMA0 |
| 31 – 60 | SMA1 |
| 61 – 90 | SMA2 |
| ≥ 91 | NPA |

Config-driven `asset_category` uses the tenant's own thresholds; `rbi_asset_category` uses
the hard-coded RBI bands above (`transaction_summary.py:2212`, `:2231-2241`).

Related: `asset_classification` is a separate key from the settlement-critical
`asset_category` — see the asset-classification-date fix notes.

---

## 6. Full trigger map

```
 EVENT                              WHAT MOVES
 ────────────────────────────────────────────────────────────────────────────
 Payment posts, demand fully paid   Demand.dpd → 0 (or days-late), peak frozen
   → synchronous, same txn            summary current_dpd only changes at next build

 EOD, step 2 update_demand_dpds     Demand.dpd/peak_dpd ratcheted for all unpaid
   → once per business day

 EOD, step 2b NPA suspension        reads Max(demands__dpd) >= 91 → suspend income
                                      (eod.py:275)
 EOD, step 3 update_txn_summaries   summary current_dpd/peak_dpd rebuilt from ledgers
                                      then group roll-up max

 Loan closure / write-off           nothing zeroed — DPD frozen as-is

 Reports (portfolio, CIC, loan a/c) read-only from due_details — no recompute
```

EOD step order is defined by `EODTask` member order in `project/apps/product/constants.py`:

```
settle_excess_payments → update_demand_dpds → update_transaction_summaries
    → update_system_date → scan_due_reminders
```

**Order matters:** the DPD ratchet (step 2) runs *before* summary build (step 3), so
summaries always see today's freshly-aged demands.

`as_of_date` comes from the business date passed into `EODHandler`, not wall clock —
backdated EOD runs age DPD to the historical date correctly
(`core/services/day_rollover.py`).

---

## ⚠ Three things worth worrying about

### 1. Two settlement paths write `dpd` differently — and the NPA trigger doesn't filter

`repayment.py:374` sets `dpd = 0` on payment; `base.py:657` sets `dpd = days_late` and
leaves it there. Meanwhile the NPA check at `eod.py:275` / `:384` is:

```python
Account.objects.annotate(max_dpd=Max("demands__dpd")).filter(max_dpd__gte=npa_threshold)
```

No `status__in=unpaid_choices()`. No component filter. So a **fully-paid** demand that
settled 95 days late via the `base.py` path keeps `dpd = 95` forever and can flag a
perfectly current account as NPA and suspend its income.

**Status:** the EOD residual guard (section 1) stops *new* drift from being aged, but it does
**not** clean up `dpd` values already written by the `base.py` path — those rows are
`status=paid`, so EOD skips them entirely and always did.

**Check to run per tenant before backporting:**

```python
# Paid demands still carrying a non-zero dpd — these are the NPA false-positive candidates
Demand.objects.filter(status="paid", dpd__gt=0).count()
Demand.objects.filter(status="paid", dpd__gte=91).count()

# Accounts the NPA trigger would fire on purely because of a paid demand
from django.db.models import Max
(Account.objects
    .filter(status="active", sharing_type="main", level="individual")
    .annotate(max_dpd=Max("demands__dpd"),
              max_unpaid_dpd=Max("demands__dpd",
                                 filter=Q(demands__status__in=DemandStatus.unpaid_choices())))
    .filter(max_dpd__gte=91)
    .exclude(max_unpaid_dpd__gte=91)
    .count())
```

If that last count is non-zero on tyger / tygerwb, income has been suspended on accounts that
are current. Fixing it needs three things together: the `base.py` backport, a one-off
`dpd = 0` correction for `status=paid` rows, and a `status__in=unpaid_choices()` filter on the
NPA annotation at `eod.py:275` / `:384`.

### 2. The ratchet and the derived value diverge silently

`Demand.dpd` never decreases; summary `current_dpd` can. A partially-paid demand that
shrinks below the `0.01` outstanding threshold drops out of `current_dpd` while
`Demand.dpd` stays at its high-water mark.

Dashboards (`product/services/dashboard.py`, `Max("dpd")`), the contact collections list
(`contact/views.py:184`) and the schedule view (`schedule/views.py:70`) all read
System A; reports read System B. They will quote **different DPD for the same loan on the
same day**. This is the likeliest source of "the report and the dashboard disagree"
tickets.

### 3. The `+1` EOD offset is duplicated

`eod.py:193` and `transaction_summary.py:415` each add 1 for EOD products as separate
literals. They agree today, but if one is ever changed for a client, DPD silently forks
between the stored and derived paths.

---

## Key file references

| Concern | Location |
|---|---|
| `Demand.dpd` / `peak_dpd` fields | `schedule/models.py:116-118` |
| EOD re-aging | `product/handlers/eod.py:144-217` |
| Settlement zeroing (repayment) | `ctm/processors/loan/repayment.py:372-381` |
| Settlement retention (ledger sync) | `ctm/processors/base.py:654-658` |
| Loan-level `current_dpd` (max #1) | `ctm/services/transaction_summary.py:369-418` |
| Loan-level `peak_dpd` | `ctm/services/transaction_summary.py:420-453` |
| Group roll-up (max #2) | `ctm/services/transaction_summary.py:2335-2359, 2452-2457` |
| Customer-level RBI NPA | `ctm/services/transaction_summary.py:45-118` |
| NPA income suspension trigger | `product/handlers/eod.py:263-303` |
| DPD config defaults | `addon/migrations/0013_add_dpd_config_to_non_template_configs.py` |
| EOD step order | `product/constants.py` → `class EODTask` |
