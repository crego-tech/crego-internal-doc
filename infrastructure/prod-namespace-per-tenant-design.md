# Design: Production Namespace-per-Tenant Isolation

**Status:** Proposal
**Author:** Abhishek (with Claude)
**Date:** 2026-06-18
**Repo:** `crego-infra`
**Scope:** `overlays/prod-gcp`, `apps/prod-gcp`, `base/prod-gcp`, `argocd-apps/prod-gcp`
**Decision input:** Target model = **full stack per tenant** (maximum isolation, accepted higher cost)

---

## 1. Problem statement

Production runs all tenants inside a **single `prod` namespace** with soft, application-level
tenancy. We want **hard isolation per tenant**: each tenant gets its own namespace running a
full application stack, so that a tenant's secrets, network, blast radius, resource quota,
and release cadence are independent. This increases cost, which is accepted.

## 2. Current state (as found)

Prod is a dedicated cluster (`crego-prod-cluster`, project `crego-app-prod`), separate from
the dev cluster. Everything lives in namespace `prod`:

**Shared tier (one copy serves every tenant):**
- `omni-api` (`replicas: 1`), `omni-web`, `flow-api`, `flow-web`, `flower`, `rabbitmq`
- One `ExternalSecret` `app-env`, one `ClusterSecretStore` `cloud-sm`
- One gateway + `httproute.yaml` with wildcard host `*.crego.ai` (host-based routing)

**Per-tenant tier (the only thing differentiated today):**
- `omni-celery-worker-{default,bcpl,credflow}` and matching
  `omni-celery-beat-{default,bcpl,credflow}`, each keyed by `TENANT_ALIAS`
  (e.g. `credflow`) and labelled `tenant: <name>`.
- Tenant data separation via `MONGO_TENANT_DBS` in the shared secret.

So today tenancy = **per-tenant Celery workers + per-tenant Mongo DBs**, sharing one API/web
tier, one secret, one namespace, one network policy domain. (dev mirrors this pattern with
`solfin`, `tyger`, `vayana`, `qa` workers.)

### 2.1 What "single namespace" costs us in isolation

- A bad deploy or resource spike in the shared `omni-api` affects **all** tenants at once.
- All tenants read the **same** `app-env` secret — no per-tenant secret boundary.
- Network policies, RBAC, and quotas are namespace-wide — no per-tenant containment.
- Tenants cannot be rolled out, rolled back, or scaled independently at the API tier.

## 3. Goals / non-goals

**Goals**
- One namespace per tenant (`prod-<tenant>`), each running a complete stack.
- Per-tenant secrets, network policies, RBAC, resource quotas, and routing.
- Independent deploy/rollback/scale per tenant.
- A kustomize layout where **adding a tenant is a small, reviewable overlay**, not a fork.

**Non-goals**
- Separate cluster per tenant (namespaces give the isolation we need at far lower cost).
- Changing the app's tenant-resolution logic or `TENANT_ALIAS` contract.
- Re-platforming Mongo/Postgres tenancy (DB-level separation already exists).

## 4. Target architecture

Each tenant namespace `prod-<tenant>` runs its own:
`omni-api`, `omni-web`, `flow-api`, `flow-web`, `flower`, `omni-celery-worker`,
`omni-celery-beat`, `flow-celery-worker`, `SecretStore`, `ExternalSecret`, `HTTPRoute`,
`NetworkPolicy`, `ServiceAccount`s, and (optionally) `ResourceQuota` / `LimitRange`.

```
prod cluster (crego-prod-cluster)
├── gateway-system (or prod-shared)
│   └── prod-gateway  +  crego-prod-ip   ← ONE shared L7 gateway, host-routed
├── prod-default/     full stack, host default.crego.ai (or app.crego.ai)
├── prod-credflow/    full stack, host credflow.crego.ai
└── prod-bcpl/        full stack, host bcpl.crego.ai
```

Routing stays host-based on a single shared gateway/IP (cheap and already wildcard
`*.crego.ai`); each tenant owns only its `HTTPRoute` for its hostname. Going one-IP-per-tenant
is possible but adds cost with little benefit — recommend shared gateway, per-tenant route.

### 4.1 Critical carry-over from the dev/qa fix

`ClusterSecretStore` is **cluster-scoped**. If each tenant overlay defines a
`ClusterSecretStore` named `cloud-sm`, the tenants will collide exactly like dev/qa1/qa2 do
today. **Use a namespaced `SecretStore` `cloud-sm` per tenant namespace** (see the dev/qa
isolation design doc, §4.1). Each tenant also needs its own `eso-sa` + Workload Identity
binding and ideally its own secret key in GCP Secret Manager
(`app-prod-<tenant>`) so secrets are genuinely isolated.

## 5. Proposed kustomize layout (tenant dimension)

Introduce a per-tenant base + thin per-tenant overlay so a new tenant is ~10 lines.

```
base/prod-tenant/                 # reusable, tenant-agnostic full stack
├── kustomization.yaml            # references apps/* bases, secret-store, networkpolicy
├── externalsecret.yaml
└── secret-store.yaml             # namespaced SecretStore (templated name)

overlays/prod-gcp/
├── _shared/                      # gateway + IP + cluster-wide bits (one ArgoCD app)
│   ├── gateway.yaml
│   └── gcpgatewaypolicy.yaml
├── default/
│   ├── kustomization.yaml        # namespace: prod-default; TENANT_ALIAS=default; sizing
│   └── httproute.yaml            # host: default.crego.ai
├── credflow/
│   ├── kustomization.yaml        # namespace: prod-credflow; TENANT_ALIAS=credflow
│   └── httproute.yaml            # host: credflow.crego.ai
└── bcpl/
    ├── kustomization.yaml        # namespace: prod-bcpl; TENANT_ALIAS=bcpl
    └── httproute.yaml            # host: bcpl.crego.ai
```

A per-tenant overlay is mostly: set `namespace: prod-<tenant>`, set `TENANT_ALIAS`, point
the `SecretStore` at `app-prod-<tenant>`, set replica/CPU sizing, and the tenant hostname.

### 5.1 ArgoCD wiring

Use **app-of-apps** with one Application per tenant (`prod-<tenant>-environment`), all under
the existing `argocd-apps/prod-gcp/` umbrella, plus one `prod-shared` Application for the
gateway. An `ApplicationSet` with a list/git generator over tenant names is the natural
evolution so onboarding a tenant = add a name to the generator list.

## 6. Cost analysis (the accepted tradeoff)

Today the API/web tier is **shared** (≈1× each). Full-stack-per-tenant replicates it **N×**.

| Component                | Today (single ns) | Per-tenant (N tenants) |
|--------------------------|-------------------|------------------------|
| omni-api                 | 1× (replicas 1)   | N×                     |
| omni-web                 | 1×                | N×                     |
| flow-api / flow-web      | 1× each           | N× each                |
| flower                   | 1×                | N×                     |
| celery worker + beat     | already per-tenant| per-tenant (unchanged) |
| rabbitmq                 | 1× shared         | N× (or keep shared)    |
| ExternalSecret / SA / NP | 1 set             | N sets (low cost)      |
| Gateway + static IP      | 1                 | 1 (shared) recommended |

Cost drivers to plan for:
- **Baseline pods scale linearly with tenants.** With 3 tenants the shared tier roughly
  triples. Mitigate with smaller per-tenant requests + HPA/KEDA scale-to-low, and by
  right-sizing `replicas` per tenant (small tenants can run `replicas: 1` minimal CPU).
- **rabbitmq:** decide whether each tenant gets its own broker (stronger isolation, more
  cost) or tenants keep sharing one broker with per-tenant vhosts/queues. Recommendation:
  keep a shared broker initially unless isolation requires otherwise.
- **Per-namespace overhead** (NetworkPolicy, ESO syncs, SAs) is cheap; the real money is the
  replicated API/web pods.
- **Node headroom / cluster autoscaler:** more pods may add nodes — confirm node pool
  autoscaling limits and per-tenant `ResourceQuota` to cap spend.

A rough rule of thumb: cluster app-tier cost scales ≈ **O(number of tenants)** for the
shared tier, vs ≈ O(1) today. Set `ResourceQuota` per tenant namespace so a single tenant
can't consume the whole cluster.

## 7. Migration plan (incremental, zero-downtime)

1. **Land the SecretStore fix first** (namespaced `SecretStore`, per the dev/qa doc) so the
   per-tenant pattern doesn't reintroduce the `cloud-sm` collision.
2. Build `base/prod-tenant/` and the `_shared/` gateway overlay; move the existing gateway +
   `crego-prod-ip` ownership into the `prod-shared` ArgoCD app.
3. **Pilot one tenant** (e.g. `credflow`): create namespace `prod-credflow`, its overlay,
   `app-prod-credflow` secret, `eso-sa` + WI binding, and `HTTPRoute` for
   `credflow.crego.ai`. Deploy alongside the existing shared stack.
4. Cut DNS/host `credflow.crego.ai` to the tenant namespace; validate; keep the shared stack
   as fallback until verified.
5. Repeat for `bcpl`, then `default`. `default` is the wildcard/primary host — migrate last
   and carefully.
6. Once all tenants run in their own namespaces, **decommission** the shared `prod`-namespace
   API/web tier and its per-tenant workers (now duplicated inside tenant namespaces). Remove
   the old worker/beat overlays from `overlays/prod-gcp/kustomization.yaml`.
7. Add per-tenant `ResourceQuota` / `LimitRange` and per-tenant NetworkPolicies
   (default-deny + allow intra-namespace + gateway ingress).

## 8. Validation & rollback

- **Validation per tenant:** `ExternalSecret` `SecretSynced` in `prod-<tenant>`; pods Ready;
  `HTTPRoute` `Accepted=True`; `curl https://<tenant>.crego.ai` returns the tenant's app;
  Celery worker consuming the tenant queue; NetworkPolicy blocks cross-namespace traffic.
- **Rollback:** because each tenant is migrated behind its own hostname while the shared
  stack still exists, rollback = repoint the host back to the shared stack and delete the
  tenant overlay. No other tenant is affected.

## 9. Risks

- **Secret sprawl:** N per-tenant secrets in GCP Secret Manager — manage with
  `scripts/create-secret-json.sh` conventions and a naming standard (`app-prod-<tenant>`).
- **Cost overrun if unbounded:** enforce `ResourceQuota` per namespace and conservative
  per-tenant `replicas`/HPA mins from day one.
- **Cluster-scoped collisions:** any cluster-scoped object copied into per-tenant overlays
  (SecretStore, ClusterRole, gateway) will collide — keep all per-tenant resources
  namespaced; keep shared cluster objects in exactly one `prod-shared` app.
- **`default` tenant + wildcard host:** `*.crego.ai` currently catches everything; ensure
  tenant-specific hostnames take precedence and the wildcard fallback is intentional.

## 10. Open questions

- Shared rabbitmq vs. per-tenant broker — which isolation level is required for compliance?
- One shared gateway/IP (recommended) vs. per-tenant IP — any regulatory need for dedicated
  ingress IPs per tenant?
- Tenant onboarding ownership — manual overlay PR vs. `ApplicationSet` generator automation?
- Per-tenant `ResourceQuota` sizing — need expected load per tenant to set caps.
