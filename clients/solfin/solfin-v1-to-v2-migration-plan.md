# Solfin V1 → V2 Migration Plan

**Cutover:** Saturday, 18 April 2026 (23:00 IST) — Sunday, 19 April 2026 (02:00 IST)
**Downtime window:** 3 hours (23:00 – 02:00 IST)
**Source:** V1 on Crego Cloud
**Target:** V2 on Solfin Cloud
**Rollback window:** V1 stays hot for **14 days** post-cutover (no parallel usage, no real‑time sync)

---

## 1. Scope & Objectives

Solfin is migrating from the shared Crego Cloud deployment (V1) to a dedicated Solfin Cloud deployment (V2). The migration covers four workstreams captured in the original scoping note:

**In scope**

1. **Cloud shift** — Infrastructure relocation from Crego Cloud to Solfin Cloud.
2. **UI changes** — Login screen, menu, color theme, user & role model, whitelabelling support.
3. **IP + Domain changes** — New public IPs, new domain, whitelisting updates across partners (BRD reference).
4. **Data migration** — Snapshot of V1 production data cut over after UAT sign‑off.
5. **API integration changes** — Lead creation integration contract update between Solfin and Crego.

**Out of scope**

- Real‑time or delta synchronisation between V1 and V2 (explicitly excluded).
- Running V1 and V2 in parallel for active business use.
- Any feature additions beyond the V2 baseline already under UAT.

---

## 2. Assumptions

- V2 is already deployed on Solfin Cloud and UAT on real V1 data has been completed by EOD **Friday, 17 April 2026**.
- All whitelabelling (login, menu, colors, roles) has been merged and signed off before cutover weekend.
- DNS TTLs for the new V2 domain have been lowered to ≤ 300 seconds at least 48 hours prior to cutover.
- Stakeholders (Solfin business owners) are available on **Sat 19 April evening and Sun 20 April** for post‑migration validation.
- No new business transactions are expected on V1 during the 3‑hour downtime window.
- Rollback within the 14‑day window is a **manual business decision**, not an automated failover.

---

## 3. Pre‑Migration (T‑7 to T‑1)

### 3.1 Infra & Environment Readiness (T‑7 to T‑3)

- Verify V2 Solfin Cloud environment is healthy: K8s, databases, object storage, queues, observability.
- Confirm `crego-infra` overlay for Solfin Cloud is on the target release tag.
- Take a baseline backup of V2 (empty/UAT state) for rollback of V2 itself if migration scripts corrupt data.
- Validate secrets, KMS keys, and service accounts on Solfin Cloud.
- Confirm Sentry, logging, and alerting are pointing at V2 projects.

### 3.2 IP + Domain + Whitelisting (T‑5 to T‑2)

- Publish final list of V2 egress and ingress IPs.
- Raise whitelisting change requests (as per BRD) with:
  - Banking / bureau partners
  - Payment gateways
  - Email / SMS providers
  - Any third‑party API consumers calling into Solfin
- Keep **V1 IPs whitelisted in parallel** — these must remain whitelisted for the full 14‑day rollback window.
- DNS: create V2 records with low TTL; do **not** cut over yet.

### 3.3 UI / Whitelabelling Readiness (T‑3)

- Final visual QA pass on V2: login screen, menu, color tokens, user & role matrix.
- Capture before/after screenshots for the stakeholder review pack.

### 3.4 API Integration — Lead Creation (T‑3 to T‑1)

**Current (V1) flow:** Solfin's upstream systems call Crego Cloud lead‑creation API.
**Target (V2) flow:** Solfin's upstream systems call Solfin Cloud lead‑creation API (same contract, new base URL + new auth credentials).

Steps:

- Share new V2 base URL, API keys, and whitelisted source IPs with the Solfin integration team.
- Solfin integration team prepares a config‑driven switch (feature flag or env var) to flip from V1 endpoint to V2 endpoint.
- Dry‑run against V2 using test payloads from a non‑prod Solfin client.
- Confirm request/response schema parity; log any mismatches and fix before cutover.
- Agree on the **exact moment** Solfin flips the endpoint (target: T0 + 2h, after DB migration completes and smoke tests pass).

### 3.5 Communications (T‑2 to T‑1)

- Send downtime notice to Solfin stakeholders and end‑users: **Sat 18 April, 23:00 – Sun 19 April, 02:00 IST.**
- Share rollback policy: "V1 remains available as a rollback target for 14 days; there is no live sync between V1 and V2 — any data created on V2 post‑cutover will be lost if we roll back."
- War‑room bridge, Slack channel, and on‑call rota confirmed.

### 3.6 Go / No‑Go (T‑1, Friday 17 April, 18:00 IST)

Go/No‑Go checklist must be green:

- [ ] UAT on real V1 data signed off
- [ ] V2 environment healthy
- [ ] Whitelisting confirmed by all partners
- [ ] DNS TTL lowered
- [ ] Backup/rollback plan reviewed and owners assigned
- [ ] Solfin integration team ready to flip endpoint
- [ ] Stakeholders notified

---

## 4. Cutover Timeline — Saturday 18 April 2026

| Time (IST)    | Activity                                                                                                   | Owner              |
| ------------- | ---------------------------------------------------------------------------------------------------------- | ------------------ |
| 22:30         | War room opens, roll call, final Go/No‑Go                                                                  | Release Manager    |
| 23:00         | **Downtime starts.** Disable the execute‑runner API on V1 to block new write traffic (V1 has no maintenance banner). | Platform           |
| 23:05         | Stop all V1 background workers (Celery, cron, queue consumers). Drain in‑flight jobs.                      | Platform           |
| 23:10         | Take final V1 DB snapshot (Postgres / Mongo / object storage). Verify checksum and size.                   | DBA                |
| 23:25         | Transfer snapshot to Solfin Cloud (secure channel).                                                        | DBA                |
| 23:45         | Restore snapshot into V2 databases. Run migration / transformation scripts if any.                         | DBA                |
| 00:30         | Run data validation suite (see §5).                                                                        | QA + Platform      |
| 01:00         | Smoke test V2: login, key user journeys, lead creation, role‑based access.                                 | QA                 |
| 01:15         | **Flip lead‑creation integration** from V1 endpoint → V2 endpoint at Solfin upstream.                      | Solfin Integration |
| 01:20         | Flip DNS / domain to point at V2. Verify propagation.                                                      | Platform           |
| 01:30         | Update IP whitelisting status with partners (confirm V2 IPs live; keep V1 IPs active for rollback window). | Platform           |
| 01:40         | Final end‑to‑end test (login → create lead via Solfin upstream → verify in V2 UI).                         | QA                 |
| 01:55         | Announce migration complete.                                                                               | Release Manager    |
| 02:00         | **Downtime ends.** V2 is live.                                                                             | —                  |
| 02:00 – 03:00 | Hypercare monitoring: error rates, latency, Sentry, logs.                                                  | On‑call            |

---

## 5. Production Data Validation Steps

Run immediately after DB restore and again after smoke tests. All checks must pass before the migration is announced complete.

### 5.1 Structural checks

- Table / collection counts match V1 snapshot exactly.
- Verify document counts match V1 for each of the following collections:
  - `_counters`
  - `activities`
  - `activity_entries`
  - `approval_requests`
  - `audit_logs`
  - `checklist_templates`
  - `default`
  - `designs`
  - `documents`
  - `flows`
  - `policies`
  - `presets`
  - `runners`
  - `secrets`
  - `stores`
  - `templates`
  - `warehouses`
  - `workbook_operations`
  - `workflow_checklists`
- Schema version / migration history matches expected V2 head.

### 5.2 Integrity checks

- Primary key uniqueness holds on all critical tables.
- Foreign key references resolve (no orphaned leads, no orphaned role assignments).
- Attachment / object storage file counts and total byte size match V1.

### 5.3 Business‑logic spot checks

- Latest 50 leads from V1 exist in V2 with identical status, owner, and timestamps.
- All active users can authenticate (sample 20 users across roles).
- Role matrix: each role sees the same menu items and permissions as in V1.
- Sum of monetary fields (e.g., loan amounts, disbursements) matches V1 totals per client/tenant.
- Latest audit‑log entry timestamp on V2 ≥ timestamp at which V1 execute‑runner API was disabled.

### 5.4 Integration checks

- Lead creation from Solfin upstream lands in V2 with correct `source`, `tenant`, and `created_by`.
- Outbound webhooks/callbacks from V2 reach partner sandboxes.
- Email/SMS providers accept traffic from new V2 IPs.

Validation results are logged to a shared sheet and signed off by QA lead + DBA lead before go‑live announcement.

---

## 6. Post‑Migration — Sunday 19 & Monday 20 April

- **Sun 19 Apr morning:** Internal team validation on V2.
- **Sun 19 Apr:** Main stakeholders review V2 on real migrated data.
- **Mon 20 Apr:** Business goes live on V2 for all users.
- Hypercare: dedicated on‑call, 30‑minute error‑rate check‑ins for first 24 hours, hourly for next 48 hours.
- Daily status update to stakeholders for the first week.

---

## 7. Rollback Plan

**Rollback is available for 14 days** from cutover (until **02 May 2026**). Rollback is a manual business decision triggered by the Release Manager with sign‑off from the Solfin business owner.

### 7.1 Rollback triggers (any one)

- Critical data integrity issue discovered on V2 that cannot be hotfixed.
- Sustained P1 outage on V2 > 2 hours with no ETA.
- Business‑blocking functional regression reported by stakeholders.

### 7.2 Rollback principle

Because there is **no real‑time sync between V1 and V2**, any data created on V2 after cutover will be lost on rollback. This is explicitly accepted — stakeholders have been informed.

### 7.3 Rollback procedure (reverse of cutover)

1. Announce rollback window and disable the execute‑runner API on V2 to block new write traffic.
2. Stop V2 background workers and drain queues.
3. Flip the Solfin lead‑creation integration endpoint back from V2 → V1.
4. Flip DNS back to V1 (TTL already low → fast propagation).
5. Re‑enable the execute‑runner API on V1 and restart V1 background workers (infra was left running but idle).
6. Confirm V1 databases are intact and match the pre‑cutover snapshot.
7. Run the same validation suite from §5 against V1 to confirm health.
8. Notify partners: traffic reverts to V1 IPs — V1 IPs are still whitelisted (kept active for this 14‑day window).
9. Communicate to stakeholders: "V2 data created since cutover has been discarded as per agreed rollback policy."
10. Open a post‑mortem and decide on re‑cutover date.

### 7.4 What must stay available for 14 days

- V1 application stack on Crego Cloud (hot, idle).
- V1 databases in last‑known‑good state.
- V1 IPs whitelisted with all partners.
- V1 DNS records available (not deleted, just not primary).
- Snapshot backups of both V1 (pre‑cutover) and V2 (daily).

### 7.5 After 14 days (from 03 May 2026)

- Final decision: decommission V1.
- Remove V1 IPs from partner whitelists.
- Archive V1 database snapshot to cold storage (retain per compliance policy).
- Tear down V1 compute on Crego Cloud.
- Update `crego-infra` to remove the V1‑Solfin overlay.

---

## 8. Risks & Mitigations

| #   | Risk                                        | Likelihood | Impact | Mitigation                                                                        |
| --- | ------------------------------------------- | ---------- | ------ | --------------------------------------------------------------------------------- |
| 1   | Data migration script fails mid‑restore     | Med        | High   | Dry‑run on UAT copy; keep V1 snapshot untouched                                   |
| 2   | Partner whitelisting not ready on time      | Med        | High   | Start T‑5; keep V1 IPs active as fallback                                         |
| 3   | DNS propagation delay                       | Low        | Med    | Lower TTL 48h in advance                                                          |
| 4   | Lead creation endpoint flip misconfigured   | Med        | High   | Config‑flag driven flip, tested in dry run                                        |
| 5   | Data created on V2 lost on rollback         | Low        | Med    | Communicated to stakeholders; rollback is explicit business decision              |
| 6   | Downtime exceeds 3‑hour window              | Med        | Med    | Rehearse cutover; hard decision point at 01:30 IST to either proceed or roll back |
| 7   | Stakeholders unavailable for Sat/Sun review | Low        | Med    | Confirmed availability at T‑1 Go/No‑Go                                            |

---

_Crego × Solfin_
_Version: 1.0 — Created 10 April 2026
