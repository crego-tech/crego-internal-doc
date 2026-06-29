# Indifi V1 → V2 Migration Plan

- **Cutover:** Saturday 11 July 2026, 23:00 IST – Sunday 12 July 2026, 04:00 IST
- **Downtime window:** 5 hours (23:00 – 04:00 IST)
- **Source (V1):** Indifi AWS Cloud (ECS)
- **Target (V2):** Indifi AWS Cloud (EKS)
- **Rollback window:** V1 stays hot for **14 days** post-cutover (no parallel usage, no real‑time sync)

---

## 1. Scope & Objectives

Indifi is migrating from V1 (running on Indifi's AWS Cloud using ECS) to V2 (running on Indifi's AWS Cloud using EKS). Both environments are on Indifi's own AWS infrastructure — this is a **platform shift from ECS to EKS**, not a cloud shift. The migration covers four workstreams:

**In scope**

1. **Platform shift (ECS → EKS)** — Migration from AWS ECS (V1) to AWS EKS (V2) within Indifi's own AWS cloud. New URL, new IPs; same AWS account.
2. **IP + Domain changes** — New public IPs, new domain, whitelisting updates across partners (BRD reference).
3. **Data migration** — Snapshot of V1 production data cut over after UAT sign‑off.
4. **API integration changes** — All APIs that Indifi has integrated will change. Refer to the V2 API collection for the updated contracts.

**Out of scope**

- Real‑time or delta synchronisation between V1 and V2 (explicitly excluded).
- Running V1 and V2 in parallel for active business use.
- Any feature additions beyond the V2 baseline already under UAT.

---

## 2. Assumptions

- V2 is already deployed on Indifi's AWS EKS and UAT on real V1 data has been completed by EOD **Friday 10 July 2026**.
- DNS TTLs for the new V2 domain have been lowered to ≤ 300 seconds at least 48 hours prior to cutover.
- Stakeholders (Indifi business owners) are available on **Sun 12 July and Mon 13 July** for post‑migration validation.
- No new business transactions are expected on V1 during the 5‑hour downtime window.
- Rollback within the 14‑day window is a **manual business decision**, not an automated failover.

---

## 3. Pre‑Migration (T‑7 to T‑1)

### 3.1 Infra & Environment Readiness (T‑7 to T‑3)

- Verify V2 EKS environment is healthy: K8s cluster, databases, object storage (S3), queues, observability.
- Confirm `crego-infra` overlay for Indifi EKS is on the target release tag.
- Take a baseline backup of V2 (empty/UAT state) for rollback of V2 itself if migration scripts corrupt data.
- Validate secrets, KMS keys, and service accounts on the EKS environment.
- Confirm Sentry, logging, and alerting are pointing at V2 projects.

### 3.2 IP + Domain + Whitelisting (T‑5 to T‑2)

- Publish final list of V2 egress and ingress IPs.
- Raise whitelisting change requests (as per BRD) with:
  - Banking / bureau partners
  - Payment gateways
  - Email / SMS providers
  - Any third‑party API consumers calling into Indifi
- Keep **V1 IPs whitelisted in parallel** — these must remain whitelisted for the full 14‑day rollback window.
- DNS: create V2 records with low TTL; do **not** cut over yet.

### 3.3 API Integration Changes (T‑3 to T‑1)

All APIs that Indifi has integrated will change in V2. The **V2 API collection** is the source of truth for updated contracts.

Steps:

- Share the V2 API collection with the Indifi integration team — covers all changed endpoints, request/response schemas, auth, and base URLs.
- Indifi integration team reviews the collection and maps each V1 API call to its V2 equivalent.
- Indifi integration team prepares a config‑driven switch (feature flag or env var) to flip from V1 endpoints to V2 endpoints.
- Dry‑run all integrated APIs against V2 using test payloads from a non‑prod Indifi client.
- Confirm request/response schema parity for each endpoint; log any mismatches and fix before cutover.
- Agree on the **exact moment** Indifi flips the endpoints (target: T0 + 2h, after DB migration completes and smoke tests pass).

### 3.4 Communications (T‑2 to T‑1)

- Send downtime notice to Indifi stakeholders and end‑users: **Sat 11 July 2026, 23:00 – Sun 12 July 2026, 04:00 IST.**
- Share rollback policy: "V1 remains available as a rollback target for 14 days; there is no live sync between V1 and V2 — any data created on V2 post‑cutover will be lost if we roll back."
- War‑room bridge, Slack channel, and on‑call rota confirmed.

### 3.5 Go / No‑Go (T‑1)

Go/No‑Go checklist must be green:

- [ ] UAT on real V1 data signed off
- [ ] V2 environment healthy
- [ ] Whitelisting confirmed by all partners
- [ ] DNS TTL lowered
- [ ] Backup/rollback plan reviewed and owners assigned
- [ ] Indifi integration team ready to flip endpoint
- [ ] Stakeholders notified

---

## 4. Cutover Timeline — Saturday 11 July 2026

| Time (IST)    | Activity                                                                                                   | Owner              |
| ------------- | ---------------------------------------------------------------------------------------------------------- | ------------------ |
| 22:30         | War room opens, roll call, final Go/No‑Go                                                                  | Release Manager    |
| 23:00         | **Downtime starts.** Disable the execute‑runner API on V1 to block new write traffic (V1 has no maintenance banner). | Platform           |
| 23:05         | Stop all V1 background workers (Celery, cron, queue consumers). Drain in‑flight jobs.                      | Platform           |
| 23:10         | Take final V1 DB snapshot (Postgres / Mongo / object storage). Verify checksum and size.                   | DBA                |
| 23:25         | Transfer snapshot to V2 EKS environment (secure channel).                                                  | DBA                |
| 23:45         | Restore snapshot into V2 databases. Run migration / transformation scripts if any.                         | DBA                |
| 00:30         | Run data validation suite (see §5).                                                                        | QA + Platform      |
| 01:00         | Smoke test V2: login, key user journeys, lead creation, role‑based access.                                 | QA                 |
| 01:15         | **Flip lead‑creation integration** from V1 endpoint → V2 endpoint at Indifi upstream.                      | Indifi Integration |
| 01:20         | Flip DNS / domain to point at V2. Verify propagation.                                                      | Platform           |
| 01:30         | Update IP whitelisting status with partners (confirm V2 IPs live; keep V1 IPs active for rollback window). | Platform           |
| 01:40         | Final end‑to‑end test (login → create lead via Indifi upstream → verify in V2 UI).                         | QA                 |
| 01:55         | Announce migration complete.                                                                               | Release Manager    |
| 04:00         | **Downtime ends.** V2 is live.                                                                             | —                  |
| 04:00 – 05:00 | Hypercare monitoring: error rates, latency, Sentry, logs.                                                  | On‑call            |

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

- Lead creation from Indifi upstream lands in V2 with correct `source`, `tenant`, and `created_by`.
- Outbound webhooks/callbacks from V2 reach partner endpoints.
- Email/SMS providers accept traffic from new V2 IPs.

Validation results are logged to a shared sheet and signed off by QA lead + DBA lead before go‑live announcement.

---

## 6. Post‑Migration — Parallel‑Run Period

### 6.1 Immediate (cutover day + next day)

- **Day 1:** Internal team validation on V2; V1 re‑enabled for parallel data entry.
- **Day 2:** Indifi team begins using V2 as the primary system. All data is also entered into V1 by the Indifi team.
- Hypercare: dedicated on‑call, 30‑minute error‑rate check‑ins for first 24 hours, hourly for next 48 hours.

### 6.2 Parallel‑run (14 days or until month‑end)

- Indifi works primarily on V2.
- All transactions are also entered into V1 during this period.
- At each week‑end (and at month‑end), compare reports across V1 and V2:
  - Trial balance report
  - GL report
  - Customer portfolio report
- Daily status update to Indifi stakeholders for the first week; weekly thereafter.

### 6.3 Exit criteria — end of parallel‑run

The parallel‑run ends and V1 is decommissioned when **all** of the following are met:

- [ ] V2 reports (trial balance, GL, customer portfolio) match V1 for the parallel‑run period.
- [ ] Indifi team confirms confidence in V2 product.
- [ ] At least 14 days have elapsed since cutover, **or** the next month‑end close has been completed on V2.
- [ ] Indifi business owner signs off on V1 decommissioning.

---

## 7. Rollback Plan

**Rollback is available for 14 days** from cutover (until **25 July 2026**). Rollback is a manual business decision triggered by the Release Manager with sign‑off from the Indifi business owner.

### 7.1 Rollback triggers (any one)

- Critical data integrity issue discovered on V2 that cannot be hotfixed.
- Sustained P1 outage on V2 > 2 hours with no ETA.
- Business‑blocking functional regression reported by stakeholders.

### 7.2 Rollback principle

Because there is **no real‑time sync between V1 and V2**, any data created on V2 after cutover will be lost on rollback. This is explicitly accepted — stakeholders have been informed.

### 7.3 Rollback procedure (reverse of cutover)

1. Announce rollback window and disable the execute‑runner API on V2 to block new write traffic.
2. Stop V2 background workers and drain queues.
3. Flip the Indifi lead‑creation integration endpoint back from V2 → V1.
4. Flip DNS back to V1 (TTL already low → fast propagation).
5. Re‑enable the execute‑runner API on V1 and restart V1 background workers (infra was left running but idle).
6. Confirm V1 databases are intact and match the pre‑cutover snapshot.
7. Run the same validation suite from §5 against V1 to confirm health.
8. Notify partners: traffic reverts to V1 IPs — V1 IPs are still whitelisted (kept active for this 14‑day window).
9. Communicate to stakeholders: "V2 data created since cutover has been discarded as per agreed rollback policy."
10. Open a post‑mortem and decide on re‑cutover date.

### 7.4 What must stay available for 14 days

- V1 application stack on Indifi AWS ECS (hot, idle).
- V1 databases in last‑known‑good state.
- V1 IPs whitelisted with all partners.
- V1 DNS records available (not deleted, just not primary).
- Snapshot backups of both V1 (pre‑cutover) and V2 (daily).

### 7.5 After 14 days (from 26 July 2026)

- Final decision: decommission V1.
- Remove V1 IPs from partner whitelists.
- Archive V1 database snapshot to cold storage (retain per compliance policy).
- Tear down V1 ECS services and task definitions.
- Update `crego-infra` to remove the V1‑Indifi overlay.

---

## 8. Risks & Mitigations

| #   | Risk                                        | Likelihood | Impact | Mitigation                                                                        |
| --- | ------------------------------------------- | ---------- | ------ | --------------------------------------------------------------------------------- |
| 1   | Data migration script fails mid‑restore     | Med        | High   | Dry‑run on UAT copy; keep V1 snapshot untouched                                   |
| 2   | Partner whitelisting not ready on time      | Med        | High   | Start T‑5; keep V1 IPs active as fallback                                         |
| 3   | DNS propagation delay                       | Low        | Med    | Lower TTL 48h in advance                                                          |
| 4   | Lead creation endpoint flip misconfigured   | Med        | High   | Config‑flag driven flip, tested in dry run                                        |
| 5   | Data created on V2 lost on rollback         | Low        | Med    | Communicated to stakeholders; rollback is explicit business decision              |
| 6   | Downtime exceeds 5‑hour window              | Med        | Med    | Rehearse cutover; hard decision point at 01:30 IST to either proceed or roll back |
| 7   | Stakeholders unavailable for Sat/Sun review | Low        | Med    | Confirmed availability at T‑1 Go/No‑Go                                            |

---

_Crego × Indifi_
_Version: 1.0 — Created 12 June 2026_
