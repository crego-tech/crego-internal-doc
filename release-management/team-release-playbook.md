# Team Release Playbook

> **Audience:** Every developer, QA engineer, and engineering lead on the team.
> **Purpose:** Your day-to-day guide for how work flows from idea to production. If you're unsure what to do next, check this document.

---

## How Work Flows (The Big Picture)

```
 YOU ARE HERE
     ↓
┌─────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ Linear  │───→│ develop  │───→│ release/ │───→│ master   │───→│ Tag      │
│ Issue   │    │ branch   │    │ v1.2.3   │    │ branch   │    │ v1.2.3   │
└─────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
     │              │               │               │               │
  Create         Deploys to      Deploys to      Merge here      Push tag
  branch         INTERNAL DEV    PRE-PROD        after UAT       → PROD
  from here                      (testing)       approval        deployment
```

For client releases, the same flow applies but with `release/v1.2.3-clientname` and tag `v1.2.3-clientname`.

---

## For Developers

### Starting New Work

1. **Pick an issue** from the current Linear cycle that is in "Todo" state (PM should have already filled in requirements in the "Requirement" stage).
2. **Move it to "Development"** in Linear.
3. **Copy the branch name** from Linear (click the issue → look for the branch name icon near the top).
4. **Create your branch from `develop`:**
   ```bash
   git checkout develop
   git pull origin develop
   git checkout -b <paste-branch-name-from-linear>
   ```
5. **Do your work.** Commit often with clear messages. Reference the Linear issue ID in commits when relevant (e.g., `CRE-123: add validation for email field`).

### Opening a Pull Request

1. **Push your branch** to GitHub.
2. **Open a PR targeting `develop`**.
3. **PR title format:** `CRE-123: Short description of what this does`
   - The `CRE-123` prefix is mandatory. It links the PR to Linear automatically.
4. **Fill out the PR template** (each repo has one — follow it).
5. **Request a reviewer.** Don't merge your own PRs.
6. Linear will automatically move your issue to **"PR Review"**.
   - **Ownership transfers to the reviewer** at this point. The reviewer is responsible for completing the review within 1 business day.
   - If changes are requested, ownership returns to you (the PR author) until you address the feedback and re-request review.
   - If a review is stuck for 2+ days, escalate to the Engg Manager.

### After Your PR is Merged

Once merged to `develop`:
- Your code auto-deploys to the **internal dev environment**.
- Linear moves the issue to **"QA"**.
- **Ownership transfers to QA** at this point. QA is responsible for picking it up and testing within 1 business day.
- **Your responsibility before handoff:** Make sure the issue has clear acceptance criteria and any testing notes QA will need. If QA can't test without extra context, that's on you.
- **You're not done yet.** The issue stays open until it passes QA and ships to prod.
- If QA passes the issue, it moves to **"Pending UAT"** — the Release Manager takes over from here to coordinate UAT scheduling.
- If QA finds a bug in your work, they'll comment on your Linear issue. Fix it with a new PR to `develop`. QA will move the issue back to **"Development"**.

### Things You Must Never Do

- Never push directly to `develop` or `master`. Always use a PR.
- Never merge a PR without at least one approval.
- Never merge to a `release/*` branch without lead/QA approval.
- Never delete the `develop` or `master` branch.
- Never force-push to any shared branch.

---

## For QA Engineers

### Testing on Dev Environment

When an issue moves to **"QA"**, it's on the internal dev environment and ready for testing. **You (QA) own the issue at this point** — pick it up within 1 business day. If an issue sits in "QA" for 2+ days, the Engg Manager or release manager will follow up.

1. **Test against the acceptance criteria** listed in the issue.
2. **If it passes:** Move it to **"Pending UAT"**. The Release Manager will coordinate including it in the next release.
3. **If it fails:** Add a comment describing the failure, tag the developer, add the `found-in:dev` label, and move the issue back to **"Development"**.

### Testing on Pre-prod (Release Branch)

When a release branch (`release/v1.2.3`) is cut and deployed to pre-prod:

1. **Issues included in the release** will be moved from **"Pending UAT"** to **"UAT"** by the release manager when the release branch is cut.
2. **Test the full release** on the pre-prod environment, not just individual issues.
3. **Focus on:**
   - Regression testing (did anything break that was working before?)
   - Integration testing (do all the new features work together?)
   - Edge cases not caught in dev
4. **If you find a bug:**
   - Create a new Linear issue with label `release-blocker` if it blocks the release. Add the `found-in:preprod` label to track that it was discovered on the pre-prod environment.
   - The fix goes to the release branch (not develop) via a PR targeting `release/v1.2.3`.
   - After it's fixed on the release branch, it must also be cherry-picked or merged back to `develop`. Flag it with the `needs-backport` label.

### UAT Sign-off

When the client or stakeholder does UAT:

1. Move issues to **"UAT"** state.
2. Track UAT feedback in Linear comments.
3. When UAT is approved, move issues to **"Pending Release"** and release manager proceeds with production deployment.
4. If UAT is rejected, work with the developer to fix issues on the release branch.

---

## The Release Process (Step by Step)

This section describes what happens during a release. It's primarily the release manager's responsibility, but everyone should understand it.

### Phase 1: Development (Ongoing)

- Developers work on features and bugs, merging to `develop`.
- Code auto-deploys to internal dev environment.
- QA tests on dev environment.
- QA-passed issues move to **"Pending UAT"** — Release Manager queues them for the next release.

### Phase 1.5: Cycle Close-out (Before Release Branch Cut)

At the end of the current cycle, before cutting the release branch:

1. **Identify incomplete issues:** Review all issues in the current cycle that have **not** reached "Pending Release" status (i.e., issues still in Triage, Backlog, Requirement, Todo, Development, PR Review, QA, or UAT).
2. **Label as delayed:** Add the `delayed` label to all such issues. This creates a historical record of what didn't make the release.
3. **Move to next cycle:** Move all delayed issues to the next cycle so they are automatically prioritized in the next sprint.
4. **Exclude archived/cancelled issues:** Skip any issues that are already archived or cancelled — they don't need the delayed label.
5. **Notify assignees:** The release manager should notify affected developers and QA engineers that their issues have been deferred to the next cycle.

> **Why this matters:** Tracking delayed issues prevents work from silently falling through the cracks between cycles. The `delayed` label lets you measure cycle predictability over time and identify recurring bottlenecks.

### Phase 2: Release Branch Cut (Weekly or as needed)

1. Release manager creates a release branch from `develop`:
   ```bash
   git checkout develop
   git pull origin develop
   git checkout -b release/v1.3.0
   git push origin release/v1.3.0
   ```
2. This triggers deployment to the **pre-prod** environment.
3. From this moment, `develop` is open for the next release's work. The release branch is **frozen** — only bug fixes go here.
4. All issues in **"Pending UAT"** for this release are moved to **"UAT"** in Linear.

### Phase 3: Pre-prod Testing and UAT

- QA tests the release on pre-prod.
- Bug fixes for the release go to the release branch (NOT develop).
- Any fix on the release branch must be backported to develop (use the `needs-backport` label).
- Client/stakeholder does UAT on pre-prod.

### Phase 4: Production Deployment

Once UAT is approved:

1. Merge the release branch to `master`:
   ```bash
   # On GitHub: Open PR from release/v1.3.0 → master
   # Get approval, merge (use merge commit, not squash)
   ```
2. Create and push a tag on `master`:
   ```bash
   git checkout master
   git pull origin master
   git tag v1.3.0
   git push origin v1.3.0
   ```
3. The tag push triggers the **production deployment**.
4. Move all issues from "Pending Release" to **"Released"** in Linear.

### Phase 5: Post-Release (DO NOT SKIP THIS)

1. **Merge master back to develop** to ensure any release-branch fixes are in develop:
   ```bash
   # On GitHub: Open PR from master → develop
   # Merge it
   ```
2. **Update `CLIENT_VERSIONS.md`** in crego-infra with the new version.
3. **Generate and share release notes.**
4. **Delete the release branch** from GitHub (it's served its purpose).

### Client-Specific Releases

**✨ Now Automated:** Client releases are automated across all service repos (crego-omni, crego-flow, crego-web) using a single script.

#### The Automated Flow

```
release-client.sh v1.3.0-acme branch
   ↓
Creates release/v1.3.0-acme in all repos
   ↓
Auto-triggers GitHub Actions workflows
   ↓
Builds & pushes images to client ECR paths
   ↓
Deploys to client pre-prod environment
   ↓
Client UAT on pre-prod
   ↓
release-client.sh v1.3.0-acme tag
   ↓
Creates v1.3.0-acme tag in all repos
   ↓
Auto-triggers production deployment
```

#### Creating a Client Release

**Step 1: Pre-prod Release (for Client UAT)**

From the `crego-infra` directory:

```bash
./scripts/release-client.sh v1.3.0-acme branch
```

What this does:
- Creates `release/v1.3.0-acme` branch from `develop` in all service repos
- Pushes branches to GitHub
- Auto-triggers workflows that:
  - Build Docker images with client-specific tags
  - Push to ECR: `crego/acme/preprod/{service}:v1.3.0-acme-{commit}`
  - Deploy to client-specific pre-prod environment

**Step 2: Verify Auto-Deployment**

1. Check GitHub Actions in all repos to verify workflows triggered successfully
2. Monitor deployment status in client pre-prod environment
3. Verify all services (omni-api, omni-worker, flow-api, flow-worker, omni-web) are running

**Step 3: Client UAT**

1. Coordinate with client stakeholders for UAT testing
2. Client tests on their pre-prod environment
3. Address any issues found:
   - Fix bugs with PRs to `release/v1.3.0-acme` branches
   - Changes auto-redeploy to client pre-prod
   - Re-test until UAT passes

**Step 4: Production Release (After UAT Approval)**

Once UAT passes and client approves:

```bash
./scripts/release-client.sh v1.3.0-acme tag
```

What this does:
- Creates `v1.3.0-acme` tag from `release/v1.3.0-acme` branch in all repos
- Pushes tags to GitHub
- Auto-triggers workflows that:
  - Build production images
  - Push to ECR: `crego/acme/prod/{service}:v1.3.0-acme-{commit}`
  - Deploy to client-specific production environments

**Step 5: Post-Release**

1. Update `CLIENT_VERSIONS.md` in crego-infra with the new version
2. Merge release branches back to develop if needed
3. Monitor client production deployment
4. Generate and share release notes with client

#### Script Options

**Dry Run (Preview Changes):**

```bash
./scripts/release-client.sh v1.3.0-acme branch --dry-run
```

This shows what would happen without making any changes. Use this to:
- Verify version format is correct
- Check that client name is extracted properly
- Preview branch/tag creation without executing

#### Troubleshooting

**Workflow didn't trigger:**
- Verify branch/tag was created: `git ls-remote --heads origin release/v1.3.0-acme`
- Check GitHub Actions tab in each repo for workflow runs
- Verify branch/tag naming follows pattern: `release/v{X}.{Y}.{Z}-{client}` or `v{X}.{Y}.{Z}-{client}`

**Build failed in one repo:**
- Check GitHub Actions logs for the failing repo
- Fix the issue in that repo's release branch
- Workflow will auto-retry on next push to branch

**Need to fix client-specific code:**
- Create PR targeting `release/v1.3.0-acme` branch
- After merge, workflow auto-redeploys to client environment
- Don't forget to backport fixes to `develop` if needed (add `needs-backport` label)

#### Manual Workflow Override (If Needed)

If automation fails or you need custom deployment:

1. Go to GitHub Actions in the specific repo
2. Find "Client Release" workflow
3. Click "Run workflow"
4. Fill in:
   - Client name: `acme`
   - Environment: `preprod` or `prod`
   - Version: `v1.3.0-acme`
   - (Other optional fields use defaults)
5. Click "Run workflow"

This maintains backward compatibility with manual triggers.

---

## Hotfix Process (Emergency Fixes)

When production is broken and you can't wait for the next release:

```
master (broken)
   ↓
hotfix/CRE-456-fix-crash  ← branch from master
   ↓                ↓
master             develop  ← merge fix to BOTH
   ↓
tag v1.3.1         ← patch bump, deploy immediately
```

1. Create a Linear issue: type `hotfix`, priority `Urgent`, label `found-in:prod`.
2. Branch from `master` (not develop).
3. Fix the issue. Open PR to `master`.
4. Get expedited review (2 reviewers required — don't skip review even in emergencies).
5. Merge to `master`. Tag as a patch version (e.g., `v1.3.1`). Push tag.
6. Immediately open a PR to merge the fix into `develop` too.
7. If a release branch is open, cherry-pick the fix there as well.

---

## Quick Reference

For detailed reference tables (workflow states, labels, priorities, branch naming), see the [Release Process Setup Guide](release-process-setup-guide.md).

---

## Common Mistakes and How to Avoid Them

| Mistake | What Goes Wrong | Prevention |
|---|---|---|
| Forgetting to merge master back to develop after a release | Next release reintroduces bugs that were fixed on the release branch | Add it to the release checklist. Automate with a GitHub Action. |
| Pushing new features to the release branch | Release scope keeps growing, UAT never converges | Release branch is frozen. New features go to develop for the next release. |
| Skipping the `needs-backport` label | Fixes on the release branch never make it back to develop | QA and release manager check for this label before closing a release. |
| Not updating `CLIENT_VERSIONS.md` | Nobody knows what version each client is on | Part of the release checklist. Can't close the release project until updated. |
| Creating a hotfix from develop instead of master | Hotfix includes unreleased code, may break production further | Hotfix flow is documented. Always branch from master for hotfixes. |
| Merging your own PR | Missed bugs, no second pair of eyes | Branch protection rules enforce reviewer requirement. |
| Not assigning type/client/repo labels | Can't generate accurate release notes, can't filter by client | PR template reminds you. Linear issue template has required fields. |
| Not adding `found-in` label on bugs | Can't track which environment bugs are discovered in, no quality metrics | Always add `found-in:dev`, `found-in:preprod`, or `found-in:prod` when logging a bug. |
