# Design: Fixing dev / qa1 / qa2 Environment Conflicts

**Status:** Proposal
**Author:** Abhishek (with Claude)
**Date:** 2026-06-18
**Repo:** `crego-infra`
**Scope:** `overlays/dev-gcp`, `overlays/qa1-gcp`, `overlays/qa2-gcp`, `base/*`, `argocd-apps/*`

---

## 1. Problem statement

`dev`, `qa1`, and `qa2` are not cleanly isolated. The overlays were cloned from `dev-gcp`
and only partially adapted, leaving two competing designs (per-env gateway vs. shared
gateway) committed side by side and a cluster-scoped resource that three ArgoCD apps fight
to own. The symptoms: intermittent External Secrets auth, confusing dead files, and
ambiguity about which environment owns what.

## 2. Current state (as found)

All three environments deploy to the **same GKE cluster**:

| Env  | ArgoCD app             | Dest server                     | Namespace | Cluster                  |
|------|------------------------|---------------------------------|-----------|--------------------------|
| dev  | `dev-gcp-environment`  | `https://kubernetes.default.svc`| `dev`     | `crego-app-dev-cluster`  |
| qa1  | `qa1-gcp-environment`  | `https://kubernetes.default.svc`| `qa1`     | `crego-app-dev-cluster`  |
| qa2  | `qa2-gcp-environment`  | `https://kubernetes.default.svc`| `qa2`     | `crego-app-dev-cluster`  |

Namespaces themselves are clean and distinct (`base/<env>/namespace.yaml` → `dev`/`qa1`/`qa2`).
The conflicts are in the **cluster-scoped and cross-namespace** resources.

### 2.1 Conflict A — `ClusterSecretStore` name collision

Each overlay ships a `ClusterSecretStore` named **`cloud-sm`**:

- `overlays/dev-gcp/secret-store.yaml` → `serviceAccountRef.namespace: dev`
- `overlays/qa1-gcp/secret-store.yaml` → `serviceAccountRef.namespace: qa1`
- `overlays/qa2-gcp/secret-store.yaml` → `serviceAccountRef.namespace: qa2`

`ClusterSecretStore` is **cluster-scoped** — only one object named `cloud-sm` can exist on
the cluster. Three ArgoCD apps rendering the same name means whichever syncs last owns it;
the other two environments' `ExternalSecret`s then authenticate through the wrong
`eso-sa`. The current "fix" is that `secret-store.yaml` is **commented out** of the qa1/qa2
kustomizations, so `dev` is the sole owner and qa1/qa2 secrets silently resolve through
**dev's** `eso-sa`. This works by accident and breaks the moment someone uncomments it or
changes sync order.

### 2.2 Conflict B — half-switched gateway model

qa1/qa2 still carry per-env gateway definitions that are disabled, while their live routes
attach to dev's gateway:

- `overlays/qa1-gcp/gateway.yaml` defines `qa1-gateway` on static IP `crego-qa1-ip`
  — **commented out** of the kustomization.
- `overlays/qa2-gcp/gateway.yaml` defines `qa2-gateway` on static IP `crego-qa2-ip`
  — **commented out**.
- The **active** `overlays/qa1-gcp/httproute.yaml` / `qa2-gcp/httproute.yaml` attach
  cross-namespace to `dev-gateway` (namespace `dev`) with hostnames
  `qa1.dev.crego.ai` / `qa2.dev.crego.ai`.
- `dev-gateway` has `allowedRoutes.namespaces.from: All` and a wildcard listener
  `*.dev.crego.ai`, so the qa subdomains attach and resolve.

Net effect: all three environments actually share **one** gateway and **one** IP
(`crego-dev-ip`). The committed files claim otherwise, and the reserved `crego-qa1-ip` /
`crego-qa2-ip` static addresses are likely idle and still billed.

### 2.3 Why this is "conflicting"

The repo describes two architectures at once. A reader (or a future ArgoCD sync) can't tell
whether qa1/qa2 are meant to be independent (own gateway, own secret store) or shared
(ride dev's). The cluster-scoped `cloud-sm` makes the ambiguity actively dangerous.

## 3. Goals / non-goals

**Goals**
- One unambiguous isolation model applied identically to dev, qa1, qa2.
- Eliminate the cluster-scoped `cloud-sm` collision permanently.
- Remove dead/contradictory files and any idle billed resources.
- Keep cost low — these are non-prod environments sharing one cluster.

**Non-goals**
- Splitting qa1/qa2 onto separate clusters (unnecessary for non-prod).
- Changing the application images or port conventions (port 8000 standard stays).

## 4. Proposed design

Keep the **shared-cluster, shared-gateway, namespace-isolated** model — it matches how the
environments already behave and is the cheapest — but make it explicit and remove the
cluster-scoped collision.

### 4.1 Replace `ClusterSecretStore` with a namespaced `SecretStore` per env (recommended)

Convert each overlay's `cloud-sm` from `ClusterSecretStore` to a namespaced `SecretStore`,
and update the `ExternalSecret` `secretStoreRef.kind` to `SecretStore`. Each environment
then owns its own store inside its own namespace — no shared object, no collision, and the
`serviceAccountRef` naturally targets the local `eso-sa`.

```yaml
# overlays/<env>/secret-store.yaml
apiVersion: external-secrets.io/v1
kind: SecretStore          # was: ClusterSecretStore
metadata:
  name: cloud-sm
  # namespaced now — lives in dev / qa1 / qa2 respectively
spec:
  provider:
    gcpsm:
      projectID: crego-app-dev
      auth:
        workloadIdentity:
          clusterLocation: asia-south1-a
          clusterName: crego-app-dev-cluster
          serviceAccountRef:
            name: eso-sa
            # namespace no longer required; resolves within the SecretStore's namespace
```

```yaml
# base/<env>/externalsecret.yaml (or the patch) — change kind only
spec:
  secretStoreRef:
    name: cloud-sm
    kind: SecretStore        # was: ClusterSecretStore
```

Then **re-enable** `secret-store.yaml` in the qa1/qa2 kustomizations (it is safe now) and
ensure each namespace has its own `eso-sa` service account with Workload Identity binding.

> Alternative if you prefer a single shared store: keep exactly **one** `ClusterSecretStore`
> and move it out of the env overlays into a shared bootstrap/addons app so a single ArgoCD
> application owns it. The namespaced `SecretStore` approach is preferred because it keeps
> each environment fully self-contained.

### 4.2 Make the shared gateway explicit; delete the dead per-env gateways

- Treat `dev-gateway` as the **shared non-prod ingress** for the cluster. Optionally move
  it (and `crego-dev-ip`) into a neutral namespace (e.g. `infra` / `gateway-system`) and
  rename it `nonprod-gateway` so it doesn't look like it belongs to `dev`. It already has
  `from: All` and a `*.dev.crego.ai` wildcard, which is exactly what shared routing needs.
- **Delete** `overlays/qa1-gcp/gateway.yaml`, `overlays/qa1-gcp/gcpgatewaypolicy.yaml`,
  `overlays/qa2-gcp/gateway.yaml`, `overlays/qa2-gcp/gcpgatewaypolicy.yaml` and their
  commented kustomization references.
- **Release** the reserved static IPs `crego-qa1-ip` and `crego-qa2-ip` in GCP (stop the
  idle charge) once confirmed unused: `gcloud compute addresses list`.
- Each env keeps only its `httproute.yaml` (parentRef → the shared gateway, distinct
  hostname). This is already how dev/qa1/qa2 route today; the change just deletes the
  contradictory files.

### 4.3 Resulting ownership matrix

| Resource                     | Owner                      | Scope        |
|------------------------------|----------------------------|--------------|
| Shared gateway + 1 static IP | shared/infra ArgoCD app    | cluster      |
| `SecretStore` `cloud-sm`     | each env overlay           | namespaced   |
| `eso-sa` + WI binding        | each env (`base/<env>`)    | namespaced   |
| Namespace + workloads        | each env overlay           | namespaced   |
| `HTTPRoute` (unique host)    | each env overlay           | namespaced   |

## 5. Migration plan

1. Add per-namespace `eso-sa` + Workload Identity bindings for `qa1`, `qa2` (if not present).
2. Convert `overlays/dev-gcp/secret-store.yaml` to namespaced `SecretStore`; flip the
   `ExternalSecret` `kind`. Sync dev, confirm `app-env` secret still populates.
3. Repeat for qa1, then qa2; re-enable `secret-store.yaml` in each kustomization. Verify
   `ExternalSecret` status = `SecretSynced` in all three namespaces.
4. Delete the dead `gateway.yaml` / `gcpgatewaypolicy.yaml` from qa1/qa2; remove commented
   refs. Sync; confirm routes still attach to the shared gateway.
5. Release `crego-qa1-ip` / `crego-qa2-ip` after confirming no LB references them.
6. (Optional) Move/rename the shared gateway to a neutral namespace and update the three
   `httproute.yaml` parentRefs.
7. Run `make validate` / `make validate-k8s` / `make validate-argocd` before each PR.

## 6. Validation & rollback

- **Validation:** `ExternalSecret` synced in all three namespaces; `kubectl get httproute -A`
  shows three routes attached `Accepted=True` to the shared gateway; `curl` each of
  `*.dev.crego.ai`, `qa1.dev.crego.ai`, `qa2.dev.crego.ai`.
- **Rollback:** changes are per-namespace and additive; revert the overlay PR and ArgoCD
  re-syncs the prior state. The secret-store conversion is the only ordering-sensitive step
  — do it one env at a time.

## 7. Risks

- Switching `ClusterSecretStore` → `SecretStore` while the old cluster-scoped object still
  exists can briefly leave a dangling reference; delete the old `cloud-sm`
  `ClusterSecretStore` only after all three namespaced stores report healthy.
- Workload Identity bindings must exist for each namespace's `eso-sa` or ESO auth fails —
  this is the most likely failure point; validate per env.

## 8. Open questions

- Should the shared non-prod gateway live in `dev` (status quo) or a neutral `infra`
  namespace (cleaner ownership)? Recommendation: neutral namespace.
- Are `crego-qa1-ip` / `crego-qa2-ip` truly unused, or reserved for a planned split? Confirm
  before releasing.
