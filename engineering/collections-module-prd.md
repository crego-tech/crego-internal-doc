# PRD — Collections Module & Configurable Collection Workflow

| | |
|---|---|
| **Status** | Draft v1 |
| **Author** | Abhishek (drafted with Claude) |
| **Date** | 2026-07-04 |
| **Related work** | omni: `feature/cre-5833-collection-agent-app-backend-implementation` (CollectionEnquiry backend) · app: `feature/cre-5834-collection-agent-app-screens`, `feature/cre-5836-add-collection-contact-listing-screen` · web: `feature/cre-5834-...` (permission types only) |
| **Decision** | Configurable workflow is built **natively in omni** (not on crego-flow) |

---

## 1. Problem Statement

Crego's LMS (omni) tracks delinquency (DPD at demand level, aggregated per account) and can report on it, but has no operational collections capability: no delinquency case that moves through a lifecycle, no assignment of overdue accounts to collection agents, and no automated outreach when a borrower slips into arrears. Clients (NBFCs/lenders) today run collections outside the platform — spreadsheets, manual calling lists, third-party tools — which means recovery outcomes are invisible to Crego, agent activity is unauditable, and RBI-mandated conduct rules (contact hours, agent disclosure, notices) are the client's manual burden.

An in-flight PR (CRE-5833/5834) adds the **agent-side leaf** of this tree — logging a call/field visit, capturing a Promise-to-Pay (PTP), collecting a payment with GPS + selfie proof — but nothing decides *which accounts an agent should work, in what order, and what the system should do automatically*. Without the module around it, the agent app is a diary, not a collections system.

## 2. Current State (verified against code)

**Already in omni (develop):**

- DPD computed at `Demand` level with per-account aggregation; bucket ranges (0–30 / 31–60 / 61–90 / 90+) configurable in product addons (`DpdSection` config exists in omni-web).
- Rule-driven notification engine (`notifications` app): JSONLogic conditions (can condition on DPD), email/SMS/push channels, role-based recipients, seedable events.
- `ContactAddress` carries pincode — the geography key for field allocation.
- `UserAssignment` models role + branch + department for staff; no territory/pincode mapping yet.
- `PaymentService` supports payment-link generation and settlement; eNACH via flow vendors.
- `collection_report_handler` produces collection MIS from demand/payment data.
- Docs framework for document storage/templates (used by CRE-5833 for selfies).

**In the CRE-5833 PR (omni, not merged):** new `collect` app — `CollectionEnquiry` (call/field-visit log with outcome, narration, PTP lifecycle open→fulfilled/broken/cancelled, payment capture, GPS, selfie), Collection Agent / Collection Head roles, daily tasks for PTP expiry + PTP-day reminders, notification events, contact enhancements.

**In the CRE-5834/5836 PRs (app):** agent screens — enquiry form/list/verification, PTP view, loan collection summary, contact listing.

**In web:** nothing beyond shared permission/RBAC type stubs. This is the biggest build gap.

## 3. Goals

1. **A supervisor can run collections end-to-end on Crego**: see the delinquent book by bucket, allocate it to agents, monitor recovery — measured by a client operating a full monthly collections cycle on-platform without external tooling.
2. **Every delinquent account is automatically cased and bucketed daily** from existing DPD data, with zero manual triggering — 100% of DPD>0 accounts have an open case within one EOD cycle.
3. **Allocation is rule-driven, not manual**: bucket + pincode (+ capacity) rules assign cases to agents; a supervisor can bulk-reallocate. Target ≥90% of cases auto-allocated without manual touch.
4. **Outreach and legal notices fire from configuration**: per-bucket cadences send payment reminders and generate legal notices without human initiation, inside RBI conduct guardrails.
5. **Collections behaviour is configurable per client/program, not coded**: buckets, cadences, allocation rules, and escalation are tenant configuration in omni — new client onboarding requires config, not code.

**Business goals:** make collections a sellable module (parity with LeadSquared Collections / Dista Collect / Credgenics-class features), deepen platform stickiness, and give clients an auditable RBI-compliance story.

## 4. Non-Goals (v1)

- **Repossession / asset disposal workflows** — separate, later initiative; low commonality across current clients.
- **AI dialers, sentiment scoring, next-best-action / propensity models** — industry direction, but premature before we have first-party collections data flowing.
- **Agency (third-party DCA) management** — v1 assumes in-house agents modeled as staff users; external-agency contracts, payouts and commission tracking are P2.
- **Building the workflow on crego-flow** — decided: collections state/config lives natively in omni. crego-flow remains origination-journey territory.

## 5. Personas & User Stories

**Collection Agent** (field/tele, uses the mobile app)
- As an agent, I want a prioritized worklist of my assigned cases (bucket, outstanding, PTP due today, geography-sorted) so that I work the right accounts first. *(P0)*
- As an agent, I want to log a call/visit outcome with PTP or payment in one flow so that my activity is captured without re-entry. *(Landing via CRE-5833/5834.)*

**Collection Head / Supervisor** (uses web)
- As a collection head, I want to see the delinquent portfolio by bucket, product, and region so that I know where recovery risk is concentrated. *(P0)*
- As a collection head, I want to define allocation rules (bucket × pincode-set × agent/team, with per-agent caseload caps) and run/re-run allocation so that the book is distributed without spreadsheets. *(P0)*
- As a collection head, I want to reassign cases in bulk when an agent leaves or a territory changes so that no case is orphaned. *(P0)*
- As a collection head, I want agent productivity views (visits, contacts, PTPs taken/kept, amount collected) so that I can manage the team. *(P1)*

**Ops / Platform Admin** (uses web)
- As an admin, I want to configure the collection strategy per product/program — bucket boundaries, communication cadence per bucket, legal-notice triggers — so that each client's policy runs without code changes. *(P0 in Phase 4)*
- As an admin, I want communication templates (SMS/email/WhatsApp) with merge fields and mandated disclosures so that outreach is consistent and compliant. *(P0 in Phase 3)*

**Borrower**
- As a borrower, I want reminders to include a payment link so that I can cure without talking to anyone. *(P0)*
- As a borrower, I must receive the recovery-agent details notification before an agent contacts me, and never be contacted outside 08:00–19:00 (RBI). *(P0 — compliance)*

## 6. Solution Overview & Phasing

The module is four layers, each shippable independently. New code lives in the existing `collect` app in omni; web work is a new `collections` module in omni-web.

### Phase 1 — Land the agent foundation (in flight)
Merge CRE-5833 (omni) and CRE-5834/5836 (app); add the missing minimal web surface: a read-only collections activity view (enquiries, PTPs) and role administration so Collection Head can be provisioned. Exit criterion: an agent can log activity end-to-end, and a supervisor can see it on web.

### Phase 2 — Case management, bucketing & allocation (the core)
**New models (omni `collect` app):**
- `CollectionCase` — one open case per delinquent account: current bucket, DPD snapshot, outstanding, assigned agent, status (`open / normalized / closed / legal / written_off`), audit trail. Enquiries link to the case. Created/updated by a daily EOD task from existing demand-level DPD; auto-normalized when account cures.
- `BucketDefinition` — tenant/program-scoped DPD ranges (default 1–30 SMA0…90+ NPA), reusing/extending existing addon DPD config rather than duplicating it.
- `AgentTerritory` — agent/team ↔ pincode-set mapping (extends `UserAssignment` context).
- `AllocationRule` + allocation engine — ordered rules matching (bucket, product, pincode, amount band) → agent pool; capacity-aware round-robin within pool; sticky assignment on bucket transition unless rule says escalate; nightly incremental run + on-demand full run; every decision audited.

**Web (new `collections` module in omni-web):** portfolio dashboard by bucket; case list with filters; case detail (timeline of enquiries/PTPs/payments/notices); allocation console (rules CRUD, run allocation, bulk reassign); territory management.

**App:** worklist becomes case-driven (assigned cases, priority-sorted) instead of raw loan lists.

### Phase 3 — Automated communications & legal notices
- `CommunicationCadence` — per bucket: sequence of touchpoints (day offset from bucket entry, channel, template). Executed by a daily scheduler; delivered through the existing notifications engine (new events + rules seeded); every reminder carries a payment link from `PaymentService`.
- **Compliance guardrails (hard, non-configurable-off):** sends only 08:00–19:00 borrower-local; recovery-agent-details notification auto-sent on case allocation before first agent contact; cooling-off/notice periods per RBI Digital Lending Directions 2025 and 2026 Master Direction supplement; all comms logged on the case.
- `LegalNotice` — template-driven notice generation (docs framework) triggered by cadence/bucket entry (e.g., LRN at 90+ DPD), with generated artifact stored, dispatch tracked (email/SMS/post ref), and case status → `legal`. Manual trigger with maker-checker for ad-hoc notices.

### Phase 4 — Configurable collection strategy (native omni)
`CollectionStrategy` — a versioned, tenant/program-scoped configuration object (JSON schema + admin UI in web, same pattern as product addons config) that binds the whole module: bucket definitions, per-bucket cadence, allocation ruleset, escalation triggers (e.g., 2 broken PTPs → escalate to Collection Head; bucket ≥ X → legal track), and PTP policy (max extensions, tolerance). The daily collections EOD task interprets the active strategy — behaviour changes are config publishes, not deployments. Strategy versions are immutable once published; cases reference the version that governs them.

## 7. Requirements Summary

**P0:** daily case creation/refresh from DPD; bucket assignment & transitions; allocation engine with bucket+pincode+capacity rules; supervisor web console (portfolio, case list/detail, allocation, reassignment); agent case worklist in app; per-bucket reminder cadences with payment links; RBI guardrails (contact-hours, agent-disclosure notice, comms logging); legal-notice generation with audit; strategy config per tenant/program.

**P1:** agent productivity dashboards; WhatsApp channel; broken-PTP auto-escalation; caseload rebalancing suggestions; collections MIS export extending `collection_report_handler`.

**P2 (design for, don't build):** external agency management & payouts; settlement/waiver workflows with approval matrices; propensity-to-pay scoring & AI prioritization; repossession pipeline; IIBF certification registry for agents.

**Key acceptance criteria (samples):**
- Given an account crosses DPD 0→1 at EOD, when the collections task runs, then an open `CollectionCase` exists in the correct bucket within that cycle, and is auto-allocated if a rule matches.
- Given a case is allocated to an agent, when allocation completes, then the borrower receives the agent-details notification before any enquiry can be logged against the case by that agent.
- Given a cadence schedules an SMS at 21:00 borrower-local, when the scheduler evaluates it, then the send is deferred to 08:00 next day and the deferral is logged.
- Given an account fully cures, when EOD runs, then the case auto-normalizes, pending cadence touchpoints cancel, and the agent's worklist drops it.

## 8. Success Metrics

- **Adoption (leading):** ≥1 client running full monthly cycle on-platform within 1 quarter of Phase 2 GA; ≥90% auto-allocation rate; ≥80% of agent-logged activity via app (vs. backfilled).
- **Operational (leading):** % delinquent accounts with ≥1 outreach within 3 days of bucket entry (target ≥95%); PTP kept rate (baseline then improve); reminder→payment-link conversion.
- **Outcome (lagging):** bucket roll-back rate (e.g., X% of 1–30 DPD cured before 31); recovery ₹ attributable to platform-initiated touchpoints; zero RBI conduct violations (contact-hour breaches = 0, agent-disclosure coverage = 100%).

## 9. Open Questions

1. **(Blocking, product)** Bucket taxonomy: standardize on SMA-0/1/2 + NPA naming or keep numeric DPD ranges per client? Affects `BucketDefinition` defaults and reporting.
2. **(Blocking, engineering)** Case granularity: per **account** or per **demand**? PRD assumes per account (industry norm); confirm against multi-tranche/SCF products where per-demand may matter.
3. **(Product)** Does the existing addon DPD config become the source of truth for `BucketDefinition`, or is collections bucketing intentionally decoupled from provisioning buckets? Recommend decoupled-but-defaulted.
4. **(Compliance/legal)** Exact notice content & 30-day recovery-agent appointment notice interpretation under the 2026 Master Direction supplement — needs legal sign-off before Phase 3 templates ship.
5. **(Engineering)** Allocation scale: expected case volumes per tenant? Determines whether nightly full re-allocation is feasible or incremental-only.
6. **(Product)** WhatsApp as a Phase 3 channel requires BSP integration — in scope for v1 or P1?

## 10. Timeline & Dependencies

- **Phase 1** — land existing PRs; small web surface. Dependencies: PR review of CRE-5833/5834/5836. Target: next minor release.
- **Phase 2** — ~1 release cycle after Phase 1. Depends on Q1/Q2 answers. Heaviest lift is web (`collections` module is net-new).
- **Phase 3** — parallel-startable with Phase 2 backend (cadence engine only needs cases + buckets). Depends on legal sign-off (Q4) and template creation.
- **Phase 4** — after Phase 2/3 stabilize; converts their hardcoded defaults into strategy config. Do **not** ship Phase 2/3 with per-tenant code branches — build against a default strategy object from day one so Phase 4 is UI + versioning, not a rewrite.

Suggested Linear structure: one project "Collections Module", milestones per phase, issues prefixed CRE- with `repo/*` labels per the workspace convention.

---

## Appendix A — Industry & Regulatory References

- Industry patterns (DPD bucketing, allocation, field + tele workflows): [DPDzero — Demystifying Debt Collections in India](https://dpdzero.com/blogs/demystifying-debt-collections-in-india/), [LeadSquared Debt Collection Platform](https://www.leadsquared.com/debt-collection-platform/), [Dista Collect NBFC case study](https://dista.ai/success-stories/nbfc-end-to-end-collections/), [Biz2X — Collections software features](https://www.biz2x.com/india/collections-management-system/features-of-debt-collection-management-software/)
- Regulatory: [RBI Digital Lending Directions FAQs](https://www.rbi.org.in/commonman/english/scripts/FAQs.aspx?Id=3413), [RBI Digital Lending Directions, 2025 — overview](https://synergialegal.com/an-overview-of-the-rbis-digital-lending-direction-2025/), [2026 uniform recovery norms proposal](https://vinodkothari.com/2026/02/rbi-proposes-uniform-recovery-norms-across-all-lenders/), [RBI recovery agent rules 2026](https://solvlegal.com/blogs/rbi-loan-recovery-agent-rules-2026-india/)

Key regulatory constraints baked into P0: contact window 08:00–19:00 (all channels incl. automated), borrower notification of authorized recovery-agent particulars before contact, 30-day notice before recovery-agent appointment, no third-party disclosure of default info, IIBF certification for agents (tracked as P2 registry), data residency in India.
