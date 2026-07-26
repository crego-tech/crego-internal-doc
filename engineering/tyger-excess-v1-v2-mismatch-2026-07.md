# Tyger excess money — V1↔V2 mismatch, July 2026

Closing the gap between the omni **Excess Payment Report** and V1's excess-money
figure for tyger, per the reconciliation sheet
(`Customer ID | Customer Name | Loan Account ID | Repayment Excess Amount | v2 Excess Money | Diff`,
where column 4 is V1 and column 5 is omni; `#N/A` = absent from the omni report).

Everything below was diagnosed on the local compose copy of tyger prod. Every
affected row was written by the **2026-07-19 V1→V2 load**. Live omni code cannot
produce these shapes, so this is a data repair — no report or query logic changed.

## Three causes

### 1. The money is parked; the report cannot see it

58 contact-level repayment transactions carry `txn_date = NULL`,
`status = 'pending'`, and `contact_id = NULL` on their `excess` Ledger rows.
The `excess` postings and contact-level `Demand` rows are correct and complete.

`ExcessPaymentHandler.default_date_field` is `txn_date`
(`reports/handlers/system/excess_payment_handler.py:53`), and
`DateContext.build_ledger_value_date_filter` (`ctm/date_context.py`) turns that
into `transaction__txn_date__date__lte=<as_of>`. NULL never satisfies that
predicate, so the receipt drops out silently.

Measured at `as_of_date=2026-06-03`: 288 rows on txn_date basis vs 302 on
value_date basis.

| Group acct | V1 | omni lifetime | omni txn_date basis | hidden |
|---|---:|---:|---:|---:|
| CLR97PXA | 92,565 | 92,565.00 | 97.00 | 92,468 |
| CLJYNWNA | 72,996 | 72,996.00 | 72,885.00 | 111 |
| CL8ALE5A | 61,970 | 61,970.00 | 22.00 | 61,948 |
| CL4K8L3A | 45,000 | 45,000.00 | 0 | 45,000 |
| CL3LXG3B | 23,581 | 23,581.00 | 1,251.00 | 22,330 |
| CL8W5LYA | 14,302 | 14,302.45 | 1,802.45 | 12,500 |
| CLJBYPBA | 8,334 | 8,334.00 | 0 | 8,334 |
| CLR3WZPA | 224 | 224.00 | 24.00 | 200 |
| CL4ERG2A | 205 | 205.00 | 0 | 205 |
| CL8MDLPB | 121 | 121.00 | 21.00 | 100 |
| CL36552A | 72 | 72.00 | 1.00 | 71 |
| CLR7VPJA | 62 | 62.05 | 0.05 | 62 |
| CL4WEP4A | 61 | 61.00 | 11.00 | 50 |
| CL8KLXPA | 2 | 2.28 | 0 | 2.28 |
| CL4GO83A | 1 | 1.00 | 0 | 1 |

**Fix:** `fix_contact_excess_transaction_metadata` — stamp `txn_date` from
`payment.txn_date`, set `status = processed` and `processed_at`, fill
`Ledger.contact_id`. No amount is created, changed or moved.

### 2. The remainder was never booked · 4 receipts · ₹92

Lifetime net excess is 0 and no sibling holds the money.

| Group acct | Payment | Receipt | Parked |
|---|---|---:|---:|
| CL84P73A | RECRN6BQ | 33,350 | 59 |
| CL4NAG3A | REC39MN6 | 21,54,655 | 3 |
| CLJEVNLA | RECB35OM | 5,00,000 | 29 |
| CL8QN4PA | RECPL55J | 22,46,565 | 1 |

**Fix:** `fix_missing_excess_parking` — post the missing `excess` leg on the
receipt's anchor transaction and bump the contact-level excess demand, then
re-derive counters with `fix_payment_ledger_counters`.

### 3. Paise noise · ~55 sheet rows · no action

V1 rounds receipts to whole rupees; omni keeps paise. CL48NN2A is the clearest
case: 103 payments each carrying a ±₹0.0x–0.4x residual (RECEM59W ₹0.46,
REC06NWJ ₹0.35, REC0EZWA −₹0.28 …) netting to ₹0.34 lifetime against V1's 0.
CLRD5WRA 13.30 vs 13 and CLJ5G5JA 880.88 vs 881 are the same thing.

The residuals are signed both ways, so posting them would churn 500+ ledger rows
for ₹130 of noise and still not make the sheet agree. Rounding belongs in the
report rounding config, not the ledger.

## The trap: do not park what a sibling already holds

Roughly **770 tyger receipts look short by ₹15.4 crore** on the arithmetic
`payment.amount − (used + excess + refund − tds)`. Nearly all of that is the
mirror image of a correctly-parked sibling, not missing money.

CLR97PXA is the worked example:

| Payment | UTR | Receipt | Net excess | Looks short by |
|---|---|---:|---:|---:|
| RECL7XPR | SBINR12025111305755408_1 | 75,00,000 | 0 | 92,468 |
| REC9GR75 | SBIN326079579978_1 | 92,468 | **92,468** | 0 |
| REC6WE5J | SBIN526136410764_1 | 14,900 | 97 | 0 |

V1 reports 92,565 = 92,468 + 97. Parking excess on RECL7XPR as well would read
1,85,033. The V1 load split several receipts into `_1`/`_2` rows and booked the
settled portion on one and the excess on the other; the "shortfall" on the
settled row is arithmetic, not a defect.

This is why `fix_missing_excess_parking` requires explicit `--payment-refs` and
supports `--expect REF=AMOUNT` — it must never discover its own targets.

Similarly the ≥₹100k band is a different defect again: REC0O4AZ is a ₹6.16cr
receipt whose only transaction is ₹3cr, i.e. a whole missing transaction. Left
for separate triage.

## Applying

```bash
TENANT_ALIAS=tyger pipenv run python manage.py fix_contact_excess_transaction_metadata \
  --account-refs-file sheet_accounts.txt --csv /tmp/metadata.csv          # add --apply
TENANT_ALIAS=tyger pipenv run python manage.py fix_missing_excess_parking \
  --payment-refs RECRN6BQ REC39MN6 RECB35OM RECPL55J \
  --expect RECRN6BQ=59 REC39MN6=3 RECB35OM=29 RECPL55J=1                  # add --apply
TENANT_ALIAS=tyger pipenv run python manage.py fix_payment_ledger_counters \
  --payment-refs RECRN6BQ REC39MN6 RECB35OM RECPL55J --apply
```

Both commands are dry-run by default and idempotent.

## Local result (2026-07-26)

- 19 transactions stamped across 18 sheet accounts; 4 excess postings totalling ₹92.
- Sheet oracle at `as_of_date=2026-07-31`: **83 of 84 accounts within ₹1 of V1.**
- The one miss, CLRDOAXB (V1 = 1), has no repayment excess ledger at all — it was
  absent from the report before this change too, and nothing here touched it.
- Exactly 21 group accounts changed, all of them on the sheet. No collateral movement.
- `verify_payment_ledger_consistency` over the affected receipts: only RECL7XPR
  still mismatches, which is the documented sibling case above.

## Known issues found along the way

- **`verify_payment_ledger_consistency` cannot run unscoped on tyger.** It passes
  every payment id into one `__in` clause and dies at Postgres' 65,535-parameter
  limit (76,462 payments). It needs chunking in `_ledger_totals`. Use
  `--payment-refs` until then.
- **38 of the 61 NULL-`txn_date` transactions belong to reverted payments**, 1 to a
  rejected one. Those must not be stamped `processed`; the command skips any
  receipt that is not `processed`.
- **23 group accounts outside the sheet carry the same cause-1 defect** and stay
  hidden until the allow-list is widened. The command lists them under
  "sit outside the allow-list" on every run:
  CL2DNP3B, CL2MYA2B, CL2PVQ2B, CL39A72A, CL3LRZ3A, CL3OXP3A, CL48XN3A,
  CL4NDO3B, CL84EEJA, CL86D53A, CL8AM52A, CL8M2O6A, CL8MPOPA, CL8QL2VA,
  CL8W546A, CLJBYMZA, CLJE3OLA, CLJOKL9B, CLJOYVGA, CLRDW3LB, CLRG52RA,
  CLRL6NOA, CLRZ5ZKA.
