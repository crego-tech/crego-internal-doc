# Omni Gap Analysis — NPA Account, 100 Invoices, 100 Simultaneous Payments, Limit Release

**Scenario:** One loan/group account under an SCF program. 100 invoices financed (100 drawdown loans). Account is NPA. 100 payments arrive at the same time. Expectation: payments settle overdue, free the limit, and freed limit is reusable by new loans.

**Date:** 2026-08-05 · **Repo:** `crego-omni` · All paths relative to `project/apps/`.

> **Remediation design:** [omni-transaction-serialization-design.md](./omni-transaction-serialization-design.md)
> — answers this analysis with the serialization guarantee, phasing, and gap→fix mapping.
> It also records one **critical finding not in this document**: `TenantAwareCache` silently and
> permanently degrades to `DummyCache` on any Redis error, and `DummyCache.add()` always returns
> `True` — so every lock below (account, batch, limit) may not exist at all, per worker process.

---

## What works as expected

1. **Settlement is synchronous and correct per payment.** Repayment appropriation runs inside one DB transaction: accrual → allocation → demand updates → limit free (`ctm/processors/loan/repayment.py:989-1028`, saved via `TransactionHelper.save_result`, all inside `tenant_atomic_context` in `ctm/services/transactions.py:1718-1720`).

2. **SCF limit release is immediate and proportional.** For non-schedule-based products (all SCF templates: `addon/templates/scf_*.json` → `"is_schedule_based": false`), every principal repayment frees limit in the same DB transaction (`ctm/processors/base.py:853-884` → `LimitService.free_limit`, `addon/services/limits.py:470`). Release walks `LoanAndLimitLink` rows, so the loan, group account, program, contact, and product limits all get headroom back simultaneously.

3. **Per-anchor serialization exists by design.** SCF loan transactions batch under the parent group account (`ctm/services/transaction_batches.py:145-152`) and the batch is drained one item at a time under a lock (`transaction_batches.py:360-398`), so the limit arithmetic is mostly serialized.

4. **Payment-level idempotency is solid.** `Payment` is re-read under `select_for_update` with a status check (`transfer/services/payments.py:971-976`); duplicate (payment, account) repayment transactions are rejected (`payments.py:843-851`). A payment won't double-apply.

5. **NPA income realization on cash works.** If `income_suspended`, the paid portion of interest/fee/charge posts a negative `npa_income_suspension` ledger, recognizing suspended income only on receipt (`repayment.py:354-368`).

6. **NPA can change appropriation order** (config-driven): contact-level asset category ≥ NPA overrides settlement order via `dpd.npa_dpd_threshold[].settlement_order` (`repayment.py:178-268`). Note the base templates ship `"npa_dpd_threshold": []`, so out of the box NPA does **not** change the order.

7. **Allocation reads realtime payables**, not cached summaries (`payments.py:632-678` uses `get_realtime_payable_amount_schedule_wise`), so payment N+1 sees payment N's effect on outstanding.

8. **De-classification of asset category is automatic** — `current_dpd` is recomputed from live outstanding on each summary rebuild, and the payment itself triggers the loan-level rebuild (`ctm/services/transaction_summary.py:407-418`, `transactions.py:1603-1610`).

---

## Where it breaks

### A. 100 simultaneous payments (concurrency)

| # | Gap | Where |
|---|-----|-------|
| A1 | **One failed payment strands the rest.** Item failure re-raises → batch marked `stopped` → the beat sweep only re-drives `pending`/`processing` batches, never `stopped`. Payments #38–100 sit unapplied forever; meanwhile new payments create a fresh batch and keep posting, so the gap is invisible. Recovery is manual only. | `transaction_batches.py:389-394`; `ctm/tasks.py:136-138` |
| A2 | **Locks are unfenced cache locks with short TTLs.** Account lock: `cache.add`, 30 s (`transactions.py:1343-1367`). Batch lock: `5 × items` = 500 s for 100 items, vs a 600 s Celery soft limit. A long batch loses its lock mid-run; the next beat tick starts a second worker on the same batch; worker A's `finally` then deletes worker B's lock. `get_next_batch_item` has no `select_for_update`, so items interleave. The per-account `sequence` stamp (`transactions.py:1633-1654`) explicitly relies on this lock. | `transaction_batches.py:35-58`; `settings/celery.py:29` |
| A3 | **Lock released before COMMIT.** The account-lock `try/finally` sits *inside* the atomic block, so the lock drops while writes are uncommitted — the next holder reads pre-commit state. | `transactions.py:1718-1843` |
| A4 | **Two batches can run on the same account concurrently.** Payments batch **per program** (`payments.py:346-372`); manual CTM transactions batch **per account** (`transaction_batches.py:136-156`). Different batches, different lock keys — only the 30 s account lock stands between them, and its loser is rejected with `BadRequest` (failed item → A1). | |
| A5 | **Contention loser gives up rather than retrying**; lock-failure → item failed → batch stopped. The batch task's first `except Exception` swallows errors without re-raise (second except block is dead code), so no Celery retry either. | `transaction_batches.py:341-347`; `tasks.py:170-209` |
| A6 | **Worker crash leaves an item at `processing` forever** — `get_next_batch_item` only picks `pending`/`failed`, and `mark_completed` raises while any item is `processing`, so the batch dead-ends into `stopped` and the payment is silently dropped. | `transaction_batches.py:217-237`; `ctm/models.py:759-770` |
| A7 | **Non-deterministic ordering.** Items order by `(value_date, txn_date)` with no tiebreaker; 100 same-day payments resolve in Postgres plan order. Matters because multi-loan allocation is greedy and dumps the entire remainder on the *last* loan (`payments.py:786-821`). | `transaction_batches.py:217-237` |
| A8 | ~~**No UTR dedupe at intake.**~~ **Corrected 2026-08-05 — not a gap.** `payment_utr` *is* `unique=True, db_index=True` (`transfer/models.py:187`), so duplicate bank-file rows are rejected at intake. It is nullable, so the only residual exposure is null-UTR intake; `payment_utr` is required before processing by `_validate_required_fields_for_processing`. | `transfer/models.py:187` |
| A9 | **Batch get_or_create race.** If the active batch is `processing` with 0 pending items, concurrent intake hits the `uniq_active_batch_per_program` constraint → `IntegrityError` → 500 on the payment-process API. Also: item added between the final `get_next_batch_item() → None` and `mark_completed()` is stranded. | `transaction_batches.py:111-120`; `models.py:702-727` |
| A10 | **Excess money is not applied inline.** Unallocated remainder becomes a contact/partner-level excess demand (`repayment.py:766-776`) settled later by EOD `settle_excess_payments`. The excess-demand increment is a read-modify-write with no `select_for_update` — concurrent payments for the same contact can lose an increment. | `repayment.py:612-737` |

**Net for the scenario:** with 100 payments at once, expect (a) intermittent 500s at intake, (b) a high chance the batch stops partway with the remainder stranded silently, (c) if the batch runs long, interleaved double-processing risk, and (d) order-dependent allocation differences run to run.

### B. NPA behavior

| # | Gap | Where |
|---|-----|-------|
| B1 | **`income_suspended` is never unset.** No de-classification/upgrade job, no reversal transaction, and full repayment does not clear it. Once NPA, the account accrues to suspense forever and every future repayment keeps emitting suspension-release ledgers — even after full cure. | grep: only setter `npa_income_suspension.py:50-69`, no unsetter |
| B2 | **NPA threshold hardcoded at 91** in the EOD selection filter; per-product `dpd.npa_days` is only a secondary skip — a product configured with `npa_days < 91` is never picked up. | `product/handlers/eod.py:251` |
| B3 | **Stale settlement order under load.** `get_settlement_order` reads cached contact/account summaries; with N same-day payments, payments 2..N can be appropriated using an asset category computed before payment 1 cured the overdue. Contact-level aggregate rebuild is debounced/async. | `repayment.py:217-246`; `transaction_summary.py:2907-2919` |
| B4 | **RBI (contact-level) NPA is sticky until *all* related loans hit exactly 0 DPD** — correct per RBI, but combined with B1 the operational flag and the classification can permanently disagree. | `transaction_summary.py:107-109` |
| B5 | **`peak_dpd` destroyed on full payment** — repayment path overwrites instead of `max()`-ing (the ledger path does it correctly at `base.py:663-664`). Historical peak DPD for reporting/CIC is lost. | `repayment.py:395-401` |
| B6 | **Backdated payment during the batch is dangerous.** It reverses future transactions/payments without locks, never re-applies the reversed payments inline, and the inline excess-settlement it relies on **self-deadlocks on the account lock** (EOD runs while the lock is still held) and is silently swallowed. | `payments.py:985-1005`; `transactions.py:1789-1794`; `eod.py:983-991, 1105-1107` |

### C. Limit release & reuse

| # | Gap | Where |
|---|-----|-------|
| C1 | **No NPA/overdue gate on utilization — the freed limit is *too* reusable.** `check_limit_available_to_block` checks only limit status/dates/headroom; the drawdown path has zero DPD/NPA/overdue checks (grep across `invoice/` finds none). A 120-DPD, income-suspended anchor can immediately re-draw every rupee freed by a payment. The only brake is a human setting `Limit.status = inactive`. If the business expectation is "NPA → freeze new utilization", **that control does not exist**. | `addon/services/limits.py:156-244`; `invoice/services/drawdowns.py` |
| C2 | **Schedule-based loans don't free limit on repayment** — only on `closed`/`settled_off`/`foreclosed`, all at once. Fine for SCF; wrong expectation for term loans (90% repaid EMI loan = 100% utilization). | `base.py:869-875` |
| C3 | **Write-off never frees limit** — `written_off.py` has no limit logic; the limit stays consumed forever. | `ctm/processors/loan/written_off.py` |
| C4 | **Limit bookkeeping failure aborts a valid customer payment.** `free_limit` raises on any link mismatch/contention inside the same atomic transaction as the repayment → the whole payment rolls back. Also `primary_limit` is dereferenced without a None check → `AttributeError` kills the repayment. | `limits.py:363-456`; `base.py:878-883` |
| C5 | **Shared/colending block path can silently no-op** — pre-lock read-then-write check, and on `updated != 1` it does nothing: no link row, no exception. Caller proceeds believing limit was blocked → silent limit leak. | `limits.py:267-285` |
| C6 | **No reconciliation.** Limit balances are event-sourced deltas; EOD never recomputes them. Any missed delta (C5, crashes, A-series races) is permanent drift. Repayment-reversal deliberately allows `available_amount` to go negative, violating the DB check constraint for newer rows. | `limits.py:506-529, 617` |
| C7 | **Limit lock hygiene:** lock acquisition sits outside `try` (failure to grab lock #3 of 5 leaks locks #1–2 for 30 s); soft-deleted-links early-return leaks all locks; the block lock is released before the outer transaction commits. | `limits.py:293-341, 588` |
| C8 | **Limit release timing is async from the payer's view.** Settlement (and hence limit free) happens when the batch worker reaches the item — beat runs every minute, batches drain serially. Under 100 payments the last freed limit can lag by many minutes; dashboards read debounced stale aggregates meanwhile, and NACH presentation sizing reads the cached `net_due_amount` snapshot. | `tasks.py:122-141`; `transfer/services/payment_batches.py:489-494, 303-311` |

---

## Direct answers to the scenario

1. **"Payment should settle the overdue"** — Yes per payment, including NPA income realization. But at 100-concurrent: batch-stop (A1), lock expiry interleaving (A2), stranded `processing` items (A6), and stale NPA appropriation order for later payments (B3).
2. **"…and free the limit"** — Yes, synchronously, for SCF loans (per principal rupee). No for schedule-based loans (C2), no for written-off loans (C3), and the free itself can kill the payment (C4).
3. **"…and that limit can be utilised by loan"** — Yes, immediately — *including while the account is still NPA*. There is no NPA/DPD/freeze gate anywhere in the drawdown or limit path (C1). Whether that's a gap depends on credit policy, but there is currently no way to enforce "NPA blocks fresh utilization" except manually inactivating the limit.
4. **De-NPA** — asset classification cures automatically on rebuild; the `income_suspended` operational flag never cures (B1) — post-cure accounting stays in suspense-mode forever.

## Recommended fixes, ranked

1. Re-drive or split `stopped` batches: mark only the failed *item*, continue the loop, sweep `stopped` batches with failed-item quarantine (A1/A5/A6).
2. Replace cache locks with DB-level serialization: `select_for_update` on the account (or a fenced lock with token check on release); at minimum hold locks past COMMIT and re-queue on contention (A2–A5).
3. Unify batching grain — one batch key per (group) account for both payments and transactions (A4).
4. Add a credit-policy gate in `check_limit_available_to_block` / drawdown approval: reject or flag when contact/group asset category ≥ configured level (C1).
5. Add an NPA upgrade path: reverse `income_suspension` and clear props when contact DPD hits 0 (B1); read `npa_days` from config in the EOD filter (B2).
6. Deterministic item ordering (`value_date, txn_date, created_at, id`) and UTR uniqueness at intake (A7/A8).
7. Decouple limit-free failures from the payment (post-commit hook or compensating queue) + None-guard on `primary_limit`; add a nightly limit reconciliation from `LoanAndLimitLink` (C4/C6).
8. Fix `peak_dpd` overwrite (`max()`), and fix the shared-path silent no-op in `limits.py:267-285` (B5/C5).
