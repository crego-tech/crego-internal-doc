# Crego Release Playbook

**Generic Release Process**
*For use by: Release Manager / Engineering Lead*

| | |
|---|---|
| **Repos** | crego-omni, crego-web, crego-flow |
| **Infra** | crego-infra (ArgoCD GitOps — separate process) |
| **Prod Branch** | `master` (omni, flow) / `main` (web) |

---

## CI/CD Deployment Reference

Understand how each git event triggers a deployment. This is the foundation for every step below.

| Git Event | Environment | Target | Status |
|---|---|---|---|
| Push to `develop` | Internal Dev | dev-gcp | ✅ All repos |
| Push to `release/**` | Pre-Production | preprod-gcp | ✅ All repos |
| Push tag `v*` | Production | prod-gcp | ✅ All repos |
| Push to `master`/`main` | Production | prod-gcp | ⚠ omni only |
| `workflow_dispatch` | Any (manual) | Configurable | ✅ Fallback |

> **⚠️ WARNING:** Always use tag-based deployment (`v*`) for production. It is the only trigger that works reliably across all repos.

---

## Step 1 — Merge Production → develop (Fix Merge-Back Gap)

> **⛔ DANGER:** MANDATORY before every release cut. If production has commits not in develop, the release branch will be missing those fixes and you will ship regressions.

### 1a. Check the merge-back gap

Run these commands to see if production has commits that develop is missing:

```bash
cd crego-omni
git fetch origin
echo "gap: $(git log origin/develop..origin/master --oneline | wc -l)"
```

```bash
cd crego-web
git fetch origin
echo "gap: $(git log origin/develop..origin/main --oneline | wc -l)"
```

```bash
cd crego-flow
git fetch origin
echo "gap: $(git log origin/develop..origin/master --oneline | wc -l)"
```

If all print **gap: 0**, skip to Step 2. Otherwise, continue below.

### 1b. Merge back (per repo with gap > 0)

Replace `{PROD_BRANCH}` with `master` (omni, flow) or `main` (web). Replace `{TAG}` with the current prod tag.

```bash
git checkout develop
git pull origin develop
git fetch origin {PROD_BRANCH}
git merge origin/{PROD_BRANCH} --no-ff -m "chore: merge {PROD_BRANCH} back to develop (post {TAG} sync)"
```

If conflicts arise, resolve them, then:

```bash
git add .
git commit
git push origin develop
```

If no conflicts:

```bash
git push origin develop
```

### 1c. Verify

- Wait for CI to pass on develop for all repos
- Re-run the gap check commands — all must print 0

---

## Step 2 — Cut Release Branches

Replace `{VERSION}` with the target version (e.g. v2.4.0). Run for each repo:

```bash
cd {REPO}
git checkout develop
git pull origin develop
git checkout -b release/{VERSION}
git push origin release/{VERSION}
```

> **ℹ️ INFO:** Pushing a `release/**` branch auto-deploys to preprod-gcp via CI/CD.

### Verify pre-prod deployments

- [ ] crego-omni: GitHub Actions green for release/{VERSION}
- [ ] crego-web: GitHub Actions green for release/{VERSION}
- [ ] crego-flow: GitHub Actions green for release/{VERSION}
- [ ] Smoke test pre-prod environment — services are up and responding

After the cut, **develop is now open** for next-version work. New features can be merged to develop immediately.

---

## Step 3 — Pre-Production Testing & Bug Fixes

QA team runs full regression on pre-prod. If bugs are found during testing:

```bash
cd {REPO}
git checkout release/{VERSION}
git pull origin release/{VERSION}
git checkout -b bugfix/cre-XXXX-description
# ... fix, commit, push ...
# Open PR targeting release/{VERSION} (NOT develop)
```

> **⚠️ WARNING:** Bugfixes go to the release branch, NOT develop. They will be carried back to develop via the merge-back in Step 6.

### Testing checklist

- [ ] Full regression on pre-prod
- [ ] Client-specific UAT (if applicable)
- [ ] VAPT verification (if security fixes included)
- [ ] Critical flows: login, loan creation, payments, GL posting, reports, flow execution

---

## Step 4 — UAT Sign-Off

Get formal UAT approval from stakeholders and/or client teams before proceeding to production deployment.

- [ ] Internal QA sign-off received
- [ ] Client UAT sign-off received (if client-specific release)
- [ ] No open release-blocker issues in Linear

> **⛔ DANGER:** Do NOT proceed to Step 5 without explicit sign-off. Once code hits production, rollback is costly.

---

## Step 5 — Merge to Production & Tag

Deploy **one repo at a time**. Verify each deployment is green before moving to the next repo.

### 5a. crego-omni

```bash
cd crego-omni
git checkout master
git pull origin master
git merge release/{VERSION} --no-ff -m "release: {VERSION}"
git push origin master
```

Then tag:

```bash
git tag -a {VERSION} -m "Release {VERSION}"
git push origin {VERSION}
```

→ Tag triggers **prod-gcp** deployment. Wait for GitHub Actions to go green.

### 5b. crego-web

```bash
cd crego-web
git checkout main
git pull origin main
git merge release/{VERSION} --no-ff -m "release: {VERSION}"
git push origin main
```

Then tag:

```bash
git tag -a {VERSION} -m "Release {VERSION}"
git push origin {VERSION}
```

→ Tag triggers **prod-gcp** deployment. Wait for GitHub Actions to go green.

### 5c. crego-flow

```bash
cd crego-flow
git checkout master
git pull origin master
git merge release/{VERSION} --no-ff -m "release: {VERSION}"
git push origin master
```

Then tag:

```bash
git tag -a {VERSION} -m "Release {VERSION}"
git push origin {VERSION}
```

→ Tag triggers **prod-gcp** deployment. Wait for GitHub Actions to go green.

### 5d. Production smoke test

- [ ] All three GitHub Actions deployments are green
- [ ] Login works (staff + customer)
- [ ] Loan creation & disbursement
- [ ] Payment / repayment flows
- [ ] GL posting batch runs
- [ ] Flow runner execution
- [ ] Report download works

---

## Step 6 — Post-Release Merge-Back to develop

> **⛔ DANGER:** DO NOT SKIP THIS STEP. Skipping causes a merge-back gap where production fixes are missing from develop. This was the root cause of regressions in past releases.

### 6a. crego-omni

```bash
cd crego-omni
git checkout develop
git pull origin develop
git merge master --no-ff -m "chore: merge master back to develop (post {VERSION} release)"
git push origin develop
```

### 6b. crego-web

```bash
cd crego-web
git checkout develop
git pull origin develop
git merge main --no-ff -m "chore: merge main back to develop (post {VERSION} release)"
git push origin develop
```

### 6c. crego-flow

```bash
cd crego-flow
git checkout develop
git pull origin develop
git merge master --no-ff -m "chore: merge master back to develop (post {VERSION} release)"
git push origin develop
```

### 6d. Verify zero gap

```bash
cd crego-omni && git fetch origin && echo "gap: $(git log origin/develop..origin/master --oneline | wc -l)"
cd crego-web && git fetch origin && echo "gap: $(git log origin/develop..origin/main --oneline | wc -l)"
cd crego-flow && git fetch origin && echo "gap: $(git log origin/develop..origin/master --oneline | wc -l)"
```

All must print **0**.

---

## Step 7 — Cleanup & Linear Updates

### 7a. Delete release branches

Run for each repo:

```bash
git branch -d release/{VERSION}
git push origin --delete release/{VERSION}
```

### 7b. Verify tags exist

```bash
cd crego-omni && git tag -l "{VERSION}"
cd crego-web && git tag -l "{VERSION}"
cd crego-flow && git tag -l "{VERSION}"
```

All three should print the version tag.

### 7c. Linear — Move issues to Released

1. Go to Tech team view
2. Filter by state = "Pending Release"
3. Select all issues (Cmd+A)
4. Bulk action → Change state → "Released"
5. Bulk action → Add label → `release/{VERSION}` label

> **⚠️ WARNING:** Only move issues that were included in the release branch. Issues still in QA/UAT should remain in their current state.

### 7d. Generate release notes

- Generate internal release notes (full technical detail)
- Generate client-specific release notes (per client)
- Save to `crego-internal-docs/release-management/release-notes/{VERSION}/`

### 7e. Notify stakeholders

- Post in Slack #releases channel
- Tag PM, QA lead, and client account managers
- Share client-specific release notes with respective client teams

---

## Post-Release Verification Checklist

Complete every item before considering the release done.

| # | Check | Owner |
|---|---|---|
| 1 | All three repos tagged {VERSION} | Release Manager |
| 2 | All prod deployments green in GitHub Actions | DevOps |
| 3 | Production smoke test passed | QA Lead |
| 4 | master/main → develop merge-back done (gap = 0) | Release Manager |
| 5 | Release branches deleted from all repos | Release Manager |
| 6 | Linear issues moved to Released with version label | Release Manager |
| 7 | Release notes generated and saved to internal docs | Release Manager |
| 8 | Stakeholders notified via Slack | Release Manager |
| 9 | Client-specific release notes shared | Account Managers |

---

## Appendix: Hotfix Process

For emergency production fixes between releases:

```bash
# 1. Branch from production
cd {REPO}
git checkout {PROD_BRANCH}
git pull origin {PROD_BRANCH}
git checkout -b hotfix/cre-XXXX-description
```

```bash
# 2. Fix, commit, push, open PR to {PROD_BRANCH}
```

```bash
# 3. After merge, tag the hotfix
git tag -a {VERSION}-hotfix.1 -m "Hotfix: {description}"
git push origin {VERSION}-hotfix.1
```

```bash
# 4. IMMEDIATELY merge back to develop
git checkout develop
git pull origin develop
git merge {PROD_BRANCH} --no-ff -m "chore: merge {PROD_BRANCH} back to develop (post hotfix)"
git push origin develop
```

> **⛔ DANGER:** The merge-back to develop after a hotfix is just as critical as after a release. Never skip it.

---

## Appendix: Client Release Process

Client releases deploy to client-specific AWS ECR instead of internal GCR. All client config is centralized in `crego-infra/config/clients.yaml`.

### Quick commands

```bash
# 1. Create client release branches (all repos)
./scripts/release-client.sh v2.5.0-bcpl branch

# 2. Build & push Docker images to client ECR (triggers Release Orchestrator)
./scripts/release-client.sh v2.5.0-bcpl build

# 3. After UAT passes, tag for production
./scripts/release-client.sh v2.5.0-bcpl tag

# Preview any action without executing
./scripts/release-client.sh v2.5.0-bcpl branch --dry-run
```

### How it works

1. **`branch`** — Creates `release/v2.5.0-bcpl` from develop in crego-omni, crego-flow, and crego-web (local git operations)
2. **`build`** — Triggers the Release Orchestrator workflow (`release-orchestrator.yaml` in crego-infra), which calls `client_release.yaml` in each repo. Each repo reads `clients.yaml` for AWS region, platform arch, endpoints, Sentry DSN, and deployment type — only client_name, env, and version are needed as inputs
3. **`tag`** — Creates the version tag in all repos, triggering production deployment

### Alternative: Release Orchestrator (GitHub Actions UI)

Instead of CLI, you can trigger the orchestrator directly:

```bash
# Cut branches across all repos
gh workflow run release-orchestrator.yaml --repo crego-tech/crego-infra \
  -f version=v2.5.0-bcpl -f action=cut -f dry_run=false

# Trigger client ECR builds
gh workflow run release-orchestrator.yaml --repo crego-tech/crego-infra \
  -f version=v2.5.0-bcpl -f action=client-build -f env=preprod -f dry_run=false

# Create ship PRs (release → production)
gh workflow run release-orchestrator.yaml --repo crego-tech/crego-infra \
  -f version=v2.5.0-bcpl -f action=ship -f dry_run=false
```

### Adding a new client

1. Add entry to `crego-infra/config/clients.yaml`
2. Ensure AWS OIDC role exists for the client
3. Add Linear label: `client:<name>`
4. Add celery worker/beat to the appropriate environment overlays in crego-infra

### Deployment streams

| Repo | Services | Notes |
|---|---|---|
| crego-omni | omni-api, omni-worker, omni-schedule, omni-flower | 4 Docker images per release |
| crego-flow | flow-api, flow-worker | 2 Docker images per release |
| crego-web | omni-web, flow-web (or both) | S3 or ECR deployment, configurable per client |

> **Note:** crego-web deploys BOTH omni-web and flow-web. These are separate packages (`packages/omni-web/` and `packages/flow-web/`) that trigger independently based on path changes for internal releases, but both build during client releases.

---

## Appendix: Repository Quick Reference

| Repo | Prod Branch | Type | GitHub Actions URL |
|---|---|---|---|
| crego-omni | `master` | Backend API (Django) | crego-tech/crego-omni/actions |
| crego-web | `main` | Frontend Monorepo (React) | crego-tech/crego-web/actions |
| crego-flow | `master` | Flow Engine API (Django) | crego-tech/crego-flow/actions |
| crego-infra | `main` | ArgoCD GitOps (separate) | crego-tech/crego-infra/actions |
