# PRD — Collateral / Securities / Asset Module (crego-omni)

| | |
|---|---|
| **Status** | Draft v0.1 |
| **Author** | Abhishek |
| **Date** | 2026-07-04 |
| **Target repo** | `crego-omni` (new `collateral` app under `project/apps/`) |
| **Related** | `product`, `coa`, `contact`, `transfer`, `schedule`, `approval`, `workflow`, `docs`, `notifications` |

---

## 1. Problem Statement

Crego's platform today has no first-class concept of collateral. Every module (product, limits, schedules, transfers) assumes unsecured or program-level credit. Clients who want to run secured products — Loan Against Property (LAP), vehicle finance, housing, loan against shares/mutual funds (LAS/LAMF) — cannot model the asset, its valuation, the charge created on it, or the LTV relationship between exposure and security.

The cost of not solving this: Crego is excluded from the largest secured-lending segments (LAP, vehicle, housing, LAS/LAMF), client deals require this capability, and competing LOS/LMS platforms (Finflux, Lentra, Newgen, M2P-ecosystem players) ship collateral management as a standard module — including asset tracking, LTV configuration, revaluation alerts, margin-call triggers, and CERSAI filing workflows.

## 2. Goals

1. **Generic collateral framework**: one data model and lifecycle that supports all asset classes (property, vehicle, equity, mutual funds, FD, gold later) — no per-asset-type forks of the module.
2. **Enable secured products end-to-end**: a client can configure a secured product, attach collateral during origination, enforce LTV at disbursal, and monitor it through the loan lifecycle.
3. **Industry-standard feature parity**: valuation workflows, charge perfection tracking (CERSAI / RC hypothecation / lien marking), revaluation schedules, margin calls, release and substitution — the features "other platforms or industry require."
4. **Regulatory compliance by configuration**: LTV caps, monitoring cadence, and breach-cure SLAs (e.g., RBI's 7-working-day LTV breach cure for LAS) expressed as tenant-configurable policy, not hard-coded.
5. **Measurable adoption**: at least one client live on a secured product (LAP or vehicle) within one quarter of GA.

## 3. Non-Goals

- **Gold loan operations** (assaying, vaulting, tare weight): specialized ops tooling; revisit after core framework proves out. The data model must still be able to represent gold as an asset type (P2 design constraint).
- **Building our own valuation engine for property/vehicles**: we orchestrate external empanelled valuers and market-data feeds; we don't compute property prices.
- **Direct depository/RTA/CERSAI integrations in v1**: v1 tracks perfection status and documents; live API integrations (NSDL/CDSL pledge, CAMS/KFintech/MFCentral lien, CERSAI filing, VAHAN RC check) are phased in (see Roadmap).
- **Collateral auction / enforcement marketplace**: SARFAESI/repossession workflows beyond status tracking are out of scope for v1.
- **Portfolio-level collateral optimization** (cross-collateralization solvers): design for many-to-many links now, optimize later.

## 4. Personas & User Stories

Personas: **Credit Ops** (lender-side maker/checker), **Credit Policy Manager**, **Relationship Manager / DSA**, **Borrower** (via client's front end), **Risk/Compliance Officer**.

Priority-ordered:

1. As a **credit ops user**, I want to register an asset (property / vehicle / securities holding) against a contact with type-specific attributes, so that it can be offered as security for a facility.
2. As a **credit ops user**, I want to link one or more assets to a loan/limit with a charge type (mortgage, hypothecation, pledge, lien), so that exposure is formally secured and visible on the account.
3. As a **credit policy manager**, I want to configure per-product LTV caps, haircuts, and eligible asset types, so that origination automatically enforces policy without manual checks.
4. As a **credit ops user**, I want valuation requests assigned to empanelled valuers with report upload and maker-checker approval, so that property/vehicle values are evidenced and auditable.
5. As a **risk officer**, I want automatic revaluation schedules and mark-to-market for market-linked assets, so that LTV is monitored on an ongoing basis as RBI requires.
6. As a **risk officer**, I want margin-call and top-up workflows triggered on LTV breach, with a configurable cure SLA (e.g., 7 working days), so that breaches are rectified within regulatory timelines.
7. As a **credit ops user**, I want to track charge perfection (CERSAI registration for property, RC hypothecation for vehicles, lien/pledge confirmation for securities) with reference numbers, dates, and documents, so that the security is legally enforceable.
8. As a **credit ops user**, I want to release or substitute collateral on closure/prepayment with approval workflow, so that borrowers get timely release and the register stays accurate.
9. As a **borrower**, I want to see my pledged assets, current value, and LTV headroom, so that I understand my available limit and margin-call risk.
10. As a **compliance officer**, I want a full audit trail of every collateral event (creation, valuation, LTV change, perfection, release), so that audits and RBI supervisory reporting are straightforward.

Edge cases: asset shared across multiple facilities (pro-rata allocation); multiple assets on one facility; valuation dispute/rejection; partial release; lien invocation on default; asset owner ≠ borrower (third-party collateral / guarantor-owned).

## 5. Solution Overview

A new Django app `collateral` in crego-omni following existing conventions (BaseModel + SoftDeleteModel, tenant scoping via namespace-per-tenant routing, BaseService layer with `tenant_atomic()`, BaseViewSet, resource metadata seeding, approval + workflow + notifications integration).

### 5.1 Core concepts

```
Asset (what)  ──<  Collateral (link: asset ↔ facility, charge type, allocation %)  >── Account/Limit (secures what)
   │                        │
   ├─ Valuation (worth)     ├─ Charge/Perfection (legal enforceability)
   ├─ AssetDocument         └─ CollateralEvent (audit trail)
   └─ type-specific attributes (JSON schema per asset type, seeded like resource metadata)
```

- **Asset**: registry entry owned by a Contact. `asset_type` (immovable_property, vehicle, equity_share, mutual_fund_unit, fixed_deposit, gold, other) + `attributes` JSONB validated against a per-type schema (e.g., property: survey no., area, title status; vehicle: registration no., chassis/engine no., make/model/year; MF: folio, scheme, ISIN, units; equity: ISIN, quantity, demat account).
- **Collateral**: the association of an Asset to a facility (Account/Limit) with charge type (`equitable_mortgage`, `registered_mortgage`, `hypothecation`, `pledge`, `lien`), allocation percentage (for shared assets), status lifecycle: `proposed → under_valuation → approved → perfected → active → release_requested → released` (+ `invoked`, `substituted`).
- **Valuation**: point-in-time value with source (`empanelled_valuer`, `market_feed_nav`, `market_feed_price`, `declared`, `insurance_idv`), validity period, report document, maker-checker approval. Latest approved valuation drives LTV.
- **LTV Policy**: per product/asset-type configuration — max LTV, haircut, revaluation frequency, breach thresholds (warning / margin call / invocation), cure SLA days. Evaluated by a policy service at origination (block disbursal above cap) and by scheduled jobs during servicing.
- **Charge/Perfection**: registration type per asset class (CERSAI for property, RC hypothecation endorsement for vehicles, depository pledge / RTA lien for securities), reference number, filing date, status, documents. V1 = tracked manually with document proof; later phases automate via APIs.
- **CollateralEvent**: append-only audit of all state changes, valuations, LTV computations, and breaches (feeds `audit` module + notifications).

### 5.2 Regulatory & industry reference (to encode as default policy templates)

| Asset class | LTV norm (India) | Notes |
|---|---|---|
| Housing loan | ≤ ₹30L: 90% · ₹30–75L: 80% · > ₹75L: 75% | RBI slab-based caps |
| LAP | ~75% market practice (risk-based) | No hard RBI cap; lender policy driven |
| Vehicle (new) | ~80–90% typical; up to 100% on-road by lender policy | No RBI-stipulated cap; wide variation |
| Vehicle (used) | ~60–79% typical (IDV/valuation based) | Depreciation-adjusted |
| Listed equity / equity MF | 50% today → **60% from 1 Apr 2026** (RBI draft Oct 2025) | Per-individual LAS ceiling raised ₹20L → **₹1 crore** |
| Debt MF / listed debt | up to **75%**; AAA-rated listed debt up to **85%** | Per RBI's revised LAS framework |
| LTV breach cure | Rectify immediately, within **7 working days** | Continuous monitoring required |

> Verify final circular text before GA — the 60%/₹1Cr changes were draft as of Oct 2025 with effect from Apr 2026. Policy engine must make all of these tenant-editable numbers, not constants.

### 5.3 Integration surface (phased)

| Integration | Purpose | Phase |
|---|---|---|
| Document store (`docs` app) | Valuation reports, title docs, RC copies, sanction annexures | P0 (existing) |
| Approval + workflow apps | Maker-checker on valuation, release, substitution | P0 (existing) |
| Notifications | Margin calls, revaluation due, perfection pending | P0 (existing) |
| NAV/price feeds (AMFI NAV, exchange EOD) | Mark-to-market for LAS/LAMF | Phase 2 |
| CAMS / KFintech / MFCentral APIs | MF lien mark / revoke / invoke | Phase 2/3 |
| NSDL / CDSL pledge APIs | Demat share pledge (OTP-based) | Phase 3 |
| CERSAI | Security interest filing for property | Phase 3 |
| VAHAN | RC verification + hypothecation status | Phase 3 |
| Insurance validation | Vehicle/property insurance tracking | Phase 2 |

## 6. Requirements

### P0 — Must have (v1 cannot ship without)

| # | Requirement | Acceptance criteria (representative) |
|---|---|---|
| P0-1 | Asset registry with typed attributes | Given a contact, when ops creates an asset of any supported type, then type-specific mandatory fields are validated against the seeded schema and the asset is tenant-scoped and auditable |
| P0-2 | Collateral linking (many-to-many with allocation) | Given an approved asset, when linked to a facility with charge type and allocation %, then total allocation across facilities cannot exceed 100% and the facility shows its security coverage |
| P0-3 | Valuation capture with maker-checker | Given a valuation entry with report document, when checker approves, then it becomes the effective value; rejected valuations never affect LTV |
| P0-4 | LTV policy per product/asset type + origination gate | Given a product LTV cap, when requested disbursal would push LTV above cap, then the disbursal is blocked with a clear policy violation reason |
| P0-5 | LTV computation & on-demand view | LTV = exposure ÷ Σ(allocated approved value × (1 − haircut)); visible on facility and asset views |
| P0-6 | Perfection tracking (manual) | Charge record with registration type, reference no., date, status, and mandatory proof document before collateral can reach `active` |
| P0-7 | Release workflow | Given a closed/prepaid facility, when release is approved (maker-checker), then collateral status → `released`, release letter document generated/attached, and event logged |
| P0-8 | Full event audit trail | Every create/update/status change/valuation/LTV breach emits a CollateralEvent consumable by `audit` and `reports` |
| P0-9 | APIs + resource metadata + seeders | CRUD/list/search APIs per omni conventions; `seed_resource_metadata` and search config entries; setup_account seeds default policy templates |

### P1 — Should have (fast follow)

- Revaluation scheduling: per-policy frequency generates tasks/notifications; stale valuations flag the facility.
- Mark-to-market job for market-linked assets (NAV/price feed ingestion) with daily LTV recompute.
- Margin call workflow: warning → margin call → cure SLA countdown → escalation; borrower-facing notification templates.
- Collateral substitution (swap asset without closing facility) with approval.
- Third-party collateral (owner ≠ borrower) with guarantor consent document.
- Portfolio dashboards/reports: coverage, LTV distribution, perfection aging, revaluation due.
- Insurance tracking on vehicle/property assets with expiry alerts.

### P2 — Future (design for, don't build)

- Live integrations: CAMS/KFintech/MFCentral lien APIs, NSDL/CDSL pledge, CERSAI filing, VAHAN RC fetch.
- Lien invocation / enforcement lifecycle (SARFAESI stage tracking, repossession status).
- Gold as asset type (assay attributes), FD auto-lien with bank APIs.
- Cross-collateralization optimization and borrower self-service pledge journeys (embeddable).

## 7. Success Metrics

- **Adoption**: ≥ 1 client live on a secured product within 1 quarter of GA; 3+ within 2 quarters.
- **Origination gate effectiveness**: 100% of secured disbursals evaluated against LTV policy (0 bypasses); policy violations blocked with reason codes.
- **Ops efficiency**: median time from asset creation → collateral `active` (perfected) tracked; target < 5 working days for LAP, < 2 for vehicle (baseline after first client).
- **Compliance**: 100% of LTV breaches surfaced within 1 day of triggering data; breach-to-cure time within configured SLA in ≥ 95% of cases.
- **Quality**: 0 collateral records active without an approved valuation + perfection proof.

## 8. Open Questions

| Question | Owner | Blocking? |
|---|---|---|
| Does collateral link at Account, Limit, or Program level (or all three)? Existing `coa`/`product` semantics decide the FK targets | Engineering + Product | Yes — data model |
| Do we reuse `workbook`/`workflow` JSON templates for the collateral lifecycle or hard-code the state machine in the app? | Engineering | Yes — architecture |
| Which client is the launch partner, and is their v1 need LAP, vehicle, or LAMF? (Roadmap phase 1 ordering depends on this) | Abhishek / Sales | Yes — sequencing |
| Valuer empanelment: is valuer a `contact` with a role, or a new entity? | Product | No |
| NAV/price feed vendor selection (AMFI direct vs aggregator) | Engineering | No (Phase 2) |
| Final RBI circular values for LAS LTV/ceiling (draft → final) | Compliance | No — configurable |

## 9. Roadmap (high level)

**Phase 0 — Framework core (≈ 4–6 weeks)**
Asset registry, typed attribute schemas, Collateral linking, Valuation with maker-checker, LTV policy + computation, perfection tracking (manual), release workflow, events/audit, APIs + seeders. Exit: internal demo of a generic secured facility on dev.

**Phase 1 — LAP + Vehicle GA (≈ 4 weeks after P0)**
Property and vehicle attribute packs, valuer workflow, insurance tracking (vehicle), default policy templates (housing slabs, LAP 75%, vehicle new/used), reports (coverage, perfection aging), UAT with launch client. Exit: first client live.

**Phase 2 — Financial assets / LAS-LAMF (≈ 6 weeks)**
Equity/MF attribute packs, NAV/price feed ingestion, daily mark-to-market + LTV recompute, revaluation scheduler, margin-call workflow with cure SLA, borrower-visible LTV headroom APIs. Exit: LAS/LAMF product runnable with manual lien marking.

**Phase 3 — Deep integrations & enforcement (quarter+)**
CAMS/KFintech/MFCentral lien APIs, NSDL/CDSL pledge, CERSAI filing, VAHAN verification, lien invocation & enforcement tracking, substitution self-service. Exit: straight-through digital LAMF journey.

## 10. References

- RBI LAS framework changes (draft Oct 2025, effective Apr 2026): shares/equity-MF LTV 50%→60%, debt MF up to 75%, AAA listed debt 85%, individual ceiling ₹20L→₹1Cr, 7-working-day breach cure — [smallcase](https://www.smallcase.com/learn/rbi-guidelines-loan-against-securities/), [Whalesbook](https://www.whalesbook.com/news/English/economy/rbi-raises-ceiling-value-for-loans-taken-against-shares-and-debt-mfs/68fbd75db633da24ed24fef1), [TaxGuru](https://taxguru.in/corporate-law/rbis-liberalises-acquisition-finance-lending-securities-capital-market-exposure.html)
- Housing LTV slabs & LAP practice — [RBI notification](https://www.rbi.org.in/commonman/english/scripts/Notification.aspx?Id=1269), [99acres](https://www.99acres.com/articles/rbi-guidelines-on-home-loan-financing-and-ltv-ratio.html)
- Vehicle LTV market practice — [BankBazaar](https://blog.bankbazaar.com/ltv-in-case-of-car-loans/)
- LAMF/LAS ecosystem (CAMS, KFintech, MFCentral, NSDL/CDSL pledge) — [Betalectic](https://betalectic.com/blog/loan-against-securities), [Finsire docs](https://docs.finsire.com/docs/loan-against-mutualfunds-1), [CAMS](https://www.camsonline.com/Business/LoanAgainstMF)
- Competitor collateral module features — [M2P LMS overview](https://m2pfintech.com/blog/top-10-loan-management-systems-in-india-for-2026/), [Roopya LOS features](https://roopya.money/best-loan-origination-management-software-features-in-india/)
