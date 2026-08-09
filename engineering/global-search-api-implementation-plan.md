# Global Search API — Implementation Plan (CRE-6199)

**Status:** In progress, paused 2026-08-07 · Companion to `global-search-api-plan.md` (the design
doc this plan verifies and corrects).

## Resume here

**Worktrees** (both created, both on `feature/cre-6199-global-serach-api` off `develop`):

```
crego-omni-wt/cre-6199-global-search    # 2 files modified, uncommitted
crego-flow-wt/cre-6199-global-search    # clean, untouched
```

**Done so far — both blockers from §Blockers, uncommitted:**

| File | Change |
|---|---|
| `project/lib/scope_engine/engine.py` | B2 — `cache_filtered: bool = True` kwarg on `apply()`; the `.exists()` + `values_list` block is now conditional. Default preserves every existing caller. |
| `project/settings/base.py` | B1 — `"search"` added to `MODULE_ENDPOINT_MAP["core"]`, with a comment explaining the TESTING short-circuit trap. Confirmed `compile_valid_patterns` turns this into `^/api/search/`. |

**Prerequisite before any `manage.py` run:** the omni worktree `.env` was copied from
`crego-omni-wt/gl-recon/`, but that file has **no `TENANT_ALIAS`**. Set `TENANT_ALIAS=tyger` in
`crego-omni-wt/cre-6199-global-search/.env` first — `.env` overrides the shell under pipenv, so
exporting the variable is not enough.

**Next step:** finish task 1 — add the `GLOBAL_SEARCH_*` settings to `settings/base.py` and
`"global_search": "60/minute"` to `settings/drf.py`. Note `drf.py` wraps the whole throttle config
in `if not TESTING:` (~line 49), so the new rate goes inside that block and throttling is inert
in tests.

**Remaining order:** Vehicle/User scope rules → registry + service → viewset/serializers → GIN
migrations → Omni tests → Flow scope extraction (its own commit) → Flow `search_tokens` → Flow
search module.

---

## Context

`crego-internal-docs/engineering/global-search-api-plan.md` proposes one search box that finds
any business resource by free text and deep-links to it. Per-service endpoints (`crego-omni`,
`crego-flow`), merged client-side by `crego-web`.

I verified the plan against both codebases. The topology, the API contract, and the
in-DB-over-Elasticsearch call are all sound — ship them as written. But **six technical
assumptions in §4–§7 are wrong**, and two of them are launch blockers that CI cannot catch.
This plan corrects them and specifies the build.

### Verification results

| Plan claim | Verdict |
|---|---|
| Topology, contract shape, in-DB over ES (§3, §6) | ✅ Correct — keep |
| `AdvancedResourceSearchService`, `ModelSearchConfig`, `ScopeEngine`, `flow_scope`, `dashboard/` precedent all exist | ✅ Correct |
| "Extend `AdvancedResourceSearchService`" (§4.1) | ❌ Wrong vehicle — see D1 |
| "`ref_id` already b-tree indexed; use `istartswith`" (§4.6) | ❌ Postgres wraps `istartswith` in `UPPER()`; a plain b-tree cannot serve it |
| "GIN trigram indexes fix the fan-out" (§4.6) | ⚠️ Only for `icontains`. Does **not** help `TrigramSimilarity() >= x`, which is what the existing fuzzy path emits |
| "Sequential fan-out lands ~150–400 ms" (§7.1) | ❌ Ignores the ScopeEngine cascade — see D2 |
| "deep-link URL from `ResourceMeta.endpoint`" (§4.3) | ❌ That field holds API paths, not UI routes |
| Flow: "anchor regexes as prefix to stay index-backed" (§5.7) | ❌ Case-insensitive regex can never use a Mongo index, anchored or not |
| Flow: "equivalent limit in `RateLimitMiddleware`" (§7.2) | ❌ That middleware only covers `/auth/`, `/login`, `/otp`, `/token` |

### Locked decisions

| | Decision |
|---|---|
| Scope | **All 16 types**, incl. adding scope config for Vehicle + User |
| Flow search | **Denormalized `search_tokens`** field, multikey-indexed |
| Deep links | **Frontend owns** the `type → route` map; API returns `{type, id}`, no `url` |
| Audience | **Staff-only in v1**, enforced at the API not just the UI |

---

## Setup — sibling worktrees, one per repo

Both repos are on `develop`; no CRE-6199 branch or worktree exists yet. Branch name is copied from
Linear verbatim, including its `serach` typo.

```bash
git -C /Users/abhishek/Developer/crego/crego-omni worktree add \
  ../crego-omni-wt/cre-6199-global-search -b feature/cre-6199-global-serach-api develop

git -C /Users/abhishek/Developer/crego/crego-flow worktree add \
  ../crego-flow-wt/cre-6199-global-search -b feature/cre-6199-global-serach-api develop
```

Sibling directories under `crego/`, per the workspace convention — matches the 13 existing
`crego-omni-wt/*` worktrees, and `.claude/worktrees/` is not reliably detected by VS Code.
Separate PR per repo, both linked in CRE-6199.

**Omni worktree needs its own `.env`** with `TENANT_ALIAS=tyger` before any `manage.py` runs —
`.env` overrides the shell under pipenv, so copy it from an existing worktree rather than relying
on exported vars. Verify the compose stack points at the right branch before end-to-end checks.

Remove when merged: `git worktree remove ../crego-<repo>-wt/cre-6199-global-search`.

---

## Blockers to fix first

**B1 — `LicenseMiddleware` will 403 `/search/` in every real environment, and every test will pass.**
`apps/core/middlewares.py:13` returns early when `settings.TESTING`; otherwise it 403s any path
not matching a compiled pattern from `MODULE_ENDPOINT_MAP`. `search` is in no module.
→ Add `"search"` to `MODULE_ENDPOINT_MAP["core"]` in `settings/base.py`, **and** add a test that
asserts `/search/` matches `SettingService.compile_valid_patterns()` output with `TESTING` patched off.

**B2 — `ScopeEngine.apply()` eagerly materializes every scoped ID, 16× per search.**
`lib/scope_engine/engine.py:78-84` runs `.exists()` then `list(values_list("id", flat=True))` on
every call. Superusers return early at `:50`, so this is invisible when testing as admin and
appears only for real staff users.
→ Add `cache_filtered: bool = True` to `apply()`; skip the block when false. Default preserves
every existing caller (`lib/views.py:88`). `GlobalSearchService` passes `False`.
Safe because the only consumer — dependent `scope_cache.filtered_*` rules — already lazy-loads on
miss via `ScopeCache.__getattr__` (`cache.py:107`).

---

## D1 — Build `GlobalSearchService` new; do not extend `AdvancedResourceSearchService`

Its param model is `{field: value}` pairs; global search is one term across many fields. Forcing
the fit breaks four ways:

- Each field applies its **declared** lookup, so `contact.json` would emit
  `Q(status__iexact="acme")`, `Q(contact_type__iexact="acme")` — predicates that can never match.
  Any field configured `lookup: "in"` passes a string where a list is required and fails at SQL compile.
- `get_annotated_queryset` adds `Round(TrigramSimilarity(...))` per fuzzy field. That emits
  `similarity(col,'q') >= 0.8`, which **`gin_trgm_ops` does not accelerate** — only the `%` operator
  (Django's `__trigram_similar`) does. Three fuzzy fields in `contact.json` today; 16× per keystroke.
- `build_q_objects` skips operation blocks with `len(matched_fields) <= 1` and ANDs otherwise — meaningless for one term.
- `get_queryset()` wraps everything in `except Exception → BadRequest`, so one bad bucket 400s the
  whole fan-out. Global search needs the opposite: drop the bucket, keep the response.

**Reuse instead:** `ModelSearchConfig` (model + seeder + JSON convention) as an optional
**subtractive** override in phase 2 — a config may only narrow the code-declared field list, never
extend it, so no one can point search at an unindexed column without a deploy.

---

## D2 — The scope cascade is the real latency driver

A role rule referencing `scope_cache.filtered_X` means "first compute every X this user can see".
ScopeEngine runs a second full scoped query and pulls **every ID** into Python. On tyger,
`filtered_accounts` is ~88k integers.

Per-type cost for `staff` (from `lib/scope_engine/config/default_role_scope_config.json`):

| Cost | Types |
|---|---|
| 🟢 Direct (`context.*` or `all: true`) | Contact, Account, Program, Product, PurchaseOrder, JournalVoucher, PostingBatch, Report, GeneratedReport, Transaction |
| 🟡 Cascade via `filtered_programs` (small table) | Invoice, Drawdown |
| 🔴 Cascade via `filtered_accounts` (~88k) | **Payment, Payout** |
| ⛔ No config for any role → `queryset.none()` | **Vehicle, User** |

Role-dependent: Transaction is direct for `staff` but cascades via `filtered_accounts` for
`collection_head` / `collection_agent`.

**v1 mitigation** (Payment/Payout ship, with a documented first-hit cost): `ScopeCache` already
Redis-caches the ID list for 300 s per (tenant, user, role, assignment, model). First search per
user per 5 min pays the materialization; the rest pay ~deserialization. Combined with the
per-bucket statement timeout and drop-bucket-on-timeout, this degrades rather than fails.

**Named follow-up, not in this ticket:** convert `__in: scope_cache.*` in
`ScopeEngine._filter_resolved` (`engine.py:133`) into a correlated subquery instead of a
materialized list. That fixes the cascade for every feature, not just search. Trigger: Payment or
Payout bucket timeout rate > 5%.

---

## Omni implementation

### New scope rules (security-reviewed change, separate commit)

In `lib/scope_engine/config/default_role_scope_config.json`:

- **Vehicle** — `Vehicle.program` FK exists (`apps/invoice/models.py:470`), so mirror PurchaseOrder
  exactly: `{"filter": [{"program_id__in": "context.program_ids"}]}`. Apply to staff,
  collection_head, collection_agent. Leave absent (denied) for customer/anchor/co_lender/counterparty.
- **User** — `{"all": true}` for `staff` only. Leave absent for every other role. Searching the
  user directory is a staff capability; this must be called out explicitly in the PR for review.

### Registry — `apps/core/search_registry.py` (new)

**No model or serializer imports at module scope.** `core` is imported by nearly every app
(`contact/views.py:19`), so a 16-model import-time fan-in is a guaranteed circular import.

```python
@dataclass(frozen=True)
class GlobalSearchResource:
    type: str            # stable API key, e.g. "purchase_order"
    label: str           # "Purchase Orders"
    model_path: str      # "invoice.PurchaseOrder"  -> lazy apps.get_model
    module: str          # MODULE_ENDPOINT_MAP key, for licence gating
    permission: str      # "invoice.view_purchaseorder"
    title_field: str
    subtitle_fields: tuple[str, ...]
    search_fields: tuple[str, ...]

    @cached_property
    def model(self): return apps.get_model(self.model_path)

    def base_queryset(self):
        return self.model._default_manager.all()   # OnlyActiveInstanceManager => soft-delete free
```

**Hard invariant: `search_fields` are local concrete columns only — no `__` traversal.**
No join → no `.distinct()` → `LIMIT` pushes into the index scan → one cheap query per bucket.
Searching Invoice by buyer name is out of scope for v1; it needs a denormalized column.
Enforced by a registry test (below) — the single highest-value test in this plan.

The 16, with search fields:

| type | model | fields |
|---|---|---|
| contact | `contact.Contact` | `name`, `ref_id` |
| account | `product.Account` | `ref_id` |
| program | `product.Program` | `name`, `ref_id` |
| product | `product.Product` | `name`, `ref_id` |
| invoice | `invoice.Invoice` | `ref_id`, `invoice_number` |
| purchase_order | `invoice.PurchaseOrder` | `ref_id`, `po_number` |
| drawdown | `invoice.Drawdown` | `ref_id` |
| vehicle | `invoice.Vehicle` | `ref_id`, `registration_number`, `chasis_number`, `engine_number` |
| payment | `transfer.Payment` | `ref_id`, `payment_utr` |
| payout | `transfer.Payout` | `ref_id`, `payout_utr` |
| transaction | `ctm.Transaction` | `reference` |
| journal_voucher | `gl.JournalVoucher` | `voucher_number`, `reference` |
| posting_batch | `gl.PostingBatch` | `batch_number`, `ref_id` |
| report | `reports.Report` | `name` |
| generated_report | `reports.GeneratedReport` | `filename` |
| user | `authz.User` | `email`, `username` |

`Vehicle.chasis_number` is misspelled in the model (`apps/invoice/models.py:440`). Use verbatim,
with an inline comment so nobody "fixes" it and silently breaks search.
`Transaction.narration` excluded — TextField on the highest-write table; GIN amplification not worth it.

### Service — `apps/core/services/global_search.py` (new)

Per bucket, gates cheapest-first. **Gates 1–3 failing → group absent. Gate 4 returning nothing →
group present with `count: 0`.** That distinction is honest and still leaks no existence.

1. Type in registry and requested
2. `resource.module` in `SettingService.get_license_data()["features"]["allowed_modules"]` — one cached call for all 16
3. `request.user.has_perm(resource.permission)` — role perms already Redis-cached 5 min (`authz/backends.py`)
4. `scope_engine.apply(qs, auth_context, cache_filtered=False)` — **one `ScopeEngine` instance shared
   across all 16 buckets**, so `get_role_scope_config()` is called once and a cascaded ID set is
   computed at most once per request

Then `Q(f1__icontains=q) | Q(f2__icontains=q) | ...`, slice `[:limit+1]`, report
`count = min(len(rows), limit)` and `has_more`. **No `COUNT(*)`** — it would double the query count.

`matched_field` resolved in Python over the ≤6 returned instances (works only because of the
local-columns invariant). Contract must permit `null`.

### Indexes — one `atomic = False` migration per app

```python
AddIndexConcurrently(
    model_name="invoice",
    index=GinIndex(fields=["ref_id"], opclasses=["gin_trgm_ops"],
                   name="invoice_ref_id_trgm_idx",
                   condition=Q(is_deleted=False)),   # matches OnlyActiveInstanceManager
)
```

- **`ref_id` gets a trigram GIN despite `db_index=True`** — the b-tree serves neither `icontains`
  nor `istartswith`. Same for the `unique=True` columns (`Transaction.reference`,
  `Payment.payment_utr`, `Vehicle.registration_number`, `JournalVoucher.voucher_number`).
- **Use `icontains` uniformly.** Never `istartswith` — mixed lookups add cases without adding index paths.
- **Partial index on every `SoftDeleteModel` table** — the planner will use it since
  `_default_manager` always emits that predicate. Smaller index, cheaper writes.
- **Min query length 3, enforced with a 400.** Below 3 chars trigram extraction yields no full
  trigrams and Postgres falls back to a seq scan. Survival rule, not UX polish.
- **Rollout order:** contact / product / invoice / gl / reports first. `transfer` and `ctm` in a
  **separate later migration**, measured — `AddIndexConcurrently` on `ctm_transaction` can run for
  hours per tenant DB, and a failed CONCURRENTLY build leaves an `indisvalid = false` index that is
  silently never used. Add a post-deploy `pg_index.indisvalid` check.
- **`pytest.ini` has `--nomigrations`, so CI never runs these.** Add a job with
  `-o addopts=""` against a scratch DB.

### View, timeouts, throttle

`GlobalSearchViewSet(ViewSet)` in `apps/core/views.py`, following `MISCViewSet` (`:351`), with a
`list()` method so the router yields exactly `GET /search/`.

- `permission_classes = [IsAuthenticated]` — **not** `ViewRestrictedDjangoModelPermissions`.
  `DjangoModelPermissions._queryset()` asserts the view has a queryset; a plain `ViewSet` has none
  and it would `AssertionError` at request time.
- **Staff-only:** reject `customer`-type users at the view with an empty result set (not 403).
- `throttle_scope = "global_search"`; add `"global_search": "60/minute"` to `DEFAULT_THROTTLE_RATES`
  in `settings/drf.py:56`. `ScopedRateThrottle` is already in `DEFAULT_THROTTLE_CLASSES`.
- **Timeout** — add `tenant_statement_timeout(ms)` to `lib/transactions.py`:
  - `SET LOCAL` only works inside a transaction, so the whole search runs in `tenant_atomic()`.
    Bare `SET` would leak across `CONN_MAX_AGE` persistent connections.
  - A timed-out statement aborts the transaction, so **each bucket needs its own
    `tenant_atomic(savepoint=True)`**; catch `OperationalError` → log → drop bucket → continue.
  - Per-statement timeouts cannot bound total latency across 16 buckets. Add a `time.monotonic()`
    wall-clock check between buckets against `GLOBAL_SEARCH_TOTAL_BUDGET_MS`; return `partial: true`.
- **Audit** — reuse the `_log_search_audit` shape (`views.py:1055`) with two departures: one row per
  request (not per object — 16×5 objects per keystroke floods the table), and **do not log `q`**.
  Users type PANs, phone numbers and customer names into a search box; the existing mixin stores
  `request.query_params.dict()` in `before_state`. Log `len(q)` only. Gate behind
  `GLOBAL_SEARCH_AUDIT_ENABLED`.

### Response

Frontend owns routing, so items carry no `url`:

```json
{"query":"...", "partial": false, "took_ms": 142,
 "groups":[{"type":"contact","label":"Contacts","count":2,"has_more":false,
   "items":[{"id":"cnt_x1","type":"contact","title":"Acme Traders",
             "subtitle":"CON-00412 · Active","matched_field":"name"}]}]}
```

One generic `GlobalSearchItemSerializer` over plain dicts in `apps/core/serializers.py` — **not**
8 new MiniSerializers. The output shape is fixed across types, so per-type serializers would need a
mapping layer anyway; the existing ones are the wrong shape (`InvoiceMiniSerializer` declares
`available_amount` from an annotation search won't add) and wiring 8 serializer modules into `core`
drags transitive imports (`transfer/serializers.py` line 1 imports a payment-connector module).

---

## Flow implementation

### `search_tokens` — the only index-backed option

Mongo cannot use an index for a case-insensitive regex, anchored or not. A single lowercased blob
doesn't help either — `^q` would anchor on the blob's start, so only `ref_id` would ever match.

Use a **`ListField(StringField())`**, which gets a **multikey** index where the anchor applies
**per array element**:

```python
{"search_tokens": {"$regex": "^" + re.escape(q.strip().lower())}}   # no $options:"i"
```

Mongo turns `^abc` into index bounds `["abc","abd")` and walks only that range.

Tokens are computed from the **same `store_info` dict** inside the **same `update_one`** in
`RunnerService.sync_runner_store_info()` (`workflow/runner/services.py:417`, already called from six
places). No new write path, no new failure mode — one extra `$set` key.

Tokenizer: for `ref_id` plus every scalar `store_info` value under 200 chars, add the whole
normalized value *and* its `[^0-9a-z]+` parts. Caps: `MAX_TOKENS=64`, `MAX_TOKEN_LEN=64`.
`ref_id` is always present, so no runner is ever unreachable.

**Search all `info.identifiers` keys — no label allowlist.** Labels are free-form per tenant
("PAN", "Pan No", "पैन"); an allowlist would silently drop a tenant's most-searched field. Filter by
value *shape* instead (scalar, non-empty, < 200 chars).

**Semantics traded:** token-**prefix**, not substring. "sharma" matches "Rahul Sharma"; "harma"
does not. Correct for a typeahead. The list page (`/runners/?search=`) keeps substring semantics.

### Scope extraction — highest correctness risk

Search must not re-derive scoping; a copy will drift and a drift here leaks another user's
applications into a dropdown with no other filter to mask it.

Extract from `RunnerService.list()` (`services.py:1111`) into
`build_scope_match(query_params, trace_id) -> RunnerScope`:

| Lines | Concern | Action |
|---|---|---|
| 1141–1170 | customer `$or`, flow scope, `_flow_meta`, `case_matrix_gated_flow_ids`, `parent_runner: None` | **extract** |
| 1172–1186 | `flow_ids` param — mutates `in_scope` *and* `gated` sets | **extract** (cannot live outside) |
| 1188–1220 | `current_node`, `STORE.*`, date filters | **leave in `list()`** — no scope semantics |
| 1222–1300 | assignment gate: gated flows self-restrict, ungated pass | **extract** |

Two ordering hazards:

1. **`$or` key collision.** Block A sets `base_match["$or"]` for customers; block C also assigns
   `base_match["$or"]`. Safe today only because `gated_flow_ids` is always empty for customers.
   Add an explicit assertion so a future edit can't silently clobber it.
2. **The single most dangerous line in the feature.** `list()` already merges search conditions into
   an existing `$or` at lines 1366–1371. Extract that as `_merge_or(base_match, conditions)` and call
   it from both. A naive `base_match["$or"] = token_clause` in search would **widen a customer's
   scope to the whole tenant**.

**Sequencing is non-negotiable:** commit 1 is pure extraction with zero behaviour change, gated on
a golden test comparing `base_match` byte-for-byte against the pre-refactor implementation across
8 personas. Everything else lands after.

### Module, rate limit, timeout

- **`project/search/`** (top level, sibling to `policy/`, `document/`). It owns no model and spans
  two domains. Subclass `BaseAPI` with `super().__init__([])` — empty list, not `DashboardAPI`'s
  fake action name — to inherit the router-prefix convention with honest intent. Plain `def` handler
  per the deliberate threadpool note at `lib/base/apis.py:29-40`.
- Call `has_resource_permission(user, "runner"|"flow", "view")` directly, **not** `_check_permission()`
  which raises 403. Bucket omission must be silent.
- **Rate limit in the service, not middleware.** `RateLimitMiddleware` is unusable: it early-outs on
  `_is_auth_endpoint()`, counts per-IP (wrong behind a LB), and uses a per-process dict (effective
  limit = `N_workers × limit`). Use a Redis fixed-window counter keyed by
  `(db_alias, user_id, minute)`, failing open — the same policy `_get_cached_count` already uses.
- **`maxTimeMS=800` per bucket** (new ground — no existing usage in the repo). On
  `ExecutionTimeout`, return the bucket **empty with `degraded: true`**, not omitted — omission is
  already the wire signal for "no permission".
- **Run buckets sequentially.** Tenant routing rides a ContextVar (`core.db_context`); a manually
  spawned thread would not inherit it and could resolve to the wrong tenant — a cross-tenant leak
  for a ~400 ms saving. If fan-out is ever needed it must use `contextvars.copy_context()`.
- **Flow bucket needs no new index.** The collection is 10²–10³ docs per tenant; a case-insensitive
  regex COLLSCAN is sub-millisecond, and an index couldn't serve it anyway.
- **Deploy order matters:** deploy code → `create_indexes.py` per tenant → `backfill_runner_search_tokens.py`
  per tenant → only then enable the UI. No runtime dual-path fallback; a silent semantic switch
  between token-search and scan-search is a correctness trap.

---

## Files

**crego-omni — create**
- `project/apps/core/search_registry.py`
- `project/apps/core/services/global_search.py`
- Migrations in `contact`, `product`, `invoice`, `gl`, `reports` (phase 1) then `transfer`, `ctm` (phase 2)
- `project/apps/core/tests/test_global_search_{registry,service,api}.py`
- `project/lib/tests/test_scope_engine_cache_flag.py`

**crego-omni — modify**
- `project/lib/scope_engine/engine.py` — `cache_filtered` kwarg on `apply()`
- `project/lib/scope_engine/config/default_role_scope_config.json` — Vehicle + User rules
- `project/lib/transactions.py` — `tenant_statement_timeout()`
- `project/apps/core/{views,urls,serializers}.py`
- `project/settings/base.py` — `MODULE_ENDPOINT_MAP["core"] += ["search"]`, `GLOBAL_SEARCH_*`
- `project/settings/drf.py` — throttle rate

**crego-flow — create**
- `project/search/{__init__,constants,apis,services}.py`
- `project/scripts/backfill_runner_search_tokens.py`
- `project/scripts/test_search_{scope,tokens,api}.py`

**crego-flow — modify**
- `project/workflow/runner/services.py` — `build_scope_match()`, `_merge_or()`, `build_search_tokens()`, `sync_runner_store_info` `$set`
- `project/workflow/runner/models.py` — `search_tokens` field + `{"fields": ["flow", "search_tokens"]}` index
- `project/app.py` — register `SearchAPI`

---

## Verification

**Omni**
```bash
TENANT_ALIAS=tyger pipenv run python manage.py migrate
TENANT_ALIAS=tyger pipenv run python manage.py test apps.core.tests.test_global_search_registry
TENANT_ALIAS=tyger pipenv run python manage.py test apps.core.tests lib.tests.test_scope_engine_cache_flag
```
1. Registry test parametrized over all 16: `apps.get_model` resolves; every `search_fields` name is
   a concrete local field; **no `"__"` in any field name**; every field has a matching `GinIndex` in
   `model._meta.indexes`. This is what stops someone shipping a seq scan.
2. `assertNumQueries` ceiling on a full 16-type search — the N+1 regression guard.
3. `str(qs.query)` contains `ILIKE` and **not** `similarity(` — guards against fuzzy creeping back.
4. Per-role bucket visibility for staff / collection_head / collection_agent, incl. the new
   Vehicle and User rules returning non-empty for staff and empty for others.
5. `EXPLAIN (ANALYZE)` on the tyger compose DB for one query per type — assert
   `Bitmap Index Scan` on the `*_trgm_idx`, not `Seq Scan`.
6. Licence test with `TESTING` patched off asserting `/search/` matches the compiled patterns (B1).
7. Manually via compose: `curl "$OMNI/search/?q=ABCDE1234F"` as staff and as customer.

**Flow**
```bash
cd project && ENV=development pipenv run python scripts/test_search_scope.py
cd project && ENV=development pipenv run python scripts/test_search_tokens.py
ENV=development python scripts/create_indexes.py && python scripts/backfill_runner_search_tokens.py
cd project && ENV=development pipenv run python scripts/test_search_api.py
```
1. Golden `base_match` comparison across 8 personas — proves the extraction commit is a no-op.
2. `db.runners.find({search_tokens:{$regex:"^abc"}}).explain()` shows `IXSCAN` on
   `flow_1_search_tokens_1` with tight bounds, **not `COLLSCAN`**.
3. Adversarial `q` (`.*`, `(((`, `a{1000}`, 100 backslashes) produces a literal-only pattern.
4. `SEARCH_MAX_TIME_MS=1` → empty `degraded` bucket, not a 500.

**End-to-end:** both endpoints against the local compose stack, staff and customer JWTs, response
shapes compared key-for-key between services.

---

## Risks

1. **Scope-extraction regression in Flow = cross-user data leak.** `list()` lines 1222–1300 encode a
   three-way split (gated self-restrict / ungated pass / explicit filters differ per branch). A
   search dropdown has no other filter to mask a mistake. Mitigated only by the
   behaviour-preserving first commit plus the golden test — do not let these merge together.
2. **Payment/Payout will be the slowest thing in the product on tyger.** The 88k
   `filtered_accounts` materialization is inherent to the role-config design, not to search; this
   feature just makes it visible for the first time. Redis (300 s) + statement timeout +
   drop-bucket contain it, but the `_filter_resolved` correlated-subquery fix is the real answer.
   Instrument the per-bucket timeout rate from day one.
3. **GIN build on `ctm_transaction` / `transfer_payment`.** Hours per tenant DB, cannot be
   transactional, and a failed CONCURRENTLY build leaves an invalid index that is silently never
   used. Staged into a separate migration, with a `pg_index.indisvalid` post-deploy check and
   sign-off from the LMS owners on the insert-path cost.
