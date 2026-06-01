# Tyger Capital V1 → V2 Migration — Role‑Based Checklist

Reference: [Migration Plan](tiger-capital-v1-to-v2-migration-plan.md)

---

## Client (Tyger Capital)

| #  | Task                                                                                         | When     | Done |
|----|----------------------------------------------------------------------------------------------|----------|------|
| 1  | Sign off UAT on V2 with real V1 data                                                        | T‑3      | [ ]  |
| 2  | Confirm stakeholder availability for cutover Sunday and following Monday                     | T‑2      | [ ]  |
| 3  | Acknowledge downtime notice and parallel‑run policy                                          | T‑2      | [ ]  |
| 4  | Participate in Go/No‑Go call                                                                 | T‑1      | [ ]  |
| 5  | Validate V2 post‑migration: login, loan workflows, role access                               | T (day)  | [ ]  |
| 6  | Begin using V2 (`tyger.crego.ai`) as primary system                                          | T+1      | [ ]  |
| 7  | Enter all transactions into both V1 and V2 during the parallel‑run                           | T+1–T+14 | [ ]  |
| 8  | Compare trial balance, GL, and customer portfolio reports weekly (V1 vs V2)                   | Weekly   | [ ]  |
| 9  | Confirm confidence in V2 and report parity                                                    | T+14 / month‑end | [ ]  |
| 10 | Sign off on V1 decommissioning                                                               | T+14 / month‑end | [ ]  |

---

## QA

| #  | Task                                                                                         | When     | Done |
|----|----------------------------------------------------------------------------------------------|----------|------|
| 1  | Final visual QA pass on V2: login screen, menu, color tokens, user & role matrix              | T‑3      | [ ]  |
| 2  | Capture before/after screenshots for stakeholder review pack                                  | T‑3      | [ ]  |
| 3  | Dry‑run SBI H2H flow end‑to‑end on V2 with test data                                         | T‑2      | [ ]  |
| 4  | Prepare data validation test suite (counts, reports, integrity checks)                        | T‑2      | [ ]  |
| 5  | Run data validation suite after DB restore (§5 of migration plan)                             | T (day)  | [ ]  |
| 6  | Verify count matching: pending loans, drawdowns, payments, upfront interest & excess           | T (day)  | [ ]  |
| 7  | Verify report matching: trial balance, GL report, customer portfolio report                    | T (day)  | [ ]  |
| 8  | Verify structural checks: table/collection counts, schema version                             | T (day)  | [ ]  |
| 9  | Verify integrity checks: PK uniqueness, FK references, attachment counts                      | T (day)  | [ ]  |
| 10 | Smoke test V2: login, key user journeys, loan workflows, SBI H2H, role‑based access           | T (day)  | [ ]  |
| 11 | Final end‑to‑end test: login → loan workflow → SBI H2H → verify in V2 UI                      | T (day)  | [ ]  |
| 12 | Verify SBI H2H integration functional on V2 IPs                                               | T (day)  | [ ]  |
| 13 | Log validation results to shared sheet and sign off                                            | T (day)  | [ ]  |
| 14 | Compare V1 vs V2 reports at week‑end and month‑end during parallel‑run                         | T+1–T+14 | [ ]  |

---

## Developers (Backend / Crego Team)

| #  | Task                                                                                         | When     | Done |
|----|----------------------------------------------------------------------------------------------|----------|------|
| 1  | Update SBI H2H integration configuration to use V2 platform endpoints                        | T‑5      | [ ]  |
| 2  | Ensure UI changes (login, menu, colors, roles) are merged and deployed to V2                  | T‑3      | [ ]  |
| 3  | Prepare and test data migration / transformation scripts                                      | T‑3      | [ ]  |
| 4  | Dry‑run migration scripts on UAT copy of V1 data                                              | T‑2      | [ ]  |
| 5  | Fix any schema mismatches or migration errors found in dry‑run                                 | T‑2      | [ ]  |
| 6  | Support DB restore and run migration scripts on cutover day                                    | T (day)  | [ ]  |
| 7  | Investigate and fix any data validation failures                                               | T (day)  | [ ]  |
| 8  | P1 support for V2 issues during parallel‑run                                                   | T+1–T+14 | [ ]  |
| 9  | Investigate and fix any report mismatches between V1 and V2                                    | T+1–T+14 | [ ]  |

---

## DevOps / Platform

| #  | Task                                                                                         | When     | Done |
|----|----------------------------------------------------------------------------------------------|----------|------|
| 1  | Verify V2 environment health: K8s, databases, object storage, queues, observability            | T‑7      | [ ]  |
| 2  | Confirm `crego-infra` overlay for Tyger Capital on V2 is on the target release tag             | T‑7      | [ ]  |
| 3  | Take baseline backup of V2 (empty/UAT state)                                                  | T‑5      | [ ]  |
| 4  | Validate secrets, KMS keys, and service accounts on V2 platform                               | T‑5      | [ ]  |
| 5  | Confirm Sentry, logging, and alerting are pointing at V2 projects                              | T‑5      | [ ]  |
| 6  | Publish final list of V2 egress and ingress IPs                                                | T‑5      | [ ]  |
| 7  | Submit SBI IP whitelisting update request for V2 IPs                                           | T‑5      | [ ]  |
| 8  | Confirm SBI has whitelisted V2 IPs                                                             | T‑3      | [ ]  |
| 9  | Submit whitelisting requests to Email/SMS providers and other API consumers                     | T‑5      | [ ]  |
| 10 | Lower DNS TTL for `tyger.crego.ai` to ≤ 300 seconds                                           | T‑2      | [ ]  |
| 11 | Create `tyger.crego.ai` DNS records (do not cut over yet)                                      | T‑2      | [ ]  |
| 12 | Disable execute‑runner API on V1 to block write traffic                                        | T + 0:00 | [ ]  |
| 13 | Stop all V1 background workers (Celery, cron, queue consumers), drain jobs                     | T + 0:05 | [ ]  |
| 14 | Take final V1 DB snapshot, verify checksum and size                                            | T + 0:10 | [ ]  |
| 15 | Transfer snapshot to V2 environment                                                            | T + 0:25 | [ ]  |
| 16 | Restore snapshot into V2 databases                                                             | T + 0:45 | [ ]  |
| 17 | Flip DNS: `tyger.crego.ai` → V2, verify propagation                                           | T + 2:20 | [ ]  |
| 18 | Update IP whitelisting status with partners (confirm V2 live, keep V1 active)                  | T + 2:30 | [ ]  |
| 19 | Re‑enable V1 at `tyger.jupiter.crego.io` for parallel‑run                                     | T + 3:00 | [ ]  |
| 20 | Hypercare monitoring: error rates, latency, Sentry, logs                                       | T + 3:00–4:00 | [ ]  |
| 21 | Maintain daily backups of both V1 and V2 during parallel‑run                                   | T+1–T+14 | [ ]  |
| 22 | Decommission V1: stop workers, remove IPs from whitelists, archive DB, tear down compute       | Post parallel‑run | [ ]  |
| 23 | Remove V1 Tyger Capital overlay from `crego-infra`                                             | Post parallel‑run | [ ]  |
| 24 | Decommission `tyger.jupiter.crego.io` DNS records                                              | Post parallel‑run | [ ]  |

---

## Manager (Release Manager)

| #  | Task                                                                                         | When     | Done |
|----|----------------------------------------------------------------------------------------------|----------|------|
| 1  | Confirm launch date and migration date with all stakeholders                                   | T‑7      | [ ]  |
| 2  | Set up war‑room bridge, Slack channel, and on‑call rota                                        | T‑5      | [ ]  |
| 3  | Send downtime notice to Tyger Capital stakeholders and end‑users                               | T‑2      | [ ]  |
| 4  | Communicate parallel‑run policy to all parties                                                 | T‑2      | [ ]  |
| 5  | Run Go/No‑Go checklist review with all teams                                                   | T‑1      | [ ]  |
| 6  | Open war room, roll call, final Go/No‑Go on cutover day                                        | T − 0:30 | [ ]  |
| 7  | Announce migration complete once all validations pass                                          | T + 2:55 | [ ]  |
| 8  | Daily status update to Tyger Capital stakeholders (first week)                                 | T+1–T+7  | [ ]  |
| 9  | Weekly status update to Tyger Capital stakeholders (week 2 onward)                             | T+8–T+14 | [ ]  |
| 10 | Coordinate weekly report comparison (V1 vs V2) with QA and client                              | Weekly   | [ ]  |
| 11 | Collect Tyger Capital sign‑off on V1 decommissioning                                          | T+14 / month‑end | [ ]  |
| 12 | Confirm V1 decommissioning with DevOps                                                         | Post parallel‑run | [ ]  |

---

_Version: 1.0 — Created 30 May 2026_
