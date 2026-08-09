# PRD — PDC (Post-Dated Cheque) Module

**Status:** Draft for review
**Author:** Abhishek
**Date:** 31 Jul 2026
**Repos affected:** `crego-omni` (new `pdc` app), `crego-web` (new `pdc` module + new top-level nav group)
**Technical design:** `crego-internal-docs/engineering/pdc-module-technical-design.md`

---

## 1. Problem & Opportunity

Omni collects money-in through exactly two rails today: manually recorded `transfer.Payment` records, and NACH debits (`transfer.PaymentBatch` + the TransBank connector). Neither covers **physical instruments**.

Post-dated cheques remain the primary or fallback repayment instrument for a large share of Indian NBFC lending — used-vehicle, LAP, equipment, gold top-ups, and almost every co-lending arrangement where the borrower has no NACH-capable account or the mandate registration fails. Lenders also hold **security cheques (SDC/UDC)** against every loan as a legal instrument for Section 138 NI Act recourse, regardless of whether NACH is live.

Today that whole workflow lives in spreadsheets and physical registers at the branch. The consequences we hear from clients:

1. **No inventory.** Nobody can answer "how many usable cheques do we hold for this loan, and where physically are they?" Cheques are lost, and lost cheques mean no 138 recourse.
2. **Silent expiry.** A cheque is valid for **3 months from its date** (RBI, effective 1 Apr 2012). Cheques quietly go stale in the vault; the branch discovers it on the day it tries to bank one.
3. **Manual presentation.** Deposit slips are typed by hand each morning from the EMI due list; cheques get presented against already-closed EMIs or already-paid accounts.
4. **Bounce handling is ad hoc.** Bounce charges are levied inconsistently, re-presentation limits are not enforced (bank penalties for repeated presentation), and the NI Act 138 notice clock — 30 days from bounce intimation, 15-day cure period, 30-day window to file — is tracked on someone's calendar.
5. **No audit trail.** Custody transfers between branch and head office are untracked, which is an audit finding in every NBFC inspection.

### Goal

Ship a **PDC module** in Omni that owns the full physical-instrument lifecycle — intake, verification, custody, mapping to a loan and its EMI schedule, presentation batching, clearing, bounce with charge posting and legal-notice tracking, re-presentation, replacement, expiry and return — with a matching operations console in Omni Web, and with realised cheques flowing into the **existing** `transfer.Payment` rail so ledger, demand settlement and GL behaviour are unchanged.

### Non-goals (this phase)

- **CTS image capture / IQA.** We store a scanned image as a `docs.Document`; we do not do CTS-2010 image quality assessment or generate CTS clearing files.
- **Positive Pay System (PPS) submission.** Designed for (see §9) but the connector is phase 3.
- **Automated bank return-file ingestion.** Phase 1 is a manual/bulk-upload return marking; the connector interface is defined so a bank-specific parser drops in later.
- **e-NACH mandate creation from a cheque.** Out of scope; NACH stays in `transfer`.
- **Cheque printing / issuance** (lender-issued cheques for disbursement). This module is money-in only; disbursement stays on `transfer.Payout`.
- **Legal case management.** We track the 138 clock and hold the notice document; we do not build a litigation tracker.

---

## 2. Personas

| Persona | Needs |
|---|---|
| **Branch Ops / Cheque Custodian** | Log cheques handed over by the customer, verify them against the physical instrument, keep the vault register honest, hand cheques to HO. |
| **Credit / Loan Ops** | Map cheques to a loan and to specific EMIs; know before disbursement whether the PDC cover is complete. |
| **Collections Officer** | See which EMIs are PDC-covered, trigger presentation, handle bounces, chase replacement cheques. |
| **Banking / Treasury Ops** | Build the day's deposit batch per collection bank, print the deposit slip, mark clearing outcomes, reconcile against the bank statement. |
| **Finance / Accounts** | Bounce charges posted correctly as demands; realised cheques appear as normal payments; no off-ledger money. |
| **Legal / Recovery** | The 138 clock per bounce, the return memo, and the notice document, in one place. |
| **Auditor / Compliance** | A complete, immutable custody and status trail per instrument. |

---

## 3. Product Concept

### 3.1 The instrument is the primary object

A **PDC Instrument** is a physical cheque the lender holds. It has an identity (`bank + IFSC/MICR + account no + cheque number`) that is unique regardless of which loan it later covers — so a cheque handed over before the loan is booked is still a first-class record.

An instrument carries one of four **purposes**:

| Purpose | Dated? | Amount? | Typical use |
|---|---|---|---|
| **EMI** | Yes (post-dated to the EMI due date) | Yes (EMI amount) | The classic repayment PDC. Mapped 1:1 to a `Schedule` row. |
| **Security (SDC)** | No (undated) | Usually blank/full exposure | Held for the life of the loan for NI Act recourse. Never batched by the scheduler; only presented on a deliberate recovery action. |
| **Advance / part-payment** | Yes | Yes | Ad-hoc prepayment or down-payment. |
| **Margin / Other** | Either | Either | Deposits, margin money, client-specific uses. |

### 3.2 Presentation is a separate object from the instrument

A cheque can be banked more than once. Each banking attempt is a **PDC Presentation** row (attempt 1, 2, 3…) carrying its own presentation date, amount, clearing date and outcome. The instrument holds current state; the presentations hold history. This mirrors how `connectors.TransBankNachPresentation` relates to `transfer.Payment`, so the two rails read the same way in reports.

**Why it matters:** re-presentation limits are a real bank constraint (most banks penalise beyond 2–3 presentations of the same instrument), and a bounce on attempt 1 followed by clearing on attempt 2 has to leave both facts on the record for legal purposes.

### 3.3 Realisation reuses the existing payment rail

When a presentation clears, the module creates a `transfer.Payment` with `mode = cheque`, `payment_type = loan_settlement`, `value_date = clearing date`, linked to the account. Everything downstream — demand settlement, CTM transactions, GL, SOA, DPD — is untouched. **PDC posts no ledger entries of its own.**

### 3.4 A bounce is an event with three consequences

1. **Financial** — a bounce charge demand, posted through the existing charge/component machinery, and only for *financial* return reasons (insufficient funds, exceeds arrangement, stop payment), never for *technical* ones (signature illegible, image not clear, stamp missing). This distinction is the single most common client complaint about competing systems.
2. **Operational** — the instrument returns to custody and becomes eligible for re-presentation, subject to the configured attempt limit and the cheque's remaining validity.
3. **Legal** — the NI Act §138 clock starts. The module records the bounce intimation date, computes the notice-due date (+30 days), the cure deadline (+15 days from notice service) and the complaint-filing window (+30 days from cure expiry), and surfaces them as a work queue. Dates are computed and displayed as SLA guidance; nothing is filed automatically.

### 3.5 Expiry is proactive, not discovered

Every dated instrument gets `expiry_date = cheque_date + 3 months` at creation. A daily scheduler:

- marks past-validity instruments `expired` and drops them out of every presentation queue;
- fires a reminder at a configurable lead time (default 30 days) so the branch can collect replacements;
- raises a **low-cover alert** when an active loan's usable PDC count falls below a configurable threshold (default 3), or when the sum of usable PDC amounts no longer covers the next N EMIs.

---

## 4. Lifecycle

```
                 ┌──────────┐   reject
   received ────►│ verified │──────────► rejected (terminal)
      │          └────┬─────┘
      │ reject        │ (auto)
      ▼               ▼
   rejected      in_custody ◄──────────────────────┐
                      │                            │
       ┌──────────────┼───────────────┐            │ withdraw
       │              │               │            │
       ▼              ▼               ▼            │
   returned      marked_for_presentation ──────────┘
   replaced           │
   cancelled          │ deposit
   stop_payment       ▼
   lost           presented
   expired            │
   (terminal)    ┌────┴────┐
                 ▼         ▼
             cleared     bounced
            (terminal)     │
                           ├─► in_custody (re-present, if attempts left & not expired)
                           ├─► replaced   (customer gives a fresh cheque)
                           └─► returned   (handed back, closed out)
```

**Notes**

- `in_custody` is the resting state. Everything the ops team does starts and (usually) ends there.
- Only `in_custody` instruments are eligible for the auto-batching scheduler, and only those with `purpose = emi` and a `cheque_date` within the batching window. Security cheques are never auto-batched.
- `expired` is reachable from `in_custody` and `marked_for_presentation` only — never from `presented` (once it is with the bank, the outcome decides).
- Mapping to a loan (`apply_to_loan`) and un-mapping (`detach`) are **relationship changes, not status changes**. A cheque can be `in_custody` and unmapped, or `in_custody` and mapped to EMI #7.

---

## 5. Functional Requirements

### 5.1 Intake

| ID | Requirement | Priority |
|---|---|---|
| IN-1 | Create a single PDC with bank, IFSC, MICR, account no, account holder name, cheque number, cheque date, amount, purpose. | Must |
| IN-2 | Bulk intake of a cheque leaf range (start cheque no + count) with auto-generated cheque numbers and auto-derived cheque dates from the loan's EMI due dates. | Must |
| IN-3 | Bulk import via the existing `workbook` framework (`pdc_bulk` handler) with a downloadable template. | Must |
| IN-4 | Attach a scanned image per cheque as a `docs.Document`. | Must |
| IN-5 | Reject duplicate instruments — same `(ifsc, account_no, cheque_number)` may not exist twice in a non-terminal state. | Must |
| IN-6 | Capture the customer bank as a `contact.ContactBank` reference when one exists; otherwise store the denormalised bank fields. | Must |
| IN-7 | Maker-checker on intake, if enabled for the resource. | Should |

### 5.2 Verification & custody

| ID | Requirement | Priority |
|---|---|---|
| CU-1 | `verify` action: an authorised user confirms the physical cheque matches the record; captures verifier and timestamp. | Must |
| CU-2 | Custody register: every instrument records current branch, custodian and location reference (vault/locker). | Must |
| CU-3 | `PDC Movement` log for every custody change: from/to branch, from/to custodian, movement type (`vault_in`, `vault_out`, `branch_transfer`, `handover_to_bank`, `return_to_customer`), remarks, optional acknowledgement document. | Must |
| CU-4 | Bulk movement — move N instruments in one action, producing N movement rows. | Should |
| CU-5 | Mark `lost` / `damaged` with mandatory remarks; blocks all presentation actions. | Must |

### 5.3 Mapping to a loan

| ID | Requirement | Priority |
|---|---|---|
| MP-1 | `apply_to_loan`: link an instrument to an `Account`, optionally to a specific `Schedule` (EMI) row. | Must |
| MP-2 | Auto-map: given an account and a set of instruments, map them to the next N unsettled EMIs in due-date order, matching amounts where possible. | Must |
| MP-3 | `detach`: unlink from account/schedule; only allowed while `in_custody`. | Must |
| MP-4 | An EMI may have at most one active mapped instrument; a re-map requires detaching the existing one. | Must |
| MP-5 | Warn (do not block) when the cheque amount ≠ the EMI amount, or the cheque date ≠ the EMI due date. | Must |
| MP-6 | Per-account **PDC cover** summary: usable count, usable amount, EMIs covered, next uncovered EMI, expiring-soon count. Exposed as an `Account` expand so the loan detail page can render it. | Must |

### 5.4 Presentation

| ID | Requirement | Priority |
|---|---|---|
| PR-1 | `mark_for_presentation` on one or many instruments; validates status, expiry, attempt limit, mapped account status, and that the covered demand is still outstanding. | Must |
| PR-2 | Create a **PDC Batch** per (collection bank, presentation date); add/remove instruments while the batch is `open`. | Must |
| PR-3 | Auto-batch scheduler: daily, build open batches for EMI-purpose instruments whose cheque date falls within `[today, today + lead_days]` (default lead 2 days), grouped by collection bank. | Must |
| PR-4 | `deposit` action on a batch: locks it, creates one `PDCPresentation` per instrument (attempt = previous + 1), moves instruments to `presented`, stamps the deposit datetime. | Must |
| PR-5 | Export a **deposit slip** (PDF/Excel) for a batch, and a bank-format flat file where the client's bank requires one. | Must |
| PR-6 | `withdraw` an instrument from an open batch — returns it to `in_custody` with no presentation row. | Must |
| PR-7 | Block presentation of `security` purpose instruments unless the user holds an explicit `can_present_security_cheque` permission. | Must |
| PR-8 | Enforce configurable max presentation attempts per instrument (default 3). | Must |

### 5.5 Clearing & bounce

| ID | Requirement | Priority |
|---|---|---|
| CB-1 | `mark_cleared` on a presentation: captures clearing date, realised amount, bank reference; creates a `transfer.Payment`; moves the instrument to `cleared`. | Must |
| CB-2 | `mark_bounce` on a presentation: captures return date, return reason code, reason description, return memo document, and bounce charge applicability. | Must |
| CB-3 | Return reasons are a **configurable master** with a `financial` / `technical` classification. A starter set of common CTS return reasons ships seeded; clients must reconcile it with their bank's return memo codes at onboarding. | Must |
| CB-4 | Bounce charge posted as a `Demand` on the mapped account using a configured charge component, **only** for financial reasons, and only once per presentation. Overridable per bounce by an authorised user with a reason. | Must |
| CB-5 | Bulk clearing/bounce marking from a list view and from an uploaded return sheet. | Must |
| CB-6 | `represent`: return a bounced instrument to `in_custody` and (optionally) straight into a new batch, subject to PR-8 and expiry. | Must |
| CB-7 | NI §138 tracking on a bounce: intimation date, notice due date (+30d), notice sent date, notice document, cure deadline (+15d from service), complaint window end (+30d from cure). Surfaced as an overdue work queue. | Must |
| CB-8 | Bounce reason, count and last bounce date roll up onto the account for collections triage. | Should |

### 5.6 Replacement, return, closure

| ID | Requirement | Priority |
|---|---|---|
| RC-1 | `replace`: create a new instrument linked to the old one (`replaces` / `replaced_by`), inheriting the loan/EMI mapping; old instrument → `replaced`. | Must |
| RC-2 | `return_to_customer`: terminal; requires an acknowledgement (document or remarks); logs a movement row. | Must |
| RC-3 | `stop_payment`: records the customer's stop-payment instruction; terminal; blocks presentation. | Must |
| RC-4 | On loan closure, list all remaining instruments for that account for bulk return, and block them from presentation. | Must |
| RC-5 | `cancel`: terminal, for data-entry errors, with mandatory remarks. | Must |

### 5.7 Schedulers

| ID | Task | Cadence | Behaviour |
|---|---|---|---|
| SC-1 | `pdc_expire_instruments_task` | Daily 00:30 | Move dated instruments past validity from `in_custody` / `marked_for_presentation` to `expired`. Idempotent. |
| SC-2 | `pdc_expiry_reminder_task` | Daily 08:00 | Fire `PDC Expiring Soon` notification event for instruments expiring within the configured lead (default 30d). Idempotent per instrument per day. |
| SC-3 | `pdc_build_presentation_batches_task` | Daily 06:00 | Build/refresh open batches for the presentation window. |
| SC-4 | `pdc_low_cover_alert_task` | Daily 08:15 | Fire `PDC Cover Low` for active accounts below the cover threshold. |
| SC-5 | `pdc_legal_notice_sla_task` | Daily 08:30 | Fire `PDC Legal Notice Due` for bounces approaching or past their §138 notice-due date. |
| SC-6 | `pdc_sync_presentation_status_task` | Every 30 min (phase 3) | Poll the bank connector for clearing outcomes where an integration exists. |

All schedulers follow the existing pattern: `@robust_task`, invoked via `TaskService`, seeded as `django_celery_beat.PeriodicTask` rows by a `seed_pdc_beat_schedule` management command with explicit timezone.

### 5.8 Reporting

| ID | Report | Priority |
|---|---|---|
| RP-1 | PDC inventory (by branch, custodian, status, purpose, expiry bucket). | Must |
| RP-2 | Presentation register (batch-wise, date-wise, bank-wise) with realisation %. | Must |
| RP-3 | Bounce register with reason-code analysis and charge recovery status. | Must |
| RP-4 | Expiring / expired cheques. | Must |
| RP-5 | Uncovered EMIs (loans with insufficient PDC cover). | Must |
| RP-6 | §138 legal tracker (bounces by notice stage and SLA status). | Should |

Delivered through the existing `reports` app handlers so they land in the standard Reports console with scheduling and export.

---

## 6. Web Console (crego-web)

A **new top-level nav group "PDC"** in `shared/constants/nav/default.ts`, colour `indigo`, licensed under `Modules.LMS`:

| Item | Route | Purpose |
|---|---|---|
| Cheques | `/pdc/instruments` | Master inventory. Filters: status, purpose, account, contact, branch, custodian, cheque date, expiry bucket, bank. Bulk actions: verify, mark for presentation, move, return, cancel. |
| Presentation Batches | `/pdc/batches` | Open/deposited/closed batches. Build, add/remove, deposit, download deposit slip, mark outcomes. |
| Presentations | `/pdc/presentations` | Every banking attempt. Bulk mark cleared / bounced. Primary reconciliation screen. |
| Bounces | `/pdc/bounces` | Bounced presentations with reason, charge status and the §138 clock. |
| Custody Register | `/pdc/movements` | Movement log; branch-transfer and handover workflows. |

Plus a **PDC tab on the loan detail page** showing cover summary, the mapped cheque per EMI, and quick actions.

All list pages use the standard `DataTable` + config-driven `FilterConfig`, and the standard `bulkOpsConfig` for import/export.

---

## 7. Configuration

Module settings (stored in the existing `Setting` / addon config mechanism, editable per tenant without a deploy):

| Key | Default | Meaning |
|---|---|---|
| `pdc.validity_months` | 3 | Cheque validity from cheque date. |
| `pdc.expiry_reminder_lead_days` | 30 | Lead time for the expiry reminder. |
| `pdc.max_presentation_attempts` | 3 | Per instrument. |
| `pdc.presentation_lead_days` | 2 | How far ahead the auto-batcher looks. |
| `pdc.min_cover_count` | 3 | Low-cover alert threshold (usable instruments). |
| `pdc.min_cover_emis` | 3 | Low-cover alert threshold (EMIs covered). |
| `pdc.bounce_charge_component_code` | — | The `ctm.Component` used to post bounce charges. |
| `pdc.auto_post_bounce_charge` | true | Whether financial bounces auto-post the charge. |
| `pdc.legal_notice_days` | 30 | §138 notice window from bounce intimation. |
| `pdc.legal_cure_days` | 15 | §138 cure period from notice service. |
| `pdc.legal_filing_days` | 30 | §138 complaint window from cure expiry. |
| `pdc.default_collection_bank` | — | Default deposit bank for auto-batching. |

Legal-clock defaults reflect the standard NI Act timeline and are configurable because service-date interpretation varies; they are **operational SLA guidance, not legal advice**, and clients should confirm them with their own counsel.

---

## 8. Success Metrics

| Metric | Baseline | Target |
|---|---|---|
| Cheques expiring unpresented | client-reported 5–12% | < 1% |
| Time to build the daily deposit batch | 45–90 min manual | < 5 min |
| Bounce charge leakage (financial bounces with no charge posted) | unmeasured | 0 |
| Instruments with a complete custody trail | 0% | 100% |
| §138 notices sent within the statutory window | unmeasured | 100% of eligible |
| PDC-covered EMIs realised on first presentation | — | tracked from day 1 |

---

## 9. Phasing

| Phase | Contents |
|---|---|
| **1 — Inventory & lifecycle** | Instrument model, intake (single/range/bulk import), verify, custody + movements, apply/detach to loan, expiry scheduler + reminders, cover summary, inventory report. Web: Cheques list, Custody register, loan PDC tab. |
| **2 — Presentation & bounce** | Batches, auto-batching, deposit + deposit slip, presentations, clear → `transfer.Payment`, bounce + reason master + charge posting, re-presentation, replacement, §138 tracking. Web: Batches, Presentations, Bounces. Reports: presentation and bounce registers. |
| **3 — Bank integration** | Connector category `cheque_clearing`: deposit-file generation, return-file ingestion, Positive Pay (PPS) submission, status sync scheduler. |

Phase 1 and 2 are the sellable unit; phase 3 is per-client.

---

## 10. Risks & Open Questions

| # | Risk / question | Owner |
|---|---|---|
| 1 | **Return reason codes vary by bank.** The seeded set must be validated against each client's bank return memos before go-live; a wrong `financial` / `technical` classification means wrong charge posting. Mitigation: reasons are a configurable master, not an enum, and the classification is editable. | Product + Onboarding |
| 2 | **Bounce charge posting** must reuse the existing charge/demand machinery. The exact service entry point is flagged as an integration TODO in the scaffold and needs to be confirmed against `schedule` / `ctm` before phase 2 build. | Backend |
| 3 | **Duplicate detection across tenants/loans** — a customer can legitimately hand the same cheque number from two different accounts of the same bank. Uniqueness is on `(ifsc, account_no, cheque_number)` in non-terminal states; confirm this matches client reality. | Product |
| 4 | **Physical reality drift.** The system's custody register is only as good as the branch's discipline. Mitigate with mandatory movement acknowledgement and a periodic physical-verification action. | Ops |
| 5 | **Co-lending / shared accounts** — which co-lender's collection bank does a cheque get deposited into? Assumed: the originating lender's, following the existing `Payment.parent` shared-payment pattern. Needs confirmation. | Product |
| 6 | **Security cheque amount** is usually blank on the physical instrument. We allow a null amount and require an explicit amount at presentation time. Confirm the legal team is comfortable with the system recording the fill-in amount. | Legal |
| 7 | **Is PDC its own licensed module?** Currently gated under `product_lms`. Promoting it to its own license key is a one-line change if we want to sell it separately. | Product |

---

## 11. Acceptance Criteria (phase 1 + 2)

1. A cheque can be created, verified, moved between custodians, mapped to an EMI, batched, deposited, cleared, and the resulting `transfer.Payment` settles the demand — end to end, with a complete audit trail on every step.
2. A bounce with a financial reason posts exactly one bounce charge demand; a bounce with a technical reason posts none.
3. An instrument cannot be presented after expiry, after the attempt limit, when the mapped account is closed, or when the covered demand is already settled.
4. The expiry scheduler run twice on the same day produces the same result (idempotent) and no duplicate notifications.
5. A security cheque never appears in an auto-built batch and cannot be presented without the explicit permission.
6. Every status change and every custody change is queryable from the audit log against the instrument.
7. All PDC endpoints respect data scoping — a branch user sees only their branch's inventory.
