# CRE-6130 — Book timezone for txn_date (working plan)

> **Linear:** [CRE-6130](https://linear.app/crego/issue/CRE-6130/summary-txn-date-lookups-resolve-in-the-browsers-timezone-not-the)
> **Branch:** `feature/cre-0000-book-timezone` in crego-omni — 6 commits pushed, unreviewed, **do not merge yet**.
> **Status as of 2026-07-29:** items 1-8 of the sequencing table below are done; the backfill
> per-basis/delete-on-rebuild work, `Account.latest_summary`, the `get_system_date` pinning and the
> repair command are outstanding. One test failure still needs a verdict — see the Linear issue.
> Commits carry a `CRE-0000` placeholder and need renaming to CRE-6130.
>
> This is the original pre-implementation plan, kept for the analysis and the reasoning behind each
> decision. The Linear issue holds current state.

---

# Transaction summary: timezone bug + backfill repair

## The short version

You asked two things. Both have real bugs behind them.

**"Is timezone handled properly in txn_date summary lookups?"** — No. The day a summary belongs
to is currently decided by *the browser of whoever is looking at it*.

**"Should the summary API create a summary if none exists?"** — It already does. Your hunch that
the backfill command was the actual problem is right. It has four separate bugs.

---

## Bug 1: the browser decides the book day

### What's happening

The web app sends the user's browser timezone on every single request:

```
crego-web/packages/omni-web/src/services/baseApi.ts:43
    'X-Timezone': Intl.DateTimeFormat().resolvedOptions().timeZone
```

A Django middleware takes that header at face value and makes it the server's active timezone
for the whole request:

```python
# project/lib/middlewares.py:90-98
tzname = request.headers.get("X-Timezone", settings.TIME_ZONE)
timezone.activate(tzname)
```

`TransactionSummary.txn_date` is a **DateTimeField**, and every lookup asks for it by day using
`txn_date__date=`. Django compiles that to `(txn_date AT TIME ZONE <active tz>)::date` — so the
answer changes with the header.

### A worked example

EOD stamps its nightly snapshot at the last microsecond of the day, in IST:

```
Row written by EOD for 28 July:  2026-07-28 23:59:59.999999 +05:30
```

Now three people open the same loan and ask for 28 July:

| Who | Their browser tz | What Django computes | Result |
|---|---|---|---|
| Mumbai ops | Asia/Kolkata | 28 July | Finds the row |
| Singapore partner | Asia/Singapore | **29 July** | Row invisible — rebuilds it from scratch |
| London auditor | Europe/London | 28 July | Finds it |

And on **SOD tenants** — which is the default when the config key is missing
(`ctm/helpers.py:785`) — the stamp is `00:00:00 IST` instead, so it flips the other way and
breaks for *everyone west of India*: Dubai, London, New York, all of it.

### It corrupts on write too, not just read

When no row exists, the API builds one and stamps it like this:

```python
# project/apps/ctm/services/transaction_summary.py:1980
txn_date = timezone.make_aware(datetime.combine(date_context.as_of_date, local_now.time()))
```

No explicit timezone, so `make_aware` uses the browser's. A New York user hitting the page at
3pm their time saves a row stamped for *the next day* in book terms. That row then wins the
"latest row of the day" ordering for a day it doesn't belong to.

The same applies to the default date itself — `DateContext.from_request` uses
`timezone.localdate()` (`date_context.py:141`), so "today" means a different day per user.

### Why `value_date` is fine

`value_date` is a plain `DateField`. Postgres stores it as a bare calendar day, no timezone
conversion on read or write. **The entire bug lives on the `txn_date` side** — which is also the
API's default mode (`date_context.py:133`).

### The fix: separate "display timezone" from "book timezone"

One rule: **`X-Timezone` decides how dates are *shown*. It must never decide which book day a
stored row belongs to.**

Add a small set of helpers pinned to `settings.TIME_ZONE`, in `project/lib/utils/dates.py`:

```python
book_tz()                    # ZoneInfo(settings.TIME_ZONE) — never get_current_timezone()
book_today() / book_now()    # replaces timezone.localdate() / localtime()
book_date(dt)                # replaces .date() and localtime(x).date() on a txn_date
book_day_range(d)            # (start of d, start of d+1) — half-open
stamp_book_datetime(d, t)    # the one canonical way to write a txn_date
```

And query builders in a new `project/lib/utils/date_filters.py`:

```python
book_day_filter(field, d)      # replaces  field__date = d
book_upto_filter(field, d)     # replaces  field__date__lte = d
book_before_filter(field, d)   # replaces  field__date__lt = d
book_days_q(field, dates)      # replaces  field__date__in = [...]
```

**Bonus: this also fixes a performance problem.** `(txn_date AT TIME ZONE 'X')::date = D` can't
use an index, so every one of these lookups currently scans past the btree on
`ctm_transaction_summary.txn_date`. A half-open range (`>= start AND < next_start`) can use it.
`book_days_q` matters most — `summary_batch.py:421` passes up to 366 dates at once.

### Where the changes go

`DateContext` (`project/apps/ctm/date_context.py`) is the chokepoint. Most of the fix is here:

```python
# lines 63 / 77 / 98 — before
return {"transaction__txn_date__date__lte": self.as_of_date}
# after
return book_upto_filter("transaction__txn_date", self.as_of_date)

# line 141 — the single highest-value line in the change
as_of_date = timezone.localdate()   →   book_today()
```

The rest is a mechanical sweep of 41 sites across 14 files, in four groups:

| Group | Where | What changes |
|---|---|---|
| Summary reads | `transaction_summary.py` (esp. **:1803**, the hot `get_summary` path), `summary_batch.py`, `summary_build_context.py` | `txn_date__date*` → the new filter helpers |
| Summary writes | `transaction_summary.py:1980, :2060`, `eod.py:76-84` | `make_aware(combine(...))` → `stamp_book_datetime()` |
| Python-side truncation | `summary_batch.py:447, :802`, `transactions.py`, `ctm/tasks.py`, `processors/base.py` | `.date()` / `localtime(x).date()` → `book_date(x)` |
| Reports + commands | `base_handler.py`, `repayment_advice_handler.py`, `gl/*`, `eod.py:519`, the backfill | mixed |

Two things worth calling out in that sweep:

- Several sites (`transactions.py:1613`, `ctm/tasks.py:49`, `processors/base.py:600`) use a **bare
  `.date()`** on a database-loaded datetime. That's the *UTC* date — wrong for every posting
  between 00:00 and 05:29 IST, even for an Indian user. Pre-existing, same fix.
- `SettingService.get_system_date()` (`core/services/settings.py:712`) falls back to
  `timezone.localdate()`. It gates `validate_txn_date` and the future-date guards, so it has the
  widest reach. **Land it as its own commit** so it can be reverted on its own if anything moves.

### What deliberately does NOT change

The middleware stays. DRF still *renders* datetimes in the browser's timezone — that's correct
and users want it. `TimezoneDateTimeField` stays (its only user is `docs.expires_at`, a genuine
user-facing wall-clock field). All `value_date` predicates stay byte-identical.

Also: pin `get_day_start` / `get_day_end` to book tz — their docstrings already *claim*
`settings.TIME_ZONE` but the code uses the active one. But **don't** make `get_day_end` half-open;
five callers rely on it being inclusive, and at microsecond resolution `<= 23:59:59.999999` loses
nothing anyway.

### Does existing data need repairing?

Mostly no. EOD runs in Celery and the backfill runs from the CLI — neither has a request, so both
already used `settings.TIME_ZONE`. Posting-linked rows get their `txn_date` passed in explicitly.

The one corrupt group is **rows built on the fly by an API request**, identifiable as:

```sql
txn_date IS NOT NULL AND value_date IS NULL AND transaction_id IS NULL
```

These are detectable precisely: `created_at` is `auto_now_add` and lands microseconds after the
stamp, so for a correct row `created_at − txn_date` is an exact multiple of 24 hours. For a
browser-stamped row it's off by that browser's offset. The remainder tells you which timezone did
it (34200s = US Eastern, 12600s = Tokyo).

Ship a `repair_browser_tz_summary_stamps` command, `--dry-run` by default. Two rules: skip rows
where the offset exceeds 12h (the arithmetic gets ambiguous), and **don't bump `updated_at`** —
it's the tie-breaker in `latest_row_ordering`. Run it only *after* the code fix ships, or live
traffic recreates bad rows behind you.

---

## Bug 2: the backfill writes a row that lies about its own date

This is the "not working fine" you suspected, and it's the most serious finding.

### What it does

```python
# backfill_transaction_summaries.py
:238  date_context = DateContext.with_value_date(d)   # payload = all ledgers with value_date <= d
:258  ts.txn_date  = txn_stamp                        # but stamped as "known as of day d"
```

It computes the payload on a **value_date** basis, then stamps a **txn_date** on it and claims
one row serves both lookup modes (docstring lines 13-15).

That directly contradicts the contract written into `summary_batch.py:195-200`:

> a snapshot is a point-in-time record of what was known/posted by its txn_date — the later
> backdated entry belongs to its own (later) txn_date and **must not rewrite the earlier day**

### Why EOD doing the same thing is fine and this isn't

EOD runs *on* the day. At 11:59pm on 28 July, no one has yet posted a backdated entry with a
28 July value date — so value-basis and txn-basis are the same thing. The claim holds.

The backfill runs *retroactively*. Running it today for 5 June sweeps in every July-posted,
June-value-dated entry and stamps the result "5 June". That's not what was known on 5 June.

### What it breaks, concretely

On tyger-shaped migrated data (value_date backdated to June, txn_date = the July migration run):

- **Daily POS inflates historically.** `DailyPOSHandler` reads in txn_date mode with no eligibility
  gate on the fetch (`daily_pos_handler.py:224`), so it picks the fabricated June row up and adds
  principal that hadn't been disbursed yet in book terms.
- **On EOD tenants, `--rebuild` overwrites correct snapshots.** The fabricated row carries the same
  `time.max` stamp as the real EOD row, so the tie breaks on `-updated_at` and the newer fabrication
  wins. The `value_date_invalidated` flag doesn't protect it — txn-mode reads ignore that flag by design.

### Fix

Build each basis honestly instead of stamping one with the other's date. Add
`--basis {value,txn,both}`, defaulting to `both`:

| Basis | Built with | Row shape |
|---|---|---|
| value | `DateContext.with_value_date(d)` | `value_date=d`, `txn_date=None` |
| txn | `DateContext.with_txn_date(d)` | `txn_date=stamp_book_datetime(d, ...)`, `value_date=None` |

That's 2× the build work. Skip it where it doesn't matter: if the range has no backdating at all
(`count(Transaction where book_date(txn_date) != value_date) == 0`), one complete row is provably
correct, which is the normal-operations case.

---

## Bug 3: `--rebuild` should delete, not flag

Right now `--rebuild` marks the old rows `value_date_invalidated=True` (`:228-233`) and leaves
them in the table. Two problems: the invalidation happens *before* the build, and it's in a
separate transaction from the insert. If a build throws (`:248-251` swallows it) or the process
is killed in between, that account is left with its old row invalidated and no replacement.

**Do a real delete instead.** I checked — this is safe:

- `TransactionSummary` extends `BaseModel`, which does **not** inherit `SoftDeleteModel`. There's
  no `is_deleted` column, so `.delete()` is a genuine SQL delete with no soft-delete trap.
- Nothing in the codebase has a foreign key pointing *at* `TransactionSummary`, so no cascades.

The shape:

```python
with tenant_atomic():
    TransactionSummary.objects.filter(
        account_id__in=[ts.account_id for ts in to_persist],   # only rows that got a replacement
        **book_day_filter("txn_date", d),
        value_date=d,
    ).delete()
    TransactionSummary.objects.bulk_create(to_persist, batch_size=500)
```

Two things this gets right that the current code doesn't: the delete happens **after** a successful
build, and both operations are in the **same transaction**, so there's no window where a date has
no valid row. Scoping to `to_persist` means accounts whose build failed keep their old row.

While in here, add the per-row fallback EOD already has around `bulk_create` (`eod.py:577-592`) —
right now one bad row aborts the whole command.

---

## Bug 4: the backfill never refreshes aggregates

EOD calls `queue_aggregate_summaries` for **both** date contexts after every write
(`eod.py:595-601`). The backfill writes tens of thousands of rows and never calls it once.

So anything served from `AggregatedSummary` — program summary (`product/views.py:180`), contact
summary (`contact/views.py:231`), portfolio aggregates — keeps returning pre-backfill numbers
indefinitely.

This is completely independent of Bugs 2 and 3, it's a two-line fix, and it's the most literal
match for "I ran the backfill and the reads still don't see it". **Worth doing first.**

Fix: call `queue_aggregate_summaries` per chunk/date, or add `--skip-aggregates` and document that
`recompute_aggregated_summaries` has to run afterwards.

---

## Smaller fixes worth folding in

- **`Account.latest_summary` picks the wrong row** (`product/models.py:399`). It does
  `order_by("-value_date").first()`, and Postgres sorts NULLs *first* on DESC. For an account
  holding only txn-mode rows (`value_date IS NULL`) it returns an arbitrary one. Use
  `F("value_date").desc(nulls_last=True)` plus the `latest_row_ordering` tie-break.
- **Wrong eligibility basis** in the backfill (`:144`) — `get_first_eligible_txn_dates` defaults to
  `value_date`. Fine for value coverage, wrong for the txn rows Bug 2's fix introduces. Pass it explicitly.
- `--statuses` is unvalidated: a typo silently matches zero accounts and reports success.
- `--chunk-size` is uncapped and can blow past Postgres's 65,535-parameter limit at `:213`.
- `SummaryBuildContext` uses `get_system_user()` (can return `None` against a NOT NULL
  `created_by`); management commands should use `get_or_create_system_user()` per CLAUDE.md.
- `:173` reports `len(end_by_account)` but `:268` uses `len(span_by_account)` — cosmetic mismatch.

## Things I checked and ruled out

Don't spend time on these — I verified each against the source:

- **NULL `value_date` dropping accounts** — `Transaction.value_date` is `DateField(db_index=True)`,
  not nullable (`ctm/models.py:100`). The `if first is None: continue` guard is dead code.
- **Off-by-one in the span computation** — `get_dates_between` is inclusive at both ends and all
  four closure boundaries behave correctly.
- **Missing `transaction` FK on backfilled rows** — nullable, and EOD leaves it unset too. Parity holds.
- **Closed-account coverage** — the backfill's population at `:132` matches the carry-forward gate
  in `portfolio_handler.py:1365-1382` exactly.

---

## Risks

1. **The `__in` → OR-of-ranges rewrite** (`summary_batch.py:421`) is the one change that could
   silently drop rows. Test `book_days_q` against a `__date__in` oracle: single date, contiguous
   run, gapped list, 366-day run, empty list.
2. **`DateContext` now returns datetimes, not dates.** Anything indexing the returned dict by the
   literal key `"txn_date__date__lte"` will `KeyError`. Known: `test_report_date_field.py:155,186,195`.
3. **Bug 2's fix changes what the backfill writes**, and previous runs already wrote the bad shape.
   Decide whether to re-run with `--rebuild` — and quantify Daily POS drift on tyger first, since
   that report was already reconciled against v1.
4. **Zero change for an Indian user.** When the browser tz equals `settings.TIME_ZONE` every rewrite
   is an identity, and IST has had no DST since 1945. The only difference is the query plan — worth
   attaching an `EXPLAIN` before/after on `get_summary` to the PR.

---

## How to verify

The whole bug and the whole fix, in one pair of requests — hit the same endpoint twice with
different timezone headers and assert the payloads match:

```bash
curl -H "X-Timezone: Asia/Kolkata"     ".../accounts/{id}/transaction_summary/?as_of_date=2026-07-28"
curl -H "X-Timezone: America/New_York" ".../accounts/{id}/transaction_summary/?as_of_date=2026-07-28"
```

(Local full stack per `compose/COMPOSE.md`.)

Then the existing parity gates, which must stay green through every commit:

```bash
TENANT_ALIAS=tyger pipenv run python manage.py verify_summary_build
TENANT_ALIAS=tyger pipenv run python manage.py verify_closed_summary_carry_forward
TENANT_ALIAS=tyger pipenv run python manage.py verify_closed_summary_carry_forward_txn_date
```

New tests:

- `project/lib/tests/test_book_timezone.py` — helpers return IST bounds inside
  `timezone.override("Asia/Tokyo" | "America/New_York" | "Pacific/Auckland")`; the `book_days_q` oracle.
- `project/apps/ctm/tests/test_date_context_book_timezone.py` — no DateContext test file exists
  today. Assert `from_request` returns the book "today" at 01:00 JST, and that value_date-mode
  dicts are byte-identical to before.
- `project/apps/ctm/tests/test_summary_timezone_independence.py` — **the headline test.** Write an
  EOD row stamped `stamp_book_datetime(day, time.max)`, assert `get_summary` finds it under Tokyo,
  New York and Kolkata. SOD mirror with `time.min`. Plus a write-side test that a build at
  15:00 EDT lands on the right book day.
- Fix `ctm/tests/test_summary_batch.py:188,618` — both carry comments asserting "the active
  timezone (Asia/Kolkata)", which is exactly the false assumption. Wrap the existing
  `test_txn_date_mode_keys_by_local_date_not_utc` in a `subTest` over three timezones so it proves
  *book* tz rather than merely *not UTC*.

---

## Order of work

| # | Commit | Why here |
|---|---|---|
| 1 | Backfill: `queue_aggregate_summaries` (Bug 4) | Two lines, most likely what you actually saw |
| 2 | `dates.py` + `date_filters.py` helpers + their tests | Pure addition, nothing changes yet |
| 3 | Pin `get_day_start`/`get_day_end` | Note in changelog: `lib/filters.py` + `audit/filters.py` now resolve to book days |
| 4 | `DateContext` rewrite + tests | The chokepoint |
| 5 | Summary read paths | |
| 6 | Summary write/stamp paths | **Corruption stops here** |
| 7 | Python `.date()` sweep + a CI grep guard banning `\.txn_date\.date\(\)` | The stale comments at `summary_batch.py:441-447` prove comments don't hold this line |
| 8 | Reports, EOD, management commands | |
| 9 | `SettingService.get_system_date` pinning | Isolated so it can be reverted alone |
| 10 | Backfill Bugs 2 + 3 + the smaller fixes | |
| 11 | `repair_browser_tz_summary_stamps` | **Only after 2-9 are live** |

Needs a Linear issue — branch `feature/cre-xxx-desc`, PR title `CRE-xxx: description`. The timezone
work and the backfill work are separable enough to be two PRs against `develop`.
