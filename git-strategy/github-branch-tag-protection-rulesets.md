# GitHub Organization-Level Rulesets for crego-tech

**Status:** Active
**Last Updated:** February 2026
**Author:** Crego Engineering
**Audience:** CTO, Engineering Manager, Release Manager, Development Team
**Related Documents:** [git-strategy.md](./git-strategy.md), [team-release-playbook.md](../release-management/team-release-playbook.md)

---

## Table of Contents

1. [Overview](#overview)
2. [GitHub Organization Structure](#github-organization-structure)
3. [GitHub Teams Setup](#github-teams-setup)
4. [Ruleset 1: Production Branches (master/main)](#ruleset-1-production-branches)
5. [Ruleset 2: Develop Branch](#ruleset-2-develop-branch)
6. [Ruleset 3: Release Branches](#ruleset-3-release-branches)
7. [Ruleset 4: Hotfix Branches](#ruleset-4-hotfix-branches)
8. [Ruleset 5: Feature & Bugfix Branches](#ruleset-5-feature--bugfix-branches)
9. [Ruleset 6: Tags (Critical)](#ruleset-6-tags)
10. [Ruleset 7: Infrastructure-Specific Branches](#ruleset-7-infrastructure-specific-branches)
11. [Ruleset 8: Wildcard Branch Protection](#ruleset-8-wildcard-branch-protection)
12. [CODEOWNERS Configuration](#codeowners-configuration)
13. [Implementation Steps](#implementation-steps)
14. [Audit & Compliance](#audit--compliance)
15. [Decision Points & Notes](#decision-points--notes)

---

## Overview

### Why Organization-Level Rulesets?

GitHub Organization Rulesets (available on GitHub Team plan and above) provide a centralized way to enforce governance policies across all repositories in an organization. This approach:

- **Consistency:** Apply the same policies to all repos (crego-ai, crego-flow, crego-omni, crego-web, crego-infra, crego-internal-docs) without per-repo duplication
- **Scalability:** Add new repos and they inherit the same protection rules automatically
- **Simplified Management:** Changes to policies are made once at the org level
- **Team-Based Permissions:** Leverage GitHub teams to grant bypass permissions based on roles
- **Audit Trail:** GitHub logs all ruleset enforcement and bypasses

### Prerequisites

- **GitHub Organization Plan:** Team plan or higher (Enterprise Cloud recommended for large orgs)
- **Organization Owner Access:** Only org owners can create/modify rulesets
- **GitHub Teams:** Org teams must be configured for bypass role assignments (see [GitHub Teams Setup](#github-teams-setup))

### Scope

These rulesets apply to:

| Repository | Production Branch | Integration Branch | Notes |
|---|---|---|---|
| crego-ai | `master` | `develop` | Backend service |
| crego-flow | `master` | `develop` | Backend service |
| crego-omni | `master` | `develop` | Backend service |
| crego-web | `main` | `develop` | Frontend monorepo |
| crego-infra | `main` | `develop` | Infrastructure (special rules apply) |
| crego-internal-docs | `main` | `develop` | Documentation |

---

## GitHub Organization Structure

### Repositories

```
crego-tech/
├── crego-ai
├── crego-flow
├── crego-omni
├── crego-web
├── crego-infra
└── crego-internal-docs
```

### Teams Model

Teams are created at the organization level and represent roles within the crego-tech org. Members can be assigned to multiple teams.

---

## GitHub Teams Setup

Create the following GitHub teams in the crego-tech organization. These teams will be used as bypass roles in rulesets.

### Team: `crego-release-managers`

**Purpose:** Release coordinators and deployment authority
**Members:** CTO, Engineering Manager (Release Manager)
**Permissions:**
- Can create release branches (`release/**`, `release/**-clientname`)
- Can create and delete tags (`v*`)
- Can merge PRs to production branches (but still requires approvals)
- Can force-push to production in emergencies (with audit)

**Bypass Grants:**
- Ruleset 1 (Production Branches): Creation, Merge
- Ruleset 3 (Release Branches): Creation, Deletion
- Ruleset 6 (Tags): Creation, Deletion
- Ruleset 7 (Infra Branches): Creation, Deletion

### Team: `crego-leads`

**Purpose:** Technical leads and emergency decision-makers
**Members:** CTO, Engineering Manager, FE Lead, BE Lead
**Permissions:**
- Can create hotfix branches in emergencies
- Can bypass some protections for urgent fixes
- Have veto authority on code reviews

**Bypass Grants:**
- Ruleset 2 (Develop Branch): Creation bypass (rarely used)
- Ruleset 4 (Hotfix Branches): Creation
- Ruleset 8 (Wildcard Protection): Limited exceptions for on-call situations

### Team: `crego-developers`

**Purpose:** Standard development team
**Members:** All FE and BE developers (6 developers)
**Permissions:**
- Can create feature and bugfix branches
- Can push to own feature branches
- Must submit PRs for code review
- No direct push to develop, master, or main

**Bypass Grants:**
- Ruleset 5 (Feature/Bugfix): Creation, force-push to own branches

### Team: `crego-qa`

**Purpose:** Quality assurance and testing
**Members:** QA Engineers (2 QA Engineers)
**Permissions:**
- Can approve PRs targeting release branches
- Can merge to release branches (conditional)
- Cannot directly push to production branches

**Bypass Grants:**
- None (QA follows standard PR workflow)

---

## Ruleset 1: Production Branches

**Name:** `Production Branch Protection (master/main)`
**Scope:** All repositories
**Target Branches:** `master` (crego-ai, crego-flow, crego-omni), `main` (crego-web, crego-infra, crego-internal-docs)

### Rules

| Rule | Setting | Bypass |
|---|---|---|
| **Restrict Creation** | No direct push; only via PR | `crego-release-managers` |
| **Restrict Deletion** | Cannot delete production branches | None (immutable) |
| **Block Force Pushes** | No force-push allowed | None (immutable) |
| **Require PR Before Merge** | Yes | None |
| **Dismiss Stale Reviews** | Yes (stale after new commit) | N/A |
| **Require Review from Code Owners** | Yes (if CODEOWNERS exists) | None |
| **Require Status Checks** | CI/CD pipeline must pass | None |
| **Required Approvals** | 2 approvals from different team members | None |
| **Require Branches Up to Date** | Yes (must rebase/merge from base) | None |
| **Require Conversation Resolution** | Yes (all comments must be resolved) | None |
| **Allowed Merge Methods** | Merge Commit only (no squash, no rebase) | N/A |

### Rationale

- **2 Approvals:** Production deploys risk entire user base; require two independent reviewers
- **Merge Commit:** Preserves full history and commit attribution; no squashing on production
- **Code Owners:** Ensures reviewers with domain knowledge approve changes
- **Status Checks:** Automated tests must pass before human reviewers even see the PR
- **crego-release-managers Bypass:** Only release managers can initiate the merge, but 2 approvals still required

### Configuration Example (GitHub UI)

```
Restrict who can push to matching branches:
  - Dismiss stale pull request approvals when new commits are pushed: ✓
  - Require status checks to pass: ✓
    - CI/CD pipeline (e.g., GitHub Actions)
  - Require branches to be up to date before merging: ✓
  - Require code review from code owners: ✓
  - Required number of approvals before merging: 2
  - Require conversation resolution before merging: ✓
  - Allow specified actors to bypass required pull requests: crego-release-managers
  - Restrict creations: ✓ (allow only: crego-release-managers)
  - Restrict force pushes: ✓ (allow: nobody)
  - Restrict deletions: ✓ (allow: nobody)
```

---

## Ruleset 2: Develop Branch

**Name:** `Develop Branch Protection`
**Scope:** All repositories
**Target Branches:** `develop`

### Rules

| Rule | Setting | Bypass |
|---|---|---|
| **Restrict Creation** | No direct push; only via PR | `crego-leads` |
| **Restrict Deletion** | Cannot delete develop branch | None (immutable) |
| **Block Force Pushes** | No force-push allowed | None |
| **Require PR Before Merge** | Yes | None |
| **Dismiss Stale Reviews** | Yes | N/A |
| **Require Review from Code Owners** | Yes (recommended) | None |
| **Require Status Checks** | CI/lint/tests must pass | None |
| **Required Approvals** | 1 approval (see [Decision Points](#decision-points--notes)) | None |
| **Require Branches Up to Date** | Yes | None |
| **Require Conversation Resolution** | Yes | None |
| **Allowed Merge Methods** | Squash & Merge only | N/A |

### Rationale

- **1 Approval (with caveat):** Develop is the integration branch for continuous deployment to dev environment. Faster velocity needed than production, but still requires one reviewer to catch obvious issues. See [Decision Points](#decision-points--notes) for discussion.
- **Squash & Merge:** Keeps develop history clean; individual feature commits are not critical here
- **Status Checks:** Automated tests prevent broken code reaching integration branch
- **Code Owners:** Encourages appropriate domain expert review
- **crego-leads Bypass:** Rarely used; mainly for on-call situations

### Configuration Example (GitHub UI)

```
Restrict who can push to matching branches:
  - Dismiss stale pull request approvals: ✓
  - Require status checks to pass: ✓
    - CI (build, unit tests)
    - Lint (code style)
    - Integration tests (if applicable)
  - Require branches to be up to date before merging: ✓
  - Require code review from code owners: ✓
  - Required number of approvals before merging: 1
  - Require conversation resolution before merging: ✓
  - Allow specified actors to bypass required pull requests: (none)
  - Restrict creations: ✓ (allow only: crego-leads)
  - Restrict force pushes: ✓ (allow: nobody)
  - Restrict deletions: ✓ (allow: nobody)
```

---

## Ruleset 3: Release Branches

**Name:** `Release Branch Protection`
**Scope:** All repositories
**Target Branches:** `release/v*`, `release/v*-*` (fnmatch pattern: `release/**`)

### Rules

| Rule | Setting | Bypass |
|---|---|---|
| **Restrict Creation** | Only crego-release-managers can create | `crego-release-managers` |
| **Restrict Deletion** | Only crego-release-managers can delete (after release) | `crego-release-managers` |
| **Block Force Pushes** | No force-push allowed | None |
| **Require PR Before Merge** | Yes (for bug fixes during RC phase) | None |
| **Dismiss Stale Reviews** | Yes | N/A |
| **Require Review from Code Owners** | Yes | None |
| **Require Status Checks** | CI must pass | None |
| **Required Approvals** | 2 (FE/BE Lead + QA) | None |
| **Require Branches Up to Date** | Yes | None |
| **Require Conversation Resolution** | Yes | None |
| **Allowed Merge Methods** | Merge Commit only | N/A |

### Rationale

- **Creation Restriction:** Only crego-release-managers (CTO, Engineering Manager) can cut release branches to prevent accidental releases
- **2 Approvals:** Lead + QA review ensures quality gate before candidate release
- **Merge Commit:** Preserves release branch history for audit trail
- **Deletion Restriction:** Prevents accidental deletion of release branch mid-release; only deleted after go-live

### Configuration Example (GitHub UI)

```
Restrict who can push to matching branches:
  - Dismiss stale pull request approvals: ✓
  - Require status checks to pass: ✓
    - CI pipeline
  - Require branches to be up to date before merging: ✓
  - Require code review from code owners: ✓
  - Required number of approvals before merging: 2
  - Require conversation resolution before merging: ✓
  - Restrict creations: ✓ (allow only: crego-release-managers)
  - Restrict deletions: ✓ (allow only: crego-release-managers)
  - Restrict force pushes: ✓ (allow: nobody)
```

---

## Ruleset 4: Hotfix Branches

**Name:** `Hotfix Branch Protection`
**Scope:** All repositories
**Target Branches:** `hotfix/**`

### Rules

| Rule | Setting | Bypass |
|---|---|---|
| **Restrict Creation** | crego-release-managers + crego-leads can create | `crego-release-managers`, `crego-leads` |
| **Restrict Deletion** | crego-release-managers can delete | `crego-release-managers` |
| **Block Force Pushes** | No force-push allowed | None |
| **Require PR Before Merge** | Yes (no skipping even for emergencies) | None |
| **Dismiss Stale Reviews** | Yes | N/A |
| **Require Status Checks** | CI must pass | None |
| **Required Approvals** | 2 (expedited but mandatory) | None |
| **Require Branches Up to Date** | Yes | None |
| **Require Conversation Resolution** | Yes | None |
| **Allowed Merge Methods** | Merge Commit only | N/A |

### Rationale

- **Creation by Leads:** Emergencies require quick decision; CTO and Engg Manager can authorize hotfix
- **2 Approvals (No Bypass):** Even hotfixes must have 2 reviewers. "Emergency" doesn't mean "unapproved." Leads can fast-track review, but approval still required.
- **Merge Commit:** Preserves hotfix in production history
- **Force Push Disabled:** Maintains audit trail even in emergencies

### Configuration Example (GitHub UI)

```
Restrict who can push to matching branches:
  - Dismiss stale pull request approvals: ✓
  - Require status checks to pass: ✓
    - CI pipeline
  - Require branches to be up to date before merging: ✓
  - Required number of approvals before merging: 2
  - Require conversation resolution before merging: ✓
  - Restrict creations: ✓ (allow: crego-release-managers, crego-leads)
  - Restrict deletions: ✓ (allow: crego-release-managers)
  - Restrict force pushes: ✓ (allow: nobody)
```

---

## Ruleset 5: Feature & Bugfix Branches

**Name:** `Feature/Bugfix Branch Protection`
**Scope:** All repositories
**Target Branches:** `feature/**`, `bugfix/**`

### Rules

| Rule | Setting | Bypass |
|---|---|---|
| **Restrict Creation** | No restriction; any developer can create | None |
| **Restrict Deletion** | Author or crego-leads can delete | Author, `crego-leads` |
| **Block Force Pushes** | Allowed (developers may rebase their own branches) | All developers (implicit) |
| **Require PR Before Merge** | No (these are working branches) | N/A |
| **Restrict Merge** | Merges must follow develop branch rules | (inherit Ruleset 2) |

### Rationale

- **No Creation Restriction:** Lightweight; developers should be free to experiment locally
- **Author Can Delete:** Encourages cleanup of stale branches
- **Force Push Allowed:** Developers often rebase feature branches before merging
- **Inherit PR Rules:** When feature branch is merged to develop, Ruleset 2 applies
- **No Per-Branch Protection:** Feature branches are temporary; protection happens at PR review time

### Configuration Example

```
No per-branch restrictions on feature/** or bugfix/**
However, PRs targeting develop must comply with Ruleset 2 (Develop Branch Protection)
```

---

## Ruleset 6: Tags

**Name:** `Production Tag Protection`
**Scope:** All repositories
**Target Tags:** `v*` (fnmatch pattern: `v*`)

### Rules

| Rule | Setting | Bypass |
|---|---|---|
| **Restrict Creation** | ONLY crego-release-managers | `crego-release-managers` |
| **Restrict Deletion** | ONLY crego-release-managers | `crego-release-managers` |
| **Restrict Updates** | Nobody can update tags (immutable) | None |
| **Require PR Before Merge** | N/A (tags don't use PRs) | N/A |

### Rationale

**CRITICAL RULE:** Tags trigger automated production deployments. Unauthorized tag creation = unauthorized production deployment.

- **Restriction to crego-release-managers:** Only CTO and Engg Manager can tag releases
- **No Updates:** Tags are immutable (v1.2.3 is forever v1.2.3)
- **No Bypass:** No exceptions, even for leads
- **Audit Trail:** Every tag creation/deletion is logged

### Tag Naming Convention

| Pattern | Purpose | Example | Created By |
|---|---|---|---|
| `vX.Y.Z` | Shared/internal production release (semver) | v2.3.1 | crego-release-managers |
| `vX.Y.Z-clientname` | Client-specific production release | v2.3.1-acme-corp | crego-release-managers |
| `vX.Y.Z-rc.N` | Release candidate (optional, pre-prod) | v2.3.1-rc.1 | crego-release-managers |

### Configuration Example (GitHub UI)

```
Restrict who can create matching tags:
  - Allow only: crego-release-managers

Restrict who can delete matching tags:
  - Allow only: crego-release-managers

Restrict who can update matching tags:
  - Allow: nobody (tags are immutable)
```

---

## Ruleset 7: Infrastructure-Specific Branches

**Name:** `Infrastructure Environment Branches`
**Scope:** crego-infra repository only
**Target Branches:** `env/**`, `clients/**`

### Rules

| Rule | Setting | Bypass |
|---|---|---|
| **Restrict Creation** | crego-release-managers only | `crego-release-managers` |
| **Restrict Deletion** | crego-release-managers only | `crego-release-managers` |
| **Block Force Pushes** | Allowed for `env/**` only (rollback procedures) | N/A |
| **Require PR Before Merge** | Yes | None |
| **Dismiss Stale Reviews** | Yes | N/A |
| **Require Status Checks** | Infrastructure validation must pass | None |
| **Required Approvals** | 2 (infra requires 2 per CONTRIBUTING.md) | None |
| **Require Branches Up to Date** | Yes | None |
| **Require Conversation Resolution** | Yes | None |
| **Allowed Merge Methods** | Merge Commit only | N/A |

### Special Considerations: Force Push for env/* Branches

- **env/dev:** Force-push allowed (dev is ephemeral)
- **env/uat:** Force-push blocked (pre-prod should be stable)
- **env/prod:** Force-push allowed for **rollback procedures only** (crego-release-managers can revert prod deployment)

### Rationale

- **Creation/Deletion Restriction:** Environment branches are critical infrastructure; only release managers should manage them
- **Force Push Exception for env/prod:** Allows crego-release-managers to quickly rollback a bad prod deployment by force-pushing the previous commit
- **2 Approvals:** Infra changes have higher risk; two reviewers catch misconfigurations
- **Merge Commit:** Preserves infra history for audit and debugging

### Configuration Example (GitHub UI)

```
For env/** pattern:
  - Restrict creations: ✓ (allow: crego-release-managers)
  - Restrict deletions: ✓ (allow: crego-release-managers)
  - Restrict force pushes: Block but allow crego-release-managers for env/prod
  - Require PR before merge: ✓
  - Required approvals: 2
  - Require status checks: ✓
  - Require branches up to date: ✓

For clients/** pattern:
  - Restrict creations: ✓ (allow: crego-release-managers)
  - Restrict deletions: ✓ (allow: crego-release-managers)
  - Restrict force pushes: Block (no exceptions)
  - Require PR before merge: ✓
  - Required approvals: 2
```

---

## Ruleset 8: Wildcard Branch Protection

**Name:** `Naming Convention Enforcement`
**Scope:** All repositories
**Target Branches:** `*` (wildcard catch-all)

### Rule

| Rule | Setting |
|---|---|
| **Enforce Naming Convention** | Branches must match known patterns or be rejected |

### Known Allowed Patterns

Developers should only create branches matching these patterns:

- `feature/cre-*` — Feature branches
- `bugfix/cre-*` — Bugfix branches
- `hotfix/cre-*` — Hotfix branches (crego-release-managers only)
- `release/v*` — Release branches (crego-release-managers only)
- `env/*` — Infrastructure environments (crego-infra only)
- `clients/*` — Client-specific branches (crego-infra only)
- `develop` — Integration branch (protected by Ruleset 2)
- `master` — Production branch (crego-ai, crego-flow, crego-omni)
- `main` — Production branch (crego-web, crego-infra, crego-internal-docs)

### Enforcement Method

**GitHub Rulesets do not natively enforce naming conventions.** Use one of these alternatives:

#### Option A: Commit Hooks (Recommended)

Each repository includes a pre-push hook that validates branch names:

```bash
#!/bin/bash
# .githooks/pre-push

BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [[ ! $BRANCH =~ ^(feature|bugfix|hotfix|release|env|clients|develop|master|main)/.*$ ]]; then
  echo "❌ Invalid branch name: $BRANCH"
  echo "Use: feature/cre-xxx, bugfix/cre-xxx, hotfix/cre-xxx, release/v*, etc."
  exit 1
fi

exit 0
```

Enable hooks in each repo:

```bash
git config core.hooksPath .githooks
```

#### Option B: GitHub Actions Workflow

Create a workflow that validates branch names on every push:

```yaml
name: Validate Branch Name

on:
  push:
    branches:
      - '**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Check branch name
        run: |
          BRANCH=${{ github.ref_name }}
          if [[ ! $BRANCH =~ ^(feature|bugfix|hotfix|release|env|clients|develop|master|main)/ ]]; then
            echo "❌ Invalid branch name: $BRANCH"
            exit 1
          fi
```

#### Option C: Protected Branch Pattern (Limited)

Use Ruleset 1-7 to protect known patterns. Reject unknown patterns with a rule targeting `*` that requires approval from crego-leads (slow, but effective forcing naming discussions).

**Recommendation:** Use **Option A (pre-push hooks)** for fast local feedback + **Option B (GitHub Actions)** as a backup check. Developers get immediate feedback before pushing.

---

## CODEOWNERS Configuration

CODEOWNERS files help GitHub suggest appropriate reviewers. Place one file in each repository root.

### crego-ai / crego-flow / crego-omni (Backend Services)

**File:** `.github/CODEOWNERS`

```
# CODEOWNERS for crego-ai (replace with crego-flow, crego-omni for those repos)

# Backend code
project/                     @crego-tech/crego-be-lead
project/tests/               @crego-tech/crego-be-developers

# CI/CD and deployment
.github/workflows/           @crego-tech/crego-release-managers
Dockerfile*                  @crego-tech/crego-release-managers
.dockerignore                @crego-tech/crego-release-managers

# Documentation
README.md                    @crego-tech/crego-be-lead
CONTRIBUTING.md              @crego-tech/crego-be-lead
```

### crego-web (Frontend Monorepo)

**File:** `.github/CODEOWNERS`

```
# CODEOWNERS for crego-web

# Frontend code
packages/                    @crego-tech/crego-fe-lead
packages/*/src/              @crego-tech/crego-fe-developers
packages/*/tests/            @crego-tech/crego-fe-developers

# Shared code
shared/                      @crego-tech/crego-fe-lead
shared/utils/                @crego-tech/crego-fe-developers
shared/components/           @crego-tech/crego-fe-lead

# Build and config
package.json                 @crego-tech/crego-fe-lead
pnpm-workspace.yaml          @crego-tech/crego-fe-lead
tsconfig.json                @crego-tech/crego-fe-lead
.github/workflows/           @crego-tech/crego-release-managers

# Documentation
README.md                    @crego-tech/crego-fe-lead
CONTRIBUTING.md              @crego-tech/crego-fe-lead
```

### crego-infra

**File:** `.github/CODEOWNERS`

```
# CODEOWNERS for crego-infra

# Infrastructure as Code
apps/                        @crego-tech/crego-be-lead
base/                        @crego-tech/crego-be-lead
overlays/                    @crego-tech/crego-be-lead
terraform/                   @crego-tech/crego-be-lead

# Environment branches (require 2 approvals per ruleset)
env/                         @crego-tech/crego-release-managers
clients/                     @crego-tech/crego-release-managers

# Scripts
scripts/                     @crego-tech/crego-release-managers

# Documentation
README.md                    @crego-tech/crego-be-lead
CONTRIBUTING.md              @crego-tech/crego-be-lead
```

### crego-internal-docs

**File:** `.github/CODEOWNERS`

```
# CODEOWNERS for crego-internal-docs

# Release management docs
release-management/          @crego-tech/crego-release-managers

# Architecture
architecture/                @crego-tech/crego-be-lead

# Engineering guides
engineering/                 @crego-tech/crego-be-lead
git-strategy/                @crego-tech/crego-release-managers

# Compliance (CTO approval)
compliance/                  @crego-tech/crego-release-managers
```

### Register Teams in GitHub

Create teams in GitHub and add team members:

```bash
# (Done in GitHub UI)

# Team: crego-be-lead
# Members: BE Lead

# Team: crego-be-developers
# Members: 3 BE developers

# Team: crego-fe-lead
# Members: FE Lead

# Team: crego-fe-developers
# Members: 3 FE developers

# Team: crego-release-managers
# Members: CTO, Engineering Manager

# Team: crego-qa
# Members: 2 QA Engineers
```

---

## Implementation Steps

### Step 1: Create GitHub Teams

1. Go to **crego-tech** organization → **Settings** → **Teams**
2. Create the following teams (see [GitHub Teams Setup](#github-teams-setup)):
   - `crego-release-managers`
   - `crego-leads`
   - `crego-developers`
   - `crego-qa`
3. Add members to each team based on roles
4. Verify all team members have been invited and accepted

**Checklist:**

- [ ] crego-release-managers created with CTO, Engg Manager
- [ ] crego-leads created with CTO, Engg Manager, FE Lead, BE Lead
- [ ] crego-developers created with all 6 developers
- [ ] crego-qa created with 2 QA engineers
- [ ] All members have accepted invitations

### Step 2: Enable Organization Rulesets

1. Go to **crego-tech** organization → **Settings** → **Rules** (or **Repository Rulesets** depending on GitHub UI version)
2. Confirm your organization is on **GitHub Team plan or higher**
3. Enable "Organization Rulesets" (if not already enabled)

### Step 3: Create Ruleset 1 — Production Branches

**Via GitHub UI:**

1. Go to **Organization Settings** → **Rules** → **New ruleset**
2. **Name:** `Production Branch Protection (master/main)`
3. **Enforcement Status:** Active
4. **Target:** Branches
5. **Include Patterns:** `master`, `main`
6. **Bypass List:**
   - Role: "Maintain or higher" role in organization
   - Teams: `crego-release-managers`
7. **Rules:**
   - ✓ Restrict creations
   - ✓ Restrict deletions (no bypass)
   - ✓ Block force pushes (no bypass)
   - ✓ Require a pull request before merging
     - Require approvals: 2
     - Dismiss stale reviews: Yes
     - Require review from code owners: Yes
   - ✓ Require status checks to pass: (select your CI/CD workflows)
   - ✓ Require branches to be up to date before merging
   - ✓ Require conversation resolution before merging
   - Allowed merge methods: Merge commits (uncheck Squash, Rebase)
8. **Save**

**Via GitHub API/Terraform (optional):**

See [Implementation via Terraform](#implementation-via-terraform-optional) below.

### Step 4: Create Ruleset 2 — Develop Branch

**Via GitHub UI:**

1. **New ruleset** → **Name:** `Develop Branch Protection`
2. **Target:** Branches
3. **Include Patterns:** `develop`
4. **Bypass List:**
   - Teams: `crego-leads`
5. **Rules:**
   - ✓ Restrict creations (allow bypass for `crego-leads`)
   - ✓ Restrict deletions (no bypass)
   - ✓ Block force pushes (no bypass)
   - ✓ Require a pull request before merging
     - Require approvals: 1
     - Dismiss stale reviews: Yes
     - Require review from code owners: Yes
   - ✓ Require status checks to pass
   - ✓ Require branches to be up to date before merging
   - ✓ Require conversation resolution before merging
   - Allowed merge methods: Squash and merge (uncheck Merge commits, Rebase)
6. **Save**

**Note on 1 vs 2 Approvals for Develop:** See [Decision Points](#decision-points--notes) section.

### Step 5: Create Ruleset 3 — Release Branches

**Via GitHub UI:**

1. **New ruleset** → **Name:** `Release Branch Protection`
2. **Target:** Branches
3. **Include Patterns:** `release/**` (fnmatch pattern)
4. **Bypass List:**
   - Teams: `crego-release-managers`
5. **Rules:**
   - ✓ Restrict creations (allow bypass for `crego-release-managers`)
   - ✓ Restrict deletions (allow bypass for `crego-release-managers`)
   - ✓ Block force pushes (no bypass)
   - ✓ Require a pull request before merging
     - Require approvals: 2
     - Dismiss stale reviews: Yes
     - Require review from code owners: Yes
   - ✓ Require status checks to pass
   - ✓ Require branches to be up to date before merging
   - ✓ Require conversation resolution before merging
   - Allowed merge methods: Merge commits
6. **Save**

### Step 6: Create Ruleset 4 — Hotfix Branches

**Via GitHub UI:**

1. **New ruleset** → **Name:** `Hotfix Branch Protection`
2. **Target:** Branches
3. **Include Patterns:** `hotfix/**`
4. **Bypass List:**
   - Teams: `crego-release-managers`, `crego-leads`
5. **Rules:**
   - ✓ Restrict creations (allow bypass for `crego-release-managers`, `crego-leads`)
   - ✓ Restrict deletions (allow bypass for `crego-release-managers`)
   - ✓ Block force pushes (no bypass)
   - ✓ Require a pull request before merging
     - Require approvals: 2 (NO BYPASS)
     - Dismiss stale reviews: Yes
     - Require review from code owners: Yes
   - ✓ Require status checks to pass
   - ✓ Require branches to be up to date before merging
   - ✓ Require conversation resolution before merging
   - Allowed merge methods: Merge commits
6. **Save**

### Step 7: Create Ruleset 5 — Feature & Bugfix Branches

**Via GitHub UI:**

1. **New ruleset** → **Name:** `Feature/Bugfix Branch Protection`
2. **Target:** Branches
3. **Include Patterns:** `feature/**`, `bugfix/**`
4. **Bypass List:** (empty — no org-level restrictions)
5. **Rules:**
   - ☐ Restrict creations (unchecked)
   - ☐ Restrict deletions (unchecked, or allow author + `crego-leads` if you want to enforce cleanup)
   - ✓ Block force pushes (allow for all developers implicitly)
   - ☐ Require a pull request before merging (unchecked — these are working branches)
6. **Save**

**Note:** PRs targeting `develop` will still require Ruleset 2 approval.

### Step 8: Create Ruleset 6 — Tags (CRITICAL)

**Via GitHub UI:**

1. **New ruleset** → **Name:** `Production Tag Protection`
2. **Target:** Tags
3. **Include Patterns:** `v*` (fnmatch pattern for semver tags)
4. **Bypass List:**
   - Teams: `crego-release-managers` (creation/deletion only, no updates)
5. **Rules:**
   - ✓ Restrict creations (allow bypass for `crego-release-managers`)
   - ✓ Restrict deletions (allow bypass for `crego-release-managers`)
   - ✓ Restrict updates (no bypass — tags are immutable)
6. **Save**

### Step 9: Create Ruleset 7 — Infrastructure Branches (crego-infra only)

**Via GitHub UI:**

1. **New ruleset** → **Name:** `Infrastructure Environment Branches`
2. **Target:** Branches
3. **Include Patterns:** `env/**`, `clients/**`
4. **Repository Specific?** YES — Apply only to `crego-infra`
5. **Bypass List:**
   - Teams: `crego-release-managers`
6. **Rules:**
   - ✓ Restrict creations (allow bypass for `crego-release-managers`)
   - ✓ Restrict deletions (allow bypass for `crego-release-managers`)
   - ✓ Block force pushes:
     - For `env/prod`: Allow bypass for `crego-release-managers` (rollback scenario)
     - For other patterns: No bypass
   - ✓ Require a pull request before merging
     - Require approvals: 2
     - Dismiss stale reviews: Yes
     - Require review from code owners: Yes
   - ✓ Require status checks to pass
   - ✓ Require branches to be up to date before merging
   - ✓ Require conversation resolution before merging
   - Allowed merge methods: Merge commits
7. **Save**

### Step 10: Create Ruleset 8 — Naming Convention (Optional but Recommended)

**Via GitHub UI:**

Using GitHub Actions for enforcement (recommended):

1. In each repository, create `.github/workflows/validate-branch-name.yml`:

```yaml
name: Validate Branch Name

on:
  push:
    branches:
      - '**'

jobs:
  validate:
    runs-on: ubuntu-latest
    if: github.event_name == 'push'
    steps:
      - name: Check branch name format
        run: |
          BRANCH=${{ github.ref_name }}
          VALID=false

          # Allowed patterns
          [[ "$BRANCH" =~ ^feature/cre- ]] && VALID=true
          [[ "$BRANCH" =~ ^bugfix/cre- ]] && VALID=true
          [[ "$BRANCH" =~ ^hotfix/cre- ]] && VALID=true
          [[ "$BRANCH" =~ ^release/v ]] && VALID=true
          [[ "$BRANCH" =~ ^env/ ]] && VALID=true
          [[ "$BRANCH" =~ ^clients/ ]] && VALID=true
          [[ "$BRANCH" == "develop" ]] && VALID=true
          [[ "$BRANCH" == "master" ]] && VALID=true
          [[ "$BRANCH" == "main" ]] && VALID=true

          if [ "$VALID" = false ]; then
            echo "❌ Invalid branch name: $BRANCH"
            echo ""
            echo "Allowed patterns:"
            echo "  - feature/cre-xxx (feature work)"
            echo "  - bugfix/cre-xxx (bug fixes)"
            echo "  - hotfix/cre-xxx (production hotfixes)"
            echo "  - release/vX.Y.Z (release branches)"
            echo "  - env/* (infra environments, crego-infra only)"
            echo "  - clients/* (client-specific, crego-infra only)"
            echo "  - develop (integration branch)"
            echo "  - master/main (production branches)"
            exit 1
          fi

          echo "✓ Branch name is valid: $BRANCH"
```

2. Commit and push the workflow to each repo

**Also enable pre-push hooks locally:**

In each repository, create `.githooks/pre-push`:

```bash
#!/bin/bash
# .githooks/pre-push — Local validation before push

BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Allowed patterns
if [[ ! $BRANCH =~ ^(feature|bugfix|hotfix|release|env|clients|develop|master|main)/ && \
      "$BRANCH" != "develop" && \
      "$BRANCH" != "master" && \
      "$BRANCH" != "main" ]]; then
  echo "❌ Invalid branch name: $BRANCH"
  echo ""
  echo "Allowed patterns:"
  echo "  feature/cre-xxx  - Feature branches"
  echo "  bugfix/cre-xxx   - Bug fix branches"
  echo "  hotfix/cre-xxx   - Production hotfixes"
  echo "  release/vX.Y.Z   - Release branches"
  echo "  develop          - Integration branch"
  echo "  master/main      - Production branches"
  exit 1
fi

exit 0
```

Make it executable:

```bash
chmod +x .githooks/pre-push
```

Instruct developers to enable hooks:

```bash
git config core.hooksPath .githooks
```

### Step 11: Add CODEOWNERS Files

1. In each repository, create `.github/CODEOWNERS` (see [CODEOWNERS Configuration](#codeowners-configuration))
2. Commit and push to each repo
3. GitHub will automatically suggest these owners as reviewers

### Step 12: Audit & Testing

1. Test each ruleset:
   - Attempt to push directly to `develop` → should be blocked
   - Attempt to create a tag without being in `crego-release-managers` → should be blocked
   - Attempt to force-push to `master`/`main` → should be blocked
   - Verify PRs require correct number of approvals before merge
2. Document any failures and adjust rulesets as needed
3. Send summary to team with new policies

---

## Implementation via Terraform (Optional)

If your organization uses Infrastructure as Code, you can define rulesets in Terraform.

### Example: Terraform Configuration (crego-infra repo)

**File:** `terraform/github_rulesets.tf`

```hcl
terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "github" {
  owner = "crego-tech"
}

# Team references (must exist in organization)
data "github_team" "release_managers" {
  slug = "crego-release-managers"
}

data "github_team" "leads" {
  slug = "crego-leads"
}

# Ruleset 1: Production Branches
resource "github_organization_ruleset" "production_branches" {
  name        = "Production Branch Protection (master/main)"
  target      = "branch"
  enforcement = "active"

  bypass_actors {
    type = "Team"
    actor_id = data.github_team.release_managers.node_id
  }

  conditions {
    ref_name {
      include = ["master", "main"]
    }
  }

  rules {
    branch_name_pattern {
      operator = "starts_with"
      pattern  = ""  # No pattern enforcement at ruleset level
    }

    creation {
      restricted = true
    }

    deletion {
      restricted = true
    }

    force {
      allow_force_pushes {
        dismissal_restrictions = false
      }
    }

    pull_request {
      require_code_review {
        require_last_push_approval = true
        required_approving_review_count = 2
        dismiss_stale_reviews_on_push = true
        require_review_from_code_owners = true
      }
      require_status_checks_before_merge {
        strict_required_status_checks_policy = true
        required_status_checks = [
          "build",
          "test",
          "lint"
        ]
      }
      require_conversation_resolution = true
    }

    merge_queue {
      merge_method = "merge"
    }
  }
}

# Ruleset 2: Develop Branch
resource "github_organization_ruleset" "develop_branch" {
  name        = "Develop Branch Protection"
  target      = "branch"
  enforcement = "active"

  bypass_actors {
    type = "Team"
    actor_id = data.github_team.leads.node_id
  }

  conditions {
    ref_name {
      include = ["develop"]
    }
  }

  rules {
    creation {
      restricted = true
    }

    deletion {
      restricted = true
    }

    force {
      allow_force_pushes {
        dismissal_restrictions = false
      }
    }

    pull_request {
      require_code_review {
        required_approving_review_count = 1
        dismiss_stale_reviews_on_push = true
        require_review_from_code_owners = true
      }
      require_status_checks_before_merge {
        strict_required_status_checks_policy = true
        required_status_checks = [
          "build",
          "test",
          "lint"
        ]
      }
      require_conversation_resolution = true
    }

    merge_queue {
      merge_method = "squash"
    }
  }
}

# Ruleset 6: Tags (CRITICAL)
resource "github_organization_ruleset" "production_tags" {
  name        = "Production Tag Protection"
  target      = "tag"
  enforcement = "active"

  bypass_actors {
    type = "Team"
    actor_id = data.github_team.release_managers.node_id
  }

  conditions {
    ref_name {
      include = ["v*"]  # All semver tags
    }
  }

  rules {
    creation {
      restricted = true
    }

    deletion {
      restricted = true
    }

    tag_name_pattern {
      operator = "starts_with"
      pattern  = "v"  # Enforce v* pattern
    }
  }
}

# Output for verification
output "rulesets" {
  value = {
    production_branches = github_organization_ruleset.production_branches.name
    develop_branch      = github_organization_ruleset.develop_branch.name
    production_tags     = github_organization_ruleset.production_tags.name
  }
}
```

**Apply with Terraform:**

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

**Advantages:**
- Version-controlled ruleset configuration
- Can be reviewed in pull requests
- Consistent across environments
- Easy to replicate in new GitHub orgs

---

## Audit & Compliance

### Review Ruleset Enforcement

**Via GitHub UI:**

1. Go to **Organization Settings** → **Rules**
2. For each ruleset, click to view:
   - Number of bypass uses per team
   - Recent enforcement actions
   - Exceptions granted

### Monitor Bypass Usage

Regularly audit which team members used bypass permissions:

**Via GitHub CLI:**

```bash
# List recent ruleset enforcement
gh api /orgs/crego-tech/rulesets \
  --method GET \
  -f per_page=100 | jq '.[] | {name, enforcement}'

# Check specific repo for violations
gh api /repos/crego-tech/crego-web/rulesets \
  --method GET | jq '.[] | select(.target == "branch") | {name, enforcement}'
```

### Audit Log Review

**Via GitHub Enterprise Audit Log (if available):**

1. Go to **Organization Settings** → **Audit Log**
2. Filter for:
   - Action: `rulesets.create`, `rulesets.update`, `rulesets.delete`
   - Action: `bypass` (for bypass permissions used)
3. Review monthly for anomalies

### Quarterly Compliance Review

Every quarter, review:

- [ ] All ruleset configurations still appropriate
- [ ] No unauthorized bypasses were granted
- [ ] Team membership is current (no orphaned access)
- [ ] CODEOWNERS files reflect current team structure
- [ ] Zero direct pushes to production branches
- [ ] All production deploys traced to an approved tag

**Report to:** CTO, Engineering Manager, Compliance Officer

---

## Decision Points & Notes

### 1. Develop Branch Approvals: 1 or 2?

**Current Policy:** 1 approval

**Rationale:**
- Develop deploys to internal dev environment (lower risk than production)
- Faster development velocity needed for team
- Automated tests provide first-line defense
- PR author still needs another human to review

**Alternative (2 approvals):**
- More conservative, better for larger teams
- Slows down development cycles
- May be warranted if project scales beyond current 12-person team

**Recommendation:** Start with 1 approval. Escalate to 2 if merges to develop cause frequent dev environment issues.

### 2. Force Push Exception for env/prod

**Current Policy:** Allow crego-release-managers to force-push to `env/prod` for rollback

**Rationale:**
- Emergency rollbacks should not require new PR
- Rollback procedure: `git revert` the bad commit and force-push
- Limited to crego-release-managers only
- Audit trail still logs the force-push

**Risk:** Accidental rollback to wrong commit

**Mitigation:**
- Require oncall review before executing rollback
- Document rollback procedure in runbooks
- Test rollback procedure quarterly

### 3. Release Candidate Tags

**Current Policy:** Optional; recommended for multi-day UAT windows

**Tag Pattern:** `vX.Y.Z-rc.1`, `vX.Y.Z-rc.2`, etc.

**When to Use:**
- Release branch cut for UAT → tag as `vX.Y.Z-rc.1`
- Critical fix during UAT → tag as `vX.Y.Z-rc.2`
- Go-live → tag as `vX.Y.Z` (final release)

**Why Optional:**
- For small/quick releases, skip RCs and go straight to `vX.Y.Z`
- For multi-week UAT, RCs help track progress

**Recommendation:** Use RCs for releases > 3 days in UAT.

### 4. Client-Specific Release Branches

**Current Policy:** Supported via `release/vX.Y.Z-clientname` branches

**Example:**
- Main release: `release/v2.5.0` (merged to master, tagged as `v2.5.0`)
- Client override: `release/v2.5.0-acmecorp` (merged to master, tagged as `v2.5.0-acmecorp`)

**When to Use:**
- Client has custom features not ready for public release
- Client needs bug fix not in main release
- Multi-tenant architecture where feature flags control features

**Ruleset Coverage:** Same as `release/**` (Ruleset 3)

### 5. Feature/Bugfix Branch Force Pushes

**Current Policy:** Allowed (developers can rebase own branches)

**Rationale:**
- Developers often rebase before merging to keep history clean
- Branch is personal; should not restrict developer workflow

**Risk:** Accidental rebase of merged commit

**Mitigation:** GitHub warns when force-pushing to branch with PR

**Alternative:** Disable force-push entirely (more restrictive, slows some workflows)

### 6. Naming Convention Enforcement

**Current Implementation:** Pre-push hooks + GitHub Actions workflow

**Why Two Methods:**
- **Pre-push hooks:** Instant local feedback (before push attempt)
- **GitHub Actions:** Catch issues if developer bypasses hooks (git -f)

**Not Enforced by Ruleset:** GitHub Rulesets cannot natively validate naming patterns. Use hooks + Actions instead.

**Maintenance:** Update `.githooks/pre-push` and `.github/workflows/validate-branch-name.yml` if patterns change.

### 7. Code Owners Review Requirement

**Current Policy:** Enabled for all protected branches

**CODEOWNERS Scope:**
- Each repo has own `.github/CODEOWNERS` file
- Teams (not individuals) listed to avoid single-person bottleneck
- Example: `project/ @crego-tech/crego-be-lead` (one person on team)

**Impact:** PR cannot merge without approval from someone on code owner team

**Alternative:** Disable for develop (faster velocity)

**Recommendation:** Keep enabled. Ensures domain experts review changes.

---

## Troubleshooting & Common Issues

### Issue: Developer Cannot Merge PR to develop

**Possible Causes:**

1. **PR has only 1 approval, but ruleset requires 2**
   - Verify Ruleset 2 is set to 1 approval, not 2
   - Current policy: 1 approval for develop

2. **Approval is from PR author (self-review)**
   - GitHub blocks self-approvals
   - Need approval from different team member
   - Solution: Ask someone else to review and approve

3. **Status checks failing (CI/tests)**
   - PR cannot merge until CI passes
   - Check GitHub Actions logs for failure reason
   - Fix code and re-run CI

4. **Conversation not resolved**
   - Developer requested changes or left comments
   - All comments must be marked as "resolved" before merge
   - Solution: Address comments and mark resolved

5. **Branch out of date with base**
   - Develop may have progressed since PR creation
   - GitHub requires branch to be up-to-date before merge
   - Solution: Click "Update branch" button or rebase locally

**Resolution Steps:**

```bash
# Check PR status
gh pr checks <PR-number>

# Re-run failed checks
gh pr checks <PR-number> --watch

# Update branch with latest develop
git fetch origin develop
git rebase origin/develop
git push -f origin feature/cre-xxx
```

### Issue: Cannot Create Release Branch

**Possible Causes:**

1. **Only crego-release-managers can create `release/**` branches**
   - Contact Engg Manager or CTO to cut release branch
   - Not a policy you can bypass

2. **Incorrect branch name format**
   - Must follow: `release/vX.Y.Z` (e.g., `release/v2.5.1`)
   - Pre-push hook will reject incorrect names

**Resolution:**

```bash
# Contact release manager
# Ask them to run:
git checkout develop
git pull origin develop
git checkout -b release/v2.5.1
git push -u origin release/v2.5.1
```

### Issue: Cannot Delete Feature Branch

**Possible Causes:**

1. **GitHub UI shows "Not allowed"**
   - Feature branch may be protected if you're not the author
   - crego-leads can delete any feature branch

2. **Branch has open PR**
   - Close or merge PR before deleting branch

**Resolution:**

```bash
# Delete locally then push deletion
git branch -d feature/cre-xxx
git push origin --delete feature/cre-xxx

# Or ask crego-leads to delete
# (if you're not the author)
```

### Issue: Production Tag Created by Unauthorized Person

**Severity:** CRITICAL — Production deployment may be unauthorized

**Response:**

1. **Immediate:** Check tag contents and associated commit

   ```bash
   git show v2.5.0  # Review commit
   git tag -v v2.5.0  # Check GPG signature (if enabled)
   ```

2. **If unauthorized:**

   ```bash
   # Delete tag immediately (crego-release-managers only)
   git push origin --delete v2.5.0
   ```

3. **Investigate:**
   - Check GitHub Audit Log: who created the tag?
   - Check if they're actually in crego-release-managers team
   - If not, remove them and review team membership

4. **Prevent future:**
   - Enable GPG signing for tags
   - Enable branch protection audit logging
   - Weekly review of tag creation

---

## FAQ

### Q: Can I merge my own PR to develop?

**A:** No. GitHub prevents self-approval. Your PR needs approval from someone else on the team. This prevents code from reaching production without peer review.

### Q: What if we need to deploy an emergency hotfix?

**A:**

1. Create `hotfix/cre-xxx` branch from `master`/`main`
2. Push to GitHub
3. Create PR targeting `master`/`main`
4. Get 2 approvals (expedited, but still required)
5. Merge and tag as `vX.Y.Z`
6. Also create PR targeting `develop` and merge there too

The "emergency" speed is in review time (leads can prioritize), not in skipping reviews.

### Q: Can we disable status checks for a PR?

**A:** No. CI/tests must pass before merge. This prevents broken code from reaching any branch. If CI is slow, optimize it rather than disabling it.

### Q: What's the difference between merge commit and squash merge?

**A:**

- **Merge commit:** Preserves all commits from the PR. Used for release/hotfix branches to keep full history.
- **Squash merge:** Combines all PR commits into one. Used for develop to keep history clean.

### Q: Can I rebase instead of merge?

**A:** Not via GitHub UI. GitHub rulesets restrict merge methods to "Merge commit" and "Squash & merge". If you need rebase, do it locally and force-push (allowed on feature branches).

### Q: How do I become a code owner?

**A:** Ask the team lead (FE Lead or BE Lead). They update `.github/CODEOWNERS` file. Code owners are assigned to teams, not individuals, to distribute responsibility.

### Q: What if a ruleset blocks something legitimate?

**A:**

1. **If you're in crego-leads:** You may have bypass permission (e.g., for hotfix creation)
2. **If you're not:** Request bypass from crego-leads via Slack/email
3. **If bypass is needed regularly:** Propose ruleset change to CTO

All requests are logged in GitHub Audit Log.

### Q: Can we disable a ruleset?

**A:** Yes, but not recommended. Rulesets enforce critical policies. If one is too strict, modify it rather than disable. Report to CTO.

---

## Related Documents

- [git-strategy.md](./git-strategy.md) — Branch naming and Git workflow
- [team-release-playbook.md](../release-management/team-release-playbook.md) — Release process and roles
- [crego-infra/CONTRIBUTING.md](../../crego-infra/CONTRIBUTING.md) — Infrastructure contribution guide
- GitHub Rulesets Documentation: https://docs.github.com/en/organizations/managing-organization-settings/managing-rulesets-for-repositories-in-your-organization

---

## Change Log

| Date | Change | Author |
|---|---|---|
| 2026-02-16 | Initial document creation | Crego Engineering |
| | Defined 8 rulesets (production, develop, release, hotfix, feature, tags, infra, wildcard) | |
| | Configured GitHub teams and bypass permissions | |
| | Added CODEOWNERS examples and implementation steps | |
| | Added troubleshooting and FAQ | |

---

**Document Owner:** CTO, Engineering Manager
**Last Reviewed:** 2026-02-16
**Next Review:** 2026-05-16 (quarterly)
