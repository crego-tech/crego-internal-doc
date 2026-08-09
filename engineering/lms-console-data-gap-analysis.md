# LMS Console — Data Availability & Conditional-State Analysis

Companion to `lms-console-design.html`. For every element the mock shows, this answers:
is it stored (✓), derivable (⚙), or missing (✗) in crego-omni — and how each enum/flag value
changes the page. Sources: `product`, `ctm`, `transfer`, `schedule`, `gl`, `invoice`, `addon`,
`contact`, `collect` apps.

Legend: **✓ stored** (read directly) · **⚙ derived** (computable from stored data, needs an
endpoint or client logic) · **✗ missing** (not in the model — change design or add data).

---

## 1. Cross-cutting findings (the big ones)

**G1 · Running balances (was → Δ → now) are not stored.**
`Ledger` stores only the delta (`amount`); `Demand` stores only the *current* cumulative
buckets. The popover values "was/now" must be produced one of two ways:
- Replay ledgers in canonical order `(value_date, sequence, id)` and emit running values —
  needs a backend endpoint (recommended) or client-side replay of `/ledgers?account=`.
- Use `TransactionSummary` (OneToOne per transaction): closing = this txn's snapshot,
  opening = previous txn's snapshot. Caveats: populated only for `active`/`written_off`
  accounts (`summary_population_q`), and `value_date_invalidated=True` after backdated
  entries → UI must show a "recompute pending" state instead of stale numbers.

**G2 · "Upfront Δ" per business event is an approximation.**
Upfront interest earns down via *daily accrual* transactions, not at repayment/fee events.
The per-event delta shown in the activity strip = Σ of upfront `accrued` ledgers between two
events. Data exists (Ledger: component category `upfront_interest`, posting `accrued`), but
needs date-range aggregation. Alternative: show the daily accruals as collapsed "n accrual
runs · ₹x" rows.

**G3 · A term loan cannot sit under an SCF Account.** `AccountSerializer.validate` forces a
child's contact/product/program to equal the parent's; SCF products *require* a parent,
term loans have none. The mock has been corrected: `LN-TL-0098` now appears only at contact
level; the Account page scopes risk/totals to its own 3 SCF loans.

**G4 · Contact identity is EAV, not columns.** `Contact` has only name, ref_id, status,
contact_type, tags, refs, branch, `rm_code`. PAN/GST/legal name/constitution come from
`ContactProps` (`pan_no`, `gst_no`, `legal_name`, `constitution`, `business_nature`,
`registration_date`…). **Phone and email are not first-class fields** (✗ — props/refs or
drop from design). "RM name" ✗ — only `rm_code`; needs a join to the ops user directory.
CIN ✗ — only via `refs`.

**G5 · NACH mandate and payment-batch linkage live in connectors.** There is **no FK from
`Payment` to `PaymentBatch`**; presentation linkage is via vendor rows in `connectors`.
Mandate cap/expiry shown on the contact page must come from connector metadata (⚙).

**G6 · Behavioural stats are computable, not stored.** "On-time rate", "avg delay",
"collected lifetime/12mo" — derive from `Schedule.last_paid_at` vs `due_date` and paid
ledgers. Fine, but each needs an aggregate endpoint; nothing to read directly.

**G7 · Excess wallet balance is derived.** `PaymentService.get_details` recomputes
`excess = Σexcess − (Σsettled + Σrefunded)` from ledgers (excluding `upfront_interest`,
`colending_fee`, non-`main` sharing). The demand's stored counter can lag; always show the
ledger-derived number.

---

## 2. Page-by-page

### 2.1 Account page

| Element | Backing | Status | Conditions / notes |
|---|---|---|---|
| Header status badge | `Account.status` | ✓ | 10 statuses — see §3.1 |
| Limit tiles + utilisation bar | `addon.Limit` | ✓ | invariant `approved = available + used + blocked`; **multiple limits possible** (primary + adhoc) → bar per limit or merged; no Limit row → hide card |
| Loans table | `sub_accounts` + `latest_summary` | ✓/⚙ | outstanding comes from `TransactionSummary.outstanding_details` — **null for closed/pre-active loans** → render "—", not ₹0 from a missing snapshot |
| Excess wallet card | contact-level `Demand` + ledgers | ⚙ | G7; wallet is *contact*-scoped — shown on Account page as convenience, label it so |
| Upfront cashback pool | `upfront_interest_details` helper | ✓ | `available_cashback` is status-gated (source loans must be closed/foreclosed) |
| Money movements | `GET /transactions/allocations` | ✓ | groups by UTR; refunds included. NACH EMI row (UTR498232771N) is contact-scope — filter to Account scope or label |
| Risk card | `AggregatedSummary` | ✓ | has `is_stale` flag → show "as of" + stale badge; `includes_sub_programs`, `sharing_type`, `partner_id` variants exist |
| Aggregated summary card | `AggregatedSummary(account)` | ✓ | refreshed async — always show `as_of_date` |
| Action buttons (Repay/Statement) | `AccountStatusTxnCodeMap` | ✓ | enable/disable per status — e.g. repayment only in `active`/`written_off`; mock has static buttons → wire to map |

Not shown but available: `sharing_type=shared` mirror accounts + `partner` (co-lending),
`AccountContactRelation` (guarantor/co-borrower), `active_payment_link`, `tags`/`refs`,
`branch`, `Program → ProgramPartner` hierarchy.

### 2.2 Loan page

| Element | Backing | Status | Conditions / notes |
|---|---|---|---|
| Stat tiles | `latest_summary` blobs | ✓ | absent for `draft/requested/rejected` → show application panel instead |
| Upfront card | `AccountProps` (`upfront_*`) + upfront demand | ✓ | **SCF only** — `calculate_upfront_interest_details` returns `{}` for non-SCF → hide card for term loans |
| Cross-loan settlement section | `Transaction(payload.upfront_settle_details)` + ledgers | ✓ | render only if such txns exist; ledger convention: `demand`=source, `account`=destination |
| Activity impact strips | Transactions + ledgers + summaries | ⚙ | G1/G2. `pending/processing` txns → dashed row, no strip; `failed` → error from `TransactionBatchItem.error_class/message`; `reversed` → strikethrough + link to reversal |
| Popover ledger tables | Ledger + Demand | ⚙ | G1 — was/now requires replay or snapshots |
| Loan facts | `AccountProps` | ✓ | keys differ by product (EMI: `emi_amount`, `frequency`, `schedule_count`; SCF: `upfront_*`) → render only present keys |
| Demands card | `Demand` per component | ✓ | `Net O/s = amount − (settled+waived+refunded+excess+paid+accrued+tax o/s)` |
| Limit linkage | `LoanAndLimitLink` | ✓ | endpoint exists: `/accounts/loans/{id}/loan-limit-links` |
| Restructure actions (tenure/EMI change, foreclose) | `TxnCode` availability | ✓ | **term_loan only** — SCF processors expose none of these → hide buttons for SCF |
| EMI schedule table | `Schedule` + `Demand` | ✓ | `tags` bpi/pre_emi not rendered → add chips; `suspended` status (NPA) needs a style |

### 2.3 Contact page

| Element | Backing | Status |
|---|---|---|
| Name / status / type / branch | `Contact` | ✓ |
| PAN, GSTIN, legal name, constitution | `ContactProps` | ✓ (EAV) |
| Phone, email, CIN, "RM name", "since" | — | ✗ (props/refs only; rm_code exists, not name) |
| Bank accounts + tags | `ContactBank` (account_no, ifsc, holder, tags) | ✓ |
| NACH mandate cap/expiry | connectors app | ⚙ (G5) |
| Address | `ContactAddress` (line, city, state, pincode, geo) | ✓ — mock shows free text; model is structured |
| Accounts & loans tree | `Account` by contact | ✓ |
| Collections | `CollectionEnquiry` (ptp, promised, payment FK, geo, selfie) | ✓ |
| Aggregated summary | `AggregatedSummary(contact)` | ✓ |

Not shown but available: `ContactRelation` (related entities), soft-delete state,
`bureau_country_status`, per-contact GL accounts (lender-specific `GLAccount.contact`).

### 2.4 Payment page

| Element | Backing | Status | Conditions |
|---|---|---|---|
| Header amounts (used/excess/refund/tds) | `Payment` counters + ledger recompute | ✓/⚙ | invariant `amount = used+excess+refund−tds` enforced **only for `processed` after 2026-03-12** → show the "✓" badge conditionally |
| Date triplet + narration | `Payment` | ✓ | `value_date ≤ txn_date`, never future — violations impossible, no state needed |
| Waterfall steps + ordering | `get_settlement_details` + loan-order annotation | ✓ | order = program config `default_loan_order_for_settlement` (`loan_end_date` default, `upfront_interest_end_date` alt); per-payment override via `payload.settlement_order` — show which rule applied |
| Component split popovers | settlement-details `components[]` | ✓ | includes tax per component |
| Excess lifecycle | excess demand ledgers + EPS txn (`payment` FK) | ✓ | |
| Payment status | 6 values | ✓ | §3.2 — `requested`: no waterfall, show queue position from `TransactionBatchItem`; `reverting/reverted`: revert_remark + reversal txns; `rejected`: rejection_reason |
| payment_type | 4 values | ✓ | `*_fee_settlement` types target programs/contacts, **no loan expansion** → waterfall must switch to fee-demand layout |
| Co-lending split | `colending_split` in settlement-details, `parent`/`shared_payments` | ✓ **not shown** | add an IFT pane: child payments, lender/co-lender split, `initiate-ift-transfer` action |
| Banks | `source_bank`/`destination_bank` | ✓ | nullable → hide row |

### 2.5 Payout page

| Element | Backing | Status | Conditions |
|---|---|---|---|
| Origination chain | `Drawdown` (OneToOne payout) → `DrawdownItem` → Invoice/PO/Vehicle | ✓ | chain exists **only for drawdown-origin SCF payouts**; `payout_type` refunds → hide chain. `item_type` has 3 variants — mock shows only `invoice`; PO (po_number, expiry, fulfilled) and Vehicle (registration, chassis, insurance) need their own chain cards |
| Gross → net table | `deducted`/`tax_deducted` ledgers | ✓ | |
| Status path | 8 statuses | ✓ | §3.3 — `send_to_bank→failed` shows `failure_remark`; `rejected` shows `rejection_reason` |
| Batch card | `PayoutBatch` | ✓ | `payment_reference_no` unique; constraint: one `open` batch per (program, destination_bank) → "open batch, will be picked up" state; `retry_count`, `last_status_check_at` for ops |
| Multi-tranche | `tranche_disbursement` TxnCode + `is_multi_tranche` config | ✓ **not shown** | tranche list per loan when flag on |

### 2.6 Transactions page

Mostly ✓. Gaps: no `pending/processing/failed` rows in mock (data exists, incl. batch-item
errors); `sequence` column hidden (needed to explain same-date ordering); `main_transaction`
(co-lending split) column absent; `payload` JSON viewer absent (it's the escape hatch that
explains upfront settles, fee additions, TDS). Filters should be driven by helper sets:
`payment_related_txn_codes()`, `fee_codes()`, `reversible_txn_codes()`.

### 2.7 Demands page

All buckets ✓. Conditions to add: `DemandStatus` has 11 values — mock renders 5; missing
`upfront_deducted`, `upfront_deferred`, `partially_waived`, `cancelled`, `partially_paid`
badge styles. `type=payable` (excess wallet) vs `receivable` → sign convention. `level` has
7 values → icon per level. `parent/children_demands` (restructure lineage) not rendered.

### 2.8 Ledger & GL page

Business ledger + GL drill-down ✓ (`GLEntry.entry_type` is where debit/credit lives;
`ComponentGLMapping` resolves DR/CR accounts per component × posting_type × txn_code —
the "posting types" reference card should be *driven by this table*, not hardcoded).
Available but not shown: `JournalVoucher`/lines (manual entries, `utr`, reversal chain),
`FinancialPeriod` open/closed/locked (blocks backdating → banner on value-date pickers),
`PostingBatch` statuses incl. `partially_completed` + `error_summary`,
`synced_with_tally` per item, `GLRefIdGeneration` voucher patterns.

---

## 3. Enum → UI matrices

### 3.1 AccountStatus (10)
| Value | Header | Page behaviour |
|---|---|---|
| draft / requested | grey/blue | application layout; no summary, no ledgers; show approval trail |
| failed / rejected | red | show `rejection_reason`; read-only |
| active | green | full page; actions from `AccountStatusTxnCodeMap` |
| closed / foreclosed | grey | frozen; upfront excess panel if `excess > 0` (settle/refund CTAs) |
| settled_off / written_off | amber/red | written_off still allows repayment (+ `run_accrual` prop) & shows `npa_marked_date`, `income_suspended` |
| reverted | grey | link reversal transactions |

### 3.2 PaymentStatus (6)
requested → banner "awaiting processing" (no txns yet) · processing → progress via
`TransactionBatchItem` · processed → full waterfall · reverting/reverted → red banner,
`revert_remark`, reversal txns · rejected → `rejection_reason`, no financial effect.

### 3.3 PayoutStatus (8)
requested → approve/reject CTAs · send_to_bank → "at bank" + batch link · failed →
`failure_remark` + retry CTA · processing/processed → chain + txns · reverting/reverted /
rejected → reasons, greyed chain.

### 3.4 TransactionStatus (6)
pending/processing → dashed strip, no balances · processed → full impact strip ·
failed → error panel (batch item) · reversed → strikethrough, link both directions ·
rejected → reason only.

### 3.5 PostingType (17) → demand bucket
outstanding↑ · accrued↑(+outstanding) · paid↑(−outstanding) · tax/tax_paid ·
hold↑ (upfront parked) · deducted/tax_deducted (settled at source) · excess↑ (unallocated) ·
settled (excess consumed) · waived/tax_waived (−outstanding) · refunded (−excess) ·
write_off · npa_income_suspension · tds_deducted · not_set. Reference card on Ledger page
shows a live example of each.

### 3.6 Product type & flags
| Flag | Source | UI effect |
|---|---|---|
| term_loan | `Product.product_type` | schedules/EMI, restructure codes, TL accrual (`month_end/due_date_tl_accrual`); no upfront |
| scf_sid/pid/vf/df | 〃 | mandatory parent Account, invoice/PO/vehicle chains, upfront interest, bullet demands |
| is_secondary | `Product` | txns processed inline (no batch queue view) |
| is_multi_tranche | `addon.Config` | tranche list + `tranche_disbursement` |
| is_schedule_based | `addon.Config` | schedule grid vs bullet layout |
| sharing_type / ProgramPartner | `Account`/`Program` | co-lending panes: mirror rows, split txns (`main_transaction`), IFT payments/payouts |
| get_cashback_on_repayment | config `common_settings` | enables upfront hold→excess release & cross-loan settle UI |

---

## 4. Shown-but-fabricated (fix or derive)

| Mock element | Verdict |
|---|---|
| Phone / email / CIN / RM name / "Since Nov 2024" (contact) | ✗ → drop or move to props/refs; use `rm_code` |
| "On-time rate 86% · avg delay 2.1d" | ⚙ compute from schedules |
| NACH cap "₹1,50,000 · till Mar 2028" | ⚙ connector metadata |
| "Collected lifetime / 12 mo" | ⚙ ledger aggregate |
| Opening/closing per event | ⚙ G1 (snapshots or replay) |
| Per-event upfront Δ | ⚙ G2 (aggregate daily accruals) |
| Static action buttons | ⚙ drive from `AccountStatusTxnCodeMap` |

## 5. Available-but-unshown (top opportunities)

Co-lending everywhere (splits, IFT, partner GL) · tags & refs chips + external-refs panel
in the drawer · narrations/remarks on all money objects · TransactionBatch queue/ops view
(error_class, counts) · guarantors & co-borrowers · PO/Vehicle finance chains ·
NPA/SMA visuals (RBIAssetCategory STD→SMA0/1/2→NPA as a severity scale) · journal vouchers ·
financial-period lock banner · payment link on account · collect selfie/geo evidence.

## 6. Recommended backend additions

1. **Ledger replay endpoint**: `/accounts/{id}/ledger-statement` returning each posting with
   `before/after` per demand bucket in `(value_date, sequence, id)` order — powers G1
   popovers exactly as designed.
2. **Upfront earn-down aggregate** between arbitrary dates (G2).
3. Expose the **resolved settlement order** (config cascade result) on settlement-details.
4. First-class phone/email on Contact (or bless specific props) if the contact 360 ships.
