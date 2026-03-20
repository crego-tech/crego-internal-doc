# Unified Version Format

**Status:** 🚧 Partially Implemented (Infrastructure ready, workflows pending)
**Last Updated:** 2025-02-21
**Owned by:** Engineering Team

## Overview

This document defines the **unified version format** used across all Crego platform systems to ensure consistent version tracking, release identification, and error correlation across Git, Docker, Kubernetes, Sentry, and web applications.

## The Problem

Prior to standardization, version tracking was inconsistent:
- Backend Sentry: `omni@a3f2c1b` (commit only)
- Frontend Sentry: `undefined` (broken)
- Docker images: `v2.0.1-a3f2c1b` (includes 'v' prefix)
- Web display: `2.0.1-dev.a3f2c1b` (different separator)
- No support for multi-client releases

This made it impossible to:
- Correlate errors across frontend/backend
- Track which exact code version was deployed where
- Support client-specific releases properly

## The Solution

**Single unified format across ALL systems:**

```
{semver}[-{client}]-{commit}
```

> **Visual reference:** For the full version-by-environment matrix, Sentry format examples, and CI/CD image tagging — see the **Versioning tab** in `crego-internal-docs/release-management/crego-release-flow.html`

## Version Examples by Release Type

### Production Releases (Git Tags: v*)

#### Shared Release

**Input:**
```bash
Git tag: v2.2.0
Commit:  a3f2c1b456789012
```

**Output (All Systems):**
| System | Format | Value |
|--------|--------|-------|
| Docker image | `{semver}-{commit}` | `2.2.0-a3f2c1b` |
| Sentry (backend) | `{service}@{docker-tag}` | `omni@2.2.0-a3f2c1b` |
| Sentry (frontend) | `{service}@{docker-tag}` | `omni-web@2.2.0-a3f2c1b` |
| Web display | `{semver}` | `2.2.0` |
| K8s label | `app.kubernetes.io/version` | `2.2.0-a3f2c1b` |
| ECR/GCR tag | Same as Docker | `2.2.0-a3f2c1b` |

#### Client-Specific Release

**Input:**
```bash
Git tag: v2.2.0-acme
Commit:  a3f2c1b456789012
```

**Output (All Systems):**
| System | Format | Value |
|--------|--------|-------|
| Docker image | `{semver}-{client}-{commit}` | `2.2.0-acme-a3f2c1b` |
| Sentry (backend) | `{service}@{docker-tag}` | `omni@2.2.0-acme-a3f2c1b` |
| Sentry (frontend) | `{service}@{docker-tag}` | `omni-web@2.2.0-acme-a3f2c1b` |
| Web display | `{semver}-{client}` | `2.2.0-acme` |
| K8s label | `app.kubernetes.io/version` | `2.2.0-acme-a3f2c1b` |
| ECR/GCR tag | Same as Docker | `2.2.0-acme-a3f2c1b` |

### Pre-Production (Release Branches: release/*)

#### Shared Release Branch

**Input:**
```bash
Branch:  release/v2.2.0
Commit:  a3f2c1b456789012
```

**Output (All Systems):**
| System | Format | Value |
|--------|--------|-------|
| Docker image | `{semver}-preprod-{commit}` | `2.2.0-preprod-a3f2c1b` |
| Sentry (backend) | `{service}@{docker-tag}` | `omni@2.2.0-preprod-a3f2c1b` |
| Sentry (frontend) | `{service}@{docker-tag}` | `omni-web@2.2.0-preprod-a3f2c1b` |
| Web display | `{semver}-preprod` | `2.2.0-preprod` |
| K8s label | `app.kubernetes.io/version` | `2.2.0-preprod-a3f2c1b` |

#### Client Release Branch

**Input:**
```bash
Branch:  release/v2.2.0-acme
Commit:  a3f2c1b456789012
```

**Output (All Systems):**
| System | Format | Value |
|--------|--------|-------|
| Docker image | `{semver}-{client}-preprod-{commit}` | `2.2.0-acme-preprod-a3f2c1b` |
| Sentry (backend) | `{service}@{docker-tag}` | `omni@2.2.0-acme-preprod-a3f2c1b` |
| Sentry (frontend) | `{service}@{docker-tag}` | `omni-web@2.2.0-acme-preprod-a3f2c1b` |
| Web display | `{semver}-{client}-preprod` | `2.2.0-acme-preprod` |
| K8s label | `app.kubernetes.io/version` | `2.2.0-acme-preprod-a3f2c1b` |

### Development (develop/feature branches)

**Input:**
```bash
Branch:  develop (or feature/cre-123)
Latest tag: v2.2.0
Commit:  a3f2c1b456789012
```

**Output (All Systems):**
| System | Format | Value |
|--------|--------|-------|
| Docker image | `{semver}-dev-{commit}` | `2.2.0-dev-a3f2c1b` |
| Sentry (backend) | `{service}@{docker-tag}` | `omni@2.2.0-dev-a3f2c1b` |
| Sentry (frontend) | `{service}@{docker-tag}` | `omni-web@2.2.0-dev-a3f2c1b` |
| Web display | `{semver}-dev.{commit}` | `2.2.0-dev.a3f2c1b` *(note: dot before commit)* |
| K8s label | `app.kubernetes.io/version` | `2.2.0-dev-a3f2c1b` |

**Note:** Web display uses a dot (`.`) separator before the commit hash for development builds only, for legacy compatibility.

## Environment vs. Version Tracking

**Critical Distinction:** Environment and version are tracked **separately**.

| Aspect | What It Identifies | Where Tracked |
|--------|-------------------|---------------|
| **Version** | What code was deployed | Docker tag, Sentry release, K8s labels |
| **Environment** | Where code was deployed | Sentry environment field, K8s namespace, domain |

### Correct Pattern

```yaml
# Docker image tag (version)
image: asia-south1-docker.pkg.dev/crego-app-prod/services/omni-api:2.2.0-acme-a3f2c1b

# Sentry configuration (version + environment)
env:
  - name: SENTRY_RELEASE
    value: "omni@2.2.0-acme-a3f2c1b"  # Version
  - name: SENTRY_ENVIRONMENT
    value: "prod"                      # Environment (separate field)
```

This allows:
- Same version deployed to multiple environments (dev → preprod → prod)
- Tracking which environment an error occurred in
- Filtering Sentry errors by environment while grouping by version

## Implementation Guide

### Phase 1: Infrastructure (✅ Completed)

**Shared Version Parsing Utility:**

Created `crego-infra/scripts/lib/version-utils.sh` with functions:
- `parse_version_tag()` - Extract components from git tags
- `parse_branch_version()` - Extract components from branch names
- `validate_deployment_target()` - Prevent RC versions in production
- `generate_sentry_release()` - Build Sentry release identifier

**GitHub Actions Composite Action:**

Created `crego-infra/.github/actions/parse-version/action.yml` for consistent version parsing across workflows.

### Phase 2: CI/CD Workflows (🚧 Pending)

**Update Required in Each Repository:**

1. **crego-web/.github/workflows/omni-deployment.yaml**
2. **crego-web/.github/workflows/flow-deployment.yaml**
3. **crego-omni/.github/workflows/infra-deployment.yml**
4. **crego-flow/.github/workflows/infra-deployment.yaml**

**Required Workflow Pattern:**

```yaml
- name: Parse version from git context
  id: version
  run: |
    source scripts/lib/version-utils.sh
    COMMIT_SHORT="${{ github.sha }}"
    COMMIT_SHORT="${COMMIT_SHORT:0:8}"

    if [[ "${{ github.ref }}" == refs/tags/* ]]; then
      TAG_NAME="${{ github.ref }}#refs/tags/"
      VERSION_JSON=$(parse_version_tag "$TAG_NAME" "$COMMIT_SHORT")
    elif [[ "${{ github.ref }}" == refs/heads/* ]]; then
      BRANCH_NAME="${{ github.ref }}#refs/heads/"
      VERSION_JSON=$(parse_branch_version "$BRANCH_NAME" "$COMMIT_SHORT")
    fi

    echo "docker-tag=$(echo "$VERSION_JSON" | jq -r '.docker_tag')" >> $GITHUB_OUTPUT
    echo "sentry-release=$(echo "$VERSION_JSON" | jq -r '.docker_tag')" >> $GITHUB_OUTPUT
```

**Docker Environment Configuration:**

```yaml
DOCKER_ENVS="{
  \"VITE_RELEASE\":\"${{ steps.version.outputs.sentry-release }}\",
  \"VITE_SENTRY_DSN\":\"${SENTRY_DSN}\",
  \"VITE_API_ROOT\":\"${API_ROOT}\"
}"
```

### Phase 3: Kubernetes Deployments (🚧 Pending)

**Update Deployment Manifests:**

Add `SENTRY_RELEASE` environment variable to all service deployments:

```yaml
# crego-infra/apps/omni-api/deployment.yaml
spec:
  template:
    spec:
      containers:
        - name: api
          env:
            - name: SENTRY_RELEASE
              value: ""  # Injected by Kustomize from image tag
            - name: SENTRY_ENVIRONMENT
              value: "prod"  # Or dev/preprod based on overlay
```

**Create Kustomize Transformer:**

`crego-infra/overlays/shared/version-injector.yaml`:

```yaml
apiVersion: builtin
kind: ReplacementTransformer
metadata:
  name: inject-version-from-image-tag
replacements:
  - source:
      kind: Deployment
      fieldPath: spec.template.spec.containers.[name=api].image
    targets:
      - select:
          kind: Deployment
        fieldPaths:
          - spec.template.spec.containers.[name=api].env.[name=SENTRY_RELEASE].value
        options:
          delimiter: ':'
          index: 1  # Extract tag after ':'
```

### Phase 4: Frontend Sentry (🚧 Pending)

**Update Sentry Initialization:**

```typescript
// crego-web/packages/omni-web/src/main.tsx
Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.VITE_ENV || 'production',
  release: `omni-web@${import.meta.env.VITE_RELEASE || __APP_VERSION__}`,
  // ...
});
```

### Phase 5: Backend Sentry (✅ Already Implemented)

Backend services already check `SENTRY_RELEASE` environment variable:

```python
# crego-omni/project/settings/sentry.py
def get_release_version():
    release = os.getenv("SENTRY_RELEASE")
    if release:
        return f"omni@{release}"  # Add service prefix

    # Fallback to git commit
    try:
        commit = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"]).decode("utf-8").strip()
        return f"omni@{commit}"
    except Exception:
        return None
```

No changes needed - will automatically use `SENTRY_RELEASE` once injected by Kubernetes.

## Multi-Client Release Pattern

### Creating a Client Release

```bash
# 1. Create client release branch
git checkout -b release/v2.2.0-acme develop

# 2. Cherry-pick or merge client-specific changes
git cherry-pick <commit-sha>

# 3. Push to trigger preprod deployment
git push origin release/v2.2.0-acme
# Deploys to preprod with version: 2.2.0-acme-preprod-{commit}

# 4. After UAT approval, create client release tag
git tag -a v2.2.0-acme -m "Release 2.2.0 for Acme Corp"
git push origin v2.2.0-acme
# Deploys to prod with version: 2.2.0-acme-{commit}
```

### Querying Client Releases in Sentry

```
# All errors for Acme client release
release:"omni@2.2.0-acme-*"

# Errors in prod environment
environment:prod release:"omni@2.2.0-acme-*"

# Compare shared vs. client release
release:"omni@2.2.0-*" OR release:"omni@2.2.0-acme-*"
```

## Release Candidate Pattern

### Creating RC Releases

```bash
# Create RC tag
git tag -a v2.2.0-rc.1 -m "Release candidate 1 for v2.2.0"
git push origin v2.2.0-rc.1

# Version generated: 2.2.0-{commit} (RC suffix not in version string)
# is_rc flag: true (prevents production deployment)
```

### RC Validation

The version parsing utility automatically prevents RC versions from deploying to production:

```bash
ERROR: Release candidate versions cannot be deployed to production
Version: 2.2.0-rc.1
Target: prod
Use a stable release tag (without -rc suffix) for production deployments
```

RC versions can only be deployed to `dev` or `preprod` environments.

## Verification Commands

### Check Docker Image Tag

```bash
# List images in GCR
gcloud container images list-tags asia-south1-docker.pkg.dev/crego-app-prod/services/omni-api

# Should show: 2.2.0-acme-a3f2c1b (not v2.2.0-acme-a3f2c1b)
```

### Check Kubernetes Deployment

```bash
# Get deployed version
kubectl get deployment omni-api -n prod -o jsonpath='{.spec.template.spec.containers[0].image}'

# Should show: asia-south1-docker.pkg.dev/.../omni-api:2.2.0-acme-a3f2c1b
```

### Check Sentry Release

```bash
# View environment variable in pod
kubectl exec -it deployment/omni-api -n prod -- env | grep SENTRY_RELEASE

# Should show: SENTRY_RELEASE=omni@2.2.0-acme-a3f2c1b
```

### Check Web Version Display

```bash
# View version in browser console
# Open https://app.crego.com
# Console: __APP_VERSION__

# Should show: 2.2.0-acme (clean version, no commit hash)
```

## Migration Checklist

- [x] Create shared version parsing utility (`version-utils.sh`)
- [x] Create GitHub Actions composite action
- [x] Update documentation
- [ ] Update crego-web workflows (omni-deployment.yaml, flow-deployment.yaml)
- [ ] Update crego-omni workflows (infra-deployment.yml)
- [ ] Update crego-flow workflows (infra-deployment.yaml)
- [ ] Create Kustomize version injector transformer
- [ ] Update all deployment manifests to include SENTRY_RELEASE
- [ ] Update frontend Sentry initialization
- [ ] Test end-to-end version flow (git tag → Docker → K8s → Sentry)
- [ ] Verify client release pattern works
- [ ] Verify RC validation blocks production deployments
- [ ] Update CI/CD documentation with new patterns

## Troubleshooting

### Frontend Sentry Shows "undefined" Release

**Symptom:** Errors in Sentry frontend have `release: undefined`

**Cause:** `VITE_RELEASE` not set during Docker build

**Fix:** Update workflow to pass `VITE_RELEASE` in `DOCKER_ENVS`

### Backend Sentry Shows Only Commit Hash

**Symptom:** Errors in Sentry backend have `release: omni@a3f2c1b` (no version)

**Cause:** `SENTRY_RELEASE` not injected in Kubernetes deployment

**Fix:** Add `SENTRY_RELEASE` environment variable to deployment manifest

### Version Mismatch Between Systems

**Symptom:** Docker image has version `2.2.0-acme-a3f2c1b` but Sentry shows `2.2.0-a3f2c1b`

**Cause:** Workflow version parsing inconsistency

**Fix:** Use shared `version-utils.sh` or composite action for all workflows

### RC Version Deployed to Production

**Symptom:** RC version (e.g., `v2.2.0-rc.1`) was deployed to prod

**Cause:** Validation not enabled in workflow

**Fix:** Add `validate_deployment_target()` call before production deployment

## Related Documentation

- [Environment Naming Standard](./environment-naming-standard.md) - Official environment names
- [Deployment Guide](./deployment-guide.md) - Deployment procedures
- [Release Process](../release-management/release-process-setup-guide.md) - Release workflows
- [Infrastructure CLAUDE.md](../../crego-infra/CLAUDE.md) - Infrastructure details

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-02-21 | Initial unified version format specification | Engineering Team |
| 2025-02-21 | Created version-utils.sh shared utility | Engineering Team |
| 2025-02-21 | Created parse-version GitHub Actions composite action | Engineering Team |

## Questions?

If you have questions about version format or encounter issues, please:
1. Check this document for the official standard
2. Review `crego-infra/scripts/lib/version-utils.sh` for implementation
3. Contact the Engineering team for clarification
