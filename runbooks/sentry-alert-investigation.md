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
