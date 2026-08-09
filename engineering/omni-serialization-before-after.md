# Omni — Transaction Serialization: Before / After

**Date:** 2026-08-08 · **Repo:** `crego-omni` · Paths relative to `project/apps/`
**Tracked on:** [CRE-6136](https://linear.app/crego/issue/CRE-6136)
**Design:** [omni-transaction-serialization-design.md](./omni-transaction-serialization-design.md)

A visual companion to the design doc. Two diagrams: what the locking looked like
before, and what it looks like after commit `8f8e6c5a`.

---

## The one-sentence version

Four independent writers — loan request, disbursement, payment, EOD — all mutate the
same account/contact-level derived state. They were serialized by a **Redis cache key
that could silently stop existing**, and even when it worked it was **released before
the writes were durable**. They are now serialized by a **PostgreSQL lock the database
itself holds until COMMIT**.

---

## What "account/loan level data" means here

Every one of the four flows converges on the same mutable state. This is why they must
be ordered against each other and not just against themselves:

```
  +----------------------------------------------------------------+
  |  PER-LOAN (Account)                                             |
  |    Ledger rows .................. the money postings            |
  |    Demand (due, dpd, paid) ...... what is owed and when         |
  |    TransactionSummary ........... outstanding / accrued / POS   |
  |    Account.max_dpd .............. monotonic worst DPD           |
  |    Account.asset_category ....... std / sma / npa  (RBI)        |
  |    Transaction.sequence ......... settlement order stamp        |
  +----------------------------------------------------------------+
  |  PER-BORROWER (Contact)  <-- shared across ALL the loans below  |
  |    contact-level excess demand .. unallocated money             |
  |    Limit.available / blocked / used                             |
  |    contact-level NPA classification                             |
  +----------------------------------------------------------------+
```

The bottom block is why the ordering root is the **contact**, not the loan: a payment
on loan A can park excess that loan B then consumes, and NPA on one loan drags the
borrower's whole classification.

---

## DIAGRAM 1 — BEFORE (up to `6262ea47`)

```
 ENTRY POINT                        GUARD                          OUTCOME
 ==========================================================================

 (1) LOAN REQUEST
     AccountService.create
       check_and_block_limit  ---->  cache.add("limit_<id>")  ---->  Limit rows
                                     Redis, TTL 30s                  blocked +=

 (2) DISBURSE
     PayoutService.process
       add_transaction_to_batch
       TransactionBatchService
         .process             ---->  cache.add("batch_<id>")   --+
           process_batch_item                                    |
             TxnService.process ->  cache.add("account_lock")  --+
                                                                 |
 (3) PAYMENT                                                     |
     PaymentService.settle                                       +--> Ledger
       TxnService.process     ---->  cache.add("account_lock")  --+   Demand
                                                                 |   Summary
 (4) EOD  (accrual / due-date DPD / month-end / NPA)              |   max_dpd
     EODHandler.run                                              |   asset_cat
       _create_accrual_transaction                               |   sequence
       npa_income_suspension                                     |
         TxnService.process   ---->  cache.add("account_lock")  --+


 ALL SEVEN LOCK SITES SHARED ONE FATE
 ------------------------------------
                        TenantAwareCache
                               |
              any error saying "redis"/"client_class"
                               |
                               v
                      self._cache = DummyCache      (permanent, per process)
                               |
                               v
                    DummyCache.add() -> True   ...FOREVER

        => every lock above "succeeds" for every caller, simultaneously.
           Logged at DEBUG. Nothing alerts. The mutex is simply gone.
```

### And even on the happy path, the account lock was wrong twice more

```
  TIME ------------------------------------------------------------------>

  Worker A   [acquire]---[BEGIN tx]---[read state]---[write]---[release]---[COMMIT]
                  ^          ^                                    ^           ^
                  |          |                                    |           |
             DEFECT 1:  lock opened                          DEFECT 2:   writes only
             lock taken  BEFORE the                          released     durable HERE
             OUTSIDE the transaction                         INSIDE the
             transaction                                     atomic block

  Worker B                                        [acquire OK]---[read state]
                                                                       ^
                                                                       |
                                          reads state from BEFORE A committed
                                          -> appropriates on stale outstanding,
                                             stale DPD, stale asset category
```

**Net effect:** "we take a lock there" was not evidence of mutual exclusion anywhere in
this codebase.

---

## DIAGRAM 2 — AFTER (`8f8e6c5a`)

```
 ENTRY POINT                        GUARD                          OUTCOME
 ==========================================================================

 (1) LOAN REQUEST
     AccountService.create
       check_and_block_limit  ---->  SELECT ... FOR UPDATE    ---->  Limit rows
                                     on the Limit rows,              blocked +=
                                     locked coldest-first
                                     (deadlock-free order)

 (2) DISBURSE
     PayoutService.process
       add_transaction_to_batch
       TransactionBatchService
         .process             ---->  cache.add("batch_<id>")   --+   <-- STILL REDIS
           process_batch_item         (now FAILS CLOSED)          |       see below
             TxnService.process --+                               |
                                  |                               |
 (3) PAYMENT                      |                               |
     PaymentService.settle        |                               +--> Ledger
       TxnService.process --------+                               |    Demand
                                  |                               |    Summary
 (4) EOD (accrual / DPD / NPA)    |                               |    max_dpd
     EODHandler.run               |                               |    asset_cat
       TxnService.process --------+                               |    sequence
                                  |                               |
                                  v                               |
                      +---------------------------+               |
                      | with tenant_atomic():     |               |
                      |   pg_advisory_xact_lock(  |---------------+
                      |     contact:<id>          |
                      |     + every colending leg |
                      |   )                       |
                      +---------------------------+
                          ONE lock call, all roots,
                          sorted -> no deadlock cycle


 THE LOCK IS NOW THE DATABASE'S PROBLEM
 --------------------------------------

  TIME ------------------------------------------------------------------>

  Worker A   [BEGIN tx]---[LOCK]---[read state]---[write]---[COMMIT + auto-release]
                  ^          ^          ^                            ^
                  |          |          |                            |
            transaction   lock taken  reads happen                Postgres drops
            opens FIRST   INSIDE it   AFTER the lock              the lock here.
                                                                  No release call
                                                                  exists to misplace.

  Worker B   [BEGIN tx]---[LOCK .......................blocked......][LOCK]---[read]
                                                                              ^
                                                                              |
                                                        sees A's committed state
```

### Why each defect is structurally gone, not just patched

| Old defect | Why it cannot recur |
|---|---|
| Lock vanishes on Redis blip | Lock lives in Postgres; the same DB the writes go to. No Redis in the path. |
| Released before COMMIT | There is no release call. `pg_advisory_xact_lock` is dropped by the DB at COMMIT/ROLLBACK. |
| Acquired outside the transaction | `serialization_lock` raises if `in_atomic_block` is false. It cannot be misused this way. |
| TTL expires mid-work, second worker enters | Transaction-scoped locks have no TTL. |
| Worker A's release deletes worker B's lock | Locks are owned by a transaction; no cross-holder release is expressible. |
| `skip_transaction=True` bypasses the guard | `process()` now ignores `skip_transaction` and always opens `tenant_atomic()`. |

---

## What did NOT change, and why

### The batch lock is still on Redis — deliberately

```
  TransactionBatchService.process(batch)
    +-- cache.add("batch_<id>")        <-- still a cache lock
    |
    +-- while True:
    |     item = get_next_batch_item(batch)
    |     process_batch_item(item)  --> TxnService.process --> [BEGIN..COMMIT]
    |                                                          [BEGIN..COMMIT]
    |                                                          [BEGIN..COMMIT]
    +-- release                                                  ^^^ each item
                                                                 commits separately
```

A transaction-scoped advisory lock **cannot span this loop** — the loop's whole point is
that each item commits on its own. Holding one transaction open across the batch would
be a long-running transaction and table bloat. Session-level `pg_advisory_lock` is ruled
out by the design doc (§2), since it breaks under transaction pooling.

Its correct replacement is Phase 2's `FOR UPDATE SKIP LOCKED` root claiming, so it was
**reclassified from Phase 1 to Phase 2** rather than given a throwaway primitive.

**Residual risk is now bounded**, because the cache fails closed (`6262ea47`): the worst
case is "two workers process the same batch", not "the mutex silently ceased to exist".
And each *item* inside those two workers still takes the contact root, so the ledger
cannot be corrupted — the duplicate work serializes and the second worker finds the
items already completed.

### Known deviation: accrual is serialized more coarsely than designed

The design doc's ordering-root table says account-local commutative work (accrual, DPD
stamp, summary rebuild) should take the **account** root:

```
  DESIGNED                              IMPLEMENTED
  ---------------------------------     ---------------------------------
  repayment / disburse -> contact       repayment / disburse -> contact
  accrual / DPD / NPA  -> account       accrual / DPD / NPA  -> contact   <-- coarser
```

`ordering_root_for_money_movement()` always prefers the contact when one exists, and
`process()` uses it for every transaction code. This is **safe** — over-serializing is
correct, just slower — but it means EOD accrual across all loans of one borrower now
runs one-at-a-time instead of in parallel.

⚠️ **Watch this on a large SCF anchor at EOD.** A contact with hundreds of loans will
serialize its whole accrual pass on a single root. `lock_wait_ms` is logged, and
`SLOW_LOCK_WARN_MS = 200` will surface it. If it bites, the fix is to branch on
transaction code in `_ordering_roots` and hand account-local codes the account root —
not to widen the timeout.

---

## Behavioural change callers will notice

```
  BEFORE:  contention -> cache.add returns False -> BadRequest 400
                                                    "Could not acquire lock"

  AFTER:   contention -> wait up to 5s
                          |
                          +-- lock acquired  -> proceed normally
                          |
                          +-- still held     -> SerializationLockTimeout (transient)
```

Contention is now a **bounded wait rather than a rejection**, which is what a payment
intake should do. `SerializationLockTimeout` is deliberately not a `ServiceException` or
`DRFValidationError`, because `DrawdownService.approve` catches those two and marks the
drawdown `loan_rejected` **permanently** — a transient lock wait must never do that.

A 5s wait on a synchronous API endpoint is still not ideal; the design doc's answer is
Phase 2 (enqueue instead of wait).

---

## Verification note

`manage.py test ctm` (148 tests) never reached `TransactionService.process` **even
once** — proven with a canary exception in `_ordering_roots` that the full run never
triggered. The account lock could have been deleted outright without turning the suite
red. `ctm/tests/test_transaction_serialization.py` now covers it; 7 of its 8 tests fail
against the pre-change code.

Treat any other "the suite is green" claim about this subsystem with the same suspicion
until a canary says otherwise.
