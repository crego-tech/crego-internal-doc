# Environment Naming Standard

**Status:** ✅ Implemented
**Last Updated:** 2025-02-21
**Owned by:** Engineering Team

## Overview

This document defines the official environment naming conventions used across the entire Crego platform, including infrastructure (Kubernetes), backend services (Django/FastAPI), and frontend applications (React).

## Official Environment Names

The Crego platform uses **abbreviated, lowercase environment names** consistently across all systems:

| Environment | Name | Description | Kubernetes Namespace |
|-------------|------|-------------|---------------------|
| **Development** | `dev` | Internal development and testing | `dev` |
| **Pre-production** | `preprod` | UAT and release validation | `preprod` |
| **Production** | `prod` | Live customer-facing systems | `prod` |

### Key Principles

1. **Always use abbreviated forms**: `dev`, `preprod`, `prod` (never `development`, `pre-prod`, or `production`)
2. **Always lowercase**: Never `Dev`, `PREPROD`, or `Prod`
3. **Consistent across all systems**: Same value in infrastructure, backend, frontend, and monitoring
4. **No hyphens in names**: Use `preprod` not `pre-prod` or `pre_prod`

## Variable Name Mapping

Different systems use different variable names for environment configuration. Here's the canonical mapping:

### Infrastructure → Services Mapping

```bash
# Infrastructure (Kubernetes kustomization.yaml)
ENVIRONMENT=dev          # ConfigMap variable

# Backend Services (Django/FastAPI application code)
ENV=dev                  # Expected by application
# Services read ENV, not ENVIRONMENT

# Frontend (Vite build process)
VITE_ENV=dev            # Vite-specific prefix required
```

### Configuration Injection Flow

```
Infrastructure ConfigMap (ENVIRONMENT)
    ↓
External Secrets Operator / ConfigMap
    ↓
Application Container Environment (ENV)
    ↓
Application Runtime (reads ENV variable)
```

**Important:** Infrastructure sets `ENVIRONMENT` in ConfigMaps, but this must be mapped to `ENV` when injected into application containers.

## Implementation by System

### Infrastructure (Kubernetes)

**Files:** `crego-infra/overlays/*/kustomization.yaml`

```yaml
# ✅ Correct
configMapGenerator:
  - literals:
      - ENVIRONMENT=dev       # For dev environments
      - ENVIRONMENT=preprod   # For preprod environments
      - ENVIRONMENT=prod      # For prod environments

# ❌ Wrong
configMapGenerator:
  - literals:
      - ENVIRONMENT=development  # Never use full words
      - ENVIRONMENT=pre-prod     # Never use hyphens
      - environment=PROD         # Never use uppercase
```

**Label Convention:**

```yaml
labels:
  - pairs:
      environment: dev  # Labels use abbreviated form
```

### Backend Services

#### crego-omni (Django)

**File:** `crego-omni/project/settings/secrets.py`

```python
# ✅ Correct
ENV = config_secret.get("ENV", "preprod")

if ENV not in ["dev", "preprod", "prod"]:
    raise ValueError("ENV must be either dev, preprod or prod")

DEBUG = ENV == "dev"
IS_PROD = ENV == "prod"
```

#### crego-flow (FastAPI)

**File:** `crego-flow/project/core/secrets.py`

```python
# ✅ Correct (after standardization)
def _set_environment_settings(self) -> Dict[str, bool]:
    if os.environ.get("ENV"):
        env = os.environ.get("ENV")
        return {"IS_PROD_ENV": env == "prod", "DEBUG": env != "prod"}
    return {"IS_PROD_ENV": False, "DEBUG": True}

def get_env(self) -> str:
    return os.getenv("ENV", "dev")  # Default to dev

# ❌ Wrong (old pattern - deprecated)
# return {"IS_PROD_ENV": env == "production", ...}
# return os.getenv("ENV", "development")
```

### Frontend Services

#### Vite Configuration

**Files:** `crego-web/packages/*/vite.config.ts`

```typescript
// ✅ Correct
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, path.resolve(__dirname, '../..'), '')
  return {
    build: {
      sourcemap: env.VITE_ENV === 'dev',  // Use 'dev' not 'development'
      // ...
    }
  }
})
```

**Note:** Vite requires the `VITE_` prefix for environment variables to be exposed to the application. The value should still be `dev`, `preprod`, or `prod`.

#### Sentry Configuration

**Files:** `crego-web/packages/*/src/main.tsx`

```typescript
// ✅ Correct
Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.VITE_ENV || 'prod',  // Use abbreviated form
  // ...
})
```

## Domain Naming Pattern

Environments are accessed through different domains:

| Environment | Domain Pattern | Example |
|-------------|---------------|---------|
| `dev` | `{service}-dev.crego.com` | `app-dev.crego.com` |
| `preprod` | `{service}-preprod.crego.com` | `app-preprod.crego.com` |
| `prod` | `{service}.crego.com` | `app.crego.com` |

## Environment-Specific Behavior

### Development (`dev`)

- **Debug Mode:** Enabled
- **Logging:** Verbose (DEBUG level)
- **Error Pages:** Detailed stack traces
- **Source Maps:** Enabled
- **Infrastructure Services:** Local (PostgreSQL, Redis, RabbitMQ in K8s)
- **Default Credentials:** Built-in defaults for faster development

### Pre-production (`preprod`)

- **Debug Mode:** Disabled
- **Logging:** Standard (INFO level)
- **Error Pages:** User-friendly
- **Source Maps:** Enabled for debugging
- **Infrastructure Services:** External (managed cloud services)
- **Testing:** UAT and release validation

### Production (`prod`)

- **Debug Mode:** Disabled
- **Logging:** Standard (INFO level)
- **Error Pages:** Minimal information
- **Source Maps:** Disabled
- **Infrastructure Services:** External (managed cloud services)
- **Monitoring:** Enhanced monitoring and alerting

## Migration Guide

### Updating Existing Code

If you find code using old environment values, update it following these patterns:

#### Infrastructure

```bash
# Before
ENVIRONMENT=development

# After
ENVIRONMENT=dev
```

#### Backend (Python)

```python
# Before
ENV = os.getenv("ENV", "development")
if env == "production":
    DEBUG = False

# After
ENV = os.getenv("ENV", "dev")
if env == "prod":
    DEBUG = False
```

#### Frontend (TypeScript)

```typescript
// Before
sourcemap: env.VITE_ENV === 'development'

// After
sourcemap: env.VITE_ENV === 'dev'
```

### Testing Your Changes

After updating environment names, verify:

```bash
# Infrastructure
kubectl get configmap -n dev -o yaml | grep ENVIRONMENT
# Should show: ENVIRONMENT: dev

# Backend (in pod)
kubectl exec -it deployment/omni-api -n dev -- env | grep ENV
# Should show: ENV=dev

# Frontend (check build output)
# Build should reference 'dev' not 'development'
```

## Common Mistakes to Avoid

| ❌ Wrong | ✅ Correct | Reason |
|----------|-----------|--------|
| `development` | `dev` | Use abbreviated form |
| `pre-prod` | `preprod` | No hyphens in names |
| `production` | `prod` | Use abbreviated form |
| `staging` | `preprod` | We use `preprod` not `staging` |
| `Development` | `dev` | Always lowercase |
| `ENVIRONMENT=prod` (in app code) | `ENV=prod` | Apps read `ENV`, infra sets `ENVIRONMENT` |

## Validation

All services validate environment names at startup:

```python
# crego-omni/project/settings/secrets.py
if ENV not in ["dev", "preprod", "prod"]:
    raise ValueError("ENV must be either dev, preprod or prod")
```

If you see this error, check that your environment variable is set correctly to one of the three valid values.

## Related Documentation

- [Unified Version Format](./unified-version-format.md) - Version tracking across systems
- [Deployment Guide](./deployment-guide.md) - Environment-specific deployment procedures
- [Infrastructure CLAUDE.md](../../crego-infra/CLAUDE.md) - Infrastructure configuration details
- [Release Process](../release-management/release-process-setup-guide.md) - Release management workflows

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-02-21 | Initial documentation of standardized naming convention | Engineering Team |
| 2025-02-21 | Updated crego-flow to use `dev`/`preprod`/`prod` | Engineering Team |
| 2025-02-21 | Updated infrastructure overlays (dev-aws, dev-gcp, prod-aws) | Engineering Team |

## Questions?

If you have questions about environment naming or encounter inconsistencies, please:
1. Check this document for the official standard
2. Review related documentation linked above
3. Contact the Engineering team for clarification
