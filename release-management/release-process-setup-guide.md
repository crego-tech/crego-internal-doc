# Release Process Setup Guide

> **Audience:** Engineering Lead, DevOps, Team Lead
> **Purpose:** One-time setup of Linear workspace, GitHub repositories, and CI/CD pipelines to support the Crego release management process.
> **Last Updated:** February 2026

---

## 1. Git Branching Model

Every repository follows the same branching structure.

**Permanent branches:**

- `master` — Production-ready code. Every commit on master is a deployed release.
- `develop` — Integration branch. All feature work merges here first. Auto-deploys to internal dev environment.

**Temporary branches:**

- `feature/<linear-issue-id>-short-description` — Feature work. Branched from `develop`, merged back to `develop` via PR.
- `bugfix/<linear-issue-id>-short-description` — Bug fixes discovered during development. Same flow as feature branches.
- `release/<version>` — Release candidates for shared (internal) environment. Branched from `develop`, merged to `master` after UAT.
- `release/<version>-<client-name>` — Client-specific release branches. Branched from the shared release branch or a specific tag.
- `hotfix/<linear-issue-id>-short-description` — Emergency production fixes. Branched from `master`, merged to both `master` and `develop`.

**Branch protection rules to configure on GitHub:**

For `master`/`main` (production branch — name varies by repo):
- Require pull request reviews (minimum 2 reviewers)
- Require status checks to pass (CI pipeline)
- Require branches to be up to date before merging
- Do not allow force pushes
- Do not allow deletions

For `develop`:
- Require pull request reviews (minimum 2 reviewers)
- Require status checks to pass (CI pipeline, lint, tests)
- Do not allow force pushes

For `release/*`:
- Require pull request reviews (minimum 2 reviewers, ideally lead or QA)
- Require status checks to pass
- Only allow merge commits (no squash) to preserve commit history for traceability

---

## 2. Linear Workspace Setup

### 2.1 Teams

Create one Linear team per functional area, or a single team if the org is small. The team should map to the people who own the sprint/cycle cadence.

Recommended: One team called **Crego Engineering** (or split into Backend, Frontend, Infra if teams are large enough to warrant separate boards).

### 2.2 Workflow States

Configure these states in order. The states after "PR Review" map your deployment pipeline into Linear so everyone can see where an issue actually is.

| State | Category | Owner | Who Moves It Here | How | Description | SLA |
|---|---|---|---|---|---|---|
| Triage | Triage | Engg Manager | Anyone | Auto — default state for new issues | Newly created issues land here for initial review | — |
| Backlog | Backlog | Engg Manager | Engg Manager | Manual — during triage or grooming | Triaged but not scheduled for a cycle | — |
| Requirement | Unstarted | Product Manager | Engg Manager / PM | Manual — PM picks up from backlog | PM fills in full requirements, acceptance criteria, designs | — |
| Todo | Unstarted | Developer (assignee) | Engg Manager | Manual — during sprint planning | Fully spec'd, ready to be picked up for development | — |
| Development | In Development | Developer | Developer | Manual — developer picks up the issue | Developer is actively working on it | — |
| PR Review | In Development | **Reviewer** | Auto (GitHub↔Linear) | Auto — triggered when PR is opened with `CRE-xxx` in title | PR is open and awaiting code review. **Reviewer owns it**, not the author | Review within **1 business day** |
| QA | In Development | **QA Engineer** | Auto (GitHub↔Linear) | Auto — triggered when PR is merged to `develop` | Code is on develop and auto-deployed to internal dev. **QA owns it** for testing | QA picks up within **1 business day** |
| Pending UAT | In Development | **Release Manager** | QA Engineer | Manual — QA testing passed | QA testing complete, issue queued for UAT. Release Manager coordinates UAT scheduling with client/stakeholders | — |
| UAT | In Development | QA / Client | QA / Release Manager | Manual — when release branch is cut and deployed to pre-prod | Issue is in a release branch, client or stakeholder performing acceptance testing | — |
| Pending Release | Completed | Release Manager | QA / Product | Manual — UAT sign-off received | UAT approved, waiting for production deployment | — |
| Released | Completed | Release Manager | Release Manager | Manual — after production deployment completes | Merged to `master`, tagged, deployed to production. Final state. | — |
| Cancelled | Cancelled | — | Engg Manager | Manual | Will not be done; reason documented in issue | — |

#### Ownership Rules & Escalation

**General principle:** At every state, exactly one role owns the issue. That person is responsible for either completing their work or moving it forward. If you're blocked, comment on the issue and escalate — don't let it sit.

**"Requirement" — PM owns it:**
- Product Manager fills in the full requirement details: problem statement, acceptance criteria, designs/mockups, and any dependencies.
- Issue should not move to Todo until the PM has completed the requirement and it has been reviewed by the Dev Lead.
- **Stuck 2+ days** → Engg Manager follows up with PM.

**"PR Review" — Reviewer owns it:**
- GitHub auto-moves the issue here when a PR is opened, but **it does not assign a reviewer**. The developer must request a specific reviewer on the PR — that reviewer now owns the issue.
- **Approved** → Reviewer (or author, per team convention) merges. Issue auto-moves to "QA".
- **Changes requested** → Issue stays in "PR Review". Ownership flips back to the **author** until they address feedback and re-request review.
- **Self-review is not allowed.** Every PR needs at least one approval from someone other than the author.
- **Stuck 2+ days** → Engg Manager intervenes (reassigns reviewer or escalates).

**"QA" — QA Engineer owns it:**
- GitHub auto-moves the issue here when a PR is merged to `develop`, but **it does not notify QA**. QA must actively monitor issues landing in this state.
- **Developer's handoff responsibility:** Ensure the issue has clear acceptance criteria and testing notes before the PR merges. If QA can't test without context, that's a developer gap.
- **Stuck 2+ days** → Engg Manager or release manager intervenes (assigns QA or reprioritizes QA backlog).

**"Pending UAT" — Release Manager owns it:**
- QA moves the issue here after testing passes on the dev environment.
- Release Manager coordinates UAT scheduling — decides when to include the issue in a release branch and arranges stakeholder/client availability.
- Issues stay here until a release branch is cut and deployed to pre-prod, at which point the Release Manager moves them to "UAT".

**States with no auto-transition** (everything else):
- The person listed in "Who Moves It Here" is responsible for manually updating the Linear state. If they don't, the issue appears stuck and the Engg Manager or release manager should follow up.

### 2.3 Labels

Create these label groups in Linear. Labels are how you filter, search, and generate release notes.

**Type (required on every issue):**

| Label | Color (suggested) | Use When |
|---|---|---|
| `type:feature` | Blue | New functionality |
| `type:bug` | Red | Something is broken |
| `type:improvement` | Green | Enhancement to existing functionality |
| `type:chore` | Gray | Refactoring, dependency updates, CI changes, documentation |
| `type:hotfix` | Orange | Emergency production fix (follows hotfix git flow) |
| `type:tech-debt` | Purple | Addressing accumulated technical debt |

**Priority (use Linear's built-in priority):**

| Level | Meaning |
|---|---|
| Urgent | Production is broken or release is blocked |
| High | Must be in the next release |
| Medium | Planned for an upcoming release |
| Low | Backlog — nice to have |
| No Priority | Not yet triaged |

**Client:**

| Label | Use When |
|---|---|
| `client:shared` | Applies to all environments (internal + all clients) |
| `client:<client-name>` | Client-specific work (e.g., `client:acme`, `client:globex`) |

Create one label per client. This is how you filter release notes per client.

**Repository:**

| Label | Use When |
|---|---|
| `repo:crego-ai` | Work touches crego-ai backend |
| `repo:crego-flow` | Work touches crego-flow backend |
| `repo:crego-web` | Work touches crego-web frontend |
| `repo:crego-infra` | Work touches crego-infra |
| `repo:crego-omni` | Work touches crego-omni |

An issue can have multiple repo labels if it spans repositories.

**Found-in (tracks where a bug was discovered):**

Use this label group on bug and hotfix issues to track which environment the issue was first discovered in. This helps measure quality — ideally most bugs are caught early (UAT) rather than in production.

| Label | Use When |
|---|---|
| `found-in:dev` | Bug was discovered during QA/UAT testing on the dev/internal environment |
| `found-in:preprod` | Bug was discovered during pre-prod testing (release branch) |
| `found-in:prod` | Bug was discovered in production (typically becomes a hotfix) |

**Flags (used during release management):**

| Label | Use When |
|---|---|
| `release-blocker` | This issue blocks the release from going out |
| `needs-cherry-pick` | Fix needs to be applied to another branch (release or client branch) |
| `needs-backport` | Fix on release/hotfix branch that must be merged back to develop |
| `breaking-change` | Introduces a breaking API or behavior change |
| `delayed` | Issue did not reach "Pending Release" by end of cycle — moved to next cycle |
| `feature-flag` | Behind a feature flag — can be toggled per client/environment |

### 2.4 Cycles

Use Linear Cycles to represent your weekly (or biweekly) development sprints. Each cycle should align with your release cadence.

Naming convention: `Sprint 24 (Feb 10–Feb 14)` or simply let Linear auto-name them.

At the start of each cycle, move issues from Backlog to Todo. At the end, any incomplete issues either roll over or go back to Backlog with a note.

### 2.5 Projects

Use Linear Projects to group work for a specific release version or a larger initiative that spans multiple cycles.

Naming convention: `Release v1.2.3` or `Q1 2026 — Onboarding Redesign`

Every issue going into a release should be attached to the corresponding project. This gives you a single dashboard showing "what's in this release" and completion percentage.

### 2.6 Issue Templates

Create these templates in Linear so that every issue starts with the right structure.

**Feature Template:**
```
## Problem
<!-- What problem does this solve? Who is affected? -->

## Proposed Solution
<!-- High-level approach. Include mockups/links if available. -->

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Affected Repositories
<!-- Tag with repo labels -->

## Notes
<!-- Any dependencies, risks, or things to watch out for -->
```

**Bug Template:**
```
## Description
<!-- What is happening? What should be happening instead? -->

## Steps to Reproduce
1. Step 1
2. Step 2

## Environment
<!-- Dev / Pre-prod / Prod? Which client? Browser/device? -->

## Expected Behavior
<!-- What should happen -->

## Actual Behavior
<!-- What actually happens. Include screenshots/logs. -->

## Severity
<!-- Blocker / Major / Minor / Cosmetic -->
```

**Hotfix Template:**
```
## Incident Description
<!-- What broke in production? -->

## Impact
<!-- Who is affected? How many users/clients? Revenue impact? -->

## Root Cause (if known)
<!-- What caused this? -->

## Fix
<!-- What needs to change? -->

## Rollback Plan
<!-- If the fix makes things worse, how do we revert? -->
```

---

## 3. GitHub–Linear Integration

### 3.1 Enable the Integration

Go to Linear → Settings → Integrations → GitHub. Connect your GitHub organization and link all repositories.

### 3.2 Automatic State Transitions

Configure these automations (Linear supports this via the GitHub integration):

| GitHub Event | Linear State Transition |
|---|---|
| PR opened referencing issue | → PR Review |
| PR merged to `develop` | → QA |
| PR merged to `master` | → Released |

To reference a Linear issue in a PR, include the issue identifier (e.g., `CRE-123`) in the PR title or branch name. Since branch names are copied from Linear, this should happen automatically.

### 3.3 Branch Name Format

Linear generates branch names in the format: `username/cre-123-short-description`

Standardize this across the team: always copy the branch name from Linear. This ensures the GitHub integration can track the issue automatically.

---

## 4. CI/CD Pipeline Configuration

### 4.1 Pipeline Triggers

Configure your CI/CD (GitHub Actions, or whatever you use) with these triggers:

| Branch Pattern | Environment | Trigger |
|---|---|---|
| `develop` | Internal Dev | On merge (automatic) |
| `release/*` (excluding client patterns) | Internal Pre-prod | On push/creation of release branch |
| `release/*-<client>` | Client-specific staging | On push/creation of client release branch |
| Tags: `v*` | Internal Production | On tag push |
| Tags: `v*-<client>` | Client Production | On tag push |

### 4.2 Tag Naming Convention

| Tag Pattern | Meaning | Example |
|---|---|---|
| `v1.2.3` | Shared/internal production release | `v1.2.3` |
| `v1.2.3-acme` | Client-specific production release | `v1.2.3-acme` |
| `v1.2.3-rc.1` | Release candidate (optional, for pre-prod) | `v1.2.3-rc.1` |

Use semantic versioning: `MAJOR.MINOR.PATCH`
- MAJOR: Breaking changes
- MINOR: New features (backward compatible)
- PATCH: Bug fixes

### 4.3 Environment Variables

Each environment should have its own configuration. Never share secrets across environments.

| Environment | Branch/Tag Source | Config Source |
|---|---|---|
| dev | `develop` | `.env.dev` or environment-specific secrets |
| pre-prod | `release/*` | `.env.preprod` |
| prod | `v*` tags | `.env.prod` |
| client-staging | `release/*-<client>` | Client-specific config |
| client-prod | `v*-<client>` tags | Client-specific config |

---

## 5. Versioning Strategy

### 5.1 When to Bump Versions

| Change Type | Version Bump | Example |
|---|---|---|
| Bug fix, patch | PATCH | 1.2.3 → 1.2.4 |
| New feature (backward compatible) | MINOR | 1.2.3 → 1.3.0 |
| Breaking change | MAJOR | 1.2.3 → 2.0.0 |

### 5.2 Who Decides the Version

The engineering lead or release manager decides the version number when cutting the release branch. Base it on the contents of the release:
- If the release contains only bug fixes → patch bump
- If it contains new features → minor bump
- If it contains breaking API changes → major bump

### 5.3 Tracking Versions per Client

Maintain a `CLIENT_VERSIONS.md` file in the `crego-infra` repo (or as a Linear document) with this format:

```markdown
# Client Version Tracker

| Client | Current Version | Last Deployed | Environment | Notes |
|--------|----------------|---------------|-------------|-------|
| Shared (internal) | v1.3.0 | 2026-02-10 | prod | — |
| Acme Corp | v1.2.4-acme | 2026-02-05 | client-prod | Waiting for v1.3.0 UAT |
| Globex Inc | v1.3.0-globex | 2026-02-12 | client-prod | Up to date |
```

Update this file as part of every release. This is the single source of truth for "what version is each client running."

---

## 6. Hotfix Flow

This is the one flow that bypasses your normal develop → release → master pipeline. It must be defined explicitly because production emergencies will happen.

```
master (broken)
  └── hotfix/CRE-456-fix-payment-crash
        ├── merge → master (fix deployed via tag)
        └── merge → develop (fix flows into next release)
```

Steps:
1. Create a Linear issue with type `hotfix` and priority `Urgent`
2. Branch from `master`: `hotfix/CRE-456-fix-payment-crash`
3. Fix, test locally, open PR to `master`
4. Get expedited review (2 reviewers minimum, but don't skip review)
5. Merge to `master`
6. Tag immediately: `v1.2.4` (patch bump from current version)
7. Push tag → triggers prod deployment
8. Open a second PR from the hotfix branch (or from master) to `develop`
9. If a release branch is currently open, cherry-pick the fix there too
10. Update the Linear issue to Released
11. If the fix affects clients, create client-specific tags as needed

---

## 7. Release Notes Automation

### 7.1 Generating Release Notes

After a release is deployed, generate release notes from Linear:

1. Go to the Linear Project for that release (e.g., `Release v1.3.0`)
2. Filter issues by state: Released
3. Group by label (type:feature, type:bug, type:improvement)
4. Export or manually compile into this format:

```markdown
# Release v1.3.0 — February 14, 2026

## New Features
- CRE-101: Added bulk import for user data
- CRE-115: New dashboard analytics widget

## Bug Fixes
- CRE-98: Fixed timeout on large file uploads
- CRE-102: Corrected tax calculation rounding

## Improvements
- CRE-110: Optimized database queries for reporting (2x faster)

## Chores
- CRE-120: Upgraded Node.js to v20 LTS
```

### 7.2 Client-Specific Release Notes

For client releases, filter by the client label (`client:acme`) in addition to the release project. Only include issues relevant to that client.

---

## 8. Setup Checklist

Use this checklist when setting up the process for the first time.

- [ ] GitHub branch protection rules configured on all repos (master, develop)
- [ ] Linear workflow states created (all 12 states listed above)
- [ ] Linear label groups created (Type, Found-in, Client, Repository, Flags)
- [ ] Linear issue templates created (Feature, Bug, Hotfix)
- [ ] Linear–GitHub integration connected and tested
- [ ] CI/CD pipelines configured for all branch/tag patterns
- [ ] Semantic versioning strategy documented and communicated
- [ ] CLIENT_VERSIONS.md created in crego-infra (or Linear doc)
- [ ] Hotfix flow documented and walked through with team
- [ ] First test release completed end-to-end (develop → release → master → tag)
- [ ] Team onboarded on the Team Release Playbook (see companion document)
