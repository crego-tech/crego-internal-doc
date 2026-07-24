# Lifecycle Documentation — Cleanup & Refactor List

**Prepared:** 24 July 2026
**Goal:** One authoritative lifecycle doc. `crego-internal-docs/engineering/development-process.html`
is the **single source of truth** for the release/development lifecycle
(Linear Flow, QA, Git Branching, CI/CD, Versioning, Hotfix, Commands,
Orchestrator, K8s & Tools, Sentry, Clients & Config, Rules). Every other file
that restates any of this should **point to the HTML**, not re-explain it.

**Important:** there are **no safe full-delete candidates** — every file below
carries unique operational or contributor content. The cleanup is *trim the
duplicated lifecycle section and replace it with a pointer*, never delete the file.

**Process note:** each of these files lives inside its own repo, so each change
goes on a feature branch and a PR per the branching model (`crego-infra` needs
2 approvals). Group by repo → one PR per repo.

---

## Suggested standard pointer (paste in place of trimmed sections)

> **Release & development lifecycle:** branching, Linear states, CI/CD,
> versioning, and hotfix flow are documented once, canonically, in
> `crego-internal-docs/engineering/development-process.html`. This guide covers
> only the parts specific to **this repo**. Do not restate the lifecycle here —
> update the HTML instead.

---

## Part 1 — Duplicate content to remove (dedupe to the HTML)

Do these now/first — they are pure de-duplication with no behavioural change.

| File | What duplicates the HTML (trim these) | Keep (unique — do NOT remove) | Action |
|---|---|---|---|
| `crego-flow/CONTRIBUTING.md` | Before You Start (Linear), Branch Naming, Development Workflow (git flow), Commit Messages, Review Requirements, Hotfix Process | PR Description Template, Code Standards (API/DB/testing/env), Error Handling & Sentry snippet | **TRIM → pointer** |
| `crego-omni/CONTRIBUTING.md` | Same lifecycle skeleton as flow (files are near-identical) | PR template, code standards, Sentry snippet | **TRIM → pointer** |
| `crego-web/CONTRIBUTING.md` | Before You Start, Branch Naming, Development Workflow, Commit Messages, Review Requirements, Hotfix Process | Repository Structure (monorepo), shared-package/cross-app testing, UI/screenshot PR template, styling/state/dependency standards, frontend Sentry snippet | **TRIM → pointer** |
| `crego-infra/CONTRIBUTING.md` | Before You Start, Branch Naming, Development Workflow, Commit Messages, Hotfix Process, **Version Tracking** block (tags, `v2.5.0`/`-bcpl`, `config/clients.yaml`) | "What Lives in This Repo", IaC/Secrets/CI-CD/Env-Parity standards, Terraform PR template (Risk/Rollback/Plan-output), 2-approval + prod/client-env approval rules | **TRIM → pointer** |
| `crego-infra/docs/unified-cicd-workflow.md` | "Decision Points Implementation" lead-in + branch→env mapping (main→prod, develop→uat, feature/hotfix→dev, `v*` tags) | Workflow Jobs, Required Secrets, Service→Dockerfile mapping, Trigger/repository-dispatch config, Slack notifications, Monitoring/Troubleshooting, Migration | **TRIM lead-in → pointer** (also see Part 2: this file's model is stale) |

**Optional minor trims (low priority):**

- `crego-infra/docs/runbooks/deployment-guide.md` — the ~4-line "Application Updates → CI/CD Pipeline Updates" note restates the pipeline; can become a one-line pointer. Everything else is unique bring-up runbook — keep.
- `crego-infra/README.md` — the "Daily Usage → Development Workflow" git snippet and the "CI/CD Workflow" section lightly restate Git Branching / CI-CD; can point to the HTML. All setup/architecture/troubleshooting content stays.

**Leave alone (flagged so nothing gets over-deleted):**
`crego-infra/docs/service-management.md`, the rest of `deployment-guide.md`, all four
`CLAUDE.md` (flow/omni/web/infra — these are code/agent guides, not lifecycle),
and all `README.md` (flow/omni service READMEs; `crego-web` has no README).

---

## Part 2 — Refactor & improvements (handle in the new session)

Beyond straight de-duplication — these need a decision or a small edit.

1. **Consolidate the backend CONTRIBUTING files.** `crego-flow/CONTRIBUTING.md`
   and `crego-omni/CONTRIBUTING.md` are near-identical (differ only in the Sentry
   snippet), and omni's header mis-says *"Applies to: crego-flow."* Options: one
   shared backend contributing guide referenced by both, or keep two but fix the
   mislabel and reduce to repo-specific deltas.

2. **Resolve the commit-format conflict in crego-web.** `crego-web/CLAUDE.md`
   says Conventional Commits; `crego-web/CONTRIBUTING.md` says `CRE-<number>:`.
   Pick one, align it to the HTML **Commands** tab, and fix the other.

3. **Fix the stale model in `unified-cicd-workflow.md`.** It still describes the
   old `dev/uat` + `main→prod, develop→uat` model with no `release/*` branches.
   Rewrite the conceptual part against the current 5-phase flow (or delete it and
   rely on the pointer). *(= gap A3 in the remediation plan.)*

4. **Internal-docs format policy — DECIDED (24 Jul 2026).** "HTML only" applies
   **only to the lifecycle process doc** (`development-process.html`, already the
   case). The other engineering `.md` files
   (`release-lifecycle-gap-analysis.md`, `release-lifecycle-remediation-plan.md`,
   `load-testing-plan.md`, the PRDs) stay as **Markdown** — leave as-is. No
   conversion. `engineering/` intentionally mixes both.

5. **Editorial consistency items that touch these docs** (cross-linked to the
   remediation plan so they're not done twice):
   - A1 — `CLIENT_VERSIONS.md` contradiction (plugin vs infra CONTRIBUTING).
   - A2 — `preprod` vs `uat` naming split (scripts/docs vs pipeline).
   - A4 — `main`/`master` per-repo table stated once in the HTML, referenced elsewhere.
   - A5 — reconcile runbook references to stub/absent scripts.

6. **Everything else (automation / CI / security / governance)** — the B, C, and
   D gaps (rollback runbook, `needs-backport` enforcement, `@main` pinning,
   unprotected deploy job, flow CI tests, web secret scan, image scanning, etc.)
   are **not documentation de-duplication** and live in
   `release-lifecycle-remediation-plan.md` with waves, effort, and owners. Pull
   from there for the code-level work.

---

## One-PR-per-repo checklist

- [ ] `crego-flow` — trim CONTRIBUTING lifecycle → pointer
- [ ] `crego-omni` — trim CONTRIBUTING lifecycle → pointer (+ fix "Applies to" mislabel)
- [ ] `crego-web` — trim CONTRIBUTING lifecycle → pointer (+ resolve commit-format conflict)
- [ ] `crego-infra` — trim CONTRIBUTING + Version Tracking → pointer; trim `unified-cicd-workflow.md` lead-in; (optional) `deployment-guide.md` + `README.md` notes — **2 approvals**
- [ ] `crego-internal-docs` — confirm HTML-only policy; ensure the HTML holds anything moved out of the repos
