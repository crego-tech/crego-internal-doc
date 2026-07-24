# Crego Release & Development Lifecycle — Remediation Plan

**Prepared:** 24 July 2026
**Source:** `release-lifecycle-gap-analysis.md` (20 gaps: 7 High, 8 Medium, 5 Low)
**Scope:** A sequenced, ownable plan to close the gaps. No code changes are made
by this document — it defines *what* to fix, *in what order*, *by whom*, and
*how much effort*. Settings-level items (branch protection, environment
reviewers) are flagged **Verify** because they are not visible in the repos.

---

## Guiding principle: fix the root cause first

The gap analysis is explicit: the process is well-designed; the damage comes from
**fragmentation and drift** — the same lifecycle is defined in seven overlapping
places and none is declared canonical. Every wave below is downstream of one
foundational act:

> **Declare one canonical source of truth (SSOT).** Nominate the `release-manager`
> plugin's SKILL (or `development-process.html`) as the authority; demote every
> other source to a short pointer to it. This single change prevents most future
> drift and makes the rest of the plan durable.

Do this **before** Wave 1 — it's an editorial change with outsized leverage.

---

## Effort & owner keys

**Effort:** S = under ½ day · M = 1–2 days · L = more than 2 days
**Owners:** RM = Release Manager · Infra = Infra/DevOps · BE = Backend (flow/omni)
· FE = Frontend (web) · Lead = Eng Lead / Docs owner

---

## Wave 0 — Foundation (do this week, ~½ day)

| Item | Action | Effort | Owner |
|---|---|---|---|
| SSOT | Declare the canonical lifecycle source; add a one-line "authoritative source" banner to every other doc pointing to it | S | Lead |

---

## Wave 1 — Safety-critical (Sprint 1)

The four items that can cause a bad prod deploy, lost fixes, or security exposure —
plus the two contradictions that are quick, purely-editorial wins.

| ID | Sev | Gap | Fix | Effort | Owner |
|----|-----|-----|-----|--------|-------|
| B2 | 🔴 | No rollback path (automated or documented), though PR policy mandates a rollback plan | Write a rollback runbook (revert overlay commit → ArgoCD sync to previous tag); add a `workflow_dispatch` rollback job | M | Infra |
| B3 | 🔴 | `needs-backport` is manual & unenforced; back-merge check is non-blocking | Add a scheduled check listing merged-but-not-backported `needs-backport` issues, or a release-gate that blocks the next cut until backports are clean | M | RM + Infra |
| D1 | 🔴 | Cross-repo Actions pinned to mutable `@main` — violates infra's own SHA-pin rule | Pin reusable-workflow/action refs to a tag or SHA across all app repos; bump deliberately | M | Infra |
| D2 | 🔴 | Deploy job unprotected + no concurrency guard | Attach `environment:` to the deploy job (or gate at the reusable-workflow level); add a `concurrency` group keyed by env+service. **Verify** prod env has required reviewers | M | Infra |
| A1 | 🔴 | `CLIENT_VERSIONS.md`: required by plugin, forbidden by infra CONTRIBUTING, maintained by nothing | Pick one: delete the instruction, or auto-generate the file from `git tag -l '*-<client>'` | S | RM |
| A2 | 🔴 | `preprod` vs `uat` env naming split across pipeline vs scripts | Standardise on `preprod`; update `bump-image.sh` allow-list and the two docs | S | Infra |

---

## Wave 2 — CI parity & security bar (Sprint 2)

Equalise the guarantees each repo actually enforces, and remove the "believed it
worked but it didn't" traps.

| ID | Sev | Gap | Fix | Effort | Owner |
|----|-----|-----|-----|--------|-------|
| B1 | 🔴 | `promote-services.sh` is a simulation stub presented as working | Implement it (GitOps overlay bump + commit) or delete it and document promotion as pipeline-driven only | M | Infra |
| B4 | 🟠 | `crego-flow` runs no automated tests in CI (omni does); CONTRIBUTING promises a test gate | Port omni's Postgres/Redis coverage job to flow, or explicitly document why flow has none | M | BE |
| C1 | 🟠 | No gitleaks/secret scan in `crego-web` | Add gitleaks to web CI (or a repo-wide reusable secret-scan workflow) | S | FE |
| C2 | 🟠 | DAST nightly/dev-only/non-blocking; no SAST or image scan gate | Decide the release-path security bar; at minimum add image scanning to the build and make its result a prod release-gate | L | Infra + Lead |

---

## Wave 3 — Drift cleanup, consistency & hygiene (Sprint 3, ongoing)

Lower-risk items. Batch them once the SSOT exists so they're fixed in one place.

| ID | Sev | Gap | Fix | Effort | Owner |
|----|-----|-----|-----|--------|-------|
| A3 | 🟠 | `unified-cicd-workflow.md` describes superseded dev/uat model | Rewrite against the current 5-phase flow, or mark deprecated with an SSOT pointer | M | Infra |
| A4 | 🟠 | `main`/`master` treated inconsistently | Document the per-repo primary-branch table once; remove defensive dual-checks where the branch is known | S | Infra |
| B5 | 🟠 | Lightweight vs annotated tags between `release-client.sh` and plugin | Make `release-client.sh` create annotated tags (`git tag -a`) | S | Infra |
| D3 | 🟠 | Approval counts unverifiable in code; orchestrator PRs auto-open, never merge | **Verify** branch protection matches documented counts (1 app / 2 infra) on all five repos; record settings-as-config | S | Lead |
| D4 | 🟠 | GCP-only prod + duplicate/latent env routing | Confirm GCP-only internal prod is intended; delete or reconcile the dead AWS fallback router so there's one router | M | Infra |
| C3 | 🟡 | Duplicate web deployment/CI workflows + "flow-web" copy-paste label in omni file | Collapse each pair into one reusable workflow parameterised by app; fix the mislabelled checkout | M | FE |
| C4 | 🟡 | Per-service QA DB migration divergence undocumented | Note the per-service DB engine (flow=MongoDB/Atlas, omni=Postgres) and the disk guard in the runbook | S | BE |
| A5 | 🟡 | Runbook documents stub/absent scripts as working | Reconcile `service-management.md` with the actual `scripts/` directory | S | Infra |
| B6 | 🟡 | Manual steps where the 5-phase model implies automation | Decide which of `sync-services.sh`, `bump-image.sh` push, Phase 4/5 steps should become CI | M | Infra + RM |
| D5 | 🟡 | `validate-infra` checks are non-blocking warnings | Make the `kubectl --dry-run`, `yamllint`, `kustomize` structural validations blocking | S | Infra |

---

## Settings-level verifications (not visible in the repos)

These can't be asserted from code — assign an owner to confirm in GitHub settings:

- **D2 / D3** — `prod` (and `preprod`/`qa`) GitHub Environments have the required
  reviewers set; branch-protection approval counts match policy (1 app repo, 2
  infra) on `master`/`main`/`develop` across all five repos.

---

## Prioritised register (single view)

| ID | Sev | Wave | Effort | Owner | Area |
|----|-----|------|--------|-------|------|
| SSOT | — | 0 | S | Lead | Foundation |
| B2 | 🔴 | 1 | M | Infra | Safety |
| B3 | 🔴 | 1 | M | RM+Infra | Coverage |
| D1 | 🔴 | 1 | M | Infra | Governance |
| D2 | 🔴 | 1 | M | Infra | Safety |
| A1 | 🔴 | 1 | S | RM | Docs conflict |
| A2 | 🔴 | 1 | S | Infra | Docs drift |
| B1 | 🔴 | 2 | M | Infra | Broken automation |
| B4 | 🟠 | 2 | M | BE | Coverage |
| C1 | 🟠 | 2 | S | FE | Consistency |
| C2 | 🟠 | 2 | L | Infra+Lead | Security |
| A3 | 🟠 | 3 | M | Infra | Docs drift |
| A4 | 🟠 | 3 | S | Infra | Docs drift |
| B5 | 🟠 | 3 | S | Infra | Consistency |
| D3 | 🟠 | 3 | S | Lead | Governance |
| D4 | 🟠 | 3 | M | Infra | Consistency |
| C3 | 🟡 | 3 | M | FE | Hygiene |
| C4 | 🟡 | 3 | S | BE | Docs |
| A5 | 🟡 | 3 | S | Infra | Docs drift |
| B6 | 🟡 | 3 | M | Infra+RM | Automation |
| D5 | 🟡 | 3 | S | Infra | Governance |

---

## Suggested next step

Convert Wave 0 + Wave 1 into Linear issues (`CRE-xxx`, `type/chore` or
`type/improvement`, label `release/*`) so they enter the backlog with owners.
The full gap analysis is retained alongside this plan for detail and evidence.
