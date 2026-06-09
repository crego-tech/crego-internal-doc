# Tyger Capital V1 → V2 Migration Plan

- **Launch date:** 6 July 2026 (Monday)
- **Cutover (T):** 5 July 2026 — Sunday
- **Downtime window:** 12:00 AM – 7:00 AM IST, Sunday 5 July 2026
- **Source (V1):** `tyger.jupiter.crego.io` — Crego Jupiter platform
- **Target (V2):** `tyger.crego.ai` — Crego V2 platform
- **Parallel‑run period:** 14 days post‑cutover (or until next month‑end) — both V1 and V2 are live; Tyger Capital team works primarily on V2 while also entering data into V1

---

## 1. Scope & Objectives

Tyger Capital is migrating from the Crego Jupiter platform (V1) to the Crego V2 platform. This is a **platform shift** — the underlying infrastructure provider does not change, but the application platform, URL, and IPs do.

**In scope**

1. **Platform shift** — Move from `tyger.jupiter.crego.io` (V1) to `tyger.crego.ai` (V2). New URL, new IPs; same infrastructure provider.
2. **UI changes** — Login screen, menu, color theme, user & role model updates. *(Confirmed ready.)*
3. **IP + Domain changes** — New public IPs and domain. IP whitelisting updates required across partners. *(Confirmed ready.)*
4. **Data migration** — Snapshot of V1 production data cut over after UAT sign‑off. *(Confirmed ready.)*
5. **API integration changes** — SBI H2H integration updated by the Crego team. IP whitelisting for Crego V2 platform must be completed with SBI.

**Out of scope**

- Any feature additions beyond the V2 baseline already under UAT.
- Changes to the SBI H2H integration contract itself (only IP/URL whitelisting changes).

---

## 2. Assumptions

- V2 is deployed on the Crego V2 platform and UAT on real V1 data has been completed before the cutover weekend.
- UI changes (login, menu, colors, roles) have been merged and signed off before cutover.
- DNS TTLs for `tyger.crego.ai` have been lowered to ≤ 300 seconds at least 48 hours prior to cutover.
- Tyger Capital stakeholders are available on cutover Sunday and the following Monday for post‑migration validation.
- No new business transactions are expected on V1 during the downtime window on Sunday.
- Both V1 and V2 will run in parallel for 14 days (or until the next month‑end). Tyger Capital primarily uses V2 but also enters data into V1 during this period.
- V1 decommissioning happens only after Tyger Capital confirms V2 reports match and they are confident in the product.

---

## 3. Pre‑Migration (T‑7 to T‑1)

### 3.1 Infra & Environment Readiness (T‑7 to T‑3)

- Verify V2 environment on the Crego V2 platform is healthy: K8s, databases, object storage, queues, observability.
- Confirm `crego-infra` overlay for Tyger Capital on V2 is on the target release tag.
- Take a baseline backup of V2 (empty/UAT state) in case migration scripts corrupt data.
- Validate secrets, KMS keys, and service accounts on the V2 platform.
- Confirm Sentry, logging, and alerting are pointing at V2 projects.

### 3.2 IP + Domain + Whitelisting (T‑5 to T‑2)

- Publish final list of V2 egress and ingress IPs for `tyger.crego.ai`.
- Raise whitelisting change requests with:
  - **SBI** (critical — required for H2H integration on V2 IPs)
  - Email / SMS providers
  - Any third‑party API consumers calling into Tyger Capital
- Keep **V1 IPs whitelisted in parallel** — these must remain whitelisted for the full parallel‑run period.
- DNS: create `tyger.crego.ai` records with low TTL; do **not** cut over yet.

### 3.3 UI Readiness (T‑3)

- Final visual QA pass on V2: login screen, menu, color tokens, user & role matrix.
- Capture before/after screenshots for the stakeholder review pack.

### 3.4 API Integration — SBI H2H (T‑3 to T‑1)

**Current (V1) flow:** SBI H2H integration connects to `tyger.jupiter.crego.io` IPs.
**Target (V2) flow:** SBI H2H integration connects to `tyger.crego.ai` IPs. The integration is updated by the Crego team; the contract remains the same, only the IP whitelisting changes.

Steps:

- Crego team updates the SBI H2H integration configuration to use V2 platform endpoints.
- Submit IP whitelisting update request to SBI for the Crego V2 platform IPs.
- Confirm SBI has whitelisted the new V2 IPs and that the H2H connection is functional.
- Dry‑run the H2H flow end‑to‑end on V2 using test data.
- Keep V1 IPs whitelisted with SBI for the parallel‑run period.

### 3.5 Communications (T‑1, Saturday 4 July 2026)

- Send downtime notice to Tyger Capital stakeholders and end‑users for Sunday 5 July 2026 (12:00 AM – 7:00 AM IST).
- Communicate the parallel‑run policy: "V1 and V2 will both remain live for 14 days (or until month‑end). Tyger Capital team will primarily use V2 while also entering data into V1. Once V1 and V2 reports match and the team is confident, V1 will be decommissioned."
- War‑room bridge, Slack channel, and on‑call rota confirmed.

### 3.6 Go / No‑Go (T‑1)

Go/No‑Go checklist must be green:

- [ ] UAT on real V1 data signed off
- [ ] V2 environment healthy on Crego V2 platform
- [ ] SBI IP whitelisting confirmed for V2 IPs
- [ ] All other partner whitelisting confirmed
- [ ] DNS TTL lowered for `tyger.crego.ai`
- [ ] Backup plan reviewed and owners assigned
- [ ] SBI H2H integration tested end‑to‑end on V2
- [ ] Stakeholders notified of Sunday downtime and parallel‑run policy

---

## 4. Cutover Timeline — Sunday `5 July 2026`

| Time (IST)    | Activity                                                                                                   |
| ------------- | ---------------------------------------------------------------------------------------------------------- |
| T − 0:30      | War room opens, roll call, final Go/No‑Go                                                                  |
| T + 0:00      | **Downtime starts.** Disable the execute‑runner API on V1 to block new write traffic.                       |
| T + 0:05      | Stop all V1 background workers (Celery, cron, queue consumers). Drain in‑flight jobs.                      |
| T + 0:10      | Take final V1 DB snapshot (Postgres / Mongo / object storage). Verify checksum and size.                   |
| T + 0:25      | Transfer snapshot to V2 environment (secure channel).                                                      |
| T + 0:45      | Restore snapshot into V2 databases. Run migration / transformation scripts if any.                         |
| T + 1:30      | Run data validation suite (see §5).                                                                        |
| T + 2:00      | Smoke test V2: login, key user journeys, loan workflows, SBI H2H, role‑based access.                      |
| T + 2:15      | Verify SBI H2H integration is live on V2 IPs.                                                              |
| T + 2:20      | Flip DNS: `tyger.crego.ai` → V2. Verify propagation.                                                       |
| T + 2:30      | Update IP whitelisting status with partners (confirm V2 IPs live; keep V1 IPs active for parallel‑run).    |
| T + 2:40      | Final end‑to‑end test (login → loan workflow → SBI H2H → verify in V2 UI).                                 |
| T + 2:55      | Announce migration complete. V2 is primary.                                                                 |
| T + 3:00      | **Downtime ends.** V2 is live at `tyger.crego.ai`.                                                          |
| T + 3:00–4:00 | Hypercare monitoring: error rates, latency, Sentry, logs.                                                  |
| T + 3:00      | **Re‑enable V1** at `tyger.jupiter.crego.io` for parallel‑run (data entry continues on both systems).       |

---

## 5. Production Data Validation Steps

Run immediately after DB restore and again after smoke tests. All checks must pass before the migration is announced complete.

### 5.1 Count matching

Verify that the following counts match exactly between V1 and V2:

- Pending list of **loans** (count and total amounts)
- Pending list of **drawdowns** (count and total amounts)
- **Payments** (count and total amounts)
- **Upfront interest and excess** (count and total amounts)

### 5.2 Report matching

The following reports must produce identical output on V1 and V2:

- **Trial balance report** — All account balances must match to the paisa.
- **GL (General Ledger) report** — All journal entries, debit/credit totals must match.
- **Customer portfolio report** — All customer‑level exposures, statuses, and balances must match.

### 5.3 Structural checks

- Table / collection counts match V1 snapshot exactly.
- Schema version / migration history matches expected V2 head.

### 5.4 Integrity checks

- Primary key uniqueness holds on all critical tables.
- Foreign key references resolve (no orphaned loans, no orphaned role assignments).
- Attachment / object storage file counts and total byte size match V1.

### 5.5 Integration checks

- SBI H2H integration functional on V2 IPs — test transaction round‑trips successfully.
- Outbound webhooks/callbacks from V2 reach partner endpoints.
- Email/SMS providers accept traffic from new V2 IPs.

Validation results are logged to a shared sheet and signed off by QA lead + DBA lead before go‑live announcement.

---

## 6. Post‑Migration — Parallel‑Run Period

### 6.1 Immediate (cutover Sunday + Monday)

- **Sunday:** Internal team validation on V2; V1 re‑enabled for parallel data entry.
- **Monday:** Tyger Capital team begins using V2 as the primary system. All data is also entered into V1 by the Tyger Capital team.
- Hypercare: dedicated on‑call, 30‑minute error‑rate check‑ins for first 24 hours, hourly for next 48 hours.

### 6.2 Parallel‑run (14 days or until month‑end)

- Tyger Capital works primarily on V2 (`tyger.crego.ai`).
- All transactions are also entered into V1 (`tyger.jupiter.crego.io`) during this period.
- At each week‑end (and at month‑end), compare reports across V1 and V2:
  - Trial balance report
  - GL report
  - Customer portfolio report
- Daily status update to Tyger Capital stakeholders for the first week; weekly thereafter.

### 6.3 Exit criteria — end of parallel‑run

The parallel‑run ends and V1 is decommissioned when **all** of the following are met:

- [ ] V2 reports (trial balance, GL, customer portfolio) match V1 for the parallel‑run period.
- [ ] Tyger Capital team confirms confidence in V2 product.
- [ ] At least 14 days have elapsed since cutover, **or** the next month‑end close has been completed on V2.
- [ ] Tyger Capital business owner signs off on V1 decommissioning.

---

## 7. Transition & Wind‑Down Plan

There is no formal rollback plan. Instead, the parallel‑run provides a safety net.

### 7.1 During the parallel‑run

- Both V1 and V2 are live and receiving data.
- If a critical issue is found on V2, Tyger Capital can **increase their reliance on V1** while the issue is resolved — no formal cutover reversal is needed because V1 never went offline.
- The Crego team treats V2 issues as P1 during the parallel‑run window.

### 7.2 What must stay available during the parallel‑run

- V1 application stack at `tyger.jupiter.crego.io` (live, actively receiving data).
- V1 databases in active state.
- V1 IPs whitelisted with all partners (including SBI).
- V1 DNS records active.
- Daily backups of both V1 and V2.

### 7.3 After the parallel‑run (V1 decommissioning)

Once exit criteria in §6.3 are met:

- Stop all V1 background workers and disable the V1 application.
- Remove V1 IPs from partner whitelists (including SBI).
- Archive V1 database snapshot to cold storage (retain per compliance policy).
- Tear down V1 compute.
- Update `crego-infra` to remove the V1 Tyger Capital overlay.
- Decommission `tyger.jupiter.crego.io` DNS records.

---

## 8. Risks & Mitigations

| #   | Risk                                                      | Likelihood | Impact | Mitigation                                                                                         |
| --- | --------------------------------------------------------- | ---------- | ------ | -------------------------------------------------------------------------------------------------- |
| 1   | Data migration script fails mid‑restore                   | Med        | High   | Dry‑run on UAT copy; keep V1 snapshot untouched                                                    |
| 2   | SBI IP whitelisting not ready on time                     | Med        | High   | Start at T‑5; keep V1 IPs active; H2H can fall back to V1 during parallel‑run                     |
| 3   | DNS propagation delay for `tyger.crego.ai`                | Low        | Med    | Lower TTL 48h in advance                                                                           |
| 4   | SBI H2H integration fails on V2 IPs                      | Med        | High   | Dry‑run before cutover; V1 remains live as fallback during parallel‑run                            |
| 5   | Reports mismatch between V1 and V2 during parallel‑run   | Med        | High   | Compare reports weekly; investigate and fix discrepancies before month‑end                          |
| 6   | Downtime exceeds planned window on Sunday                 | Med        | Med    | Rehearse cutover; hard decision point at T + 2:00 to either proceed or defer                       |
| 7   | Dual data entry burden on Tyger Capital team              | Med        | Med    | Limit parallel‑run to 14 days or next month‑end; provide support for data entry queries            |
| 8   | Stakeholders unavailable on cutover Sunday                | Low        | Med    | Confirmed availability at T‑1 Go/No‑Go                                                            |

---

_Version: 1.0 — Created 30 May 2026_
