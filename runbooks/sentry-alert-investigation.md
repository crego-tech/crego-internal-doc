# Sentry Alert Investigation Runbook

## Alert Triage

### Assess Severity

- **Critical**: 5xx errors affecting > 10% of users
- **High**: New error pattern affecting multiple users
- **Medium**: Known error with increased frequency
- **Low**: Isolated error

### Check Context

- Environment: dev, preprod, prod?
- Service: omni-api, flow-api, omni-web, flow-web?
- Tenant: Which tenant (if multi-tenant)?

## Investigation Steps

### 1. Review Error Context in Sentry

- Error message and stack trace
- Request context (URL, method, headers)
- User context (email, roles)
- Tenant context (alias, domain)
- Breadcrumbs (user actions before error)

#### Review Multi-Tenant Context

Check the error event for tenant-specific information to determine if the error is isolated to one tenant or platform-wide:

**Tenant Tags (always present):**
- `tenant_id` - Numeric tenant ID
- `tenant_alias` - Tenant alias (e.g., "acme")
- `tenant_domain` - Tenant domain (e.g., "acme.example.com")
- `tenant_tier` - Tenant tier (free, basic, enterprise)

**Tenant Context (detailed info):**
```json
{
  "tenant": {
    "id": 12345,
    "alias": "acme",
    "tier": "enterprise",
    "name": "Acme Corporation"
  }
}
```

**User Context (when PII enabled):**
```json
{
  "user": {
    "id": "67890",
    "email": "john.doe@acme.com",
    "username": "john.doe",
    "roles": ["admin", "finance"]
  }
}
```

**Analysis Questions:**
- Is the error affecting only one tenant? (Filter by `tenant_id` tag)
- Are all users in the same role affected? (Check `user.roles`)
- Is this a tenant-tier specific issue? (Compare enterprise vs. free tier)

#### Review Performance Data

Check the performance trace to identify bottlenecks and slow operations:

**Transaction Duration:**
- Compare error transaction duration to baseline
- Look for unusually slow operations (>2x normal)
- Check if timeout-related error

**Slow Operations in Trace:**
1. Navigate to error event → "Trace" tab
2. Look for spans with high duration:
   - Database queries (check query count and time)
   - External API calls (check response times)
   - File I/O operations
   - Complex calculations

**Database Query Analysis:**
- Total query count in transaction
- Slowest query duration
- N+1 query patterns (many similar queries)

**Example Bottleneck:**
```
Transaction: 3,500ms (baseline: 200ms)
├─ Database queries: 2,800ms (15 queries)  ← Bottleneck
├─ External API: 500ms
└─ Business logic: 200ms
```

**Action Items:**
- If database is slow: Check query optimization, indexes
- If API is slow: Check external service status, implement caching
- If business logic is slow: Review algorithm efficiency

#### Review Release Information

Determine which release introduced the error and compare error rates:

**Check Release Version:**
1. Error event → "Tags" → `release`
2. Note the release version (e.g., `v2.3.0`)

**Compare Error Rates Between Releases:**
1. Navigate to Issues → Error group
2. Click "Releases" tab
3. Look for spike in error rate after specific release

**Review Changelog:**
```bash
# Check what changed in the release
git log v2.2.0..v2.3.0 --oneline

# Check specific file changes
git diff v2.2.0..v2.3.0 -- path/to/file.py
```

**Questions to Answer:**
- Did this error exist in previous releases?
- What code changes were made in the problematic release?
- Are there related changes in the same area?

#### Frontend Errors - Check Source Maps

For frontend errors, verify stack traces are readable (not minified):

**Verify Stack Trace Quality:**
1. Error event → "Exception" section
2. Check if file names are readable (e.g., `src/components/Invoice.tsx` vs. `main.abc123.js`)
3. Check if line numbers match actual source code

**If Source Maps Are Missing:**

**Check Sentry Artifacts:**
1. Navigate to Project Settings → Source Maps
2. Select the release version
3. Verify bundle files and source maps are present

**Expected Artifacts:**
```
Release: v2.3.0
├── main.abc123.js
├── main.abc123.js.map
├── vendor.def456.js
└── vendor.def456.js.map
```

**If Artifacts Are Missing:**

```bash
# Check CI/CD logs for source map upload
# GitHub Actions: Look for "Source maps uploaded successfully"

# Verify SENTRY_AUTH_TOKEN in CI/CD
gh secret list | grep SENTRY_AUTH_TOKEN

# Manual source map upload (emergency)
sentry-cli releases files v2.3.0 upload-sourcemaps \
  ./dist \
  --url-prefix '~/assets' \
  --org crego \
  --project omni-web

# Verify upload
sentry-cli releases files v2.3.0 list
```

### 2. Check for Patterns

- Go to "Events" tab in Sentry
- Look for:
  - Specific users affected
  - Specific tenants affected
  - Time pattern (spike vs gradual)
  - Geographic pattern

### 3. Check Recent Deployments

- In Sentry, check "Releases" tab
- Did error start after specific deployment?
- Review changelog for that release

### 4. Check Related Systems

```bash
# Database health
kubectl logs postgresql-0 -n <env> --tail=100

# Celery queue health
kubectl exec -it omni-celery-worker-0 -n <env> -- celery -A celery_app inspect active

# External services status
```

## Resolution

### For Known Issues

- Link Sentry issue to existing Linear issue
- Update Linear with new occurrences
- Escalate if urgent

### For New Issues

- Linear issue auto-created by Sentry integration
- Add reproduction steps
- Assign to relevant team
- Set priority

### For Production Emergencies

- Page on-call engineer
- Start incident response
- Consider rollback if deployment-related

## Common Sentry-Specific Issues

These issues are specific to Sentry integration and configuration. Resolve these before investigating application bugs.

### 1. Missing Context (Tenant/User Data Not Appearing)

**Symptom:**
- Errors appear in Sentry but lack tenant tags (`tenant_id`, `tenant_alias`, `tenant_domain`)
- Cannot filter errors by tenant
- Multi-tenant context missing in event details

**Root Causes:**
1. Tenant middleware not configured in Django settings
2. Service instantiated without `user` parameter (context not passed)
3. Request lacks tenant context (e.g., internal cron jobs, system operations)
4. Frontend: `setTenantContext()` not called after login

**Diagnosis:**

```bash
# Backend (Django): Check middleware configuration
kubectl exec -it deployment/omni-api -n prod-gcp -- \
  cat project/settings/middleware.py | grep TenantMiddleware

# Check service initialization in code
# Look for: service = InvoiceService(user=request.user)
# NOT: service = InvoiceService()

# Check error event in Sentry UI
# Navigate to: Issues → Select error → Tags
# Verify presence of: tenant_id, tenant_alias, tenant_domain
```

**Resolution (Backend - Django):**

```python
# project/settings/middleware.py
MIDDLEWARE = [
    # ... other middleware
    'project.middleware.TenantMiddleware',  # Must be present
    # ... other middleware
]

# Ensure services receive user context
from project.lib.base_service import BaseService

class InvoiceService(BaseService):
    def __init__(self, user):
        super().__init__(user)  # Tenant context extracted from user
        # ... rest of initialization
```

**Resolution (Backend - FastAPI):**

```python
# Ensure middleware adds tenant to request.state
from fastapi import Request

@app.middleware("http")
async def add_tenant_context(request: Request, call_next):
    request.state.tenant = resolve_tenant_from_request(request)
    response = await call_next(request)
    return response

# Ensure services receive user context
service = FlowService(user=request.state.user)
```

**Resolution (Frontend):**

```typescript
// After successful login, set tenant context
import { setTenantContext } from '@/utils/sentry';

function onLoginSuccess(tenant) {
  setTenantContext({
    id: tenant.id,
    alias: tenant.alias,
    tier: tenant.tier
  });
}
```

---

### 2. Source Maps Not Working (Frontend Stack Traces Minified)

**Symptom:**
- Frontend error stack traces show minified code
- File names like `main.abc123.js` instead of `src/components/Invoice.tsx`
- Line numbers don't match actual source code
- Unable to locate error in codebase

**Root Causes:**
1. `SENTRY_AUTH_TOKEN` missing or expired in CI/CD
2. Source map upload failed during build (check CI/CD logs)
3. Release version mismatch (bundle version ≠ Sentry release tag)
4. Vite Sentry plugin not configured correctly
5. Source maps not generated during build (check Vite config)

**Diagnosis:**

```bash
# 1. Check source maps in Sentry UI
# Navigate to: Project Settings → Source Maps → Releases
# Select release version (e.g., v2.3.0)
# Verify bundle files and .map files are present

# 2. Check CI/CD logs for source map upload
# GitHub Actions: Look for output:
# "Source maps uploaded successfully to release v2.3.0"

# 3. Verify SENTRY_AUTH_TOKEN in CI/CD
gh secret list | grep SENTRY_AUTH_TOKEN

# 4. Check Vite plugin configuration
# Look for @sentry/vite-plugin in vite.config.ts
```

**Resolution (Emergency Manual Upload):**

```bash
# Install Sentry CLI
npm install -g @sentry/cli

# Set authentication token
export SENTRY_AUTH_TOKEN=your_token_here

# Upload source maps manually
sentry-cli releases files v2.3.0 upload-sourcemaps \
  ./dist \
  --url-prefix '~/assets' \
  --org crego \
  --project omni-web

# Verify upload succeeded
sentry-cli releases files v2.3.0 list
# Expected output: List of .js and .js.map files
```

**Permanent Fix:**

1. **Update SENTRY_AUTH_TOKEN in GitHub Actions:**
   ```bash
   # Navigate to: GitHub → Settings → Secrets and variables → Actions
   # Update or create secret: SENTRY_AUTH_TOKEN
   ```

2. **Verify Vite plugin configuration:**
   ```typescript
   // vite.config.ts
   import { sentryVitePlugin } from "@sentry/vite-plugin";

   export default defineConfig({
     build: {
       sourcemap: true  // MUST be enabled
     },
     plugins: [
       sentryVitePlugin({
         org: "crego",
         project: "omni-web",
         authToken: process.env.SENTRY_AUTH_TOKEN
       })
     ]
   });
   ```

3. **Add source map upload verification to CI/CD:**
   ```yaml
   # .github/workflows/build.yml
   - name: Verify source maps uploaded
     run: |
       sentry-cli releases files ${{ env.RELEASE_VERSION }} list | grep ".map"
   ```

---

### 3. Performance Traces Missing (No Transaction Data)

**Symptom:**
- Errors are captured in Sentry but no performance data
- Transaction list is empty in Sentry UI
- No trace details in error events
- Cannot identify slow operations

**Root Causes:**
1. Sampling rate too low (default prod: 1% means 99% not traced)
2. Transactions not manually started for custom operations
3. Sentry quota exhausted (hitting transaction quota limit)
4. Performance tracing disabled in configuration

**Diagnosis:**

```bash
# 1. Check sampling rate in environment
kubectl exec -it deployment/omni-api -n prod-gcp -- \
  env | grep SENTRY_TRACES_SAMPLE_RATE
# Default prod: 0.01 (only 1% of transactions traced)

# 2. Check if transactions are created in code
# Look for @sentry_trace decorators or sentry_transaction context managers

# 3. Check Sentry quota usage
# Navigate to: Sentry → Settings → Subscription → Usage
# Look for: Transaction quota (e.g., 50,000/month)
# Check if quota is exhausted
```

**Resolution (Increase Sampling Temporarily):**

```bash
# Increase sampling rate for debugging (test environment only)
kubectl set env deployment/omni-api -n dev-gcp \
  SENTRY_TRACES_SAMPLE_RATE=0.5

# Restart pods to load new configuration
kubectl rollout restart deployment/omni-api -n dev-gcp

# Verify change
kubectl exec -it deployment/omni-api -n dev-gcp -- \
  env | grep SENTRY_TRACES_SAMPLE_RATE
# Expected: 0.5
```

**Resolution (Add Manual Tracing):**

```python
# Django/Backend example
from project.lib.sentry_utils import sentry_trace

@sentry_trace(op="invoice.bulk_approve", description="Bulk approve invoices")
def bulk_approve_invoices(invoice_ids):
    """
    Function execution automatically tracked.
    Creates a transaction with spans.
    """
    for invoice_id in invoice_ids:
        approve_invoice(invoice_id)

# FastAPI/Workflow example
import sentry_sdk

async def execute_workflow(flow_id):
    with sentry_sdk.start_transaction(op="workflow.execute", name=f"Execute {flow_id}"):
        # Workflow execution automatically traced
        result = await run_workflow(flow_id)
        return result
```

**Resolution (Check Quota):**

If quota is exhausted:
1. Upgrade Sentry plan (increase transaction quota)
2. Lower sampling rate to conserve quota
3. Focus tracing on critical operations only

---

### 4. Too Many Noise Errors (Alert Fatigue)

**Symptom:**
- Alert fatigue from non-critical errors
- 404/403 errors cluttering Sentry dashboard
- Expected validation errors appearing as issues
- Difficult to find real problems

**Root Causes:**
1. 4xx errors not filtered (should only track 5xx server errors)
2. Expected errors captured (validation errors, business rule violations)
3. Missing ignore rules in Sentry project settings
4. No error grouping/fingerprinting configured

**Diagnosis:**

```bash
# Review error patterns in Sentry UI
# Navigate to: Issues → Group by error type
# Look for patterns:
# - All 404s from same endpoint
# - All ValidationErrors from same form
# - All PermissionDenied errors
```

**Resolution (Update Error Filtering in Code):**

```python
# Backend (Django): project/settings/sentry.py

def before_send(event, hint):
    """
    Filter errors before sending to Sentry.
    """
    # 1. Filter 4xx client errors (already implemented)
    if 'request' in event:
        status_code = event['request'].get('status_code')
        if status_code and 400 <= status_code < 500:
            return None  # Don't send to Sentry

    # 2. Filter expected business exceptions
    if 'exception' in event:
        exc_type = event['exception']['values'][0]['type']
        expected_errors = [
            'ValidationError',      # DRF validation
            'PermissionDenied',     # Authorization
            'NotAuthenticated',     # Auth
            'BusinessRuleError'     # Expected business rules
        ]
        if exc_type in expected_errors:
            return None

    # 3. Filter health check errors
    if 'request' in event:
        url = event['request'].get('url', '')
        if '/health' in url:
            return None

    return event

sentry_sdk.init(
    dsn=SENTRY_DSN,
    before_send=before_send,
    # ... other config
)
```

**Resolution (Add Ignore Rules in Sentry UI):**

1. Navigate to: Project Settings → Inbound Filters
2. Add ignore rules:
   - **Error message contains**: "Permission denied"
   - **Error type**: "ValidationError"
   - **URL pattern**: "/health/*" (ignore health check errors)
   - **IP addresses**: Internal monitoring IPs

3. Configure grouping rules:
   - Navigate to: Project Settings → Issue Grouping
   - Add fingerprint rules to group similar errors

**Example Fingerprinting:**

```python
# Group all validation errors together
import sentry_sdk

try:
    validate_invoice(data)
except ValidationError as e:
    sentry_sdk.set_tag("error_category", "validation")
    sentry_sdk.set_context("validation", {
        "fields": e.field_errors.keys()
    })
    # Don't capture - already handled in before_send
    raise
```

---

### 5. Tenant-Specific Errors (Isolated to One Tenant)

**Symptom:**
- Errors only affect one tenant, not platform-wide
- Other tenants working normally
- Tenant-specific configuration issue suspected

**Root Causes:**
1. Tenant configuration mismatch (settings, feature flags)
2. Tenant-specific data problem (corrupt data, schema mismatch)
3. Tenant database connection issue
4. Tenant-specific integration configuration (API keys, webhooks)

**Diagnosis:**

```bash
# 1. Filter errors by tenant in Sentry
# Navigate to: Issues → Filter by tag: tenant_alias=acme

# 2. Compare tenant configuration
# Check Django admin or database for tenant-specific settings

# 3. Check tenant database connection
kubectl exec -it deployment/omni-api -n prod-gcp -- \
  python manage.py shell
>>> from django_tenants.utils import get_tenant_model
>>> Tenant = get_tenant_model()
>>> tenant = Tenant.objects.get(alias='acme')
>>> tenant.status
'active'

# 4. Check tenant-specific integrations
# Review API keys, webhook configurations in tenant settings
```

**Resolution Steps:**

1. **Compare with working tenant:**
   - Export configuration from working tenant
   - Compare with affected tenant
   - Identify differences

2. **Check tenant data integrity:**
   ```python
   # Run tenant-specific verification
   TENANT_ALIAS=acme pipenv run python manage.py check_data_integrity
   ```

3. **Review tenant-specific logs:**
   ```bash
   # Filter application logs by tenant
   kubectl logs deployment/omni-api -n prod-gcp | grep "tenant_alias=acme"
   ```

4. **Test tenant isolation:**
   ```bash
   # Verify tenant queue isolation
   TENANT_ALIAS=acme pipenv run python manage.py monitor_tenant_isolation
   ```

5. **If configuration issue:**
   - Update tenant configuration in admin
   - Restart affected services
   - Verify error resolved

6. **If data issue:**
   - Run data migration/correction script
   - Consider data restore from backup
   - Document issue in Linear for tracking

## Common Issues

### Database Connection Pool Exhausted

**Symptoms**: `connection pool exhausted` errors
**Resolution**: Restart pods, investigate long-running queries

### Celery Worker Out of Memory

**Symptoms**: `MemoryError` in tasks
**Resolution**: Restart workers, optimize task memory usage

### External API Timeout

**Symptoms**: `ReadTimeout` errors
**Resolution**: Check external service status, implement retry logic
