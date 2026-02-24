# DEPRECATED: Do Not Store Credentials in This File

> WARNING: Credentials must NEVER be stored in plaintext in this repository. This file is deprecated and kept only for reference structure. All credentials are now managed in HashiCorp Vault.

## Accessing Credentials

See `/sessions/gallant-relaxed-einstein/mnt/crego/crego-internal-docs/12-credentials/how-to-access.md` for step-by-step guides to retrieve credentials from Vault.

---

## Grafana - Dev

- URL: [grafana.dev.crego.ai](https://grafana.dev.crego.ai)
- Username: `admin`
- Password: → **Vault path:** `secrets/crego/dev/grafana/admin-password`
- Rotation: Every 90 days
- Contact: Platform team

## Grafana - Preprod

- URL: [grafana.preprod.crego.ai](https://grafana.preprod.crego.ai)
- Username: `admin`
- Password: → **Vault path:** `secrets/crego/preprod/grafana/admin-password`
- Rotation: Every 90 days
- Contact: Platform team

## ArgoCD - Dev

- URL: [argocd.dev.crego.ai](https://argocd.dev.crego.ai)
- Username: `admin`
- Password: → **Vault path:** `secrets/crego/dev/argocd/admin-password`
- Rotation: Every 90 days
- Contact: Platform team

## ArgoCD - Preprod

- URL: [argocd.preprod.crego.ai](https://argocd.preprod.crego.ai)
- Username: `admin`
- Password: → **Vault path:** `secrets/crego/preprod/argocd/admin-password`
- Rotation: Every 90 days
- Contact: Platform team