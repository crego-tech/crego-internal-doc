# Sentry Secret Rotation Guide

## When to Rotate

- Annually (recommended)
- When token compromised
- When team members with access leave

## Rotation Process

### 1. Generate New Credentials in Sentry

- Log in to sentry.io
- For DSN: Project Settings → Client Keys → Create new key
- For auth token: Settings → Auth Tokens → Create new token (scopes: project:releases, project:write)

### 2. Update Cloud Secret Managers

```bash
cd crego-infra
./scripts/create-secret-json.sh dev-gcp
# Enter new DSN/token values when prompted
./scripts/create-secret-json.sh dev-gcp --apply

# Repeat for all environments
./scripts/create-secret-json.sh preprod-gcp --apply
./scripts/create-secret-json.sh prod-gcp --apply
```

### 3. Update GitHub Secrets

- GitHub repo → Settings → Secrets and variables → Actions
- Update: `WEB_OMNI_SENTRY_DSN`, `WEB_FLOW_SENTRY_DSN`, `SENTRY_AUTH_TOKEN`

### 4. Verify Sync

```bash
kubectl get externalsecret app-env -n dev
kubectl get secret app-env -n dev -o jsonpath='{.data.OMNI_SENTRY_DSN}' | base64 -d
```

### 5. Restart Services (if needed)

```bash
kubectl rollout restart deployment omni-api -n dev
kubectl rollout restart deployment flow-api -n dev
```

### 6. Revoke Old Credentials

- In Sentry, delete old client keys and auth tokens after verifying new ones work

### 7. Test

- Trigger test errors in each service
- Verify errors appear in Sentry
- Verify source maps upload in CI/CD
