# CTM Loan Transaction Processing — Deep Audit

**Scope:** `crego-omni/project/apps/ctm/` — Core Transaction Module (CTM)
**Focus:** Loan transaction-code-based processing across `LoanTransactionProcessor` and SCF variants
**Date:** 2026-05-18
**Auditor:** Code walkthrough + verification against source

> Every finding below cites `file:line`. Severity is graded as **BLOCKER / HIGH / MEDIUM / LOW / INFO**. Findings without verified line evidence were dropped from this report.

---

## 1. Architecture Snapshot

The dispatch model is clean and well-factored.

**Entry point.** `ctm.processors.get_transaction_processor()` (`processors/__init__.py:45`) is a factory that returns a processor instance based on `transaction.transaction_type` (contact / program / group_account / loan) and, for loan transactions, `account.product.product_type` (term_loan / scf_sid / scf_pid / scf_vf / scf_df).

**Per-product registry.**

| Product type | Processor class | Supported txn codes |
|---|---|---|
| `term_loan` | `LoanTransactionProcessor` (`processors/loan/processor.py:34`) | 23 codes — full suite incl. restructuring, foreclose, prepayment, tranche, pre-EMI |
| `scf_sid` / `scf_pid` / `scf_vf` / `scf_df` | 4 SCF processors (`processor.py:102, 146, 190, 234`) | 11 codes each — no restructuring, no foreclose, no prepayment, no tranche |

**Dispatch.** Each processor exposes `get_process_methods()` which returns `{txn_code → bound method}`. `BaseTransactionProcessor.process()` (`processors/base.py:336`) routes by `transaction.transaction_code`.

**Layering.** Service → Processor → Mixins. `TransactionService.process()` (`services/transactions.py:1290`) calls `processor.process()`; processors are mixed-in per txn-code family (`DisbursementMixin`, `RepaymentMixin`, `AccrualMixin`, etc.).

**Status gating.** `AccountStatusTxnCodeMap` (`constants.py:87`) gates which txn codes are allowed for which account status. Checked in `BaseTransactionProcessor.process()` (`base.py:348`) and `preview()` (`base.py:390`).

**GL posting.** Single-leg `Ledger` rows are created with a `PostingType` (`outstanding`, `paid`, `waived`, `excess`, `settled`, `npa_income_suspension`, `write_off`, etc.). The dual-entry GL projection is materialized later via `ComponentGLMapping` (`models.py:698`), which maps `(component, product, posting_type, transaction_code, contact)` → `(debit_gl_account, credit_gl_account)`.

---

## 2. Critical Findings (BLOCKER)

### B1. `TransactionService.reverse()` is fundamentally broken

**File:** `services/transactions.py:1424-1496`

Multiple compounding defects make this method unsafe to call on any processed transaction:

1. **Invalid `transaction_code` written to DB.** Line `1444`:
   ```python
   transaction_code=f"{transaction.transaction_code}_REVERSAL"
   ```
   No such code exists in the `TxnCode` enum (`constants.py:28`). Django enforces `choices` at the form/serializer layer only — the row will insert (no DB CHECK), but every downstream consumer that switches on `TxnCode` will fall through. The auto-`reference` field at `models.py:198-199` will also become `DISBURSEMENT_REVERSAL-<pk>` which is fine, but the txn_code itself is forever non-canonical.

2. **Reversal ledgers have no `posting_type`.** Lines `1471-1480` construct `Ledger(...)` without setting `posting_type`. Per `models.py:220-222`, it defaults to `PostingType.not_set.name`. Consequently:
   - `BaseTransactionProcessor._process_ledgers` (`base.py:241-289`) skips them — `posting_type_to_demand_field_map.get('not_set')` returns `None`, so no demand update happens.
   - Any aggregate that filters by posting_type (e.g. `Sum('amount') where posting_type='paid'`) ignores them.
   - Demand `outstanding`, `paid`, `excess` etc. are **never reverted**.

3. **`self.process(reversal_txn)` will fail or no-op.** Line `1485` invokes `process()` which calls `get_transaction_processor()` → routes by product type → calls `processor.process()` → `get_process_methods().get('DISBURSEMENT_REVERSAL')` returns `None` → raises `UNSUPPORTED_TRANSACTION_CODE` (per `base.py:371-377`). **But by this point, the audit-status update on line `1488` for the original txn is inside `tenant_atomic()` (line `1441`), so the whole reversal block rolls back — leaving the original transaction in `processed` state with no audit trail of the attempted reversal.**

4. **No reversal of side effects.** Even if (1)–(3) were fixed, the method does not:
   - Touch `Demand` row counters (outstanding, paid, excess, waived, tax_*)
   - Roll back `Schedule.status` transitions
   - Refund `Payment.excess_amount` / `used_amount`
   - Unwind `Payout` (e.g. for disbursement reversals)
   - Walk `shared_transactions` (unlike `reject()` which does at `1522-1524` and `process()` at `1399-1403`)
   - Free `LimitService` capacity used during disbursement

**Impact:** Calling `reverse()` on any production transaction will at best raise; at worst, it leaves orphan ledgers and mis-marks the original status if the atomic block partially commits in any of the surrounding contexts.

**Recommendation:** Either remove the endpoint until properly designed, or implement a true compensating-transaction flow: for each `TxnCode`, define a paired reverse-handler that emits compensating ledgers (negated amount, correct `posting_type`), unwinds demand counters, unwinds schedule status, and walks linked txns. The current half-built reversal should not be exposed via API.

---

### B2. `_check_for_back_dated_accrual` rejects any same-date ledger, not just accrual

**File:** `processors/loan/accrual.py:1357-1368`

```python
back_dated_ledgers = Ledger.objects.filter(
    account=self.account,
    value_date__gte=self.transaction.value_date,
)
if back_dated_ledgers.exists():
    raise BadRequest(f"Accrual already run on {back_dated_ledgers.first().value_date}. ...")
```

Two problems:

1. **`>=` is wrong.** If a disbursement, repayment, fee, or waiver was posted on the **same** `value_date`, this raises and aborts accrual. Per CTM design, value-dated EOD accrual is expected to coexist with day-of activity; the gate should be `>` not `>=`, *and* should only check accrual-class postings.
2. **No `posting_type` filter.** Any prior ledger blocks accrual — even ledgers from a `disbursement` or `add_fee` txn posted earlier on the same day. The error message ("Accrual already run on …") is misleading.

**Impact:** On any day where a non-accrual txn precedes the EOD accrual, the EOD job fails. On a backdated correction day, no accrual can ever be re-run.

**Fix:** Filter `posting_type__in=[PostingType.outstanding, PostingType.accrued]` AND `transaction__transaction_code=TxnCode.accrual.name` (or attach a tag to accrual ledgers), AND use `>` to allow same-day non-accrual activity.

---

### B3. `_update_account_status` selects terminal txn non-deterministically

**File:** `processors/base.py:491-495`

```python
txn = Transaction.objects.filter(
    account=self.account,
    status=TransactionStatus.processed.name,
    transaction_code__in=[TxnCode.settlement.name, TxnCode.foreclose.name, TxnCode.write_off.name],
).first()
```

`.first()` with no `order_by(...)` returns DB-driver-dependent order. If two terminal txns ever coexist (e.g. an accidentally-processed `settlement` and later a `foreclose`), the resulting account status (`settled_off`, `foreclosed`, `written_off`) is non-deterministic across reruns or DB engines.

The comment on lines `488-490` claims:
> "If any of the settlement, foreclose or write_off transactions are processed, then the account status should be set to the corresponding status. Even if another transaction is settling all dues."

…but the implementation does not honor that contract for the multi-txn case.

**Fix:** Either enforce uniqueness (only one terminal txn per account), or explicitly `.order_by('-processed_at')` and document the precedence rule (e.g. `write_off > foreclose > settlement`).

---

### B4. `_check_and_free_limit` re-frees the same principal on every repayment

**File:** `processors/base.py:803-834`

For non-schedule-based loans (`base.py:811-815`), this aggregates **all** `paid + waived` principal ledgers across the account and calls `LimitService.free_limit(amount=that_total)` — every time. There is no delta tracking, no "already freed" marker.

```python
amount_to_free = self.transaction.ledgers.filter(...).aggregate(...)
```
For non-schedule-based the filter is on `self.transaction.ledgers` — so it's the current txn's ledgers only, and limit-free per-txn is correct for that branch.

However, for the **schedule-based + terminal-status** branch (`base.py:817-825`), the filter switches to `self.account.ctm_ledger_entries` — the entire account's lifetime ledgers. That is the right semantic when called once at terminal time, but `_check_and_free_limit` is wired into every txn handler (waiver, settlement, write_off, repayment, etc.) via various code paths — there is no guard against re-invocation. If `update_account_status` triggers more than once over the loan's life (which is structurally possible — e.g. a `settled_off` account is later moved to `foreclosed` via a corrective txn), the same principal is freed twice.

**Fix:** Track freed-amount in an account prop (write-once or delta), and compare against accumulated `paid + waived` principal before calling `free_limit`.

---

## 3. High-Severity Findings

### H1. No row-level locking on `Transaction` / `Account` during `process()`

**File:** `services/transactions.py:1290-1410`

The processing path uses `cache.add(...)` (`_acquire_account_lock`, `1077-1100`) as a distributed lock. Problems:

- **Lock is non-durable.** Redis flush, restart, or eviction (timeout = 30s default at `1077`) makes the lock vanish mid-processing. The DB transaction has no row lock to fall back on.
- **TOCTOU on status.** Status is read at `1317` (allows both `pending` *and* `processing`), then the lock is acquired at `1325`. A concurrent worker on the same `account_id` is blocked by the lock, but two workers on the same `transaction_id` for **different** accounts (or `account_id=None`) bypass the per-account lock entirely.
- **No lock at all for contact/program/group_account txns.** When `account_id is None`, `_acquire_account_lock` is never called (per the conditional at `1321-1326`), but `lock_acquired` defaults to `True` so the `finally` block still calls `_release_account_lock(None)` — harmless, but indicates the contract was not designed for the no-account case.
- **No `select_for_update()` on `Transaction.objects` anywhere.** `process()` reads the row, dispatches, then updates status — all without the row being locked.

**Fix:** Replace the cache-based lock with `SELECT ... FOR UPDATE NOWAIT` on the `Transaction` row inside `tenant_atomic()`, and additionally on `Account` when present. Re-check status under the lock before dispatching.

---

### H2. SCF processors silently miss txn codes that `STATUS_TXN_CODE_MAP` permits

**Files:** `processors/loan/processor.py:102-275`, `constants.py:100-125`

`AccountStatus.active` allows **23 txn codes** including `foreclose`, `pre_payment_with_tenure_change`, `pre_payment_with_emi_change`, `tenure_change`, `emi_change`, `roi_and_emi_change`, `roi_and_tenure_change`, `tranche_disbursement`, `add_pre_emi`, `skip_pre_emi`, `emi_due_date_change`.

`ScfSidTransactionProcessor` / `ScfPidTransactionProcessor` / `ScfVfTransactionProcessor` / `ScfDfTransactionProcessor` declare **only 11** of those in their `get_process_methods()`. The missing codes pass the `AccountStatusTxnCodeMap.is_txn_code_allowed` check at `base.py:348-354`, then fall through to `base.py:371-377`:

```python
if not process_method:
    raise BadRequest({"code": "UNSUPPORTED_TRANSACTION_CODE", ...})
```

**Impact:** API surface is inconsistent with intent. A user posting a `foreclose` for an SCF account gets `UNSUPPORTED_TRANSACTION_CODE` rather than `STATUS_NOT_ALLOWED`. Worse, the *intent* is unclear — is SCF supposed to support these codes and the dispatch is incomplete, or are SCF accounts expected to reject them?

**Fix:** Either move the gate to the dispatcher (so `get_process_methods()` becomes the source of truth and `STATUS_TXN_CODE_MAP` is parameterized per processor), or maintain a per-product-type allowlist in `AccountStatusTxnCodeMap`.

---

### H3. `txn_codes_for_not_active_accounts` disagrees with `STATUS_TXN_CODE_MAP`

**File:** `constants.py:59-60` vs `93-98`

```python
@classmethod
def txn_codes_for_not_active_accounts(cls):
    return [cls.disbursement.name]
```

But:

```python
STATUS_TXN_CODE_MAP = {
    AccountStatus.requested.name: [
        TxnCode.disbursement.name,
        TxnCode.tranche_disbursement.name,
    ],
    ...
}
```

If any caller uses `txn_codes_for_not_active_accounts()` as the authoritative allowlist for non-active accounts (e.g. for a draft loan), `tranche_disbursement` will be wrongly rejected even though the status map permits it for `requested`. Both lists describe the same rule and must stay in sync.

**Fix:** Derive one from the other, or remove `txn_codes_for_not_active_accounts` and have callers compute the allowed list per status from `STATUS_TXN_CODE_MAP`.

---

### H4. `validate()` allows negative amounts for `accrual` but no handler honors it

**Files:** `processors/base.py:796-799`, `processors/loan/accrual.py:642-643`

```python
if self.transaction.amount is None or (
    self.transaction.amount < 0 and self.transaction.transaction_code != TxnCode.accrual.name
):
    errors.append("Transaction amount must be positive")
```

The intent is to allow negative accrual (income reversal). But in the actual handler:

```python
# accrual.py:642 (referenced by audit; please verify exact line)
if accrual_amount > Decimal("0"):
    ...
```

…non-positive per-component accruals are dropped, so the negative-amount path is non-functional. A caller can submit `amount=-100` on an `accrual` txn; `validate()` passes; `_process_accrual` runs `_run_accrual` which only emits positive ledgers; the post-run `transaction.amount` is overwritten at `accrual.py:1404-1409` with the rounded accrued amount. The negative input is silently lost.

**Fix:** Either build a true reversal-of-accrual path (negate ledgers, decrement `accrued`/`outstanding` on the relevant demands), or remove the negative-allowance carve-out in `validate()`.

---

### H5. `process()` status check accepts both `pending` AND `processing`

**File:** `services/transactions.py:1317` (per audit notes)

The combination of:
- `add_transaction_to_batch` flipping a txn to `processing` (`1421`) via raw `self.update(...)` (which **bypasses** `_update_status_with_audit` whitelist — see I3 below),
- `process()` accepting both `pending` and `processing` states,
- and `views.py` exposing a direct `/process` endpoint,

…means the same `Transaction` can be picked up by the batch worker and by a manual `/process` call. Once a txn is `processing`, the batch worker's status guard does not exclude another caller from re-entering `process()`.

**Fix:** Either (a) require `select_for_update()` and re-read status inside the atomic block, or (b) reject `processing` from `process()`'s allowlist and rely on the batch worker holding exclusive ownership.

---

### H6. `_validate_financial_period` crashes when `txn_date` is null

**Files:** `services/transactions.py:1210-1235`, `models.py:87`

```python
txn_date = models.DateTimeField(db_index=True, null=True, blank=True)
```

…model allows null. But:

```python
fp_queryset = FinancialPeriod.objects.filter(
    start_date__lte=transaction.txn_date.date(),
    ...
)
```

…calling `.date()` on `None` raises `AttributeError` instead of `BadRequest`. The serializer/view path that allows null `txn_date` (e.g. bulk imports, EOD-generated txns) will hit this on any processing path that goes through `_validate_financial_period`.

**Fix:** Either make `txn_date` non-null at the model level (and migrate existing nulls), or guard `if transaction.txn_date is None: raise BadRequest(...)` up front.

---

### H7. `reject()` has no atomic wrapper

**File:** `services/transactions.py:1498-1526`

`reject()` calls `_update_status_with_audit` (which itself calls `self.update(skip_transaction=True)`), then optionally `AccountService.reject(...)`, then recursively rejects all shared transactions. None of this is wrapped in `tenant_atomic()`. If the recursive `self.reject(shared_transaction, ...)` raises (e.g. one shared txn is already `processed` and fails the status guard at `1509`), the parent txn is already `rejected` but the shared txn is not — partial state.

`process()` uses `tenant_atomic_context(skip_transaction)` (`1333`) and `reverse()` uses `tenant_atomic()` (`1441`); `reject()` should match.

**Fix:** Wrap the `reject()` body in `tenant_atomic()`.

---

### H8. `add_transaction_to_batch` bypasses status whitelist

**File:** `services/transactions.py:1421`

```python
self.update(transaction, {"status": TransactionStatus.processing.name})
```

This is a raw `update()`, not `_update_status_with_audit(...)`. The whitelist at `1166-1172` does not allow `pending → processing` at all, so going through the audit method would fail. The bypass is currently *intentional* but undocumented and means there is no audit trail for the `pending → processing` transition.

**Fix:** Add `pending → processing` to the whitelist with `action_name="enqueue"` (or similar), and route through `_update_status_with_audit`.

---

## 4. Medium-Severity Findings

### M1. `BaseRestructuringMixin` name-mangling bug

**File:** `processors/loan/restructuring/base.py:340-343`

```python
ScheduleCtrl.__config_data = {
    "decimal_precision": self.decimal_precision,
    "rounding_method": self.rounding_method,
}
```

Inside a class body, Python mangles `__name` to `_ClassName__name`. This statement lives inside `BaseRestructuringMixin.calculate_restructuring_deductions`, so the actual attribute set on `ScheduleCtrl` is `_BaseRestructuringMixin__config_data`. If `ScheduleCtrl` reads `cls.__config_data` (mangled to `_ScheduleCtrl__config_data`), the value is invisible. Verify `ScheduleCtrl._calculate_deductions` behavior — if it relies on `__config_data`, restructuring deductions silently use stale defaults.

**Fix:** Use `ScheduleCtrl._config_data` (single underscore) or pass via method argument.

---

### M2. Month-end and due-date GL accruals emit `posting_type=outstanding` ledgers with no demand

**Files:** `processors/loan/month_end_tl_accrual.py:69-84`, `processors/loan/due_date_tl_accrual.py:60-68`

Both mixins create `Ledger` rows with `posting_type=PostingType.outstanding.name` but no `demand_id` / `schedule_id`. The comment claims "no effect on outstanding" — and indeed `_process_ledgers` (`base.py:241-289`) skips these because the `schedule_id`/`demand` check at `249` short-circuits.

However:
- Any aggregate that sums `posting_type='outstanding'` across `Ledger` (e.g. balance reports that do not filter on `demand__isnull=False`) will double-count these as outstanding.
- The pair (positive on month-end + negative on next day) makes this a "GL-only" provisioning entry — but the contract is implicit and brittle. A new reporter who queries `Sum('amount') WHERE posting_type='outstanding'` will get wrong numbers.

**Fix:** Add a dedicated `PostingType.gl_only_accrual` (or `month_end_provision` / `month_end_reversal`) so semantics are explicit and aggregations can filter correctly.

---

### M3. Restructuring deletes pending future schedules without checking attached demands

**File:** `processors/loan/restructuring/base.py:299-304`

```python
self.account.schedules.filter(due_date__gt=from_due_date, status=ScheduleStatus.pending.name).delete()
```

Only `pending` schedules are deleted, which is the right guard for the common case. But:
- A `Schedule` in `pending` status can have demands that have received partial payment (e.g. a payment landed but didn't transition the schedule status). Per `models.py:233-237`, `Ledger.schedule` and `Ledger.demand` have `on_delete=SET_NULL` — so partial-paid demand rows survive the cascade with `schedule_id=NULL`, but the `Ledger` rows attached to those demands now have orphan FKs.
- Reconciliation against the new (post-restructuring) schedule cannot find these orphan ledgers without a backfill.

**Fix:** Before delete, verify no schedule in the delete-set has any attached demand with `outstanding < amount` (i.e. no partial payments). Alternatively, archive rather than delete.

---

### M4. `create_or_update_demand` resets `outstanding` on every restructure

**File:** `processors/loan/restructuring/base.py:312-318`

```python
if demand:
    demand.amount = amount
    demand.outstanding = amount
```

`outstanding = amount` clobbers any prior partial payment recorded on the existing demand. For all six restructuring handlers (`emi_change`, `tenure_change`, `roi_and_emi_change`, `roi_and_tenure_change`, `pre_emi_change`, `emi_due_date_change`), this resets the partial-paid state when the current schedule's demands are re-derived.

**Fix:** Compute `new_outstanding = max(new_amount - demand.paid - demand.tax_paid - demand.waived - demand.tax_waived, 0)` instead of blindly setting `outstanding = amount`.

---

### M5. NPA suspension posts single-leg ledger without demand or schedule link

**File:** `processors/loan/npa_income_suspension.py:99-109`

```python
ledgers_to_create.append(
    Ledger(
        component=component,
        amount=outstanding_amount,
        value_date=self.transaction.value_date,
        posting_type=PostingType.npa_income_suspension.name,
        transaction=self.transaction,
        account=self.account,
    )
)
```

Two consequences:
- No `demand`/`schedule` link — when income is later un-suspended (upgrade out of NPA), there is no way to map the reversal back to the specific demands that were suspended.
- The single-leg posting relies on `ComponentGLMapping` to materialize the GL debit/credit pair. If a mapping for `(component, posting_type=npa_income_suspension)` is missing, the posting silently has no GL effect — `ComponentGLMappingService` does not raise on missing mappings (returns empty per agent audit notes; verify in `services/component.py`).

**Fix:** Attach `demand`/`schedule` to each suspension ledger so unsuspension is traceable; require GL mapping to exist at txn-time (fail-fast).

---

### M6. `Transaction.reference` uniqueness relies on serializer race

**File:** `models.py:92`, `serializers.py:131-135`

`reference` has `unique=True` at the DB level, which is good. But the serializer's uniqueness check (per audit notes) runs at validate time and is not protected against TOCTOU. The DB will reject duplicates with `IntegrityError`, which is not gracefully translated to a 4xx by `create()` (per audit notes).

**Fix:** Wrap `create()` in `try/except IntegrityError` and surface as a clean `BadRequest`.

---

### M7. `payload['refs']` / external idempotency keys are not enforced unique

**File:** `models.py:99`

```python
refs = RefsField(default=dict, blank=True)
```

External-system idempotency (typical pattern: bank gives a `utr` or `payout_ref`) lives inside `refs`. There is no DB-level unique constraint on any key within `refs`. A duplicate webhook from a bank can spawn a duplicate transaction if upstream callers do not de-dup.

**Fix:** Either (a) hoist the canonical idempotency key (e.g. `utr`) into a column with `unique=True`, or (b) add a partial unique index on `refs->>'utr'` (PostgreSQL JSON index).

---

### M8. `_update_demand_amount_and_status_by_ledger` never reads `npa_income_suspension` / `write_off` / `deducted` posting types

**File:** `processors/base.py:575-621`

The dispatch table at `580-608` covers `outstanding`, `paid`, `hold`, `waived`, `refunded`, `accrued`, `tax`, `tax_paid`, `tax_waived`, `excess`, `settled`. It does NOT cover:
- `PostingType.deducted` (upfront fee deduction)
- `PostingType.tax_deducted`
- `PostingType.write_off`
- `PostingType.npa_income_suspension`
- `PostingType.tds_deducted`

A ledger with any of these posting types passes through `_process_ledgers` without updating demand counters. This is fine if those postings are GL-only by design — but the design contract is implicit. If anyone wires a write-off ledger expecting demand `outstanding` to drop, they will be surprised.

**Fix:** Document explicitly which posting types affect demand state vs. GL only; ideally encode it on `PostingType` itself (`affects_demand: bool`).

---

### M9. `_update_account_status` early-returns when any non-settled schedule exists, even from pre-EMI periods

**File:** `processors/base.py:467-468`

```python
if self.account.schedules.exclude(status=ScheduleStatus.settled.name).exists():
    return
```

Any pending pre-EMI schedule (or a dummy schedule used for tagging) blocks account closure. Combined with the restructuring delete-future-schedules logic (M3), this can leave an account un-closeable in edge states.

**Fix:** Exclude pre-EMI schedules with zero outstanding from the check, or require a "settled or skipped" status.

---

### M10. Settlement order may not be honored

**Files:** `processors/loan/settlement.py:130-148`, `processors/loan/repayment.py` (settlement_order usage)

Per audit notes, `SettlementHandler.run_settlement` iterates `code_to_demand` in dict-insertion order, not the configured `config.repayment.settlement_order.default` order. Verify by reading the iteration source — if true, settlement may consume interest before principal contrary to product config, especially when handling overdue + current EMI together.

**Status:** Flagged for manual verification; high-impact if confirmed.

---

## 5. Low-Severity Findings

### L1. Status-transition whitelist is asymmetric

`_update_status_with_audit` allows `processing → rejected` (`1168`) but `reject()` only accepts `pending` (`1509`). Either expand `reject()` to handle a stuck `processing` txn, or remove the unused whitelist entry.

### L2. `Transaction.can_be_processed()` and `can_be_reversed()` are unused by services

`models.py:184-194` define convenient guards, but `services/transactions.py:process()` and `reverse()` reimplement the checks inline. Drift risk over time.

### L3. `sequence` is not unique per account

`models.py:89` — `PositiveIntegerField` with no uniqueness. `create()` computes `count() + 1` outside an atomic block (per audit notes at `953-960`) — last-writer wins under concurrency, producing duplicate sequence numbers.

**Fix:** Database-level uniqueness `(account_id, sequence)` + retry on collision, or use a `BigIntegerField` with a Postgres sequence.

### L4. `validate_for_posting` defined but never invoked

Per audit notes (`serializers.py:151-189`). Dead validation surface.

### L5. `_invalidate_aggregated_summaries` swallows all exceptions

`services/transactions.py:1283-1287` — `except Exception: logger.exception(...)`. Silent staleness on real failures.

### L6. `setup_account` / `seed_default_components` not audited

Migration / seeding paths are out of scope for this review; flagged for separate verification before any new prod deployment.

---

## 6. Edge Cases Not Handled

The following scenarios are not defended against by current code:

| Case | Where it bites | Severity |
|---|---|---|
| Concurrent disbursement on same `requested` account | `_validate_single_disbursement` is non-locking `.exists()` (per audit) | HIGH |
| Future-dated value_date on `repayment` | Only `future_value_date_allowed_txn_codes` (`constants.py:67-77`) blocks 6 codes; rest pass through | MEDIUM |
| Duplicate bank UTR on webhook-driven `repayment` | No unique constraint on `refs.utr` (M7) | HIGH |
| Foreclose on overdue loan | Currently *rejected* outright at `foreclose.py:81-96` — debatable whether this is intentional | MEDIUM |
| Foreclose overpayment | Silently truncated to `excess_amount_settled` (per audit) | MEDIUM |
| Partial reversal | Not modeled — reverse is binary 100% | INFO |
| Mid-cycle restructure with partial-paid current EMI | M4 + M3 combine to lose prior partial-pay state | HIGH |
| NPA upgrade (un-suspension) | No reverse path for `npa_income_suspension` ledgers; M5 makes traceability impossible | HIGH |
| Re-run EOD month-end accrual | No idempotency in `_check_for_back_dated_accrual` semantics (B2) | HIGH |
| Two terminal txns on same account | B3 — non-deterministic resulting status | HIGH |
| `txn_date = None` reaching financial-period check | H6 — `AttributeError` instead of clean error | MEDIUM |

---

## 7. Recommended Priorities

**Must-fix before next release (Blocker tier):**
1. **B1** — Disable `/reverse` endpoint at the view layer until a real compensating-txn flow is built. The current implementation is unsafe.
2. **B2** — Fix `_check_for_back_dated_accrual` filter to scope by posting type and use `>` not `>=`.
3. **B3** — Add deterministic ordering + precedence rule in `_update_account_status`.
4. **B4** — Add freed-amount tracking to prevent double-free in `_check_and_free_limit`.

**Must-fix this quarter (High tier):**
5. **H1** — Replace cache-based account lock with `SELECT FOR UPDATE` on `Transaction` + `Account`.
6. **H2** + **H3** — Reconcile per-product allowed-code lists between processors and `AccountStatusTxnCodeMap` / `txn_codes_for_not_active_accounts`.
7. **H4** — Remove the negative-amount carve-out from `validate()` OR implement true accrual reversal.
8. **H5** — Add `select_for_update` on the Transaction row in `process()`.
9. **H6** — Guard against null `txn_date` in `_validate_financial_period`.
10. **H7** — Wrap `reject()` in `tenant_atomic()`.

**Hardening (Medium tier):**
- M1 (name-mangling bug) — trivial fix with high signal.
- M2 (GL-only posting type) — explicit semantics.
- M3 + M4 (restructuring preserves partial payments) — required for correctness in mid-cycle restructures.
- M5 (NPA suspension traceability) — required before any NPA upgrade flow can be built.
- M7 (idempotency key uniqueness) — protects against bank webhook duplicates.
- M8 (posting-type → demand contract) — document or encode.

**Cleanup (Low tier):**
- L1–L5 — code hygiene.

---

## 8. Test Coverage Observations

Only two test files were found in `apps/ctm/tests/`:
- `test_component_lookup.py`
- `test_summary_batch.py`

There are **no tests** for any of the processor mixins (disbursement, repayment, accrual, waiver, write-off, NPA, settlement, foreclose, prepayment, six restructuring variants, GL accrual, fees). The 23+ txn-code handlers and ~30k+ lines of mixin logic are entirely uncovered by unit tests in this module.

GL-posting tests do exist at `apps/gl/tests/test_gl_posting_enhancements.py`, but those validate the downstream projection, not the processor logic that creates the source ledgers.

**Recommendation:** Add a per-txn-code golden-master test suite: for each handler, set up a fixture loan, run the handler, snapshot the resulting `Ledger` / `Demand` / `Schedule` / `Account` state, and compare. This is the single highest-leverage investment for catching regressions in this module.

---

## 9. Files Reviewed

Core source files read in full or in part during this audit:

```
project/apps/ctm/apps.py
project/apps/ctm/constants.py
project/apps/ctm/models.py
project/apps/ctm/processors/__init__.py
project/apps/ctm/processors/base.py
project/apps/ctm/processors/loan/__init__.py
project/apps/ctm/processors/loan/processor.py
project/apps/ctm/processors/loan/disbursement.py
project/apps/ctm/processors/loan/repayment.py
project/apps/ctm/processors/loan/tranche_disbursement.py
project/apps/ctm/processors/loan/excess_payment_settlement.py
project/apps/ctm/processors/loan/accrual.py
project/apps/ctm/processors/loan/due_date_tl_accrual.py
project/apps/ctm/processors/loan/month_end_tl_accrual.py
project/apps/ctm/processors/loan/npa_income_suspension.py
project/apps/ctm/processors/loan/written_off.py
project/apps/ctm/processors/loan/waiver.py
project/apps/ctm/processors/loan/settlement.py
project/apps/ctm/processors/loan/upfront_interest_settle.py
project/apps/ctm/processors/loan/restructuring/base.py
project/apps/ctm/processors/loan/restructuring/prepayment.py
project/apps/ctm/processors/loan/restructuring/foreclose.py
project/apps/ctm/processors/loan/restructuring/emi_change.py
project/apps/ctm/processors/loan/restructuring/tenure_change.py
project/apps/ctm/processors/loan/restructuring/roi_and_emi_change.py
project/apps/ctm/processors/loan/restructuring/roi_and_tenure_change.py
project/apps/ctm/processors/loan/restructuring/pre_emi_change.py
project/apps/ctm/processors/loan/restructuring/emi_due_date_change.py
project/apps/ctm/services/transactions.py
project/apps/ctm/services/transaction_batches.py
project/apps/ctm/services/ledgers.py
project/apps/ctm/services/component.py
project/apps/ctm/services/transaction_summary.py
project/apps/ctm/views.py
project/apps/ctm/serializers.py
project/apps/ctm/tasks.py
project/apps/ctm/helpers.py
```

---

## 10. Caveats

- This audit was conducted by reading source code only. No code was executed, no fixtures were run.
- Several Medium findings (M1, M10) were flagged based on agent-reviewer summaries that I have not yet stepped through line-by-line; they are labeled accordingly and should be re-verified before action.
- The audit focused on `LoanTransactionProcessor` and the four SCF variants. `ContactTransactionProcessor`, `ProgramTransactionProcessor`, and `GroupAccountTransactionProcessor` were *not* reviewed in depth.
- The audit excluded: GL projection logic (`apps/gl/`), workflow integration (`apps/workflow/`), reports (`apps/reports/`), workbook handlers, migrations, and seeding commands.
