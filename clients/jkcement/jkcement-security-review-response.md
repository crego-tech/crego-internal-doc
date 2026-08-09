# Crego response — JK Cement API security review

**Scope:** `POST /flow/api/runners/`, `POST /flow/api/runners/{id}/execute/` · `jkcement.preprod.crego.ai`
**Date:** 2026-07-29

---

## Summary

Thank you for the review. We traced every finding to source and verified each one against the
live pre-production environment rather than answering from design intent.

Five findings we confirm outright: F-2, F-5, F-6, F-7, F-9. Three rest on a premise we need to
correct — F-1, F-4 and F-8 — though in two of those cases your underlying concern still holds and
we are acting on it. F-3 is half right, and the half you missed is worse than the half you found.

The review also prompted a full internal audit of the same path. It surfaced six issues you did
not, one of them more serious than anything in your report. All six are in Section 2, with dates.

---

## 1. Findings

| ID | Your severity | Our assessment | Status | Fix by |
|---|---|---|---|---|
| F-1 | Critical | High | Premise corrected | 2026-08-08 |
| F-2 | Critical | Critical | Confirmed | 2026-08-29 |
| F-3 | High | Critical | Corrected + escalated | 2026-08-08 |
| F-4 | High | — | Clarified | — |
| F-5 | High | High | Confirmed | 2026-08-29 |
| F-6 | Medium | Medium | Confirmed | 2026-09-30 |
| F-7 | Medium | **Critical** | Confirmed + escalated | 2026-08-08 |
| F-8 | Medium | Medium | Premise corrected | 2026-08-29 |
| F-9 | Low | Low | Confirmed | 2026-09-30 |

---

### F-1 — Superuser token · Premise corrected

The captured token is an internal admin console session, not the customer journey. Customers
authenticate with an SMS or email OTP — the method is configured per tenant, with reCAPTCHA on the
OTP request — and hold no administrative credential. Their role is separate and least-privileged.

Your point does land elsewhere, on a path your capture could not see. Our Flow service
authenticates to the Omni platform as an administrator. Same least-privilege failure, service side
rather than user side.

**Fix:** dedicated non-admin service account, scoped to what Flow actually does. **2026-08-08.**

---

### F-2 — Decisioning internals exposed · Confirmed

Accurate as written. The Execute response does return vendor mapping, API roots and internal
template and policy identifiers.

The fix is wider than the response body. The same configuration is reachable through adjacent
endpoints that are insufficiently authorised (A-2 below), so trimming the response alone would
leave the data exposed. We are doing both together.

**Fix:** restrict the response to the fields the UI consumes; authorise the config endpoints;
encrypt stored integration credentials. **2026-08-08** (authorisation), **2026-08-29** (response).

---

### F-3 — Client-supplied parameters · Corrected, and escalated

`params`, `approvalMode`, `prefillMode` and `showPreapprovedOffers` are not accepted from the
client. They live in the server-side flow design and are read from there. They appear in the
exchange because they are in the *response* — which is F-2, not mass assignment. Submitting
`approvalMode: manual` changes nothing; please verify that directly.

You were right about mass assignment, but on different fields. `type` and `create_if_not_exists`
*are* honoured from the client, and both feed an internal user-provisioning call made under our
service principal. A caller permitted only to create a runner can provision a user account with a
profile of their choosing. That is privilege escalation, and it is more serious than the finding
as written.

**Fix:** pin the profile server-side, remove `type` from the accepted payload, gate on-behalf-of
creation behind an explicit permission, and stop the resolve path issuing credentials.
**2026-08-08.**

---

### F-4 — Object-level and tenant authorization · Clarified

**Object level.** Runner access is governed by the flow design. Each step in a flow is gated by
the roles defined on that step, customer included, so a caller only reaches the steps their role
permits on the applications that role is entitled to.

**Tenant isolation.** Enforced at the data layer rather than the token layer. Each tenant runs on
a separate database, so a request carrying one tenant's context cannot read another tenant's
records.

Please run your cross-user and cross-tenant tests. Separately, and independent of this finding, we
are removing a weakness in the key material that isolation currently sits alongside — see A-6.

---

### F-5 — No possession check before PAN · Confirmed

Two paths, and they behave differently.

A customer starting their own application has already proven possession: login is SMS or email
OTP, so the mobile is verified before they reach the journey.

The API does not require it. A runner can be created against an arbitrary mobile with
auto-creation and no possession proof, and nothing records that a check ever took place. An
assisted or agent-driven application can therefore be raised against a third party's mobile. That
is the case you describe and it is not currently prevented.

We also checked whether our fixed non-production OTP could be live in pre-production. It is not —
OTPs there are randomly generated.

**Fix:** an auditable verification record written on every successful OTP login, and possession
required before PAN submission and before any automated decisioning. For assisted journeys the
sequence becomes: resolve unverified → OTP to the customer → verified → documents unblocked.
**2026-08-29.**

---

### F-6 — Vendor errors leaked · Confirmed

Downstream error bodies and status codes are returned substantially verbatim. Your availability
point is fair too — vendor credit exhaustion should not have quietly blocked onboarding, and we
should have known before you did.

**Fix:** log the detail server-side and return a generic message with a correlation reference;
alerting on vendor quotas ahead of exhaustion. **2026-08-29** (alerting), **2026-09-30**
(sanitisation).

---

### F-7 — Issuer / host mismatch · Confirmed. Raising to Critical.

Not a naming convention — a defect. In pre-production a single service fronts several tenants, and
the issuer is computed once at process start, before any tenant context exists. It therefore
resolves to a default host and is stamped on every tenant's tokens. Production deploys each tenant
in its own pod, so the process-level defect does not arise there.

You asked whether `iss` and `aud` are strictly validated. The answer differs by service:

- **Omni platform: yes.** Signature, expiry, issuer and audience all verified.
- **Flow service: audience yes, issuer effectively no.** Flow reads the issuer out of the token,
  fetches signing keys from it, then checks the token's issuer against the value it took from that
  same token. There is no allowlist of trusted issuers.

That is a genuine authentication weakness and now our highest-priority item. Full detail in A-1.

**Fix:** trusted-issuer allowlist evaluated before any key retrieval; keys from configuration
rather than from the token; algorithm pinning. **2026-08-08.**

---

### F-8 — Real PII in preprod · Premise corrected, concern confirmed

Pre-production is not running relaxed controls. We verified against the live environment that it
is configured as `preprod` with debug off, and that production authentication, CSRF, CORS and OTP
behaviour all apply. Local-development shortcuts are not active there.

Your concern still stands, for reasons the capture could not show. Pre-production draws
configuration from the same secret bundle as development, so it shares signing keys and admin
credentials with a lower-trust environment. It has no WAF or rate limiting at the edge, where
development does. It is served on a wildcard hostname, and its outbound network access is
unrestricted.

The mechanism differs from the one you described, but the conclusion — preprod should not process
real personal data under these controls — is one we accept.

**Fix:** dedicated preprod secrets with independent key material; WAF and rate limiting; explicit
hostname allowlist; restricted egress; a written synthetic-data policy backed by a recurring scan.
We will confirm separately, in writing, the disposition of the real data currently held there.
**2026-08-29** (secret separation), **2026-09-30** (edge controls, data policy, disposition).

---

### F-9 — Sentry telemetry · Confirmed

Trace propagation matches every same-origin request, so the headers attach to all customer API
calls. Your severity is right.

**Fix:** scope propagation to explicit API origins and disable it on the customer build. We retain
correlation through our own request-ID header, so nothing is lost operationally. **2026-09-30.**

---

## 2. Additional items found by Crego

Not in your report. Disclosed in full.

### A-1 — Unvalidated token issuer in Flow · Critical

Expanding F-7. Flow decides which signing keys to trust *from the token it is validating*. It
reads the issuer before verifying anything, fetches the keys that issuer publishes, verifies the
signature against them, then confirms the issuer matches — against the value from the same token.
The check is circular. There is no trusted-issuer allowlist, and outbound network access is
unrestricted.

**Impact:** a party able to publish a key set at a network-reachable location could present a
token Flow accepts, for any tenant and any role. Combined with A-3 this could reach administrative
operations on Omni.

**Mitigating:** it requires hosting reachable content plus knowledge of our token structure and
audience value. No evidence of exploitation. Log review is underway and we will report the outcome
either way.

**Fix:** allowlist evaluated before any key retrieval; keys from configuration, which removes the
network dependency entirely; algorithm pinning. **2026-08-08.**

### A-2 — Authorisation silently skipped · Critical

Our permission helper returns success when an endpoint has not declared which resource it governs.
Several endpoints never declare it — including one that exposes stored integration configuration —
so the check passes unconditionally. Any valid tenant token, a customer's included, can read them.
Those credentials are not encrypted at rest.

**Fix:** declaration becomes mandatory and is enforced at startup, so an undeclared endpoint cannot
ship; missing permissions added; encryption at rest. **2026-08-08** (authorisation), **2026-08-29**
(encryption).

### A-3 — Flow holds admin credentials on Omni · High

Service-to-service calls authenticate as an Omni administrator, provisioned per tenant. This is the
least-privilege failure behind F-1, on the service path.

**Fix:** dedicated non-admin service account per tenant. **2026-08-08.**

### A-4 — Permission cache not bound to token · High

Authorisation decisions are cached against the user ID alone for five minutes. A cache hit bypasses
the platform's own verification, so a token the platform would reject can still resolve that user's
permissions. This is what makes A-1 exploitable rather than self-limiting.

**Fix:** cache keyed to the specific token and tenant, lifetime bounded by token expiry,
invalidated on rejection. **2026-08-08.**

### A-5 — Authentication exemption matched too broadly · Medium

Public callback routes are exempted by matching a marker substring anywhere in the path. Because
the path includes caller-controlled segments, a request can be crafted to reach certain endpoints
unauthenticated.

**Fix:** exemption by exact route definition. **2026-08-08.**

### A-6 — Shared signing key across environments · High

One JWT signing key per environment, and pre-production shares key material with development —
`demo.preprod` and `jkcement.preprod` publish an identical key, which we verified. Nothing compares
the token's tenant claim to the host addressed. Database separation holds tenants apart today
(F-4), but we are not willing to leave that as the only thing doing so.

**Fix:** independent key material per environment; tenant-aware issuer; reject tokens whose tenant
claim does not match the host. **2026-08-29.**

---

## 3. Schedule and assurance

| Wave | Scope | By |
|---|---|---|
| 1 | F-3, A-1, A-2, A-3, A-4, A-5 — the authentication and privilege chain | **2026-08-08** |
| 2 | F-2, F-5, F-8, A-6 | **2026-08-29** |
| 3 | F-6, F-9, F-8 (edge controls and data policy) | **2026-09-30** |

Wave 1 ships as a single release. The items form one chain and fixing any of them in isolation
leaves the rest reachable.

We commit to the following:

1. A regression test with every fix, failing against current code and added to CI, so none of these
   can silently return.
2. Written confirmation at the close of each wave. Retesting is welcome after any of them.
3. Reporting the outcome of the A-1 log review.
4. Confirming separately the disposition of real personal data in pre-production and the interim
   controls applied to it.

We are happy to walk your team through any of this, including the three findings whose premise we
have corrected. We would rather you satisfy yourselves on the mechanism than take our word for it.

---

*Crego Engineering · 2026-07-29*
