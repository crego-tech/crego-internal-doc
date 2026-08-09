# Universal View — Module Plan (Omni FE + BE)

Status: Draft v1 · 2026-08-05 · Owner: Abhishek
Scope: Schema-driven resource views for Omni — listing (filters/search/ordering/summary), detail views (hyperlink+tooltip, card, sidebar, full page), JSON-schema forms, customizable home page. AI-driven view editing is **Phase 4**, not v1.

---

## 1. Concept (from design notes)

A single, generic rendering system where every resource (Contact, Application, Loan/Account, Payment, Payout, Program, and sub-resources like Address, Bank, GL Entry, Txns, Schedule & Demand) is described by JSON — schema + view config — and the frontend renders list/detail/form views from that JSON instead of hand-built pages.

- **4 detail render modes**: hyperlink + tooltip → card → sidebar full view → full page. Extensible per module.
- **Listing**: filters, search, summary view, ordering — config-driven columns (hyperlink, chip, date, dynamic row, mini resource, nested table).
- **View config is data**: prefixed per resource-view, changeable on the fly (manually in v1, by AI later) to give user-specific views.
- **One view may compose multiple APIs** (e.g., Loan detail pulls schedule + demands + GL).
- **Forms**: JSON Schema + JSON Logic (dependencies, dynamic selects) + JSON-driven React rendering + escape hatch for custom resources.
- **Home page**: customizable dashboard (aggregate loan view, collection efficiency, overdue loans, pending payments).
- **Bar**: full-grade SaaS — enriched, customizable, visually modern (shadcn).

---

## 2. What already exists (build on it, don't rebuild)

The investigation found the platform is already ~60–70% of the way there. The module's job is to **close the loop**, not re-derive schema.

### Backend (crego-omni)

| Capability | Existing asset |
|---|---|
| Per-resource schema catalogue | `ResourceMeta` (`core/models.py:728`, `core/registry.py`, `GET /resource-metadata/`) — schema.fields (typed, choices, relations, `sensitive`, `hidden`), `listing_fields`, `filter_fields`, `sortable_fields`, `mini_fields`, `actions` (+permission codes, bulk flags), `statuses`, `transitions`, `endpoint`, `is_approval_enabled`, `metadata_hash` |
| Dynamic search/filter config | `ModelSearchConfig` + `AdvancedSearchMixin` (`GET /{resource}/search/`), fuzzy via pg_trgm, self/related/props modes, documented FE contract (`docs/model-search-config-frontend-integration.md`) |
| Generic list APIs | `BaseViewSet` on every resource: django-filter, `?search=`, ordering, `?expand=`/`?omit=` (drf-flex-fields), `BootstrapPagination`, CSV/PDF/Excel renderers, generic `bulk_actions` |
| Permissions | `ViewRestrictedDjangoModelPermissions` (`view_<model>` on GET) + Role/Group framework + **ScopeEngine** row-level filtering (defaults to `.none()` for unconfigured models) |
| JSON Schema precedent | `jsonschema==4.23` dep; `workflow` form nodes; `addon/schemas/*.json`; `json-logic` + `lib/condition_evaluator.py` |
| Per-user prefs precedent | `notifications.UserPreference`; tenant `Setting` JSON blobs (incl. `flags_settings`, `ui_settings`) |
| EAV / custom fields | `Props` per entity + generic props endpoints |

### Frontend (crego-web / omni-web)

| Capability | Existing asset |
|---|---|
| Generic table | `components/common/DataTable/` — typed columns (`text/currency/date/status/link/chip…`), server pagination, multi-sort, URL-synced filters, row selection + bulk bar, expandable rows, virtualization, per-column `permission`/`module` gating |
| Filters | `ListControls` + `FilterConfig`/`FilterField` types + `useFilters` (incl. server-persisted "set as default") |
| JSON-schema forms | RJSF 6 beta wrapper `components/rjsf/FormView.tsx` + ~20 custom widgets (entity selectors, amount, async select) + `shared/components/RjsfEditor` (schema builder UI) + `JsonLogicBuilder` |
| Detail rendering | `DetailPreview`/`DetailCard` (generic recursive), `EntityInfoPopover` (hover chip — this *is* the hyperlink+tooltip mode), `DetailPageHeader`/`DetailPageContent`, `EntitySnapshotViewer` (already renders entities purely from `ResourceMeta.schema`) |
| ResourceMeta client | `shared/types/resourceMeta.ts`, `shared/hooks/useMeta.ts` (staleTime Infinity), `shared/lib/resourceMeta.ts` |
| Dashboard | `modules/dashboard/` — config-driven cards, 12-col DnD grid, path-resolver for card data, localStorage layout |
| Prefs persistence | `DefaultsContext` → server `Setting.api_settings` blob (PATCH + invalidate) |
| Theming/labels | shadcn New York + Tailwind v4 tokens, tenant brand settings, `UIDict` per-tenant label overrides |

**Gap analysis — genuinely new surface:**

1. No saved-views / column-layout / view-definition model anywhere (BE or FE).
2. DataTable has no column visibility/reorder/persistence UI.
3. Nothing generates a page from `ResourceMeta` today (only approvals snapshot viewer).
4. No generic form-definition model (JSON Schema exists only inside workflow/addon).
5. Dashboard layout persistence is localStorage-only; a second dashboard would collide with `modules/dashboard` and the mosaic widgets/pins scaffold (`packages/mosaic-web`, scaffold branch `feature/cre-5479-mosaic-scaffold`).

---

## 3. Key decisions

### D1 — DRF vs alternative → **Keep DRF**

The notes ask this explicitly. Answer: DRF. Every gate the platform enforces (ScopeEngine, `ViewRestrictedDjangoModelPermissions`, ResourceMeta action validation, LicenseMiddleware, maker-checker, audit, flex-fields expand, renderers, throttles) is wired through `BaseViewSet`/`BaseSerializer`. An alternative (GraphQL, a custom query endpoint) would bypass all four security gates and need them reimplemented — the single biggest way to *fail* SaaS-grade. Universal View therefore consumes **existing resource endpoints** for data; it only adds new endpoints for view definitions.

"Single view → multiple APIs" is solved client-side: parallel react-query calls per section + `?expand=` for embedded relations. No BFF/aggregator in v1 (revisit only if waterfalls hurt; see R-P4).

### D2 — FE placement → **Module inside omni-web** (`packages/omni-web/src/modules/universal-view/`)

Not a new package. Rationale: DataTable, filters, RJSF widgets, entity registry, permissions/license contexts are all omni-local; a separate package forks ~3k LOC or forces a risky promotion of DataTable to `shared/`. Keep the module boundary clean (own `api/ queries/ renderer/ types/`), promote pieces to `shared/` opportunistically. Coordinate with mosaic before building the home-page piece (§5.4).

### D3 — BE placement → **New Django app** `project/apps/uview/`

Independent module per platform convention: own `PROJECT_APPS` entry, `urls.py`, `MODULE_ENDPOINT_MAP` entry (licensable), seeders, README. It stores *view definitions*, not data.

### D4 — View config is layered, versioned JSON

Resolution order (most specific wins, per key): **system default (code-seeded) → tenant override → role override → user override**. Every stored config carries `schema_version` + the `metadata_hash` of the ResourceMeta it was authored against, so stale configs are detectable.

---

## 4. Backend design (`uview` app)

### Models (all extend `BaseModel`/`SoftDeleteModel`, status enums not `is_active`)

- **`ViewDefinition`** — `resource_name` (FK-by-name to ResourceMeta), `view_type` enum (`listing | card | sidebar | page | tooltip | form | dashboard`), `code` (slug), `scope` enum (`system | tenant | role | user`) + `role` FK / `user` FK nullable, `config` JSON (validated against a versioned JSON Schema in `uview/schemas/view_config.v1.json`), `schema_version`, `source_metadata_hash`, `status` (`draft | active | archived`), `is_default`.
- **`SavedFilter`** — `resource_name`, `name`, `owner` (user), `visibility` (`private | role | tenant`), `filters` JSON (serialized in the same shape `useFilters` produces), `search`, `ordering`.
- **`HomePageConfig`** — `scope` (system/role/user), `layout` JSON (grid of card refs), reuse dashboard card registry; supersedes localStorage layout.
- (Phase 2) **`FormDefinition`** — `resource_name`, `mode` (`create | edit | action:<name>`), `json_schema`, `ui_schema`, `logic` (json-logic rules for dependencies/visibility), versioned like ViewDefinition.

### API

- `/uview/view-definitions/` — CRUD via `BaseViewSet` + `UViewService`; write of `system`-scope restricted to superuser/admin permission; user-scope writes restricted to `request.user`.
- `GET /uview/view-definitions/resolve/?resource=<name>&view_type=<t>` — merges the layer stack for the caller's context (`request.context` role/assignment), returns final config + `resource_meta_hash` + validity report (fields referenced but missing from current ResourceMeta). Cached (tenant-aware Redis) keyed by `(tenant, resource, view_type, role, user, ViewDefinition.updated_at max)`; invalidated in service `create/update/delete` and by `seed_resource_metadata`.
- `/uview/saved-filters/`, `/uview/home-pages/` — standard CRUD.
- Seed command `seed_uview_defaults` — generates a sane default listing/card/page config per ResourceMeta (from `listing_fields`/`mini_fields`) so every resource works day one with zero authoring; added to `setup_account` and run per tenant.

### Platform compliance checklist (each is a silent blocker if missed)

1. `PROJECT_APPS` + `project/urls.py` registration.
2. `MODULE_ENDPOINT_MAP` + `.env.modules.json` — else LicenseMiddleware 403s everything.
3. **ScopeEngine config for `ViewDefinition`/`SavedFilter`/`HomePageConfig`** — else non-superusers get `.none()`. User-scope rows need a `self` scope; system/tenant rows need `all` read.
4. `seed_resource_metadata` after adding models; `{Model}Action` enums in `constants.py`; `status_config.py` transition graph.
5. `tenant_atomic()` only; async via `TaskService.invoke` inside `tenant_on_commit`.
6. Read/Write serializer split; services own persistence; tests (pytest APITestCase, tenant isolation asserted).

---

## 5. Frontend design (`modules/universal-view/`)

### 5.1 View config contract (TypeScript + JSON Schema, shared shape with BE)

```
ListingViewConfig {
  columns: [{ field, label?, type?, render?: rendererId, width, align,
              link?: {resource, idField}, chip?: {statusMapping}, permission? }]
  filters: FilterField[]        // reuse existing FilterConfig shape
  defaultOrdering, pageSize, summary?: {metrics[]}, rowActions: actionRefs[]
}
DetailViewConfig {
  mode: tooltip|card|sidebar|page
  sections: [{ title, cols, items: [{field|composite, renderer?}],
               source?: {endpoint, params, expand} }]   // multi-API composition
  headerFields, relatedTabs: [{resource, filterBy}]
}
```

Renderer ids map to a **whitelisted registry** (no arbitrary components/eval — see R-S2). `zod` validates configs on load; invalid/unknown fields degrade gracefully (skip + console/Sentry warn), never crash the page.

### 5.2 Components

- **`<UniversalList resource code?>`** — resolves config, feeds existing `DataTable` (columns built from config × `ResourceMeta.schema` types × per-column `permission_code`), `apiConfig.endpoint` from ResourceMeta. New work: column show/hide/reorder popover + persistence via `DefaultsContext` (server-side; drop localStorage), saved-filter picker backed by `SavedFilter` API, summary strip.
- **`<UniversalDetail resource id mode>`** — one renderer, four shells: tooltip → extend `EntityInfoPopover`; card → `DetailCard`; sidebar → shadcn `Sheet`; page → `DetailPageHeader/Content`. Sections with their own `source` fetch in parallel (react-query), each with its own skeleton/error/empty state (skeleton-first per the notes; dashboard skeleton convention).
- **`<UniversalForm resource mode>`** — RJSF `FormView` fed by `FormDefinition` (fallback: auto-generate schema from `ResourceMeta.schema.fields`), json-logic evaluated for field visibility/requiredness/dynamic selects (dependency chains via existing entity-selector widgets).
- **Home page** — reuse `DashboardGrid` + card registry; layout read/written through `HomePageConfig` API instead of localStorage.
- **Admin/author UI** (Phase 3) — view editor built on `RjsfEditor`/`SchemaBuilder` + live preview; this is also the surface AI will drive in Phase 4 (AI emits the same JSON, human approves — maker-checker on `ViewDefinition` if needed).

### 5.3 Routing & gating

`/u/:resource` (list) and `/u/:resource/:id` (detail) inside omni router, wrapped `withLicence(Modules.UVIEW)` + `withPermission` derived per resource from ResourceMeta permission codes. Existing hand-built modules keep working; migrate one resource at a time behind the license flag.

### 5.4 Mosaic collision

`packages/mosaic-web` scaffold targets AI-composed widgets/pins — overlapping the "customizable home page". Resolve before Phase 3: either Universal View's `HomePageConfig` becomes mosaic's persistence layer, or the home-page scope moves to mosaic entirely. Do not ship two dashboard systems.

---

## 6. SaaS-grade nuances & blockers (the risk register)

### Security — highest severity

- **R-S1 · Field-level exposure is server-side or it's nothing.** ResourceMeta marks fields `sensitive`/`hidden`, but a view config that omits a column doesn't stop the API returning it, and `?expand=`/`?omit=` are caller-controlled. Hiding in UI ≠ protection. Mitigation: enforce sensitive-field stripping in `BaseSerializer` per role (server), treat view config as presentation only. Without this, "user-customizable views" becomes a data-leak feature.
- **R-S2 · Config injection / XSS.** View JSON drives rendering; `link` targets, templates, and labels are tenant/user-authored data. Never eval, never `dangerouslySetInnerHTML`, renderer registry is a closed whitelist, URLs restricted to internal route patterns. Validate config server-side against `view_config.v1.json` on write.
- **R-S3 · Filter-based exfiltration.** django-filter + ModelSearchConfig allow related-field lookups (`contact__pan__icontains`). A user without permission on Contact can binary-search values through a Loan list filter. Mitigation: filterable fields resolved against the caller's permissions at query time, not just at config time; audit advanced searches (already partially done via `AdvancedSearchMixin` audit events).
- **R-S4 · Shared views ≠ shared data.** A role-scoped ViewDefinition must never widen data access — ScopeEngine still applies per caller. Also: user-scope configs must be writable only by their owner (service-level check, not just queryset filter).
- **R-S5 · ScopeEngine `.none()` default.** New `uview` models unseen in role scope config render the whole module blank for non-superusers — ship scope config + seeder together, add an integration test per role.

### Performance & scale

- **R-P1 · Arbitrary columns → N+1 and unindexed queries.** Config-chosen columns/orderings hit fields with no index or force per-row joins. Mitigation: allowed sort/filter fields constrained to `ResourceMeta.sortable_fields`/`filter_fields` (indexed by convention); `resolve` endpoint annotates required `expand` so a single request fetches embedded relations via flex-fields prefetch (`ExpandPrefetchBackend` exists); load-test the 5 heaviest resources (GLEntry, Transaction, Demand) with worst-case configs.
- **R-P2 · Count queries.** `BootstrapPagination` computes `count`/`total_pages` — expensive on multi-million-row tenants. Offer estimated counts or cursor pagination for large resources before GA.
- **R-P3 · Resolve-cache invalidation.** Per-user resolved configs cached in tenant-aware Redis; invalidation must fire on ViewDefinition writes *and* `seed_resource_metadata` (metadata drift). A stale cache after a model change = broken views at scale.
- **R-P4 · Multi-API detail views waterfall.** Parallel queries per section, skeleton per section; cap sections; watch p95 before considering aggregation endpoint. Note the existing gotcha: invalid `?order_by=` silently returns `queryset.none()` (`lib/views.py:92-110`) — a misauthored config shows an *empty list, not an error*. Surface config-vs-meta validation in the resolve response.

### Multi-tenancy & config lifecycle

- **R-T1 · DB-per-tenant means no global config.** System defaults must be *seeded per tenant* (`setup_account` step) and re-syncable via management command; there is no shared row to update once.
- **R-T2 · Schema drift.** Model changes alter `metadata_hash`; stored configs referencing renamed/removed fields go stale silently. Mitigation: `resolve` returns a validity report; renderer skips invalid fields; nightly/`seed_resource_metadata`-triggered job flags stale ViewDefinitions; never hard-fail.
- **R-T3 · Config versioning & migration.** `schema_version` on every config + explicit migration functions when the contract evolves; export/import (JSON) for promoting configs dev → preprod → prod and across tenants — otherwise config authored in UAT is re-typed by hand in prod.
- **R-T4 · Audit + approval.** View/config changes are tenant-visible behavior changes: `BaseService` audit snapshots come free; decide whether tenant-scope ViewDefinition edits go through maker-checker (`is_approval_enabled`) — recommended for prod tenants.
- **R-T5 · Layer-merge ambiguity.** Define merge semantics precisely (per-key override vs whole-config replace; recommend: whole-section replace, documented) — vague merging is a long-tail bug factory once role+user overrides coexist.

### Frontend-specific

- **R-F1 · RJSF is on a 6.0 beta** (`@rjsf/shadcn`). Pin exactly, wrap all usage behind `FormView` (already the pattern), budget for breaking changes before GA.
- **R-F2 · No test infra exists in crego-web.** Schema-driven rendering is precisely where silent regressions live. Introduce vitest with the module; contract tests: (config JSON + meta fixture) → rendered columns/sections; golden fixtures per resource.
- **R-F3 · BE↔FE contract drift.** No OpenAPI — `shared/types/resourceMeta.ts` is hand-maintained against `core/registry.py`. Add a CI contract test (BE dumps meta JSON fixture → FE type-checks it) or generate the TS types from the seeder output.
- **R-F4 · DataTable coupling.** It imports omni contexts/services; extending it for column management is fine in-place, but resist "promote to shared" mid-project (breaking-change review, two UI kits drift). Do it, if at all, as its own CRE issue.
- **R-F5 · URL state vs saved views.** `useFilters` syncs to URL; saved filters + defaults + URL params need one precedence rule (URL > saved view > defaults) or deep links break.
- **R-F6 · Labels, i18n, timezone.** Column labels must route through `UIDict` (tenant overrides) — configs should store field keys, not display strings. Dates: `X-Timezone` header + `Asia/Kolkata` server TZ; renderer must format consistently.
- **R-F7 · Context re-render cost.** 15-deep provider stack + a config-driven page = memoize resolved config and column arrays (per `.cursor/rules/react-performance-patterns`).

### Operational

- **R-O1 · Licensing wiring on both sides**: `MODULE_ENDPOINT_MAP` + `.env.modules.json` (BE) and `Modules` enum + `withLicence` (FE) — miss either and it's 403s or invisible nav.
- **R-O2 · Rollout**: ship behind license flag, migrate resource-by-resource (start: Payouts or Demands — mid-complexity), keep hand-built pages until parity; define parity checklist per resource (columns, filters, actions, bulk, export).
- **R-O3 · Export/renderers**: CSV/Excel export should honor the active view's columns — reuse `workbook` handlers with the viewset's filterset (pattern exists).

---

## 7. Phasing

**Phase 1 — Contract + generic listing (foundation)**
`uview` app (ViewDefinition, resolve API, seeder, scope config, license wiring) · view-config JSON Schema v1 · `<UniversalList>` on DataTable + column show/hide/reorder + server-persisted prefs · pilot on 2 resources · vitest + contract tests.

**Phase 2 — Detail views + forms**
`<UniversalDetail>` (tooltip/card/sidebar/page) with multi-source sections + skeletons · `FormDefinition` + `<UniversalForm>` (RJSF + json-logic) · sensitive-field server enforcement (R-S1) · SavedFilter API + picker.

**Phase 3 — Customization + home page**
View author/editor UI (RjsfEditor-based, live preview) · role/tenant overrides + approval flow · `HomePageConfig` (resolve mosaic collision first) · export/import of configs · migrate remaining core resources.

**Phase 4 — AI on-the-fly views**
AI emits/edits the same ViewDefinition JSON via the resolve/validate contract; human-in-the-loop approval; per-user "ask for a view" (e.g., "loan list with ROI ≥ 13% & overdue" → SavedFilter + column set). The strict, versioned, validated JSON contract from Phase 1 is exactly what makes this safe.

---

## 8. Open questions

1. Mosaic: does the home page live in Universal View or mosaic-web? (blocks Phase 3 scope)
2. Should tenant-scope view edits require maker-checker from day one, or Phase 3?
3. Cursor/estimated pagination for GLEntry/Transaction-class tables — needed at current tenant sizes?
4. Does `ONYX` licensing interact with per-resource availability of Universal View?
5. Which two resources pilot Phase 1? (proposal: Payouts + Demands)

---

*Grounded against crego-omni (`core/registry.py`, `lib/views.py`, `lib/scope_engine/`, `settings/base.py`) and crego-web (`components/common/DataTable/`, `components/rjsf/`, `shared/types/resourceMeta.ts`, `modules/dashboard/`) as of develop/main, Aug 2026.*
