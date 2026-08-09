# PRD — Operating Lease Product (Crego Omni)

**Status:** Draft for review
**Author:** Abhishek
**Date:** 29 Jul 2026
**Source of truth for economics:** `Operating Lease.xlsx` (Sheet1 + Restructuring)
**Perspective:** Omni is the **lessor's** system of record. Lessee-side entries are documented for reference/reconciliation only and are not posted by Omni.

---

## 1. Problem & Opportunity

Omni today models **credit** products — Term Loan and the SCF family. Every one of them shares an assumption baked into the schedule engine, the demand model and the GL mappings: the borrower owes **principal + interest**, and the financed asset (if any) sits on the borrower's books as security.

An **operating lease** breaks that assumption in three ways:

1. **The asset never leaves the lessor's balance sheet.** Omni must run a fixed-asset register and a straight-line depreciation schedule that converges to a residual value — something Omni has no concept of today.
2. **There is no principal/interest split to the customer.** The customer is billed a single **lease rental**, and the whole rental is **income**, not partly a balance-sheet repayment. Interest and principal are computed internally *only* to roll the outstanding balance forward and to price restructures.
3. **The full rental attracts GST**, not just the fee components. Today GST in Omni is a per-component `tax` flag applied mostly to fees; here it applies to 100% of the billed amount, every cycle, for the life of the lease.

Without this, equipment-leasing, fleet and asset-as-a-service lenders cannot be onboarded onto Omni at all, and we lose deals to point solutions.

### Goal

Ship an **Operating Lease** product type in Omni that supports the complete lifecycle — product configuration, lease booking, rental scheduling, GST invoicing, collections and allocation, restructuring, and end-of-lease/termination — with correct lessor accounting for every scenario documented in the source workbook.

### Non-goals (this phase)

- Finance lease / hire purchase (asset transfers to lessee; different Ind AS 116 treatment).
- Lessee-side books (Right-of-Use asset, lease liability under Ind AS 116). We *display* lessee entries as reference only.
- Sub-leasing and lease novation.
- Asset telematics / usage-based rentals.
- e-Invoice (IRN) and e-Way Bill generation — assumed handled by the existing invoicing integration path.

---

## 2. Personas

| Persona | Needs |
|---|---|
| **Product Manager (Lessor)** | Define lease products: tenure, rental frequency, implicit rate, residual value policy (guaranteed/non-guaranteed), depreciation method, GST rate, penal charges. |
| **Credit / Ops Officer** | Book a lease against a specific asset, preview the rental, generate the schedule, disburse to the vendor. |
| **Billing Officer** | Run the monthly rental billing cycle, issue GST invoices, issue credit notes for service deficiency. |
| **Collections Officer** | Allocate receipts, handle short payments and excess payments, track DPD, trigger repossession. |
| **Finance / Accounts** | Get correct, balanced GL entries for every lease event; run depreciation; reconcile the asset register to the GL; close periods. |
| **Asset / Fleet Manager** | Track physical asset, insurance, NBV, and manage end-of-lease disposal or renewal. |

---

## 3. Product Concept

### 3.1 The economics (worked example, verified against the workbook)

| Input | Value |
|---|---|
| Asset Value (capitalised cost) | ₹10,00,000 |
| Residual Value (RV) | ₹2,00,000 |
| Implicit rate (ROI) | 12.00% p.a. |
| Payment frequency | Monthly (12/yr) |
| Tenure | 7 years (84 rentals) |
| Rental timing | Arrears (`0`) — advance (`1`) also supported |

**Derived**

| Output | Value | Basis |
|---|---|---|
| **Lease Rental** | **₹16,122.19** | `PMT(rate=12%/12, nper=84, pv=10,00,000, fv=-2,00,000)` |
| GST @ 18% | ₹2,901.99 | On the full rental |
| **Total billed / cycle** | **₹19,024.18** | Rental + GST |
| Depreciation / month | ₹9,523.81 | Straight line: `(10,00,000 − 2,00,000) / 84` |

The RV is the `FV` term in the annuity. This is the single most important formula difference from Term Loan, where `FV = 0`.

**Schedule behaviour (internal columns):** opening balance amortises from ₹10,00,000 and converges to **exactly the residual value ₹2,00,000** at instalment 84 — it does not go to zero. Interest = `opening × ROI/12`; principal = `rental − interest`; closing = `opening − principal`.

| # | Opening | Interest | Principal | Closing | Rental | GST | Total |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 10,00,000.00 | 10,000.00 | 6,122.19 | 9,93,877.81 | 16,122.19 | 2,901.99 | 19,024.18 |
| 12 | 9,29,185.68 | 9,291.86 | 6,830.33 | **9,22,355.35** | 16,122.19 | 2,901.99 | 19,024.18 |
| 84 | 2,13,982.36 | 2,139.82 | 13,982.36 | **2,00,000.00** | 16,122.19 | 2,901.99 | 19,024.18 |

> **Customer-facing rule:** interest and principal are **internal only**. The invoice, the statement and the customer app show **Lease Rental + GST**. Interest/principal columns are visible to Ops/Finance for restructure pricing and outstanding computation, and must be labelled as such in the UI.

### 3.2 Residual Value policy

Configured per product, overridable per lease:

- **Non-guaranteed** — lessor bears the risk. If the asset sells below RV at end of lease, the lessor books a loss on sale. No claim on the lessee.
- **Guaranteed** — the lessee makes good any shortfall between realised sale value and RV.
  *Example:* RV ₹2,00,000, asset sold for ₹1,60,000 ⇒ ₹40,000 recoverable from lessee (`Lessee Receivable Dr / Recovery Income Cr`).

### 3.3 Depreciation

- Method: **Straight line** (phase 1). WDV is a phase-2 configuration option.
- Base: `(Asset Value − Residual Value) / total periods`.
- Posted monthly as an accrual event; accumulated depreciation is deducted from asset value so **NBV converges to RV** on the same curve as the schedule closing balance.
- Depreciation runs on the **asset**, independently of whether the customer paid. If a lease goes delinquent, depreciation continues (and must be caught up at repossession).

---

## 4. Lifecycle & Workflow

```
Product Setup ──▶ Lease Application ──▶ Credit / Approval ──▶ Asset Onboarding
                                                                    │
                                                                    ▼
                                       Booking & Disbursement to Vendor (asset capitalised)
                                                                    │
                                                                    ▼
                             ┌───────────────  Live Lease  ───────────────┐
                             │  Monthly cycle:                            │
                             │   1. Rental due (schedule)                 │
                             │   2. GST invoice raised                    │
                             │   3. Depreciation accrued                  │
                             │   4. Receipt + allocation                  │
                             │   5. DPD / penal (penal also attracts GST) │
                             └────────────────────────────────────────────┘
                                    │                │                │
             ┌──────────────────────┘                │                └────────────────┐
             ▼                                       ▼                                 ▼
      Restructuring                       Waiver / Credit Note                 Delinquency
  (tenure / ROI / RV /                   (service deficiency;                        │
   moratorium / prepay)                   GST reversed pro-rata)              Repossession
             │                                       │                                │
             └──────────────────┬────────────────────┘                                │
                                ▼                                                     ▼
                        End of Lease                                        Write-off unpaid rentals
                  ┌──────────┬──────────┬─────────────┐                     Catch-up depreciation
                  ▼          ▼          ▼             ▼                     Sell asset → loss/gain
              Return &    Renew /    Lessee        RV shortfall
              Sell asset  Re-lease   purchase      claim (if guaranteed)
```

### 4.1 Lease account states

Reuses the existing `AccountStatus` ladder, with lease-specific meaning:

`draft → requested → active → (foreclosed | closed | written_off | repossessed*)`

`repossessed` is a **new** terminal-adjacent state to be added: the customer relationship is closed but the asset disposal and shortfall recovery are still open.

---

## 5. Functional Requirements

### FR-1 — Product Configuration

The Product Manager configures an Operating Lease product with:

| Group | Fields |
|---|---|
| **Lease terms** | Tenure (value + unit), rental frequency (monthly/quarterly/half-yearly/yearly), rental timing (**arrears / advance**), implicit rate (ROI), days-in-year / days-in-month conventions, rounding. |
| **Asset & RV** | Residual value basis (% of asset cost \| absolute), RV type (**guaranteed / non-guaranteed**), depreciation method (SLM), depreciation start (capitalisation date \| lease start). |
| **Components** | `lease_rental` (mandatory), `security_deposit`, `advance_rental`, `penal_charge`, `maintenance_fee`, `insurance_recovery`, `documentation_fee`, `residual_value`, `recovery_income`. Each with value type, capping, settlement mode, and **GST rate**. |
| **Tax** | GST enabled on `lease_rental` **and** `penal_charge` by default (workbook: *"Penal charges will always attract GST"*). Rate configurable; place-of-supply drives CGST+SGST vs IGST. |
| **Repayment** | Settlement waterfall order across components; excess-payment treatment (**advance from lessee**, default); short-payment treatment. |
| **DPD & penal** | DPD buckets, NPA thresholds, penal rate/basis, grace period. |
| **Restructuring** | Which levers are permitted (tenure / ROI / RV / moratorium / prepayment), prepayment lock-in, prepayment charge. |

**AC-1.1** A product cannot be activated unless `lease_rental` exists, has GST configured, and appears in the settlement order.
**AC-1.2** Changing RV, ROI, tenure or frequency on the product re-prices only **new** leases; live leases are untouched.
**AC-1.3** The config screen shows a **live rental preview** (rental, GST, total, depreciation/month) as the user edits terms.

### FR-2 — Lease Booking

**AC-2.1** Ops selects lessee, product/program, and enters asset details (description, category, vendor, invoice value, capitalisation date, registration/serial number, insurance).
**AC-2.2** System computes and displays: lease rental, GST, total per cycle, depreciation/month, RV, and the first/last rental dates — **before** commitment.
**AC-2.3** Ops may override the computed rental; the system then **solves for the implied rate** and displays it, flagging any deviation beyond a configured tolerance for approval.
**AC-2.4** On activation, the asset is **capitalised on the lessor's books** and the full rental schedule is generated.
**AC-2.5** Security deposit and advance rentals, if configured, are collected/deducted at booking and shown in the disbursement summary.

### FR-3 — Rental Schedule

**AC-3.1** Schedule shows, per instalment: #, start date, due date, opening balance, interest, principal, closing balance, lease rental, GST, total (incl. GST), status, paid, outstanding, DPD.
**AC-3.2** Closing balance at the final instalment equals the residual value exactly (tolerance ≤ ₹1 after rounding).
**AC-3.3** Rentals in **advance** shift the due date to the start of the period and the first rental is due on the lease start date.
**AC-3.4** Ops can export the schedule (XLSX/PDF) and the customer-facing version **hides** interest/principal.
**AC-3.5** A schedule can be previewed without persisting (booking screen, restructure screen).

### FR-4 — Invoicing & GST

**AC-4.1** On each due date, the system raises a **tax invoice**: taxable value = lease rental, tax = GST, total = rental + GST.
**AC-4.2** Place of supply determines the split: intra-state ⇒ CGST 9% + SGST 9%; inter-state ⇒ IGST 18%. Lessor GSTIN state vs lessee state.
**AC-4.3** Penal charges levied in a cycle are added to the same invoice with GST applied.
**AC-4.4** **Credit note** for service deficiency: full or partial waiver of a rental. GST is reversed **in the same proportion** as the taxable value.
**AC-4.5** Credit note behaviour depends on whether the invoice was already paid:
- *Unpaid* → reverse receivable (`Lease Income Dr`, `Output GST Dr`, `Lessee Receivable Cr`).
- *Paid* → create a customer payable, then **refund or adjust** against future rentals; Ops chooses.

**AC-4.6** Invoices are immutable once issued; corrections are made only via credit note.

### FR-5 — Collections & Payment Allocation

**AC-5.1** A receipt is allocated per the configured waterfall across `penal_charge → maintenance/other → lease_rental (+GST)`.
**AC-5.2 — Short payment.** *Workbook: lessee pays ₹10,000 against ₹19,024.18.* The invoice remains open for ₹9,024.18; the balance stays as `Lessee Receivable`; DPD starts accruing from the due date. **No** partial GST reversal — the full GST was already recognised at invoice.
**AC-5.3 — Excess payment.** *Workbook: lessee pays ₹20,000 against ₹19,024.18.* The excess ₹975.82 is booked as **`Advance from Lessee`** (a liability), not as prepayment of principal. On the next due date it is auto-applied against the new receivable, and any further excess again goes to advance.
**AC-5.4** Ops can see, per lease, an **allocation trail** showing which receipt settled which demand and which component.
**AC-5.5** Advance-from-lessee balances are visible on the lease summary and in the customer statement.

### FR-6 — Restructuring

Lease rentals only change when one of five things changes (per the workbook):

1. Tenure 2. ROI 3. Residual Value 4. Moratorium 5. Prepayment (if contractually allowed)

**Method:** take the outstanding balance at the restructure effective date and re-solve the annuity for the remaining term.

**AC-6.1 — Re-pricing.** *Example: after 12 rentals, O/S = ₹9,22,355.35, new RV ₹3,00,000, remaining 72 months, ROI 12%* ⇒ **new rental ₹15,167.17**.
**AC-6.2 — Prepayment, Case 1 (tenure unchanged).** *Prepay ₹1,00,000 ⇒ O/S ₹8,22,355.35, 72 months, RV ₹2,00,000* ⇒ **new rental ₹14,167.17**.
**AC-6.3 — Prepayment, Case 2 (rental unchanged).** Solve for tenure ⇒ **58.40 months**. A fractional period is not payable, so the system bills **58 full rentals** (leaving a balance of ₹2,05,550.66) and a **59th stub rental of ₹7,606.16** that lands the closing balance exactly on the residual value. The stub must be shown explicitly in the redrawn schedule.
**AC-6.4** Restructure produces a **before/after comparison** (rental, tenure, RV, total outflow, total GST) that must be explicitly approved before the schedule is redrawn.
**AC-6.5** Moratorium: rentals are paused for N periods; the interest accrued during the moratorium is capitalised into the outstanding and the schedule is redrawn for the remaining term.
**AC-6.6** All past (settled) instalments are frozen; only future instalments are regenerated. The old schedule is retained for audit.
**AC-6.7** Restructuring is blocked when a lease is in `written_off` or `closed`.

### FR-7 — Asset Register, RV Realisation & Termination

**AC-7.1** Asset register per lease: cost, capitalisation date, accumulated depreciation, **NBV**, RV, insurance and registration details, physical status (with lessee / repossessed / in yard / sold).
**AC-7.2** Monthly depreciation runs as a scheduled job for every active leased asset; NBV converges to RV at lease end.
**AC-7.3 — End of lease, options:** (a) return & sell, (b) renew / re-lease at a fresh RV, (c) lessee purchases at RV.
**AC-7.4 — RV shortfall (guaranteed RV).** *Example: RV ₹2,00,000, sold for ₹1,60,000.* Lessor books ₹40,000 as `Lessee Receivable / Recovery Income` and raises a demand on the lessee. If **non-guaranteed**, the ₹40,000 is a `Loss on Asset Sale` and no demand is raised.
**AC-7.5 — Repossession.** *Workbook scenario: lessee stops paying after 12 months.*
- Catch up depreciation to date (₹1,14,285.71 for 12 months) ⇒ NBV ₹8,85,714.29.
- Write off unpaid rentals (₹20,000) as bad debt.
- On resale at ₹7,50,000 ⇒ **loss on sale ₹1,35,714.29**.
**AC-7.6** Foreclosure: lessee settles all remaining rentals (+ RV or foreclosure charge per config) before term end; asset ownership transfer is recorded.

### FR-8 — General Ledger

**AC-8.1** Every lease event produces a **balanced** journal, posted through the existing GL posting-batch pipeline.
**AC-8.2** GST posts to CGST/SGST/IGST accounts based on place of supply.
**AC-8.3** Ops/Finance can preview the journal for any event **before** it posts, and drill from a GL entry back to the lease, schedule row and demand.
**AC-8.4** The screen offers a **Lessee (reference)** toggle showing the mirror entries the lessee would pass — display only, never posted.

---

## 6. GL Event Catalogue (Lessor — Omni posts these)

Amounts from the worked example.

| # | Event | Dr | Cr | Amount |
|---|---|---|---|---|
| 1 | **Asset capitalisation** (booking) | Leased Asset | Vendor Payable / Bank | 10,00,000.00 |
| 2 | **Rental invoice raised** | Lessee Receivable | — | 19,024.18 |
| | | — | Lease Income | 16,122.19 |
| | | — | Output GST (CGST+SGST / IGST) | 2,901.99 |
| 3 | **Receipt in full** | Bank | Lessee Receivable | 19,024.18 |
| 4 | **Depreciation (monthly)** | Depreciation Expense | Accumulated Depreciation | 9,523.81 |
| 5 | **Short payment** (₹10,000 received) | Bank | Lessee Receivable | 10,000.00 |
| | *balance ₹9,024.18 stays open, DPD accrues* | | | |
| 6 | **Excess payment** (₹20,000 received) | Bank | Lessee Receivable | 19,024.18 |
| | | — | Advance from Lessee | 975.82 |
| 7 | **Advance adjusted next cycle** | Advance from Lessee | Lessee Receivable | 975.82 |
| 8 | **Waiver — invoice unpaid** (credit note) | Lease Income | — | 16,122.19 |
| | | Output GST | — | 2,901.99 |
| | | — | Lessee Receivable | 19,024.18 |
| 9 | **Waiver — invoice already paid** | Lease Income | — | 16,122.19 |
| | | Output GST | — | 2,901.99 |
| | | — | Customer Payable | 19,024.18 |
| 10 | **Refund / adjust of customer payable** | Customer Payable | Bank / Advance | 19,024.18 |
| 11 | **RV shortfall — guaranteed** (sold ₹1,60,000) | Bank | — | 1,60,000.00 |
| | | Loss on Asset Sale | — | 40,000.00 |
| | | — | Leased Asset (NBV) | 2,00,000.00 |
| | *then raise the guarantee claim* | Lessee Receivable | Recovery Income | 40,000.00 |
| | *on recovery* | Bank | Lessee Receivable | 40,000.00 |
| 12 | **Repossession — catch-up depreciation** | Depreciation Expense | Accumulated Depreciation | 1,14,285.71 |
| 13 | **Repossession — write off unpaid rentals** | Bad Debt Expense | Lessee Receivable | 20,000.00 |
| 14 | **Repossession — resale at ₹7,50,000** | Bank | — | 7,50,000.00 |
| | | Loss on Sale | — | 1,35,714.29 |
| | | — | Leased Asset (NBV) | 8,85,714.29 |
| 15 | **Penal charge levied** | Lessee Receivable | Penal Income + Output GST | as levied |

**Partial waiver:** GST is reversed in the **same proportion** as the taxable value waived.

### Lessee-side mirror (reference only — Omni does not post)

| Event | Dr | Cr | Amount |
|---|---|---|---|
| Rental due | Lease Liability 16,122.19 · GST Input Credit 2,901.99 | Lessor Payable | 19,024.18 |
| Payment made | Lessor Payable | Bank | 19,024.18 |
| Short payment (₹10,000) | Lessor Payable | Bank | 10,000.00 |
| RV guarantee shortfall | Loss on Residual Guarantee | Residual Guarantee Payable | 40,000.00 |

---

## 7. How this fits Omni (architecture summary)

This is deliberately additive — the existing config-driven architecture absorbs most of it.

| Area | Change |
|---|---|
| **Product type** | Add `operating_lease` to `ProductType` and `ConfigType` (they must stay in sync — config templates and JSON-schema lookup both key off it). |
| **Config schema** | New `addon/schemas/operating_lease.json`: lease-term block, RV/depreciation block, lease components with `tax`, settlement order, DPD, restructuring levers. |
| **Components** | Seed `lease_rental`, `residual_value`, `security_deposit`, `advance_rental`, `penal_charge`, `maintenance_fee`, `insurance_recovery`, `recovery_income`. New `ComponentCategory` values: `rental`, `residual`, `depreciation`. Gate them to the new product type. |
| **Schedule engine** | Add an operating-lease key to the demand-expression table. The **only** structural difference from reducing-balance term loan is the annuity's `FV = residual_value` instead of `0`, plus advance/arrears timing. No new maths engine required. |
| **Transaction codes** | New events: `lease_rental_invoice`, `depreciation_accrual`, `advance_adjustment`, `rental_waiver`, `residual_settlement`, `repossession`, `asset_disposal`, `lease_termination`. Each must be added to the account-status → allowed-transaction-code map. |
| **Processor** | New `OperatingLeaseTransactionProcessor` composed from existing mixins (repayment, waiver, write-off, restructure, excess settlement) plus lease-specific ones (depreciation, disposal, RV settlement). Register in the processor registry. |
| **Asset register** | **New capability** — a leased-asset model with cost, capitalisation date, accumulated depreciation, NBV, disposal. This is the only genuinely new domain object. |
| **GL** | Seed the lease GL accounts and component→GL mappings for each `(component, posting type, transaction code)` triple. GST posts automatically via the existing CGST/SGST/IGST path. |
| **Frontend** | New product-config form for the lease type; new Lease Details screen (tabs: Overview, Schedule, Invoices, Payments, Asset & Depreciation, Restructure, GL); asset register list; sidebar entry under LMS. |

### Known dependency / risk

The GST GL-posting routine has an early return **inside** the loop over tax ledgers, so only the **first** taxable component of a transaction is posted to GST accounts. Term Loan rarely hits this (one taxable fee per transaction); an operating lease invoice carrying **rental GST + penal GST in the same transaction** will hit it immediately and under-post GST. **This must be fixed before Phase 2.** Owner: GL. Severity: high (tax under-statement).

---

## 8. Phasing

| Phase | Scope | Outcome |
|---|---|---|
| **P1 — Core lease** | Product type + config schema, components, schedule with RV, lease booking, asset capitalisation, rental schedule UI, schedule export. | A lease can be configured, booked and scheduled correctly. |
| **P2 — Bill & collect** | GST invoicing (CGST/SGST/IGST), penal charges, receipts, waterfall allocation, short payment + DPD, excess → advance from lessee, GL events 1–7 & 15, **GST loop fix**. | A lease can be billed and collected end to end with correct books. |
| **P3 — Asset & depreciation** | Asset register, monthly depreciation job, NBV tracking, asset-to-GL reconciliation, GL event 4. | Lessor books are complete and reconcilable. |
| **P4 — Change events** | Restructuring (all five levers incl. prepayment stub handling), waiver/credit note with proportional GST reversal, GL events 8–10. | Live leases can be modified correctly. |
| **P5 — End of lease** | RV realisation (guaranteed & non-guaranteed), renewal, lessee purchase, foreclosure, repossession, disposal, write-off, GL events 11–14. | Full lifecycle closed out. |
| **P6 — Reporting** | Lease portfolio dashboard, RV exposure report, depreciation register, GST output register, DPD/ageing for leases. | Portfolio is manageable and auditable. |

---

## 9. Success Metrics

| Metric | Target |
|---|---|
| Time to configure a new lease product | < 30 minutes, no engineering involvement |
| Schedule accuracy vs. reference workbook | 100% match to 2 decimals across all 84 rows |
| Automated GL coverage of lease events | 100% of the 15 catalogued events; zero manual journal vouchers for BAU |
| Closing balance convergence to RV at final instalment | Within ₹1 |
| Billing cycle run | Fully automated; zero manual invoice creation |
| Asset register ↔ GL reconciliation breaks | Zero at month end |

---

## 10. Open Questions

1. **Advance rentals** — when N rentals are collected upfront, are they revenue-deferred and released monthly, or applied against the first N instalments? (Affects revenue recognition.)
2. **Security deposit** — refundable at end of lease, or adjustable against RV shortfall / final rentals? Interest payable on it?
3. **Depreciation method** — is SLM sufficient for P1, or is WDV needed for tax-book parity from day one? Do we need dual books (companies-act vs income-tax depreciation)?
4. **Ind AS 116 lessor classification** — do we need an automated operating-vs-finance lease classification test, or is it a manual product-level decision?
5. **Mid-term asset substitution** — can the underlying asset be swapped without re-papering the lease?
6. **Insurance** — does the lessor or lessee insure? If lessor, is the premium a recoverable component billed with GST?
7. **Prepayment stub (AC-6.3)** — confirm the business preference: reduced final rental (recommended) vs. extra part-period at the start.
8. **Repossession accounting** — should the repossessed asset be reclassified to an "Assets Held for Sale" GL account pending disposal?
9. **Penal charge basis** — flat per occurrence, or % p.a. on the overdue rental? Does it compound?

---

## Appendix A — Verified reference figures

All figures below were recomputed independently and match `Operating Lease.xlsx` exactly.

| Quantity | Value |
|---|---|
| Lease rental | 16,122.186238 |
| GST @ 18% | 2,901.993523 |
| Total incl. GST | 19,024.179761 |
| Depreciation / month (SLM) | 9,523.809524 |
| Closing balance after instalment 12 | 9,22,355.3546 |
| Closing balance after instalment 84 | 2,00,000.00 |
| Accumulated depreciation @ 12 months | 1,14,285.7143 |
| NBV @ 12 months | 8,85,714.2857 |
| Restructure: RV → 3,00,000, 72 months left | 15,167.16699 |
| Prepay 1,00,000, tenure unchanged | 14,167.16699 |
| Prepay 1,00,000, rental unchanged → tenure | 58.395785 months |
| Repossession loss (resale 7,50,000) | 1,35,714.2857 |
