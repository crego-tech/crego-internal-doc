# `develop`: `AccrualHelper.is_eod_summary_for_date` deleted by a hotfix merge

**Found:** 2026-08-18, while investigating why crego-omni's `Coverage` job is red (CRE-6236)
**Severity:** P0 on `develop`. Production (`master`) is **not** affected.
**Status:** not yet raised in Linear — the Linear connection was pointed at a different
workspace when this was written. Raise it against the Tech team / Platform project.

## The problem

`AccrualHelper.is_eod_summary_for_date()` is called from 8 places and does not exist.

| File | Calls |
|---|---|
| `project/apps/ctm/services/summary_batch.py` | 3 (≈174, ≈261, ≈427) |
| `project/apps/ctm/services/transaction_summary.py` | 5 (incl. ≈1815) |

Every one raises `AttributeError: type object 'AccrualHelper' has no attribute
'is_eod_summary_for_date'` at runtime. These are EOD / transaction-summary build paths —
core financial processing.

| Branch | method defined | call sites | state |
|---|---|---|---|
| `origin/master` (prod) | 0 | **0** | consistent — CRE-6184 never reached master |
| `origin/develop` | 0 | **8** | **broken** |

`develop` auto-deploys to the internal dev environment, so EOD summary building is broken
there now.

## How it happened

`d6ced5cd0` (CRE-6184, "Implement EOD summary logic in TransactionSummary and
AccrualHelper", #1559) added **both** the method in `ctm/helpers.py` and all 8 call sites.
It went to `develop` and never to `master`.

A hotfix branch (`hotfix/eod-last-accrual-type`, commit `57ba9d2bd`, "Enhance AccrualHelper
to include as_of_date parameter in get_last_accrual_eod method") was branched from
**`master`**, which never had CRE-6184, and edited the same file. Coming back into
`develop` — `919a45afa` → `ee41c4e98` (#1595) → `36fe4cefd` → `ddfbcc261` (#1612) — the
merge resolved `helpers.py` in favour of the master-based version, silently dropping
`is_eod_summary_for_date` while leaving all 8 callers behind.

Verified: the method is present in `d6ced5cd0`'s tree and absent from `57ba9d2bd`'s.

## Fix

Restore the method from the commit that added it:

```bash
git show d6ced5cd0 -- project/apps/ctm/helpers.py
```

It is ~13 lines. Whoever owns CRE-6184 should confirm the restored logic still lines up
with the current `get_last_accrual_eod(account_id, as_of_date)` signature, which the
hotfix changed **in the same class**. Those two changes were never reconciled — that is
the actual hazard, not the missing method on its own.

## Why nobody noticed

`Coverage` has been failing on crego-omni for weeks, so a 50-error regression inside it
produced no signal at all. That is precisely the failure mode CRE-6236 exists to remove.
Worth pairing the fix with a decision about making `Coverage` a required check once the
suite is green.

## The rest of omni's red suite

The same run showed 9 failures and 93 errors. Recorded here so they are not lost:

| Cluster | Count | Nature |
|---|---|---|
| `is_eod_summary_for_date` missing | 50 | This issue |
| `Setting.objects.latest_active()` returns `None` in `authz/tests/test_customer_token_exchange.py` setUp | 26 | Missing fixture |
| `ValueError: No financial period found for date 2026-08-15/16` | 15 | Date-dependent tests; break again whenever the calendar passes the configured periods |
| Stale tests calling `_get_group_max_dpd_map` (renamed to `_get_contact_max_dpd_map` in CRE-6247) | 7 | Tests not updated |
| `get_last_accrual_eod() missing 1 required positional argument: 'as_of_date'` | 3 | Callers not updated after `57ba9d2bd` |
| Assorted assertion failures | 9 | Various |

## crego-web, for the same reason

`Lint and Format Check` fails on both web packages, also pre-existing on `develop`:

- **omni-web** — 113 `tsc` errors (eslint: 46 warnings, 0 errors; formatting clean as of CRE-6236)
- **flow-web** — 17 eslint errors, all React Compiler rules (`react-hooks/set-state-in-effect`,
  `/refs`, `/preserve-manual-memoization`) across `FieldAddress`, `FieldBank`, `WidgetIfsc`,
  `WidgetSelect2`, `HealthCheck` and two others. These need component restructuring, not a
  formatter.
