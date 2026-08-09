# CRE-5962 — Collections Auto-Assignment (PR #1396) — Implementation Walkthrough & Review

- **PR:** [crego-omni#1396](https://github.com/crego-tech/crego-omni/pull/1396) — `feature/cre-5962-collection-cases-auto-assignment` → `develop`
- **Author:** Amit Sharma (`amit-backend`)
- **Size:** 62 files, +10,454 / −96
- **Reviewed at commit:** `bdd475e6`
- **Reviewed:** 2026-07-27
- **Status at review time:** OPEN
- **Related:** [collections-module-prd.md](collections-module-prd.md), `crego-omni/docs/COLLECTIONS_BACKEND_DESIGN.md`, `crego-omni/docs/COLLECTIONS_FRONTEND_API.md`, `crego-omni/docs/DPD_BUCKET_ANALYZE.md`

---

## What it does

Builds a *collections module* on top of the existing loan book: it decides **who chases which
delinquent borrower**, **when to nudge them**, and **what the collections manager sees on a
dashboard**.

Before this PR, `collect/` had exactly one thing: `CollectionEnquiry` (an agent logging a
call/field-visit, optionally with a Promise-to-Pay). This PR adds the machinery *around* it.

---

## 1. The core idea in one picture

```
        LOAN BOOK (existing)                    COLLECTIONS (new)
   ┌────────────────────────────┐        ┌──────────────────────────────┐
   │ Account ──> Demand.dpd     │        │  DpdBucket   "0-30/31-90/90+"│
   │  (EOD computes DPD daily)  │───────>│      ▼                       │
   │ Contact (the borrower)     │        │  AssignmentRule (conditions) │
   └────────────────────────────┘        │      ▼                       │
                                         │  RuleEvent  (assign/escalate │
                                         │              /notify)        │
                                         │      ▼                       │
                                         │  CollectionCase (who owns it)│
                                         │      ▼                       │
                                         │  CollectionSummary (EOD snap)│
                                         └──────────────────────────────┘
```

Five new models, one migration chain (`0002` → `0009`), all purely additive.

| Model | Grain | What it holds | Key design call |
|---|---|---|---|
| `DpdBucket` | config | `label, min_dpd, max_dpd, is_npa` | **Never stored on a case.** A case's bucket is derived by looking its DPD up in the ordered active set. The active set must tile `[0, ∞)` exactly once. |
| `AssignmentRule` | config | `name, conditions (JSON), status` | **No `priority`, no `is_default`.** Rules are composable — all matching rules contribute. |
| `RuleEvent` | config | `event_type`, + either an assignee **or** a `notification_rule` FK | Two shapes in one table: exclusive (assign/escalate) vs additive (notify). |
| `CollectionCase` | **one per contact** | `contact, assigned_agent, matched_rule, status` | **Zero derived snapshots.** Outstanding/DPD/PTP counts are computed on read, so nothing goes stale. |
| `CollectionSummary` | one per **day** | ~19 KPIs + bucket/PTP distributions | Written by EOD; only exists because "as-of last Tuesday" can't be reconstructed from current state. |

Constraint worth knowing (`collect/models.py:400`):

```python
# one ACTIVE case per contact; closed cases stay as history
UniqueConstraint(fields=["contact"], condition=Q(is_deleted=False) & ~Q(status="closed"))
```

---

## 2. The nightly pipeline — where everything actually happens

Two new steps bolt onto the existing EOD handler (`product/handlers/eod.py:852` and `:910`):

```
EOD PIPELINE (per tenant, nightly)
│
├─ … update_demand_dpds()          ← Demand.dpd written here
├─ … update_system_date()          ← business day rolls over
│
├─ evaluate_collection_cases()   ◄── NEW
│  │
│  ├─ 1. sync_collection_cases()
│  │     open a case for every newly-delinquent borrower;
│  │     reopen resolved cases that fell behind again
│  │
│  ├─ 2. reconcile_collection_payments()
│  │     walk open PTPs, mark fulfilled if paid;
│  │     resolve cases with nothing outstanding
│  │     ↳ runs BEFORE the sweep so a promise settled today
│  │       isn't chased again tonight
│  │
│  └─ 3. evaluate_collection_rules()   ← THE SWEEP
│           assignment + dunning
│
└─ build_collection_summary()   ◄── NEW (runs last)
      upsert today's CollectionSummary row
```

The ordering is deliberate: the sweep sits *after* `update_system_date` so DPD and dunning
anchors are evaluated against the **new** business day — the same reason `scan_due_reminders`
sits at the end of the pipeline.

### The sweep itself (`collect/tasks.py:122`)

```
evaluate_collection_rules()
│
├─ load active rules + prefetch events   (once)
├─ dunning.prime(notify_events)          (preload NotificationRules — makes the
│                                         per-loan gate query-free)
├─ picker = AgentPicker()                (memoizes agent lists + loads per role)
├─ buckets = active_buckets()            (once)
│
└─ for each batch of 500 open cases:
   ├─ facts_map   = build_facts_map(batch, buckets)   ← ~5 queries per batch
   ├─ targets_map = dunning.build_targets(batch)      ← loan-level facts
   ├─ reachable   = dunning.reachable_contact_ids(…)
   │
   └─ for each case:  ── try/except per case, one failure never aborts the batch
      │
      ├─ resolution = resolve(rules, facts)
      │
      ├─ EXCLUSIVE HALF (ownership)
      │   ├─ human_owned?  (matched_rule IS NULL and agent IS NOT NULL)
      │   │     → skipped_manual++            ← do NOT reassign
      │   ├─ elif exclusive_event:
      │   │     agent = picker.pick(event, case)
      │   │     ├─ None + role target → unassignable++   (do NOT write!)
      │   │     └─ else assign_from_rule(case, agent, rule)
      │   └─ elif matched_rule_id is not None:
      │         → release_from_rule(case)      (rule no longer matches)
      │
      └─ ADDITIVE HALF (dunning)          ← runs even for human-owned cases
          fire_due_events(additive_events, case, targets, contact)
```

> **Note:** a manually-reassigned case is *not* skipped wholesale. `human_owned` only suppresses
> the **assignment**; the code falls through and still runs dunning. Per the comment at
> `tasks.py:224`: *"Guard 2 suppresses only the assignment. Dunning still runs: chasing the
> borrower is independent of who happens to own the case."*

### Why it's safe to re-run

Five independent properties (documented in the task docstring at `tasks.py:123`):

| # | Property | Mechanism |
|---|---|---|
| 1 | Assignment applies **on change only** | `assign_from_rule` returns early if agent+rule+status already match → no write, no audit row |
| 2 | Human decisions are never clobbered | `matched_rule = NULL` is the sentinel for "a person owns this" |
| 3 | Agent choice is a **function of the case**, not a cursor | `crc32(case.id) % len(agents)` |
| 4 | Dunning is pinned to a correlation id | `dunning:{event.id}:{account_id}:{today}` |
| 5 | Per-case failure isolation | `try/except` inside the loop, `errors++`, continue |

On #3: it uses `zlib.crc32`, **not** Python's `hash()`, because string hashing is salted per
process — `hash()` would hand the same case to different agents in different Celery workers.

```python
# rule_engine.py — round_robin
return agents[crc32(case.id.encode()) % len(agents)]
```

---

## 3. The rule engine

### How a rule matches

`conditions` is a flat, ID-referenced JSON object. **Every present key must match; an absent key
is unconstrained; `{}` matches everything.**

```json
{
  "bucket_ids":  ["01K…", "01K…"],
  "branch_ids":  ["01K…"],
  "program_ids": ["01K…"],
  "product_ids": ["01K…"],
  "outstanding": { "gte": 50000, "lte": 100000 },
  "overdue":     { "gte": 1000 }
}
```

| Field | Semantics |
|---|---|
| `bucket_ids`, `branch_ids` | single-valued — the borrower's value must be in the set |
| `program_ids`, `product_ids` | multi-valued — **any** overlap matches |
| `outstanding`, `overdue` | numeric range, `gte` / `lte` (Decimal comparison) |

Matching is done **in Python**, not SQL — facts are bulk-loaded once per 500-case batch
(`build_facts_map`), then every rule is tested in memory. That keeps it O(batch queries), not
O(rules × cases) queries.

```
CaseFacts = {
  bucket_id     ← bucket_of(max_dpd across the borrower's demands)
  branch_id     ← contact.branch
  program_ids   ← set, from the borrower's accounts
  product_ids   ← set
  outstanding   ← Σ demand.outstanding
  overdue       ← Σ outstanding where dpd > 0
}
```

### How multiple matches combine

There is **no priority column**. Instead:

```
        Rule A (created Jan 1)   Rule B (Jan 2)      Rule C (Jan 3)
        ├─ assign → Agent-1      ├─ assign → Agent-2 ├─ escalate
        └─ notify: reminder      └─ notify: paylink  └─ notify: legal
                 │                        │                  │
                 └────────────────────────┼──────────────────┘
                                          ▼
                       ┌──────────────────────────────────┐
                       │  EXCLUSIVE  (assign / escalate)  │
                       │  sort by (rule.created_at,       │
                       │           rule.id, event.id)     │
                       │  → winner: Rule A's assign       │
                       │  → discarded: B's assign,        │
                       │               C's escalate       │  (logged)
                       ├──────────────────────────────────┤
                       │  ADDITIVE  (notify)              │
                       │  → ALL THREE fire                │
                       └──────────────────────────────────┘
```

The sort key is a **total order**, so the outcome doesn't depend on the order rules come back
from the DB. That's why `AssignmentRule.Meta.ordering = ["created_at", "id"]` lives on the model
rather than at each call site.

### Agent picking

```
picker.pick(event, case)
│
├─ assignee_type == "user"  → that user, done
│
└─ assignee_type == "role"
   ├─ agents = active users with that role, ORDER BY id  (stable!)
   ├─ strategy == "load_balanced"
   │     → min(agents, key=(open_case_count, id))
   │     → increment the in-run counter so the NEXT case in this
   │       batch sees the updated load (otherwise everything piles
   │       onto one agent)
   └─ strategy == "round_robin"  (default)
         → agents[crc32(case.id) % len(agents)]
```

If a role resolves to **zero** agents, the sweep deliberately does **not** write — nulling the
assignee would silently drop a live owner while leaving the case marked "assigned". It counts
`unassignable` instead so the empty role is visible.

### Case lifecycle

```
                    sync_collection_cases()
                            │
                     (borrower delinquent)
                            ▼
                        ┌───────┐
              ┌────────>│  new  │<──────────┐
              │         └───┬───┘           │ release_from_rule()
              │             │ sweep assigns │ (rule no longer matches)
              │             ▼               │
              │      ┌────────────┐  ───────┘
   reopen()   │      │  assigned  │
   (fell      │      └─────┬──────┘
    behind    │            │ agent works it
    again)    │            ▼
              │     ┌─────────────┐      escalate event
              │     │ in_progress │─────────────────────> ┌───────────┐
              │     └──────┬──────┘                       │ escalated │
              │            │ nothing outstanding          └───────────┘
              │            ▼
              │      ┌──────────┐
              └──────│ resolved │
                     └────┬─────┘
                          │ human decision
                          ▼
                     ┌────────┐
                     │ closed │  (terminal — frees the unique constraint)
                     └────────┘
```

**The `matched_rule` sentinel** is the single cleverest bit of the design:

| `matched_rule` | `assigned_agent` | Meaning | Sweep behaviour |
|---|---|---|---|
| set | set | auto-assigned | re-evaluate; reassign if the winner changed |
| **NULL** | **set** | **human reassigned it** | **never touch the assignment** |
| set | NULL/stale | rule no longer matches | `release_from_rule` → back to `new` |
| NULL | NULL | never assigned, no rule matched | leave alone (there is no fallback rule) |

`POST /collect/contacts/{id}/reassign/` sets the agent **and clears `matched_rule`** — that one
write is what makes a human decision permanent.

---

## 4. Dunning (the notification half)

The interesting design decision here is what got **removed**. Migration `0003` drops
`RuleEvent.template` and `RuleEvent.channels`; `0007` drops `schedule_anchor`. The reason: they
could never have been honoured — the notifications module's entry point accepts no
template/channel/ETA override. Template, channels, send hour **and the send-day condition** all
belong to the `NotificationRule`.

So a `RuleEvent` of type `notify` now carries *only* an FK to a `NotificationRule`.

```
sweep (daily, every delinquent loan)
   │
   ▼
DunningService.fire(event, case, target, contact)
   │
   ├─ rule = preloaded NotificationRule (via prime())     ← no DB hit
   ├─ context = build_context(target, case, contact)
   │     { dpd, days_to_due, days_to_promise,
   │       overdue_amount, outstanding_amount,
   │       payment_link, contact_id ⚠, account{…}, contact{…} }
   │
   ├─ TIMING GATE — JsonLogic.apply(rule.conditions, context)
   │     e.g. {"in": [{"var":"days_to_due"}, [-1,-7,-15,-30]]}
   │     ↳ most days this is False → returns immediately, ZERO queries
   │
   └─ resolver.trigger_rule(rule_id, context,
                            correlation_id="dunning:{event}:{account}:{today}",
                            respect_conditions=False)   ← already gated above
        │
        ├─ parse_event_master_name("Collect CollectionCase Reminder")
        │        → ("collect", "CollectionCase", "Reminder")     ⚠ must be 3 words
        │
        ├─ scope config: CollectionCase → {"contacts__id": "contact_id"}
        │        → UserAssignment.filter(contacts__id=ctx["contact_id"], active)
        │        → the borrower's User
        │
        └─ per recipient:
             idempotency_key = sha256(correlation_id : rule_id : recipient)
             → InboxNotification(status="scheduled", scheduled_for=09:00)
             → poller sends email / SMS / push at that hour
```

### Seeded dunning events

Three events (`notifications/management/commands/seed_notifications.py`), each with per-channel
templates and a rule whose JSONLogic picks **discrete** days:

| Event | Channels | Send days (DPD) |
|---|---|---|
| `Collect CollectionCase Reminder` | email, sms, push | 1, 7, 15, 30 |
| `Collect CollectionCase Paymentlink` | email, sms | 7, 15, 30, 45, 60 |
| `Collect CollectionCase Legalnotice` | email, sms | 90, 120, 150, 180 |

Discrete lists, not `<= -90` — an inequality would match *every* day past 90 DPD, and the
correlation id only dedups within a day, so a 200-DPD borrower would get a legal notice every
single morning.

### Context keys available to templates

`case_id`, `contact_id`, `account_id`, `as_of`, `dpd`, `days_to_due`, `days_to_promise`,
`overdue_amount`, `outstanding_amount`, `payment_link`, `account{id, ref_id, contact_id,
program_id, branch_id}`, `contact{id, name, mobile_number}`.

### Footguns the PR calls out explicitly

- **Event names must be exactly three words** (`{App} {Model} {Action}`). Otherwise
  `parse_event_master_name` returns `None`, recipient resolution silently degrades to a weaker
  context-key fallback, and the message may reach nobody — with no error.
- **`contact_id` in the context is load-bearing**, not decorative — it's the key the notification
  scope config filters `UserAssignment` on.
- **Unreachable borrowers**: a borrower with no registered user account can't be notified. The
  notifications module treats "nobody to notify" as success, so the sweep counts
  `dunning_unreachable` separately and logs a warning. That's the only signal.

---

## 5. Dashboard & summary

```
GET /collect/dashboard/?as_of=YYYY-MM-DD
        │
        ├─ as_of == today  → CollectionSummaryService(as_of).build()   {"source": "live"}
        │                     (60s cache to absorb burst refreshes)
        │
        └─ as_of <  today  → CollectionSummary row for that date       {"source": "snapshot"}
                              missing → {"data": null, "message": "No EOD snapshot…"}
```

The same `build()` powers both the live path and the nightly `write_snapshot()`, so today's live
numbers and tomorrow's snapshot of today **agree by construction**.

Details worth noting:

- `collected_amount_total` is stored **cumulative**, so a date-range total is a two-row
  subtraction rather than a scan of every day in between.
- Ratios store their **denominators** alongside (`opening_delinquent_amount`, `due_amount`,
  `total_book_amount`) so a range can be *recomputed* rather than averaged — averaging daily
  percentages skews toward low-volume days.
- `bucket_distribution` snapshots the bucket **ranges**, not FKs, so history stays interpretable
  after someone reconfigures the buckets.
- `write_snapshot()` refuses `as_of != today` — a snapshot is a fact about a day, never
  backfilled. It upserts on `snapshot_date`, so a retried EOD corrects the row.

### Agent workload

```python
mean = Σ(open_cases) / team_size
load > mean × 1.5  → overloaded
load < mean × 0.5  → underutilized
else               → normal
```

Deterministic, so the summary card's "1 overloaded" always equals what `?workload=overloaded`
returns on the roster.

Agent detail adds: `role`, `dpd_breakdown` (contacts per active bucket, by worst DPD),
`active_ptps`, and `activity` (`today` / `this_week` counts of calls, field visits, PTPs logged,
payments taken — attributed by `created_by`, i.e. who logged it, not who owns the case).

### PTP reconciliation

`reconcile_ptp()` recomputes (never increments) the amount repaid since the promise was made:

```
baseline = enquiry.created_at.date()          ← when the promise was LOGGED
paid_since = max(repaid_total(as_of) - repaid_total(baseline), 0)
fulfilled  = paid_since >= promised_amount
```

Baseline is the *logging* date, not the promised date — if it were the promised date, every kept
PTP would net out to exactly zero. Recomputing rather than incrementing makes it idempotent;
flooring at 0 stops reversals producing negative `paid_amount`.

---

## 6. API surface

```
collect/
├── contacts/                         ← the WORKLIST
│   ├── GET    /                        list delinquent borrowers
│   ├── GET    /search/?q=
│   └── POST   /{id}/reassign/          {"agent_id": "01K…"}   [CanReassignCollectionCase]
│
├── dpd-buckets/                      ← whole-set config (no row-level writes)
│   ├── GET    /                        current set
│   ├── POST   /analyze/                dry-run impact preview   → 200  [CanChangeDpdBucket]
│   └── POST   /apply/                  save + queue sweep       → 202  [CanChangeDpdBucket]
│
├── assignment-rules/                   full CRUD + PUT /bulk_actions/
├── rule-events/                        full CRUD (?rule=<id>)
│
├── dashboard/
│   ├── GET    /?as_of=                 single-date KPIs
│   ├── GET    /?start=&end=            range (stock / flow / trend)
│   └── GET    /leaderboard/?limit=     [IsCollectionTeamViewer]
│
├── ptps/
│   ├── GET    /                        promises, filterable by window
│   └── GET    /summary/                badge counts
│
├── agents/
│   ├── GET    /                        roster       [IsCollectionTeamViewer]
│   ├── GET    /summary/                team KPIs    [IsCollectionTeamViewer]
│   └── GET    /{id}/                   detail       [CanViewOwnOrTeamAgentDetail]
│
└── enquiries/                          (pre-existing) call/visit logging
```

There is **no `/collect/cases/` endpoint** — ownership is per-contact (one active case per
borrower), so reassignment lives on the worklist row.

### Worklist row

```json
{
  "id": "01K…", "ref_id": "CUST-001", "name": "Acme Traders",
  "max_dpd": 92, "total_outstanding": "125000.000000", "open_ptp_count": 1,
  "case_id": "01K…", "case_status": "assigned",
  "assigned_agent_id": "01K…", "assigned_agent_username": "priya",
  "bucket": { "id": "01K…", "label": "90+", "is_npa": true }
}
```

Filters: `bucket`, `assignment`, `assigned_to`, `case_status`, `min_dpd`/`max_dpd`,
`min_outstanding`/`max_outstanding`, `has_open_ptp`, `is_npa`, `branch`, `search`, `ordering`.

### The DPD bucket flow — draft → preview → save

This replaced an earlier two-step flow. Buckets are edited **as a whole set**, because the
invariant ("tile `[0, ∞)` exactly once") is a property of the set, not of any row.

```
 1. GET  /collect/dpd-buckets/          load current set
 2. …edit locally…                      keep `id` on existing rows (preserves rule FKs),
                                        omit `id` for new ones
 3. POST /collect/dpd-buckets/analyze/  ─┐  synchronous, saves NOTHING,
    { "buckets": [ … ] }                 │  safe to call on every keystroke
                                         │
    → 200 {                              │
        "affected_demands": 1724,        │
        "affected_cases": 28,            │  ← headline
        "agent_reassignments": 41,       │  ← "why this matters"
        "rules_impacted": 3,             │
        "rules_orphaned": 1,             │  ← WARN: rules point at a bucket you're deleting
        "estimated_seconds": 4,          │
        "config_version": "c7c1a9f2…"    │
      }                                 ─┘

 4. POST /collect/dpd-buckets/apply/     saves synchronously (400 + rollback if invalid),
    { "buckets": [ … ] }                 then queues the reassignment sweep
    → 202 { "status": "queued", … }
```

Validation errors are field-shaped:

```json
{ "min_dpd": "DPD range 31–60 is not assigned to any bucket.", "code": "bucket_gap" }
```

Row-level `POST/PUT/PATCH/DELETE` on `/dpd-buckets/{id}/` return **405** — everything goes
through `apply`.

`agent_reassignments` is computed by actually running the rule engine against the *proposed*
buckets and diffing `matched_rule` per case. It's a real dry-run, not an estimate.

### Permissions

| Class | Guards | Rule |
|---|---|---|
| `CanReassignCollectionCase` | `POST /contacts/{id}/reassign/` | requires `collect.change_collectioncase` |
| `CanChangeDpdBucket` | `analyze/`, `apply/` | requires `collect.change_dpdbucket` |
| `IsCollectionTeamViewer` | agent roster, team summary, leaderboard | head/staff/admin only — agents can't see peers |
| `CanViewOwnOrTeamAgentDetail` | `GET /agents/{id}/` | agent may read **only** their own record; head/staff read any |

Scope engine config (`default_role_scope_config.json`) additionally filters `CollectionCase` to
`assigned_agent_id = user.id` for `collection_agent`, and to self-or-branch for
`collection_head`.

---

## 7. The bug this PR quietly fixes

From commit `917c141`:

> the contact-list rollups filtered demands on `Demand.contact` alone, which is populated on
> **~1 in 8500 rows** — the borrower link is `account.contact`. `max_dpd` / `total_outstanding` /
> `open_ptp_count` were returning **0 for nearly every contact**.

The fix accepts both paths and is now **shared** with the worklist so the two lists can't drift:

```python
Demand.objects.filter(Q(contact=OuterRef("pk")) | Q(account__contact=OuterRef("pk")))
```

Each metric is a correlated subquery (not a join) so rows don't multiply, and each `Coalesce`s to
0 so NULLs don't float to the top on `DESC`. `contact/views.py` shrinks by 32 lines because it
now calls the shared helper.

Three index migrations support the new query load, two built `CONCURRENTLY` (`atomic = False`)
because `Demand` and `Payment` are hot:

| Index | Serves |
|---|---|
| `demand_dpd_status_idx` **partial** on `outstanding > 0` | `delinquent_demands()` — the sweep's and dashboard's base scan |
| `demand_account_dpd_idx` | per-account max-DPD rollups |
| `payment_value_date_status_idx` | collected today / MTD / total |
| `component_category_idx` | the `category = principal` filter in NPA + bucket distribution |

---

## 8. Review observations

Raised in rough priority order. None are blockers on their own.

1. **`unassignable` is counted but not surfaced anywhere a human looks.** A role with zero active
   agents means those cases silently stay unowned. It's in the EOD metrics blob and the log line
   — fine for a postmortem, invisible day-to-day. Same class of problem as `dunning_unreachable`,
   which at least gets a `logger.warning` per case.

2. **The `matched_rule = NULL` sentinel is overloaded.** "Human owns this" and "never assigned"
   are both `matched_rule IS NULL`; they're only distinguishable by whether `assigned_agent` is
   also null. It works, but a case that a human assigns and then unassigns silently becomes
   eligible for auto-assignment again. Worth confirming that's deliberate and documenting it for
   the frontend.

3. **`release_from_rule` sends a case back to `new` and drops the agent** with no notification to
   the agent who was working it. If an admin edits a bucket boundary, agents can lose cases
   overnight with no signal. The `analyze` preview mitigates this for the admin, not for the agent.

4. **Three-word event names are enforced by a validator, but the failure mode is silent at
   *resolution* time** (bad name → `None` → weaker fallback → possibly nobody). Since
   `parse_event_master_name` is now load-bearing for a borrower-facing flow, a startup-time
   assertion over the seeded collections events would be cheap insurance.

5. **`build_facts_map` + `build_targets` + `reachable_contact_ids` run per 500-case batch.** Fine
   at current scale; worth a note on expected case volume. The `estimated_seconds ≈
   affected_cases / 100` heuristic should be validated against a real tenant before it's shown to
   users as a progress hint.

6. **Test coverage is genuinely good** (8 new test modules, ~1,600 lines) covering the tricky
   parts — tie-break determinism, idempotent re-run, PTP baseline, bucket tiling. Not executed as
   part of this review. Given that test directories missing `__init__.py` are silently skipped by
   the runner (this has bitten `ctm/` and `core/` before), confirm `collect/tests/__init__.py`
   exists on the branch — it does on `develop`, so this should be fine, but it's a cheap check.
   Also note the suite has a known red
   baseline on both `master` and `develop`; diff failures against the parent baseline rather than
   treating any red as PR-introduced.

---

## Appendix — enum reference

All enums are stored and transmitted as the lowercase **name** (e.g. `in_progress`), never the
display label.

```
CollectionStatus:      no_answer, contacted
CollectionType:        call, field_visit
PTPStatus:             open, fulfilled, broken, cancelled
CollectionCaseStatus:  new, assigned, in_progress, resolved, escalated, closed
DpdBucketStatus:       active, inactive
AssignmentRuleStatus:  active, inactive
RuleField:             bucket_ids, branch_ids, program_ids, product_ids, outstanding, overdue
RuleEventType:         notify (additive), assign_agent (exclusive), escalate (exclusive)
AssigneeType:          user, role
AssignStrategy:        round_robin, load_balanced
WorkloadStatus:        overloaded, underutilized, normal
```
