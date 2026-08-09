# Omni — Transaction Serialization: Design & Remediation Plan

**Date:** 2026-08-05 (updated 2026-08-08) · **Repo:** `crego-omni` · Paths relative to `project/apps/`
**Answers:** [omni-npa-bulk-payment-limit-gap-analysis.md](./omni-npa-bulk-payment-limit-gap-analysis.md)
**Visual before/after:** [omni-serialization-before-after.md](./omni-serialization-before-after.md)
**Tracked on:** [CRE-6136](https://linear.app/crego/issue/CRE-6136)
**Branch:** `feature/cre-6136-credit-limit-enforcement-is-unsound-under-concurrency-over`

> **Status 2026-08-08.** Phase 0 and Phase 1's money path are implemented and green
> (32 new tests on Postgres; `ctm`+`lib`+`addon` = 270 tests, the only 2 failures
> being `test_last_accrual_eod`, already red on the parent commit):
>
> | Commit | What |
> |---|---|
> | `96729962` | limit locks: Redis → Postgres row locks, deterministic order, `lock_timeout` |
> | `e4ec8d99` | `verify_limit_consistency` + DB-agnostic limit tests |
> | `6262ea47` | **fail-closed `TenantAwareCache`** + **`lib/serialization.py`** advisory-lock primitive |
> | `8f8e6c5a` | **account lock → `serialization_lock`**; `process` always opens its own transaction; colending roots taken in one call |
>
> **Six of the seven original cache-lock sites are now gone.** The only one left is the
> batch lock (`transaction_batches.py:49`) — see the note below on why it does not
> belong in Phase 1 at all.
>
> ⚠️ **The account lock was never covered by a test.** A canary exception planted in
> `_ordering_roots` was not triggered once by the full 148-test `ctm` run, so the lock
> could have been deleted outright without turning the suite red — the "255-test
> regression sweep" cited in the 2026-08-06 status above was, for this code path,
> vacuous. `ctm/tests/test_transaction_serialization.py` now covers it (7 of its 8
> tests fail against the pre-change code). Treat any other "the suite is green"
> claim in this document with the same suspicion until a canary says otherwise.
>
> **Batch lock reclassified to Phase 2.** `TransactionBatchService.process` runs a
> loop whose items each commit in their own transaction, so a transaction-scoped
> advisory lock cannot express it, and §2 rules out session-level `pg_advisory_lock`
> outright. Its correct replacement is Phase 2's `FOR UPDATE SKIP LOCKED` root
> claiming, not a bespoke Phase 1 primitive. Until then it remains on `cache.add` —
> but the cache now fails closed (`6262ea47`), so it degrades to "two workers may
> process one batch", not "the mutex silently ceased to exist".
>
> Not yet done: the batch lock (now Phase 2) and everything in Phases 2–5.

---

## The ask, restated as a guarantee

> For any account/loan, every transaction must apply in a strict sequence, with no race
> conditions and no computation on stale derived state.

Formally, three properties. Naming them matters because each has a different mechanism and a
different test:

| # | Property | Meaning | Mechanism |
|---|---|---|---|
| **P1** | **Total order** | For a given ordering root, transactions apply in one agreed sequence, and that sequence is durable and replayable | Per-root FIFO queue + `sequence` stamp |
| **P2** | **Mutual exclusion** | No two workers mutate the same root concurrently | Postgres transaction-scoped advisory lock |
| **P3** | **Read-your-predecessor** | Transaction N reads state that includes every committed effect of N-1 | Read-after-lock + version-stamped derived artifacts |

Today **none of the three holds**, and P2 has a failure mode that silently disables it process-wide.

---

## Why it fails today

Three layers were built to provide this. Two are unsound.

```
┌─────────────────────────────────────────────────────────────────────────┐
│ LAYER 1 — Batch drain            "one item at a time per entity"        │
│   ✗ TWO grains for the same account: payments batch per PROGRAM         │
│     (payments.py:346), CTM txns batch per ACCOUNT (transaction_         │
│     batches.py:136). Different rows, different locks, no mutual excl.   │
│   ✗ Any item failure re-raises → batch `stopped` → beat sweeps only     │
│     pending/processing → remainder stranded, silently, forever          │
│   ✗ order_by(value_date, txn_date) — no tiebreaker → Postgres plan order│
├─────────────────────────────────────────────────────────────────────────┤
│ LAYER 2 — Cache locks            account / batch / limit                │
│   ✗ UNSOUND: TenantAwareCache falls back to DummyCache and STAYS there  │
│   ✗ Released before COMMIT (finally sits *inside* the atomic block)     │
│   ✗ TTL expires mid-work (batch: 5s × items; account: 30s flat)         │
│   ✗ Unfenced: worker A's finally deletes worker B's lock                │
│   ✗ Contention → BadRequest → item failed → batch stopped (see Layer 1) │
├─────────────────────────────────────────────────────────────────────────┤
│ LAYER 3 — Guarded F() updates    UPDATE … WHERE available >= amt        │
│   ✓ SOUND for what it does — per-row atomic                             │
│   ✗ Does NOT serialize the read→compute→write span around it            │
└─────────────────────────────────────────────────────────────────────────┘
```

### The single most important finding

`tenancy/cache.py:80-105`. Every lock in the system runs through this:

```python
def _safe_cache_operation(self, operation, *args, **kwargs):
    if self._use_dummy_cache:
        return operation(*args, **kwargs)          # never goes back to Redis
    try:
        return operation(*args, **kwargs)
    except Exception as e:
        if "redis" in str(e).lower() or "client_class" in ... :
            self._cache = DummyCache(...)          # permanent, process-wide
            self._use_dummy_cache = True
            return operation(*args, **kwargs)
```

`DummyCache.add()` **always returns `True`**. One Redis blip — a connection reset, a failover, a
`redis` substring anywhere in the error text — and that worker process silently loses **every lock
in Omni** for the rest of its life: account lock, batch lock, all five limit locks. Logged at
`debug`. Nothing alerts.

Measured against the old code, the mechanism is one call subtler than it first reads — worth
recording because it explains the observed symptom (an occasional hard error, then quiet
corruption):

```
call 1 (worker A): raised ConnectionError    ← the retry re-invokes the already-bound
call 2 (worker B): add() -> True                method, not DummyCache, so it re-raises
call 3 (worker C): add() -> True             ← from here on, every worker "acquires"
backend is now: DummyCache                      the same lock key, forever
```

So the first payment after a blip fails loudly, and every one after it proceeds with no mutual
exclusion at all. Fixed in `6262ea47`: bounded 30 s cooldown instead of permanent, `ERROR` instead
of `debug`, and every operation degrades to its conservative answer — `add()` returns `False`,
reads miss, `incr` raises rather than inventing a counter, and non-connectivity errors propagate
instead of being masked as a cache miss.

This is not "locks are weak under load". It is "locks may not exist at all, per-process,
non-deterministically". It invalidates every concurrency assumption in the codebase, including the
`sequence` stamp at `transactions.py:1633` which is explicitly documented as relying on the account
lock.

**Corrections to the gap analysis:** A8 is wrong — `payment_utr` *is* `unique=True`
(`transfer/models.py:187`), so UTR dedupe exists (it is nullable, so the gap is only for
null-UTR intake). A3 is confirmed correct: `finally: _release_account_lock()` at
`transactions.py:1842-1843` sits inside `with context:` — the lock drops before COMMIT.

---

## Design

Five mechanisms. Each maps to one property and removes one broken layer.

### 1 — Ordering root: define what "sequence" is a sequence *of*

Ordering is meaningless without a scope. Every transaction gets exactly one **ordering root**,
derived structurally, not configured:

| Operation class | Root | Why |
|---|---|---|
| Ledger-posting money movement — repayment, excess settlement, refund, waiver, write-off, settlement, foreclosure | **contact** | mutates contact-level excess demand, RBI NPA classification, and limits — all contact-scoped |
| Disbursement / drawdown | **contact** + limit reservation | consumes limit, which is contact/program/product-scoped |
| Account-local & commutative — accrual, DPD stamp, summary rebuild, schedule generation | **account** | provably touches no cross-account state |

Contact-as-root for money movement is the opinionated call. It is coarser than strictly necessary
and costs throughput, but it is **provably deadlock-free with a single lock** and it matches the
business reality that a customer's money is fungible across their loans. The alternative
(group-account root + separate contact-level coordination for excess/NPA) needs a lock-ordering
protocol and gets it wrong under backdated reversal. Start coarse; split only if p99 lock wait
exceeds budget.

### 2 — Postgres advisory locks replace every cache lock (P2)

```python
# lib/serialization.py
@contextmanager
def serialization_lock(*roots, wait_ms: int = 5000):
    """Transaction-scoped advisory locks on ordering roots.

    Released by Postgres at COMMIT/ROLLBACK. Cannot be released early,
    cannot expire mid-work, cannot silently vanish when Redis hiccups.
    """
    assert connection.in_atomic_block, "serialization_lock requires an open transaction"
    keys = sorted(_lock_key(r) for r in roots)      # canonical order → no deadlock
    with connection.cursor() as c:
        c.execute("SET LOCAL lock_timeout = %s", [f"{wait_ms}ms"])
        for k in keys:
            c.execute("SELECT pg_advisory_xact_lock(%s)", [k])   # int8 key
    yield

def _lock_key(root) -> int:
    # signed int8 from blake2b(tenant_alias : kind : id) — tenant in the key because
    # advisory locks are per-database, not per-schema
    ...
```

Why advisory locks over `SELECT FOR UPDATE` on a token table:

| | advisory xact lock | FOR UPDATE on token row |
|---|---|---|
| Released at COMMIT | ✓ | ✓ |
| Survives Redis outage | ✓ | ✓ |
| Needs schema + seed rows | no | yes, one per entity |
| Can lock before the row exists | ✓ | no (blocks limit reservation) |
| Table bloat / vacuum | none | yes |
| Collision risk | negligible (int8 hash); a collision only over-serializes | none |

Verified: **no pgbouncer in `crego-infra`**, so transaction-pooling incompatibility does not apply.
If pgbouncer is ever introduced, `pg_advisory_xact_lock` remains safe (transaction-scoped);
session-level `pg_advisory_lock` would not be — never use it.

Contention becomes a **bounded wait**, not a rejection. On `lock_timeout` the API enqueues instead
of returning 400 — which is what a payment intake should do anyway.

### 3 — One queue, one grain, head-of-line per root (P1)

Collapse the two batch grains into one: **batch key = ordering root**. A program-wide payment file
fans out into per-contact queues at intake.

This single change dissolves A1 and A4. Today one failed payment strands 62 unrelated payments
*because the batch is per program*. Per-root, a failure blocks exactly the contact it belongs to —
which is correct, because you genuinely cannot skip past a failed transaction on an account without
breaking the sequence.

```
Claiming which root to work on          →  FOR UPDATE SKIP LOCKED LIMIT 1
   (across batches; skipping a busy root is correct)

Claiming the next item within a root    →  ORDER BY value_date, txn_date, created_at, id
   (in-order; skipping is NOT correct)      FOR UPDATE NOWAIT LIMIT 1
```

Getting this backwards is the easiest mistake in the whole plan: `SKIP LOCKED` on the *item* query
would silently reorder settlements.

Two implementation notes from building the primitive, both of which cost a debugging cycle:

- **`SET LOCAL lock_timeout = %s` is a syntax error.** Postgres `SET` does not accept bind
  parameters; the value must be interpolated. Coerce with `int()` first — that is what makes the
  interpolation injection-proof, and it is what `limits.py` already does.
- **The wait budget must be set before the first `pg_advisory_xact_lock`, not around it.** A failed
  `SET LOCAL` aborts the transaction, which releases the lock and makes a contention test pass for
  entirely the wrong reason. That is exactly how the first test run went green on a broken build.

Queue semantics:

- Item failure → `failed`, `attempts += 1`, `next_attempt_at = now + backoff`. Batch is **not**
  stopped. The root's queue is blocked at the head; every other root keeps flowing.
- After N attempts → `dead_letter` + Sentry + an ops-visible `blocked` flag on the root. An operator
  explicitly skips or fixes. **Loud blocked queue replaces today's silent permanent strand.**
- Crashed worker → the row lock dies with the connection; the item is reclaimable. No more items
  stuck at `processing` forever (A6).
- Drain is triggered by `tenant_on_commit(TaskService.invoke(...))` at enqueue. Beat becomes a
  **safety net**, not the primary path — this is also the fix for C8's multi-minute limit-release lag.

### 4 — Version-stamped derived state (P3)

Two rules:

1. **Read after lock, inside the transaction.** `get_settlement_order` (`repayment.py:178-268`)
   currently reads contact/account summaries computed before the lock was taken — payments 2..N
   appropriate using an asset category from before payment 1 cured the overdue (B3). Move every
   derived read inside the locked span.

2. **Make staleness detectable, not silent.** Add `state_version` to Account and Contact, bumped
   `F()+1` in the same transaction as any ledger write. Every derived artifact
   (`TransactionSummary`, `AggregatedSummary`, limit read-model) stores `computed_at_version`.
   - Strong readers (appropriation, limit checks, EOD) assert `artifact.version == root.version`
     and recompute on mismatch.
   - Weak readers (dashboards, reports) may serve stale but the response carries `stale: true`.

This converts "stale data computation" from an invisible wrong number into a checkable invariant.

### 5 — Outbox for cross-root side-effects

A limit-bookkeeping failure must not roll back a customer's payment (C4), and must not be lost
either. Write an outbox row in the same transaction; drain after commit; reconcile nightly. This is
where CRE-6136's `LimitMovement` append-only ledger plugs in.

```
BEFORE                                  AFTER
┌── atomic ──────────────────┐          ┌── atomic ──────────────┐
│ settle  →  free_limit ✗    │          │ settle  →  outbox row  │
│         rollback EVERYTHING│          └──────── COMMIT ────────┘
└────────────────────────────┘                     │
   customer's payment lost                         └─→ drain → free_limit
   to a limit link mismatch                              retry / alert / reconcile
```

---

## Gap → mechanism mapping

Every finding from the gap analysis and CRE-6136, and what closes it.

| Gap | Closed by | Notes |
|---|---|---|
| **A1** batch stop strands rest | §3 per-root grain + quarantine | root-scoped blocking is the *correct* behaviour |
| **A2** unfenced cache locks, TTL | §2 advisory locks | TTL concept disappears entirely |
| **A3** lock released before COMMIT | §2 | Postgres owns release |
| **A4** two batches, same account | §3 one grain | |
| **A5** contention → give up | §2 `lock_timeout` → wait, then enqueue | |
| **A6** item stuck at `processing` | §3 row-lock claim | lock dies with connection |
| **A7** non-deterministic order | §3 `(value_date, txn_date, created_at, id)` | |
| **A8** ~~no UTR dedupe~~ | **already exists** | `payment_utr unique=True`; only null-UTR intake is open |
| **A9** batch get_or_create race | §3 | `select_for_update().get_or_create()` locks nothing when no row exists → IntegrityError on the partial unique index. Handle `IntegrityError` → retry-get |
| **A10** excess demand RMW race | §1 contact root | contact-scoped state under the contact lock |
| **B1** `income_suspended` never cleared | separate — NPA upgrade job | needs a reversal transaction + prop clear when contact DPD hits 0 |
| **B2** NPA threshold hardcoded 91 | separate — read `dpd.npa_days` | `product/handlers/eod.py:251` |
| **B3** stale settlement order | §4 read-after-lock | |
| **B4** RBI stickiness vs flag disagree | resolved once B1 lands | |
| **B5** `peak_dpd` overwritten | separate — `max()` | `repayment.py:395-401`; ledger path already correct at `base.py:663` |
| **B6** backdated payment reversal | §1 + §2 | self-deadlock on the account lock disappears (advisory locks are re-entrant per transaction); reversal of N accounts under one contact root is one lock |
| **C1** no NPA gate on utilization | separate — credit policy gate | **product decision required**, see Open questions |
| **C2** schedule-based loans don't free | separate — product decision | correct for SCF, wrong for term loans |
| **C3** write-off never frees limit | separate — one-liner in `written_off.py` | |
| **C4** limit failure kills payment | §5 outbox + None-guard on `primary_limit` | |
| **C5** shared-path silent no-op | CRE-6136 #4 — fail loud | |
| **C6** no limit reconciliation | CRE-6136 Phase 1 `LimitMovement` + nightly verify | |
| **C7** limit lock hygiene | §2 — the locks being fixed are deleted | |
| **C8** limit release lags minutes | §3 drain-on-commit | beat demoted to safety net |
| **6136-1** DummyCache silent fallback | §2 + fail-fast cache | **highest severity item in this document** |
| **6136-2** savepoint release | §2 | |
| **6136-3** tenant vs global lock prefix | §2 — key includes tenant explicitly | |
| **6136-5** block not idempotent on replay | CRE-6136 Phase 2 idempotency key | |
| **6136-6** validate/enforce read different limit sets | CRE-6136 Phase 0 | |
| **6136-9** no admission control at creation | CRE-6136 Phase 3 | |

---

## Phasing

Sequenced so that each phase is independently shippable and each one *reduces* risk on the next.
Phases 1–2 are the load-bearing ones; everything after is cleanup that becomes safe once
serialization is real.

| Phase | Scope | Schema? | Risk | Why here |
|---|---|---|---|---|
| **0 — Stop the bleeding** ✅ | ~~Make `TenantAwareCache` fail closed instead of falling back to DummyCache~~ (`6262ea47`). Still open: `lock_backend_healthy` metric + alert, `peak_dpd` `max()` (B5), free limit on write-off (C3), None-guard `primary_limit` (C4a). | no | low | Nothing else is trustworthy until the DummyCache path is dead. |
| **1 — Serialization primitive** ✅ | ~~`lib/serialization.py` + ordering-root resolver + Postgres concurrency harness~~ (`6262ea47`); ~~limit locks~~ (`96729962`); ~~account lock~~ (`8f8e6c5a`). Batch lock moved to Phase 2 — a transaction-scoped lock cannot span its multi-commit loop. | no | **high** | The whole guarantee rests here. Behaviour-preserving on the happy path; the change is that contention now *waits* instead of failing. |
| **2 — One queue, one grain** | Merge payment batching into the CTM batch on the ordering-root key. Deterministic item order. Head-of-line quarantine + dead-letter + `blocked` flag. Drain-on-commit; beat demoted. | yes (item `attempts`, `next_attempt_at`, batch `blocked`) | **high** | Dissolves A1/A4/A6/A7/A9/C8 together. Must follow Phase 1 — the queue relies on the lock. |
| **3 — Anti-staleness** | `state_version` on Account/Contact. `computed_at_version` on summaries. Read-after-lock in `get_settlement_order`. `stale` flag on weak reads. | yes | medium | P3. Independent of Phase 2, can run in parallel. |
| **4 — Limits** | **CRE-6136 as written** — Phase 0→4. Outbox decoupling of `free_limit` from the payment. Nightly `verify_limit_consistency`. | yes | medium | CRE-6136 Phase 0 partially overlaps Phase 1 here — see coordination note below. |
| **5 — NPA correctness** | NPA upgrade path: reverse `income_suspension`, clear props at contact DPD 0 (B1). Read `npa_days` from config (B2). Credit-policy gate on utilization (C1), config-gated. | no | low | Only safe once appropriation reads fresh state (Phase 3) — otherwise the upgrade job races the settlement. |

### Coordination with CRE-6136

CRE-6136 is in Development and its analysis is correct. Two adjustments:

1. **Its Phase 0 "delete the Redis lock" must be generalized, not limit-scoped.** Deleting the Redis
   lock only in `limits.py` leaves the account lock and batch lock running on the same unsound
   `DummyCache` path. Pull that work into Phase 1 here so all seven lock sites move together, on one
   primitive.
2. **Its early-commit `reserve()` pattern is right for limits and wrong for ledger state.** Limits
   are shared across ordering roots, so a short committed reservation is the correct shape. Ledger
   mutations must stay inside the caller's transaction under the root lock. Keep the two patterns
   explicitly separate in the code and in review, or someone will "consistently" apply reservations
   to demands.

---

## Risks — the three that will actually bite

**1. The default test harness cannot express any of this — and there are two separate traps.**

*Correcting CRE-6136's verification note:* CI is **not** SQLite. `.github/workflows/ci.yml:87-165`
runs `manage.py test` against a `postgres:15` service, so `select_for_update` and advisory locks do
work there. The two real traps are:

- **`TestCase` wraps each test in one transaction that is rolled back.** Two threads inside it
  cannot see each other's writes, and `pg_advisory_xact_lock` is *re-entrant within the same
  transaction* — it succeeds on the second call. A naive "does the lock block?" test therefore
  passes whether or not the lock works. Concurrency tests **must** be `TransactionTestCase` with
  real threads on separate connections.
- **`pytest.ini` points `DJANGO_SETTINGS_MODULE` at `project.settings.test`, which *is* SQLite
  in-memory** (`settings/test.py:28-35`). Any developer running `pytest` locally gets a database
  where `select_for_update()` is a no-op and `pg_advisory_xact_lock` does not exist. CI is safe;
  the local loop is not.

**Done** (`6262ea47`). The harness is `project/lib/tests/test_serialization.py`, and
`serialization_lock` raises on a non-Postgres backend unless `settings.TESTING` — degrading
silently in a deployment would be the same failure mode as the DummyCache bug it replaces. The
re-entrancy trap was confirmed live: advisory locks succeed on a second acquire within the same
transaction, so a `TestCase`-based contention test is guaranteed to pass.

Run the Postgres cases with:

```
PIPENV_DONT_LOAD_ENV=1 TENANT_ALIAS=tyger \
  DEFAULT_POSTGRES_DB_HOST=localhost DEFAULT_POSTGRES_DB_PORT=5432 \
  DEFAULT_POSTGRES_DB_NAME=omni_local_test \
  DEFAULT_POSTGRES_DB_USERNAME=<user> DEFAULT_POSTGRES_DB_PASSWORD=<pass> \
  pipenv run python manage.py test lib.tests.test_serialization tenancy.tests --keepdb
```

**2. Contact-as-root will find a hot anchor.**
An SCF anchor with tens of thousands of drawdown loans becomes one serialization point. The design
is correct; the throughput may not be. Mitigation is built in: measure `lock_wait_ms` p50/p99 per
root from day one of Phase 1, before Phase 2 depends on it. If p99 > ~200 ms, split money movement
to a group-account root and move contact-level excess to the reservation pattern. Do not discover
this in production.

**3. Blocking replaces failing — and blocking is visible to users.**
Today contention throws `BadRequest` and the payment silently disappears into a stopped batch.
After Phase 1 it *waits*. That is correct, but a 5 s `lock_timeout` on a synchronous API endpoint is
a user-visible latency change, and a genuinely stuck root now produces a queue that visibly backs
up instead of quietly dropping work. Ops needs the dashboard (`blocked` roots, queue depth,
dead-letter count) shipped **with** Phase 2, not after it.

---

## Verification

Concurrency correctness is not testable by assertion on a single thread. Minimum matrix, all on
real Postgres with `TransactionTestCase` + threads on separate connections (see Risk 1 — a
`TestCase`-based version of any row below passes vacuously):

| Test | Asserts | Status |
|---|---|---|
| Lock survives to COMMIT | holder sleeps *outside* the `with` block but inside the transaction; waiter must not acquire until commit | ✅ `6262ea47` |
| Contention is transient | timeout raises `SerializationLockTimeout`, not a `DRFValidationError` that would permanently reject a drawdown | ✅ |
| Same root re-entrant | the old backdated-payment self-deadlock cannot recur | ✅ |
| Opposite lock orders | two threads, same pair declared in reverse, 8 rounds — no deadlock | ✅ |
| Distinct roots don't block | serialization is per-root, not global | ✅ |
| `lock_timeout` doesn't leak | `SET LOCAL` scoped to the transaction | ✅ |
| Redis down for the whole run | `add()` returns False, never True; degradation bounded and logged at ERROR | ✅ |
| Limit over-utilisation fuzz | `sum(movements) == limit balance` under N concurrent drawdowns | ✅ `e4ec8d99` |
| 100 payments, 1 NPA contact, 100 loans, N threads | all 100 applied exactly once; `sequence` is a dense 1..100; final outstanding independent of thread scheduling | ⬜ Phase 2 |
| Same, with a poison item at #38 | #1-37 applied, root blocked, **other contacts unaffected**, dead-letter after N attempts | ⬜ Phase 2 |
| Kill -9 a worker mid-item | item reclaimed, applied exactly once, no `processing` orphan | ⬜ Phase 2 |
| Backdated payment concurrent with forward payments | reversal + replay under one root lock, final state == serial replay | ⬜ Phase 2 |
| Determinism fuzz | same input set, 20 runs, shuffled arrival order → identical final ledger | ⬜ Phase 2 |

The last one is the real acceptance test for the whole programme: **same transactions, any arrival
order, identical books.**

---

## Open questions (product, not engineering)

1. **C1 — should NPA freeze fresh utilization?** There is currently no gate anywhere in the drawdown
   path, so a 120-DPD income-suspended anchor can immediately re-draw every rupee a payment frees.
   Whether that is a bug depends on credit policy. Engineering can ship it config-gated either way,
   but someone must decide the default.
2. **C2 — should schedule-based (term) loans free limit per repayment?** Current behaviour (free only
   at closure) is right for SCF and arguably wrong for term loans.
3. **CRE-6136 open item — the deliberate overdraw path.** Ships flag-gated as intended behaviour;
   Phase 1's report must break out its volume and value per tenant before deciding whether to cap it.
