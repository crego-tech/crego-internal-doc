# JK Cement security review — internal remediation backlog

**Created:** 2026-07-27
**Client response:** `crego-internal-docs/clients/jkcement/jkcement-security-review-response.md`
**Status:** P0 Linear issues raised 2026-08-12 (P0 target 2026-08-08 **missed**). P1s not yet raised.

| Item | Linear | Title |
|---|---|---|
| P0-1 | [CRE-6237](https://linear.app/crego/issue/CRE-6237) | Trusted-issuer allowlist in Flow JWT validation |
| P0-2 | [CRE-6238](https://linear.app/crego/issue/CRE-6238) | Bind permission cache to token identity |
| P0-3 | [CRE-6239](https://linear.app/crego/issue/CRE-6239) | Make `resource_name` mandatory |
| P0-4 | [CRE-6240](https://linear.app/crego/issue/CRE-6240) | De-privilege the Flow service account |
| P0-5 | [CRE-6241](https://linear.app/crego/issue/CRE-6241) | Pin provisioned profile server-side |
| P0-6 | [CRE-6242](https://linear.app/crego/issue/CRE-6242) | Route-template matching for `no_auth` |

> **P0-1 is still live on `master` and `develop` as of 2026-08-12.** It was re-detected
> independently by the Semgrep SAST job added in CRE-6236
> (`python.jwt.security.unverified-jwt-decode`). The finding is suppressed in
> `crego-flow/.semgrepignore` **only** so that CI is usable — the entry is dated and
> annotated as known-live debt, not a false positive. **Delete that entry when CRE-6237
> ships.**

> **Internal only.** This document contains exploit detail and exact source locations.
> The client-facing response deliberately omits both.

---

## Why the sequencing matters

P0-1 and P0-4 are individually serious. Chained, they are an **unauthenticated path to Omni
administrative operations per tenant**:

```
attacker hosts a JWKS document
  → Flow reads `iss` from the unverified token and fetches keys from it   (P0-1)
  → signature "verifies"; `iss` is checked against itself — tautology     (P0-1)
  → permission cache hit on user_id skips Omni's own rejection            (P0-2)
  → attacker acts as any user, any tenant, any role on Flow
  → Flow calls Omni using ADMIN_USERNAME/ADMIN_PASSWORD (superuser)       (P0-4)
```

Fixing any single link leaves the others reachable — P0-1 without P0-2 leaves the cache
bypass, P0-2 without P0-1 leaves the forgery. **Ship the P0 wave as one release.**

Unrestricted egress (`0.0.0.0/0`, `crego-infra/base/*/networkpolicy.yaml`) is what makes the
first step reachable, which is why the egress allowlist is a security control here and not
hygiene — but it is containment, not a fix.

---

## P0 — authentication bypass chain · target 2026-08-08

### P0-1 · Trusted-issuer allowlist in Flow

**Files:** `crego-flow/project/auth/jwt_validator.py` (82-116, 155-203),
`auth/models.py`, `auth/config.py`, new `auth/issuers.py`, `core/secrets.py`

Current behaviour: `jwt.decode(token, options={"verify_signature": False})` reads `iss`
(line 90) → `_get_public_key(issuer, kid)` → `_fetch_jwks` does
`requests.get(f"{issuer}/.well-known/jwks.json")` (line ~193) → `jwt.decode(..., issuer=issuer,
verify_iss=True)` validates the issuer against the value taken from the same token.
`AuthConfig` has no issuer list.

**Preferred fix — remove the network dependency, don't fence it.** Flow already receives
`JWT_VERIFICATION_KEY` via `envFrom: secretRef: app-env`. Reconstruct the key set locally
using Omni's exact derivation (`crego-omni/project/apps/authz/utils.py:190-212`):
base64 → PEM → `kid = sha256(pem_bytes).hexdigest()[:16]`. This deletes the SSRF primitive
outright.

Order of operations in `validate_token`:
1. `jwt.get_unverified_header` → reject unless `alg in {RS256, ES256}` (kills `alg: none` and
   HS256 key-confusion against the public PEM).
2. Read `iss` from the unverified payload; missing → `MissingClaimError`.
3. **`if issuer not in trusted_issuers: raise InvalidIssuerError`** — before any network call.
4. Resolve the key: static reconstruction first; pinned JWKS URL from config as fallback,
   never derived from the token.
5. `jwt.decode(..., issuer=<canonical allowlist string>, audience=Secrets.JWT_AUDIENCE,
   options={..., "require": ["exp","iat","iss","aud","user_id","tenant"]})`.

If JWKS fetch is retained as a fallback: https only, `allow_redirects=False`,
`timeout=(2.0, 3.0)` (currently a flat `10`), response size cap.

**Config:** `FLOW_TRUSTED_ISSUERS` (required in preprod/prod — add to
`Secrets.REQUIRED_SECRETS`), `FLOW_ALLOW_JWKS_FETCH`, `FLOW_ISSUER_ENFORCE`.
Add all to `.env.example` per CONTRIBUTING.md.

**Rollout — this can 401 the entire platform.**
1. Decode a live token from each environment first and record the exact `iss`. Do not infer it.
2. Ship one release in shadow mode: on mismatch, log `AUTH_ISSUER_NOT_ALLOWLISTED iss=<...>`
   at ERROR and **allow**. Watch for a full release.
3. Deploy the secret and verify in-pod (`kubectl exec ... env | grep FLOW_TRUSTED`) **before**
   rolling the image.
4. Then flip `FLOW_ISSUER_ENFORCE=true`.

**Open question that changes the cost:** is `iss` one-per-environment or per-tenant?
`crego-omni/project/settings/base.py:293` evaluates it at import time when no tenant context
exists, so it should be one-per-environment — which makes the allowlist a single entry and
removes any coupling to tenant onboarding. **Confirm against a live prod token before
choosing.** If it is ever made per-tenant (P1-3), tenant onboarding must append to the
allowlist or the next onboarding silently 401s.

**Tests:** non-allowlisted `iss` → `InvalidIssuerError` **and** `requests.get.call_count == 0`;
`alg: none` rejected; HS256 signed with the public PEM rejected; wrong `aud` rejected; missing
`tenant` rejected; valid token passes.

---

### P0-2 · Bind permission cache to token identity

**Files:** `crego-flow/project/auth/permissions.py` (34, 74-128),
`auth/middleware.py` (85-91), `auth/jwt_validator.py` (119-130)

Cache key is `permissions:user:{user_id}` with a 5-minute TTL. A hit returns cached
permissions and `is_superuser` **without calling Omni at all** — so a token Omni would reject
still resolves the cached user's real authority. Not tenant-scoped either.

Omni sets `JTI_CLAIM: "jti"`, so every access token carries one.

- Surface `jti` and `exp` in `user_attributes` (jwt_validator 119-130).
- Key becomes `permissions:{tenant}:{user_id}:{jti}`; fall back to
  `sha256(token)[:32]` if `jti` is absent — never the raw token, it would land in Redis
  keyspace and `SCAN` output.
- Clamp TTL: `ttl = max(0, min(300, int(exp - time.time()) - 5))`; skip caching if `<= 0`.
  A cache entry must never outlive its token.
- Distinguish rejection from transport failure. `_fetch_from_omni` returns `None` for both
  today. On a 401/403 (`_handle_error` gives `_status_code`), **delete the key** and return
  `None`.

**Performance:** access tokens live 15 minutes, so a jti-scoped 5-minute cache still yields
~3 populated windows per token. Net cost is at most one extra `/users/me/` per user per 15
minutes. Expect a brief Omni spike at rollout as every active session takes the uncached path
once — roll pods gradually.

**Residual gap to document in the PR:** Omni has `TOKEN_BLACKLIST_ENABLED`, but a revoked
token still gets up to 5 minutes of cached permissions. Follow-up: Omni publishes revocations
to Redis, Flow subscribes. Consider a 60s TTL for `is_superuser` in the interim.

**Tests:** two `jti` for one `user_id` → distinct keys; same `user_id` across two tenants →
distinct keys; `exp` 30s out → stored TTL ≤ 25s; `exp` past → nothing cached; Omni 401 → key
deleted.

---

### P0-3 · Make `resource_name` mandatory

**Files:** `crego-flow/project/lib/base/apis.py` (26, 85-86),
`lib/base/permissions.py` (66-112), `workflow/secret/apis.py`

`_check_permission` returns early when `self.resource_name` is unset (line 86). It is unset on
`SecretAPI`, `DesignAPI`, `StoreAPI`, `ActivityAPI`, `ApprovalAPI`, `ChecklistAPI`,
`WareHouseAPI`, `AuditAPI`, `PresetAPI`, `PincodeAPI`, `DocumentStorageAPI`.

**`SecretAPI` is the acute one:** `GET /secrets/` with no check, and `Secret.value` is a plain
`DictField` (`workflow/secret/models.py:7`) holding vendor credentials, unencrypted. **Any
valid tenant JWT — including a customer profile — can read every secret in the tenant.**

- Raise in `BaseAPI.__init__` when `resource_name` is unset, so a new API cannot ship
  unguarded.
- Add the missing `RESOURCE_PERMISSIONS` entries; wire the corresponding Omni permissions.
- Encrypt `Secret.value` at rest — separate follow-up, 2026-08-29, needs a migration and a
  key-management decision.

This also subsumes much of F-2: projecting `params` off the runner response accomplishes
little while `GET /designs/{id}/` returns the whole design to anyone.

---

### P0-4 · De-privilege the Flow service account

**Files:** `crego-flow/project/lib/omni_service_token.py`,
`crego-omni/project/apps/authz/apps.py` (17-46)

Flow mints its service token by logging into Omni as `ADMIN_USERNAME`/`ADMIN_PASSWORD`. That
account is provisioned `is_staff=True, is_superuser=True` per tenant on every `post_migrate`,
with the password re-applied from env — so it cannot be rotated in the database, only in the
secret, and it is currently identical across dev and preprod (shared `app-dev` bundle).

Replace with a per-tenant `flow-service` user, `is_superuser=False`, bound to a role granting
exactly what `omni_api_client.py` needs. **Derive the permission set from every method in that
file** — note `omni_get` allows arbitrary GET paths, so the read scope must be enumerated
deliberately rather than granted broadly.

**Risk:** under-scoping breaks Flow cron jobs (case-matrix escalation scan, notifications).
Enumerate before merging.

---

### P0-5 · Pin provisioned profile server-side

**Files:** `crego-flow/project/workflow/runner/services.py` (206-225),
`lib/omni_api_client.py` (17, 42, 342-375), `lib/base/permissions.py`

`RunnerService.create` reads `data.get("type", "customer")` and
`data.get("create_if_not_exists", True)` from the client body → `TemplateFilters
.get_user_by_contact` → `OmniApiClient.get_user_by_contact` with `use_service_token=True`
(default) → `POST /auth/tokens/impersonate/` as the tenant admin. Omni's `ImpersonateSerializer`
accepts any `ProfileType`, and `TokenImpersonateView` creates the user with it and mints tokens.

**`POST /runners/` with `{"type": "staff", "mobile": "...", "create_if_not_exists": true}`
provisions a staff user.** Caller needs only `add_flow_runner`.

Scope is narrow — `get_user_by_contact` is **not** in `TemplateFilters.get_filters()`, so
designs cannot reach it. Two call sites: `runner/services.py:210-214` and
`workbook/services.py:219-224` (the latter already hardcodes `customer`).

- Hard-pin `user_type="customer"`; delete `type` from the accepted payload (it is not used
  elsewhere — `data` is rebuilt into a fixed dict at services.py:291).
- Derive `create_if_not_exists` server-side: new permission + per-flow
  `allow_user_provisioning`, default `False`.
- Validate against `ALLOWED_PROVISION_PROFILES = {"customer"}` in `omni_api_client` as
  belt-and-braces so a future caller cannot reintroduce it.

**Before merging:** query the Omni audit log for impersonation-created users with
`profile != customer` in the last 90 days (logged at `crego-omni/project/apps/authz/views.py:1093-1096`).
If any exist, gate behind `FLOW_ALLOW_CLIENT_USER_TYPE` for one release.

**Paired Omni change (P1-4)** is where the real fix lives; this is defence in depth.

---

### P0-6 · Route-template matching for `no_auth`

**File:** `crego-flow/project/auth/middleware.py` (143-153, 160-175, 236-239)

`if "no_auth" in path: return True` matches any path segment, including caller-controlled ones.
Against the real route table:

| Crafted path | Reaches | Effect |
|---|---|---|
| `/api/audit/resource/no_auth/<id>/` | `AuditAPI` `/resource/{content_type}/{object_id}/` | **audit log read, unauthenticated** |
| `/api/checklists/runner/<rid>/stage/no_auth/` | free-form `stage` param | unauthenticated |
| `/api/runners/no_auth/execute/` | `/{id}/execute/` with `id="no_auth"` | exempt |
| `/api/pincodes/no_auth/` | `/{pincode}/` | unauthenticated |

Exempt requests get `tenant="default"` (line 162), so these land in the default tenant's DB.

Fix: resolve the matched Starlette route and compare the **template**, not the concrete URL.
A path param can never forge a template. Unmatched route → not exempt.

```
NO_AUTH_ROUTE_TEMPLATES = {
  "/runners/callback/{flow_id}/{node_id}/no_auth/",
  "/runners/runner-callback/{runner_id}/{node_id}/no_auth/",
  "/runners/{id}/no_auth/",
  "/flows/{id}/info/no_auth/",
}
```

Two adjacent cleanups in the same file: `_create_exempt_user` only resolves tenant from Host
when `"callback" in path`, so the other `no_auth` routes silently serve the `default`
tenant — a latent multi-tenant data bug. And `RateLimitMiddleware._is_auth_endpoint` (236-239)
has the same substring smell on `"/token"` — cosmetic, only *adds* rate limiting, fold in.

**Tests:** table of `(path, expected_exempt)` covering all four bypasses above → `False`, and
the four genuine callbacks → `True`. Add the bypass paths as ZAP rules in
`.github/workflows/flow-zap-scan.yml`.

---

## P1 — authorization and isolation · target 2026-08-29

### P1-1 · Object-level ACL on runners

**Files:** new `crego-flow/project/workflow/runner/access.py`,
`workflow/runner/apis.py`, `workflow/runner/services.py` (781-795, 287-289, 997-1090)

`RunnerService.list` already encodes the correct model: customers see
`created_by == uid OR primary_user_id == uid`; superuser/`has_full_access` see everything;
others are scoped to `CaseAssignment`. **`get` and `execute` don't consult it.** The check in
`create` is commented out — and it references `design.users`, a field that does not exist on
`Design`. Delete the dead comment rather than resurrecting it.

Extract one policy object used by both list and detail so they cannot diverge. Lift
`_restricted_to_own_assignments` out of `RunnerService` (781) and `CaseMatrixRuleService`
(35-47) — currently duplicated verbatim.

Routes needing the guard (audited against `_check_permission` call sites):

| Route | Line | Today |
|---|---|---|
| `POST /{id}/execute/` | 176 | **no check at all** |
| `POST /parse_template/` | 547 | **none** — renders caller-supplied Mako against an arbitrary `runner_id` |
| `GET /{id}/activity/` | 409 | **none** |
| `GET /{id}/checklist/` | 569 | **none** |
| `GET /constants/current_nodes/` | 612 | **none** |
| `GET /{id}/`, `/store/`, `/current_state/` | 704, 437, 397 | permission only, no object check |
| `PUT /{id}/update_store/`, `/update_design/` | 448, 421 | permission only, no object check |
| `DELETE /{id}/` | BaseAPI | permission only, no object check |

**Required carve-out, not optional:** case matrix is opt-in per flow
(`flow.case_matrix_enabled`, services.py:311). For flows where it is `False`, **no assignments
exist at all**, so an assignment-based rule denies every non-full-access staff user. Fall back
to the resource permission for those flows.

**Rollout:** `FLOW_ENFORCE_RUNNER_OBJECT_ACL` default `false`; log
`RUNNER_ACL_WOULD_DENY runner=<id> user=<id> reason=<...>` and allow. One full release in
shadow, grep the logs, then flip.

Owner-bypass on `execute`: customers drive their own runner but likely lack
`change_flow_runner`. **Confirm against Omni's customer permission set before merging** — if
they do hold it, drop the bypass.

### P1-2 · Token → tenant binding

**Files:** `crego-omni/project/lib/authentication.py`, `apps/tenancy/middleware.py` (196-209)

Compare the token's `tenant` claim to the resolved tenant in
`ContextAwareJWTAuthentication.authenticate`, after `super().authenticate()` and before
`_attach_context_to_user`. **Not in middleware** — that runs before the token is decoded.

`ENFORCE_TOKEN_TENANT_MATCH` default `false`, log mismatches for one week first.
`_create_token_for_user` swallows exceptions and writes `tenant="default"`, so legitimate
mismatches may exist.

Separately: `_extract_tenant_from_header` honours `X-Tenant-Alias` from **any** caller, and
preprod serves a wildcard host — so an unresolvable Host plus a chosen alias reaches arbitrary
tenant routing. Restrict to in-cluster callers. Flow already targets `OMNI_INTERNAL_HOST`
(`http://omni-api:8000`), so a Host-based restriction needs no Flow change; add a shared
secret later.

### P1-3 · Per-tenant issuer identity

**Files:** `crego-omni/project/settings/base.py` (32-62, 285-308),
`apps/authz/tokens.py`, new `apps/authz/issuers.py`,
`apps/connectors/services/webhooks.py:209`

`SIMPLE_JWT["ISSUER"]` is assigned once at import (base.py:293). Nothing re-assigns it — the
"will be updated dynamically" comment is false. So it freezes to `SERVICE_HOST`.

Implementation detail that matters: `SIMPLE_JWT["TOKEN_BACKEND_CLASS"]` is in simplejwt's
`IMPORT_STRINGS` but **never consumed**. The only working hook is overriding the
`token_backend` property on `authz.tokens.AccessToken` / `RefreshToken`, which is sufficient
because `AUTH_TOKEN_CLASSES` points at our class.

Mint with a **string** issuer (PyJWT raises `TypeError` on a list); accept a **set** on
decode (PyJWT's `_validate_iss` handles `Container[str]`).

Derive the domain from the tenant config, never from the `Host` header.

**Blast radius: every live token.** `LEGACY_JWT_ISSUERS` must accept the old value for one
refresh-token lifetime (3 days) or this is a hard logout of every user plus broken Flow cron.
**Sequence after P1-5** so there is one logout event, not two.

Pre-flight: assert every `TENANT_CONFIG` domain resolves and serves
`/api/auth/.well-known/jwks.json`, or Flow gets an issuer whose JWKS URL 404s.

Note for later: `TokenBackend.encode` emits no `kid` header, so Flow falls through to
`jwks["keys"][0]`. **Key rotation is impossible today.** Emitting `kid` is a prerequisite —
call it out, don't bundle it.

### P1-4 · Split the impersonation endpoint

**Files:** `crego-omni/project/apps/authz/views.py` (1044-1109),
`serializers.py` (444-455), `permissions.py` (6-12), `urls.py`, + migration

Beyond P0-5: `TokenImpersonateView` will mint a token for **any existing user matched by
email, including a superuser**. Django's `has_perm` short-circuits `True` for `is_superuser`
before consulting `RoleBasedPermissionBackend` (`authz/backends.py:53-55`). So
`{"email": "<admin>"}` yields a full-admin bearer token.

**New `POST /auth/users/resolve/`** — what Flow actually needs. Returns only the user
sub-object, **no tokens**. Profile hardcoded to `customer`. Refuses to return a user who is
`is_superuser`/`is_staff` or whose profile is not `customer`. Audit row + throttle.

**Narrow `/auth/tokens/impersonate/`** — drop `create_if_not_exists` and `type`; require a
`reason`; refuse staff/superuser targets; require `RequiresBoundAssignment` (a real human with
a `UserAssignment` — the system token never satisfies this); add an `act` claim; mandatory
`AuditLog` write, not just `logger.info`; gate behind a `SettingService` flag, default off.

**Three deploys, in order:** add resolve → deploy Omni → point Flow at it → deploy Flow →
narrow impersonate. Reversing this breaks Flow.

**Before merging:** Flow templates live in Mongo, not the repo. Grep the template store for
consumers of `.access` on this call.

### P1-5 · Dedicated `app-preprod` secret

**File:** `crego-infra/base/preprod-gcp/externalsecret.yaml:15`

Extracts `key: app-dev` — preprod shares dev's JWT signing keys, `SECRET_KEY`,
`ADMIN_PASSWORD` and DB credentials. `qa1` and `prod` each have their own; preprod is the
outlier.

Verified 2026-07-27: `ENV=preprod` in the pod, so `DEBUG=False` — the universal `123456` OTP
is **not** active. The gap is credential sharing, not debug mode.

**Blast radius: total.** Pre-stage the secret, diff `app-dev` vs `app-preprod` key by key,
maintenance window, leave `app-dev` untouched so rollback is a one-line revert. This rotates
the JWT signing key — absorb one logout, then do P1-3.

### P1-6 · Consent / possession record

**Files:** `crego-omni/project/apps/authz/` — new model, `views.py:905` (`LoginViewSet.verify`),
`OIDCTokenExchangeView`, `permissions.py`

New append-only `ContactVerification`: user FK, channel, `identifier_hash` (HMAC under
`SECRET_KEY` — never raw), masked identifier, `verified_at`, method (`otp`/`oidc`/`manual`),
purpose, consent text version, IP, user agent, request id, `initiated_by`.

Written on every successful `verify_otp` — small addition to existing code. Also cover
`OIDCTokenExchangeView` and `UsernamePasswordLogin` for tenants configured that way (login mode
is per-tenant: `authConfig.login_settings.modes[userType]` ∈ `otp_sms`, `otp_email`,
`username_password`, `oidc_username_password` — see `crego-web/packages/omni-web/src/pages/LoginPage.tsx:181-213`).
Only the OTP modes actually prove possession; the other two must not satisfy the gate.
`/auth/users/resolve/` with `create_if_not_exists` creates the user **unverified** and writes
none.

Note: `AuthContext.initiateLogin` (`contexts/AuthContext.tsx:245-264`) does an OIDC redirect but
is **dead code** — nothing calls it; SSO renders `SSOLogin` instead. Don't reason from it.

Gate PAN/KYC submission with a `RequiresVerifiedContact` permission class **per viewset** —
not a blanket middleware, which would break internal and batch flows.

Backfill `method="legacy"` for every user with a non-null `last_login`; log-only first.

### P1-7 · Remove the hardcoded test OTP

**File:** `crego-omni/project/apps/authz/utils.py` (43-68)

`TEST_OTP_MAP` hardcodes a real mobile number in the repo. Move to a JSON env var. Make
`get_test_otp` return `None` when `ENV == "prod"` — a condition independent of `DEBUG`.
Change `generate_otp`'s `if DEBUG: return "123456"` to an explicit
`if ALLOW_FIXED_OTP and ENV != "prod"`. Add a settings-import assertion that **refuses to
boot** if `ENV == "prod" and ALLOW_FIXED_OTP`. Same for `OTPProvider.send_otp`'s
`if DEBUG: return True`.

Small, low risk, high value. Could ship ahead of the wave.

---

## P2 — disclosure and hardening · target 2026-09-30

### P2-1 · Runner `params` projection

**Files:** `crego-flow/project/workflow/runner/apis.py` (738, 769-770, 938),
`workflow/runner/services.py` (~486)

**The UI does not use it.** Traced: `params` from the runner response reaches exactly three
call sites — `NodeDebugger.jsx:54`, `PageDetails.jsx:44`, `RunnerLayout/index.jsx:89` — all
writing to `NodeContext` (`contexts/NodeContext.jsx:7-10`). **No component reads it back.**
Every `useNode()` consumer destructures only `nodeDesign`. It is dead payload.

(The design editor's `params` — `DesignVisualEditor.jsx:163` `designData?.params?.vendors`,
`DesignParams.jsx` — comes from `GET /designs/{id}/`, a different endpoint. Don't touch it
here; P0-3 covers its authorisation.)

`FLOW_RUNNER_PARAMS_MODE`: `full` → `allowlist` (log stripped keys once per design) → `empty`.

**Do not touch** `executor.py:507,522` — `PARAMS` in the Mako context is server-side and must
stay complete.

Before flipping to `empty`: check access logs for non-browser consumers on `/runners/{id}/`
(partner integrations).

### P2-2 · Error sanitisation

**Files:** `crego-flow/project/lib/omni_api_client.py` (60-68),
`core/exceptions.py`, `operations/api_request.py` (157-158)

`_handle_error` is the single choke point for all 20 call sites. Keep `_status_code` (callers
branch on it); replace the verbatim body with a generic message plus a reference id.

The reference id already exists end to end: `AuditContextMiddleware`
(`core/middlewares/audit.py:44-71`) generates it, sets `request_id_var`, stamps every log line,
and returns it as `X-Request-Id`. No new plumbing.

Also: `generic_exception` returns `str(exc)` — stop. `bad_request`'s `exc.to_dict()` includes
`description` (i.e. `str(e)` from downstream) — suppress when not `DEBUG`.

**Do not change** `api_request._process_response` (209-240): it merges the vendor body into
node output, which flows into `STORE` and edge conditions. Designs depend on it. The boundary
is the HTTP response, not the store.

**Phase 2 (not now):** the execute response's `data` field (`apis.py:238`, `apis.py:511`) is
the other leak vector, but projecting it is genuinely breaking — blocking nodes return `node`
+ `data` the UI renders. Needs per-node `expose_response` opt-in.

Ship behind `FLOW_ERROR_PASSTHROUGH`. Some designs may branch on error text via Mako — grep
the designs collection per tenant first, and log at WARN when a template dereferences `.error`.

### P2-3 · Infra edge and egress

**Files:** `crego-infra/base/preprod-gcp/networkpolicy.yaml`,
`overlays/preprod-gcp/gcpbackendpolicy.yaml`, `overlays/preprod-gcp/httproute.yaml`,
new `terraform/modules/gcp-cloud-armor/`

Four separate PRs. `crego-infra/CONTRIBUTING.md` requires 2 approvals, `CRE-xxx` PR title, and
Environments Affected / Risk Assessment / Rollback Plan filled in. Run `make validate` first.

**Egress allowlist.** `allow-egress-to-managed-services` is `podSelector: {}` + `0.0.0.0/0`,
with the intended rules sitting commented out below — someone started this and reverted. Don't
just uncomment: `to: []` with only ports is still all-destinations. Per-workload policies, not
one catch-all. **Must include `169.254.169.254/32` or Workload Identity and ESO break.** Also
`199.36.153.8/30` for `private.googleapis.com`, kube-dns, intra-namespace, and enumerated
SMS/bureau/Sentry provider ranges.
Deploy to `dev-gcp` first (identical `0.0.0.0/0`), soak 48h with VPC Flow Logs, build the
allowlist from observed flows, then preprod. A missed destination shows up as silent Celery
timeouts, not 500s.

**Cloud Armor.** `dev-gcp` already references `dev-cloud-armor-policy` — which exists in no
manifest and no Terraform, i.e. it was created by hand, which CONTRIBUTING.md prohibits. Add
the Terraform module and import the existing dev policy into state. Preconfigured WAF rulesets
in **preview mode** for a week; rate limit `/api/auth/` tighter than the global rule (the DRF
`10/minute` throttle sits behind the app and still costs a round trip per attempt).
A Service can only be targeted by one `GCPBackendPolicy` — add `securityPolicy` to the existing
`default:` block, don't create parallel objects.

**Hostname allowlist.** Replace `*.preprod.crego.ai` with the ~19 explicit tenant hostnames
(already enumerated in the overlay's celery worker list). This is what enables the
`X-Tenant-Alias` attack in P1-2. Verify the cert map covers each name.

**Move `/flower` off the public route** — currently matched on every wildcard host.

### P2-4 · Sentry propagation

**Files:** `crego-web/packages/omni-web/src/main.tsx` (19-22),
`packages/flow-web/src/main.jsx` (19-26)

`tracePropagationTargets: [/^\//, import.meta.env.VITE_API_ROOT]`. The env var is unset — the
app actually reads `VITE_API_ROOT_OMNI` / `VITE_API_ROOT_FLOW` (`services/baseApi.ts:13`,
`services/flowApi.ts:9`) — so the list collapses to `[/^\//]`, matching every same-origin
request including static assets.

Scope to the two real API roots; `[]` on the customer build. `X-Request-Id` already gives
correlation, so nothing is lost operationally.

### P2-5 · Preprod synthetic-data posture

Operational, not a manifest change — this is what F-8 actually asks for.

Write the rule down (`crego-infra/docs/`, referenced from CONTRIBUTING.md), then enforce it:
cut any prod→preprod copy path in `scripts/` or CI, any GCS policy letting preprod SAs read
prod buckets, any restore-from-prod-backup runbook step. Seed instead: `setup_account` plus a
new `seed_demo_data` generating synthetic contacts/PANs from a fixed seed.

If real data is already there, **truncate and reseed**. A masking pass must also purge
`audit_log.before_state`/`after_state`, `django_celery_results` payloads, Mongo warehouse
collections on the Flow side, uploaded document blobs, and Sentry events already sent — assume
you'll miss one.

Weekly scanner asserting no real-format PII outside the synthetic set.

---

## Test infrastructure

**`crego-flow` has no pytest.** `Pipfile` dev-packages is `pre-commit` only; no `conftest.py`,
`pytest.ini` or `tox.ini`. `.github/workflows/ci.yml` runs **no tests** — only PR-title
validation and lint/scan.

Convention is standalone `project/scripts/test_*.py` calling
`scripts_utils.setup_script_environment()`, plain `assert`, explicit `__main__` block.
`project/scripts/test_request_ip_and_tenant_resolution.py` is the best template — it already
fakes a Starlette request and instantiates `AuthMiddleware.__new__(AuthMiddleware)` without a
live DB. Reuse that harness for P0-1, P0-2 and P0-6.

1. Write the scripts in the existing style so they run today.
2. Add a `security-tests` CI job with an **explicit allowlist** — most existing `test_*.py`
   need live Mongo/Omni, so don't glob.
3. Follow-up: add pytest to `[dev-packages]`, create `project/tests/`, port the hermetic
   scripts. CONTRIBUTING.md requires "a regression test that would have caught the bug" for
   every fix — that requirement is currently unenforceable.

`crego-omni` has pytest (`DJANGO_SETTINGS_MODULE=project.settings.test`). Note the suite was
red on both branches for weeks and was only fixed 2026-07-27 (PR #1476) — baseline against the
parent before claiming a clean run.

---

## Feature flags

All default-safe, all removable after their shadow period:

`FLOW_ISSUER_ENFORCE` · `FLOW_ALLOW_JWKS_FETCH` · `FLOW_ENFORCE_RUNNER_OBJECT_ACL` ·
`FLOW_ALLOW_CLIENT_USER_TYPE` · `FLOW_ERROR_PASSTHROUGH` · `FLOW_RUNNER_PARAMS_MODE` ·
`ENFORCE_TOKEN_TENANT_MATCH` · `LEGACY_JWT_ISSUERS` · `ALLOW_FIXED_OTP`

---

## Open items

1. **Confirm the three target dates against actual capacity** before the response goes out.
   They are currently proposals.
2. **Decode a live prod token and record the exact `iss`.** P0-1 depends on it, and it decides
   whether the allowlist is one entry or per-tenant.
3. **Query the Omni audit log** for impersonation-created users with `profile != customer` in
   the last 90 days, before P0-5.
4. **Log review for P0-1 exploitation** — anomalous `iss` values in Flow auth logs. We
   committed to reporting the outcome to the client.
5. **Grep the Mongo template store** for `.access` consumers before P1-4 removes tokens from
   the resolve path.
6. **Decide who signs the response** and whether it goes via the existing VAPT channel
   (`crego-internal-docs/compliance/v2-vapt-reports/`).
7. **Raise Linear issues** — P0-1 … P0-6 each warrant their own CRE-xxx, labelled
   `type/bug`, `found-in/preprod`, `client/jkcement`, `release-blocker` for the P0 wave.
