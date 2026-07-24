# Crego Release & Development Lifecycle — Gap Analysis

**Prepared:** 21 July 2026
**Scope:** Every place the development/release lifecycle is defined across the workspace — the three Cowork plugins, GitHub Actions workflows in `crego-flow`, `crego-omni`, `crego-web`, `crego-infra`, the infra shell scripts, infra docs & runbooks, `development-process.html`, and the per-repo `CONTRIBUTING.md` / `CLAUDE.md` files.
**Assumption (unattended run):** You asked for *all* gap types, so this covers documentation-vs-reality drift, missing/broken automation, cross-repo inconsistencies, and governance/safety — delivered as a report you can share. Where a gap depends on GitHub *settings* not visible in the repo (branch protection, environment reviewers), it is flagged as "verify" rather than asserted.

---

## 1. Executive summary

The release process itself is **well-designed** — the `release-manager` plugin encodes a clean 5-phase GitFlow model (develop → release branch → tag → prod → back-merge), sensible Linear states, and guided commands with confirmation gates. The problem is **not the design; it's fragmentation and drift.** The same lifecycle is defined in at least **seven overlapping places**, no single one is declared canonical, and they have diverged as the pipeline evolved from an older `dev/uat` model to the current `dev/preprod/prod` release-branch model.

The result is three recurring failure modes:

1. **Contradictions between sources** — e.g. the release runbook tells you to update a `CLIENT_VERSIONS.md` file that the infra contributing guide says shouldn't exist and that nothing actually maintains.
2. **Documented steps with no working implementation** — e.g. `promote-services.sh` is a simulation stub; automated rollback is a "future enhancement"; the `needs-backport` flow is entirely manual.
3. **Silent per-repo asymmetry** — e.g. `crego-omni` runs a full test+coverage suite on every PR; `crego-flow` runs **no tests at all**, while its `CONTRIBUTING.md` promises "all CI checks must pass (tests, lint, build)."

Counts below: **7 High**, **8 Medium**, **5 Low** severity gaps.

**Severity key:** 🔴 High = can cause a bad prod deploy, lost fixes, or security exposure · 🟠 Medium = drift/inconsistency that will bite during a release · 🟡 Low = hygiene / clarity.

---

## 2. Where the lifecycle is defined (the landscape)

| # | Source | Role | Current state |
|---|--------|------|---------------|
| 1 | `release-manager.plugin` (SKILL.md + 5 commands + `git-commands.md`) | Canonical process + guided execution | Cleanest source; treated here as the intended process |
| 2 | `crego-internal-docs/engineering/development-process.html` | Engineer-facing single-source-of-truth (95 KB) | Comprehensive but mixes `main`/`master` and `preprod`/`uat` terminology |
| 3 | `crego-infra/docs/unified-cicd-workflow.md` | Infra CI/CD explainer | **Stale** — describes the old `dev/uat/prod` + `main→prod, develop→uat` model; no release branches |
| 4 | `crego-infra/docs/service-management.md` + `runbooks/deployment-guide.md` | Operational runbooks | Describes scripts as functional that aren't; no rollback procedure |
| 5 | GitHub Actions across 4 repos (`ci`, `infra-deployment`, `unified-ci-cd`, `release-orchestrator`, `client_release`, `deploy_qa`, `*-deployment`, `*-ci`, `pr-check`, zap-scan, claude-review) | The actual pipeline | The real behaviour; partially matches the docs |
| 6 | `crego-infra/scripts/*` (`bump-image`, `promote-services`, `release-client`, `sync-services`, `lib/version-utils`) | Manual release/deploy tooling | Mix of working (release-client, version-utils) and broken/stale (promote-services) |
| 7 | Per-repo `CONTRIBUTING.md` (flow, infra, "copy to each backend"), `CLAUDE.md`, `README.md` | Contributor rules | Overlap with plugin; some rules contradict the pipeline |

There is **no document that names itself the authority** or points to the others. That is the root cause of most gaps below.

---

## 3. Gaps by category

### A. Documentation drift & conflicting sources

**🔴 A1 — `CLIENT_VERSIONS.md` is a three-way contradiction.**
The `release-management` SKILL (Phase 5) and `ship-release.md` post-ship checklist both instruct: *"Update `CLIENT_VERSIONS.md` in crego-infra."* But `crego-infra/CONTRIBUTING.md` (line 156) states the opposite: *"All release versions are tracked via git tags — no separate version file needed."* And **no such file exists** and **no script writes it**. Every release, a human is told to update a file that policy says shouldn't exist and tooling doesn't maintain → the step is silently skipped, and there is no reliable place to see "what version is each client on."
*Fix:* pick one — either delete the instruction from the plugin/ship command, or generate `CLIENT_VERSIONS.md` automatically from `git tag -l '*-<client>'`.

**🔴 A2 — Environment terminology has split three ways.**
The active pipeline and `version-utils.sh` use **`preprod`**; the older infra tooling (`bump-image.sh` valid envs = `dev|uat|prod`, `promote-services.sh`, `sync-services.sh`) and its docs use **`uat`**; `development-process.html` mixes both. So the CI overlay-update writes `overlays/preprod-gcp`, while `bump-image.sh`/`promote-services.sh` only understand `uat`. Anyone using the manual scripts operates on a different environment name than the pipeline. *Fix:* standardise on `preprod`, update `bump-image.sh`'s allow-list and the two docs.

**🟠 A3 — `unified-cicd-workflow.md` describes a superseded model.**
It maps `develop → uat`, `main → prod`, has **no `release/*` branch** concept, and claims "manual promotion steps are now automatic." This predates the release-branch/pre-prod flow that the plugin, `release-client.sh` and `infra-deployment.yaml` now implement. An engineer reading it would build the wrong mental model. *Fix:* rewrite against the current 5-phase flow or mark it deprecated with a pointer to the SSOT.

**🟠 A4 — `main` vs `master` is inconsistent everywhere.**
Backend repos use `master`; `crego-web` uses `main`. The plugin handles this correctly, but `development-process.html` and `unified-cicd-workflow.md` use `main` generically, and the deployment workflows defensively check **both** (`github.ref_name == 'main' || 'master'`), signalling uncertainty. *Fix:* document the per-repo primary-branch table once (the SKILL already has it) and reference it; remove the defensive dual-checks where the branch is known.

**🟡 A5 — `service-management.md` documents `promote-services.sh` and a `deploy-services.sh` as working.** The former is a stub (see B1); the latter isn't among the current scripts. Stale runbook. *Fix:* reconcile with the actual `scripts/` directory.

---

### B. Missing or broken automation & coverage

**🔴 B1 — `promote-services.sh` is a non-functional stub.**
Its core `promote_service()` prints `"…promoted successfully (simulated)"` and applies nothing — the real logic is a `# In a real implementation, this would…` comment. It's presented as the environment-promotion tool in `service-management.md`. Anyone who runs it believes a promotion happened when nothing did. *Fix:* implement it (GitOps overlay bump + commit) or delete it and document that promotion is pipeline-driven only.

**🔴 B2 — No rollback path — automated or documented — despite policy requiring one.**
`crego-infra/CONTRIBUTING.md` mandates a "Rollback Plan" section and checklist item in every PR, yet: no workflow has a rollback/revert job; `deployment-guide.md` has **no rollback procedure** (only manual re-sync/patch troubleshooting); and `unified-cicd-workflow.md` lists "automatic rollback on failure" under **Future Enhancements**. Recovery today = a human manually reverting the overlay commit in `crego-infra` and re-syncing ArgoCD, undocumented. *Fix:* add a documented rollback runbook (revert overlay commit → ArgoCD sync to previous tag) and ideally a `workflow_dispatch` rollback job.

**🔴 B3 — `needs-backport` is a label with no enforcement.**
The model relies on fixes made directly on a release branch being merged back to `develop`. This is entirely manual: the `needs-backport` label is defined and `cut-release.md` reminds the RM to apply it, but nothing tracks whether labelled items were actually backported before `develop` moves on. `release-orchestrator.yaml`'s "prod is ahead of develop" check is **non-blocking** (warning only). Real risk: release-branch fixes silently lost from `develop`. *Fix:* a scheduled check that lists merged-but-not-backported `needs-backport` issues, or a release-gate that blocks the next cut until backports are clean.

**🟠 B4 — `crego-flow` runs no automated tests in CI.**
`crego-flow/.github/workflows/ci.yml` = PR-title validation + `pre-commit` lint + `gitleaks`. **No test job, no build.** `crego-omni/ci.yml` has a full Postgres/Redis-backed Django `coverage` job. Yet `crego-flow/CONTRIBUTING.md` promises "All CI checks must pass (tests, lint, build)" and a "Tests pass locally / new tests added" checklist. The gate the doc describes doesn't exist for flow. *Fix:* port omni's coverage job to flow (or explicitly document why flow has none).

**🟠 B5 — `git-commands.md`/`ship`/`hotfix` use annotated tags; `release-client.sh` uses lightweight tags.**
The plugin consistently does `git tag -a vX.Y.Z -m …`; `release-client.sh`'s `tag` action does `git tag ${VERSION}` (lightweight, no `-a`/`-m`). Both trigger the `v*` pipeline, but tag metadata (author, message, date) is inconsistent between manual and scripted paths, and `git describe`/release-notes tooling behaves differently. *Fix:* make `release-client.sh` create annotated tags.

**🟡 B6 — Several manual steps sit where the 5-phase model implies automation.** `sync-services.sh` (human runs `argocd app sync`), `bump-image.sh` (warns "don't forget to commit and push", never pushes), and the Phase 4/5 merge-back, branch cleanup, release-notes, and Linear state moves are all manual (the plugin guides them but doesn't automate). Fine if intentional, but worth deciding which should become CI. 

---

### C. Cross-repo inconsistencies

**🟠 C1 — Secret scanning is backend-only.**
`gitleaks` runs in `crego-flow` and `crego-omni` CI but is **absent from every `crego-web` workflow** (`pr-check.yml`, `flow-ci.yaml`, `omni-ci.yaml`). Frontend `.env`/token leaks would not be caught pre-merge. *Fix:* add gitleaks to the web CI (or a repo-wide reusable secret-scan workflow).

**🟠 C2 — DAST is nightly, dev-only, and non-blocking; no SAST or image scanning anywhere.**
`flow-zap-scan.yml` / `omni-zap-scan.yml` run OWASP ZAP on a nightly cron against **dev** URLs with `-I` and `|| true` — they never fail a build and never run against pre-prod/prod. There is **no** SAST (CodeQL/semgrep), **no** container/image scan (Trivy) in CI, and **no** web DAST. ECR `scanOnPush` (registry-side) is the only image scanning, and it gates nothing. *Fix:* decide the security bar for the release path — at minimum add image scanning to the build and make a scan result a release-gate for prod.

**🟡 C3 — `crego-web` carries near-duplicate `flow-deployment.yaml` / `omni-deployment.yaml`.**
They are byte-for-byte identical except package path, service name, Sentry DSN and build script — and `omni-deployment.yaml` still has a copy-paste bug: its checkout step is labelled **"Checkout flow-web code."** Same duplication for `flow-ci.yaml`/`omni-ci.yaml` and `deploy_qa_flow.yaml`/`deploy_qa_omni.yaml`. *Fix:* collapse each pair into one reusable workflow parameterised by app.

**🟡 C4 — Backend `deploy_qa` migration logic diverges in ways that aren't documented.** `crego-flow` QA does a **MongoDB** dump/restore and treats prod as Atlas; `crego-omni` does **PostgreSQL** `pg_dump`/`pg_restore` with a disk-space guard and a real `crego-prod-cluster` source. Correct per-service, but the difference (and the disk guard existing in only one) isn't captured anywhere. *Fix:* note the per-service DB engine in the runbook.

---

### D. Governance & safety

**🔴 D1 — GitHub Actions are pinned to mutable `@main`, violating the repo's own rule.**
`crego-infra/CONTRIBUTING.md` (line 146) requires: *"Use explicit version pins for GitHub Actions (use commit SHA, not `@main` or `@latest`)."* In reality **every** cross-repo call uses `crego-tech/crego-infra/.github/workflows/unified-ci-cd.yaml@main` and `…/parse-version@main`. A push to `crego-infra`'s `main` instantly changes the deploy behaviour of all app repos with no review in those repos — a supply-chain and change-control risk, and a direct self-contradiction. *Fix:* pin reusable-workflow/action references to a tag or SHA and bump deliberately.

**🔴 D2 — The actual deploy job runs with no environment protection.**
App-repo trigger jobs attach `environment: prod|preprod|qa` (enabling native approvals/secrets *if configured in GitHub settings*), but the job that actually **builds, pushes, and commits the overlay** is the reusable `unified-ci-cd.yaml@main`, which attaches **no `environment:`** and has **no `concurrency:` guard**. So (a) any required-reviewer gate only pauses the lightweight trigger job, not the deploy itself, and the reusable workflow is unprotected if called directly; (b) two releases/deploys can race and clobber each other's commit to `crego-infra` `main`. *Fix:* attach the environment to the deploy job (or gate at the reusable-workflow level) and add a `concurrency` group keyed by env+service. **Verify** that the `prod` GitHub Environment actually has required reviewers set.

**🟠 D3 — Documented approval counts aren't verifiable in code (and orchestrator PRs auto-open but never merge).**
Policy says 1 approval for app repos, **2** for infra; `release-orchestrator.yaml` PR bodies say "requires 2 reviewer approvals." None of this is enforceable from the workflow files — it lives in branch-protection settings not in the repo. `ship`/`merge-back` orchestrator actions **create** PRs but never merge, relying on a human. *Fix:* confirm branch-protection matches the documented counts on `master`/`main`/`develop` for all five repos; record the settings-as-config somewhere.

**🟠 D4 — Prod deploys reach GCP only; the AWS-prod path is latent and the routing logic is duplicated.**
Effective internal prod trigger = `v*` tag → `["prod-gcp"]` (in every `infra-deployment`/`*-deployment` workflow). Meanwhile `unified-ci-cd.yaml` contains a **separate, latent** fallback router (`main/master → prod-aws + prod-gcp`, `hotfix/* → dev+prod`, `release/* → preprod-gcp`) that only fires if the reusable workflow is called without `target_environments`. Two different sources of truth for env routing, and `prod-aws` for shared/internal is never actually targeted. *Fix:* confirm GCP-only internal prod is intended; delete or reconcile the dead fallback routing so there's one router.

**🟡 D5 — `validate-infra.yaml` gates are advisory only.** Its `kubectl --dry-run`, `yamllint`, and `kustomize` checks emit `|| echo "Warning…"` instead of failing — so a broken manifest passes CI. *Fix:* make the structural validations blocking.

---

## 4. Prioritised gap register

| ID | Severity | Area | Gap | Primary location |
|----|----------|------|-----|------------------|
| A1 | 🔴 | Docs conflict | `CLIENT_VERSIONS.md`: required by plugin, forbidden by infra CONTRIBUTING, maintained by nothing | SKILL.md / ship-release.md vs crego-infra/CONTRIBUTING.md:156 |
| B1 | 🔴 | Broken automation | `promote-services.sh` is a simulation stub | crego-infra/scripts/promote-services.sh |
| B2 | 🔴 | Safety | No rollback runbook or automation, though PR policy mandates a rollback plan | deployment-guide.md / unified-cicd-workflow.md |
| B3 | 🔴 | Coverage | `needs-backport` is manual & unenforced; back-merge check is non-blocking | release-orchestrator.yaml / SKILL.md |
| D1 | 🔴 | Governance | Cross-repo Actions pinned to `@main` — violates infra's own SHA-pin rule | all `*-deployment` / `infra-deployment` / `deploy_qa` |
| D2 | 🔴 | Safety | Deploy job unprotected + no concurrency guard | crego-infra/.github/workflows/unified-ci-cd.yaml |
| A2 | 🔴 | Docs drift | `preprod` vs `uat` env naming split across pipeline vs scripts | bump-image.sh / version-utils.sh / docs |
| B4 | 🟠 | Coverage | `crego-flow` CI runs no tests (omni does); CONTRIBUTING promises a test gate | crego-flow/.github/workflows/ci.yml |
| C1 | 🟠 | Consistency | No gitleaks/secret scan in `crego-web` | crego-web workflows |
| C2 | 🟠 | Security | DAST nightly/dev-only/non-blocking; no SAST or image scan gate | *-zap-scan.yml |
| D3 | 🟠 | Governance | Approval counts unverifiable in code; orchestrator PRs auto-open, never merge | branch protection (settings) |
| D4 | 🟠 | Consistency | GCP-only prod + duplicate/latent env routing | unified-ci-cd.yaml vs *-deployment.yaml |
| A3 | 🟠 | Docs drift | `unified-cicd-workflow.md` describes superseded dev/uat model | crego-infra/docs/unified-cicd-workflow.md |
| A4 | 🟠 | Docs drift | `main`/`master` treated inconsistently | development-process.html / deployment workflows |
| B5 | 🟠 | Consistency | Lightweight vs annotated tags between script and plugin | release-client.sh vs git-commands.md |
| C3 | 🟡 | Hygiene | Duplicate web deployment/CI workflows + "flow-web" copy-paste label in omni file | crego-web/.github/workflows |
| C4 | 🟡 | Docs | Per-service QA DB migration divergence undocumented | deploy_qa.yaml (flow vs omni) |
| A5 | 🟡 | Docs drift | Runbook documents stub/absent scripts as working | service-management.md |
| B6 | 🟡 | Automation | Manual steps where model implies automation | sync/bump scripts, Phase 4/5 |
| D5 | 🟡 | Governance | `validate-infra` checks are non-blocking warnings | crego-infra/.github/workflows/validate-infra.yaml |

---

## 5. Recommended next steps

1. **Declare one canonical source.** Make the `release-manager` SKILL (or `development-process.html`) the authority, and demote the others to pointers. This single act prevents most future drift.
2. **Close the four safety-critical items first:** rollback runbook (B2), backport enforcement (B3), `@main` pinning (D1), and the unprotected/racy deploy job (D2).
3. **Reconcile the `CLIENT_VERSIONS.md` and `preprod`/`uat` contradictions** (A1, A2) — both are quick, purely-editorial fixes that remove active confusion.
4. **Equalise CI across repos** — flow tests (B4), web secret scan (C1), and a shared security-scan bar (C2).
5. **Verify the settings-level gates** you can't see in code: branch-protection approval counts and the `prod` environment's required reviewers (D2, D3).

*Verification note:* Findings on GitHub Actions, shell scripts, plugins, runbooks and CONTRIBUTING files were read directly from the connected `crego` folder. Two early assumptions were corrected against the source — backend repos **do** deploy via `infra-deployment.yaml`, and `omni-ci.yaml` **does** exist and mirrors `flow-ci.yaml`, so neither is a gap. Anything depending on GitHub org settings (branch protection, environment reviewers) is marked "verify" because it is not visible in the repository files.
