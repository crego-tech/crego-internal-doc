# Technical Design — PDC (Post-Dated Cheque) Module

**Status:** Draft for review
**Author:** Abhishek
**Date:** 31 Jul 2026
**PRD:** `crego-internal-docs/engineering/pdc-module-prd.md`
**Repos:** `crego-omni` (new `pdc` Django app), `crego-web` (new `packages/omni-web/src/modules/pdc` + nav group)

---

## 1. Placement decision

| Option | Verdict |
|---|---|
| New `pdc` Django app, realisation reuses `transfer.Payment` | **Chosen.** |
| New `pdc` app, self-contained realisation posting to `ctm`/`schedule` directly | Rejected — duplicates the money-in rail, two sources of truth for cash. |
| Extend `transfer` | Rejected — `transfer` is already the largest app; PDC has its own custody, legal and inventory concerns that have nothing to do with electronic transfers. |

**Consequences of the choice**

- PDC owns *instruments*. `transfer` continues to own *money*. A cleared cheque becomes a `transfer.Payment` (`mode = cheque`) and everything downstream — demand settlement, CTM transactions, GL, SOA, DPD — is untouched.
- PDC posts **no** ledger entries and creates **no** transactions directly. Bounce charges are posted as `schedule.Demand` rows through the existing charge machinery.
- `PaymentMode` gains a `cheque` member (`transfer/constants.py`) — the one change required outside the new app's own files, besides registration.

---

## 2. Data model

New app `project/apps/pdc/`. Four models, all `BaseModel, SoftDeleteModel`, string `PrimaryKeyField` ids, no tenant column (database-per-tenant).

### 2.1 `PDCInstrument` — `pdc_instrument`

The cheque itself. Current state lives here; history lives in `PDCPresentation` and `PDCMovement`.

| Group | Fields |
|---|---|
| Identity | `ref_id` (generated `PDC-{seq}` / `PDC-{account.ref_id}-{nnn}`), `cheque_number`, `micr_code` |
| Drawer bank | `contact_bank` FK → `contact.ContactBank` (nullable), plus denormalised `bank_name`, `branch_name`, `ifsc`, `account_no`, `account_holder_name`, `account_type` for cheques from a bank not yet on file |
| Instrument | `purpose` (`emi` / `security` / `advance` / `margin`), `amount` (nullable for security), `cheque_date` (nullable for undated), `expiry_date` (derived), `is_undated` |
| Mapping | `contact` FK, `account` FK → `product.Account` (nullable), `schedule` FK → `schedule.Schedule` (nullable, the covered EMI) |
| Deposit | `collection_bank` FK → `contact.ContactBank` (lender's bank the cheque is banked into) |
| State | `status` (see §3), `presentation_count`, `last_presented_at`, `last_bounced_at`, `bounce_count` |
| Custody | `branch` FK → `core.Branch`, `custodian` FK → `authz.User`, `location_ref` (vault/locker) |
| Chain | `replaces` / `replaced_by` self FK |
| Docs | `cheque_document` FK → `docs.Document` (scan) |
| Realisation | `payment` FK → `transfer.Payment` (set on clearing) |
| Free-form | `remarks`, `tags`, `refs`, `metadata` |

**Constraints & indexes**

- Partial unique: `(ifsc, account_no, cheque_number)` where `is_deleted = false` **and** `status` not in terminal states — the same leaf number may legitimately recur once an instrument is closed out.
- Partial unique: one active instrument per `schedule` — enforced with a condition on non-terminal statuses.
- Indexes: `(account, status)`, `(status, cheque_date)`, `(status, expiry_date)`, `(branch, status)`, `(collection_bank, status, cheque_date)`.
- `clean()` invariants: a dated instrument requires `cheque_date`; a non-security instrument requires `amount`; `expiry_date` must equal `cheque_date + validity_months`.

`audit_parent_entity` returns `self.account` when mapped (so the loan's audit trail shows cheque activity), else `self`.

### 2.2 `PDCBatch` — `pdc_batch`

A deposit batch: the set of cheques handed to one collection bank on one date. Structurally the twin of `transfer.PayoutBatch`.

`ref_id` (unique), `collection_bank` FK, `presentation_date`, `status` (`open` / `deposited` / `partially_cleared` / `closed` / `cancelled`), `total_amount`, `instrument_count`, `deposited_at`, `closed_at`, `deposit_slip_document` FK, `remarks`, `metadata`.

Partial unique: one `open` batch per `(collection_bank, presentation_date)` — so the auto-batcher is idempotent.

### 2.3 `PDCPresentation` — `pdc_presentation`

One banking attempt. Deliberately modelled on `connectors.TransBankNachPresentation` so PDC and NACH read identically in reporting.

`instrument` FK, `batch` FK (nullable — a one-off presentation outside a batch), `attempt_number`, `presentation_date`, `presentation_amount`, `status` (`pending` / `presented` / `cleared` / `bounced` / `withdrawn`), `clearing_date`, `realised_amount`, `bank_reference`, `payment` FK (created on clearing).

Bounce block: `return_reason` FK → `PDCReturnReason`, `return_reason_code` (raw bank code, passthrough), `return_reason_description`, `return_memo_document` FK, `bounce_charge_applied` bool, `bounce_charge_demand` FK → `schedule.Demand`, `bounce_charge_waiver_reason`.

Legal block (§138): `legal_intimation_date`, `legal_notice_due_date`, `legal_notice_sent_date`, `legal_notice_document` FK, `legal_cure_due_date`, `legal_filing_due_date`, `legal_status`.

Immutable snapshots taken at deposit time — `account_ref_snapshot`, `schedule_id_snapshot`, `due_amount_snapshot`, `instrument_snapshot` — so a presentation record stays meaningful after the loan or schedule is restructured. Same technique as the NACH presentation model.

Unique: `(instrument, attempt_number)`.

### 2.4 `PDCMovement` — `pdc_movement`

Custody log. `instrument` FK, `movement_type` (`vault_in` / `vault_out` / `branch_transfer` / `custodian_transfer` / `handover_to_bank` / `return_from_bank` / `return_to_customer`), `from_branch` / `to_branch`, `from_custodian` / `to_custodian`, `from_location_ref` / `to_location_ref`, `moved_at`, `acknowledgement_document` FK, `remarks`.

Append-only by convention (no update action exposed).

### 2.5 `PDCReturnReason` — `pdc_return_reason`

Configurable master, **not** an enum. `code`, `description`, `category` (`financial` / `technical` / `other`), `is_charge_applicable`, `is_legal_actionable`, `status`.

Seeded with a starter set of common CTS return reasons via `seed_pdc_return_reasons`. **Onboarding must reconcile this against each client bank's return memo codes** — the `financial` / `technical` split drives whether a bounce charge is posted, and bank code numbering is not uniform. This is why it is a table and not a hardcoded list.

### 2.6 Entity relationships

```
contact.Contact ─┬─ contact.ContactBank ──── (drawer) ─┐
                 │                                     │
product.Account ─┼── schedule.Schedule ── (covers) ─── PDCInstrument ──┬── PDCMovement  (custody history)
                 │                                          │         │
                 │                                          │         └── PDCPresentation (attempt history)
                 │                                                              │
                 │                                          PDCBatch ───────────┤
                 │                                                              │
                 └────────────────── transfer.Payment ◄── (on clearing) ────────┘
                                                                                │
                                       schedule.Demand ◄── (bounce charge) ─────┘
```

---

## 3. State machines

`pdc/status_config.py`, following the `transfer/status_config.py` pattern — a plain transition graph, auto-discovered into `ResourceMeta.transitions`, with approval gating applied by `StatusTransitionService` where configured. No `django-fsm`.

### `PDCInstrumentStatusFlow`

| From | To |
|---|---|
| `received` | `verified`, `rejected`, `cancelled` |
| `verified` | `in_custody`, `cancelled` |
| `in_custody` | `marked_for_presentation`, `expired`, `returned`, `replaced`, `stop_payment`, `lost`, `cancelled` |
| `marked_for_presentation` | `presented`, `in_custody` (withdraw), `expired`, `cancelled` |
| `presented` | `cleared`, `bounced` |
| `bounced` | `in_custody` (re-present), `returned`, `replaced`, `stop_payment`, `lost` |
| `cleared`, `rejected`, `expired`, `returned`, `replaced`, `stop_payment`, `lost`, `cancelled` | *(terminal)* |

Terminal set is exported as `PDCInstrumentStatus.terminal_statuses()` and drives the partial unique constraints and the eligibility guards.

### `PDCBatchStatusFlow`

`open → deposited → partially_cleared → closed`; `open → cancelled`; `deposited → closed`.

### `PDCPresentationStatusFlow`

`pending → presented → cleared | bounced`; `pending → withdrawn`. All of `cleared`, `bounced`, `withdrawn` terminal.

---

## 4. Services

`pdc/services/` — one module per model plural, per the `{app}.services.{model_plural}.{Model}Service` auto-registration convention.

| Service | File | Methods beyond CRUD |
|---|---|---|
| `PDCInstrumentService` | `instruments.py` | `verify`, `apply_to_loan`, `detach`, `mark_for_presentation`, `withdraw`, `represent`, `replace`, `return_to_customer`, `stop_payment`, `mark_lost`, `cancel`, `mark_expired`, `move` (custody), `create_range` (leaf-range intake), `get_account_cover_summary` |
| `PDCBatchService` | `batches.py` | `add_instruments`, `remove_instruments`, `deposit`, `close`, `cancel`, `build_auto_batches`, `generate_deposit_slip` |
| `PDCPresentationService` | `presentations.py` | `mark_cleared`, `mark_bounce`, `record_legal_notice` |
| `PDCMovementService` | `movements.py` | `create_bulk` (bulk custody move) |
| `PDCReturnReasonService` | `return_reasons.py` | CRUD only |

**Contract adherence**

- All writes wrapped in `tenant_atomic()`; never bare `transaction.atomic()`.
- Audit via `self._log_audit(..., action_name=PDCInstrumentAction.<x>.name)` — never a literal string, never a status name.
- Async fan-out via `tenant_on_commit(lambda: TaskService.invoke(...))` — never `.apply_async()`.
- Errors raised as `DRFValidationError({"field": "msg"}, code=PDCErrorCodes.X)` or `BusinessRuleError`; never formatted in the viewset.
- Enum members referenced as `.name` for storage, `.value` for display.

**Eligibility guard (single chokepoint).** `PDCInstrumentService._assert_presentable(instrument)` is the one place that answers "can this cheque be banked right now?" and is called by `mark_for_presentation`, `PDCBatchService.add_instruments` and the auto-batcher:

1. status is `in_custody`;
2. not expired and `cheque_date <= presentation_date`;
3. `presentation_count < pdc.max_presentation_attempts`;
4. `purpose != security`, unless the caller holds `pdc.can_present_security_cheque`;
5. mapped account (if any) is not closed;
6. covered demand (if any) still has outstanding.

### 4.1 Clearing → payment

`PDCPresentationService.mark_cleared` builds a `transfer.Payment` through `PaymentService`, not by direct ORM create:

```
amount        = realised_amount
mode          = PaymentMode.cheque.name
payment_type  = PaymentType.loan_settlement.name
value_date    = clearing_date
txn_date/bank_date = clearing datetime
contact       = instrument.contact
source_bank   = instrument.contact_bank        (drawer)
destination_bank = instrument.collection_bank  (lender)
narration     = "Cheque <no> cleared - <batch ref>"
```

then links `presentation.payment` and `instrument.payment`, moves the instrument to `cleared`, and rolls the batch status forward.

### 4.2 Bounce → charge

`mark_bounce` records the outcome, then posts the charge **only** when all of: the return reason is `financial` / `is_charge_applicable`, `pdc.auto_post_bounce_charge` is on, the instrument is mapped to an account, and no charge already exists for this presentation.

> **Integration TODO (blocks phase 2).** The exact entry point for posting an ad-hoc charge demand against an account (`schedule` / `ctm` charge service + component resolution from `pdc.bounce_charge_component_code`) must be confirmed before build. The scaffold isolates this in `PDCPresentationService._post_bounce_charge()` with an explicit `TODO`, so nothing else in the module depends on the answer.

Legal dates are computed on the same call from the configured windows.

---

## 5. API surface

`pdc/urls.py`, `SimpleRouter`, kebab-case plural prefixes, no version segment (consistent with the rest of Omni).

| Route | ViewSet | Notes |
|---|---|---|
| `pdc/instruments/` | `PDCInstrumentViewSet` | Full CRUD + `@action`s below. `DocUploadOnCreateMixin` for the cheque scan; `WorkbookOperationMixinViewSet` for bulk import/export. |
| `pdc/batches/` | `PDCBatchViewSet` | List/retrieve/create + batch actions. |
| `pdc/presentations/` | `PDCPresentationViewSet` | List/retrieve + `mark-cleared`, `mark-bounce`, `record-legal-notice`. |
| `pdc/movements/` | `PDCMovementViewSet` | List/retrieve/create. |
| `pdc/return-reasons/` | `PDCReturnReasonViewSet` | CRUD (admin). |

Custom actions (viewset method name **must** equal the service method name):

```
POST pdc/instruments/{id}/verify/
POST pdc/instruments/{id}/apply-to-loan/          {account, schedule?}
POST pdc/instruments/{id}/detach/
POST pdc/instruments/{id}/mark-for-presentation/  {presentation_date?, collection_bank?}
POST pdc/instruments/{id}/withdraw/
POST pdc/instruments/{id}/represent/
POST pdc/instruments/{id}/replace/                {new cheque payload}
POST pdc/instruments/{id}/return-to-customer/
POST pdc/instruments/{id}/stop-payment/
POST pdc/instruments/{id}/mark-lost/
POST pdc/instruments/{id}/move/                   {to_branch, to_custodian, location_ref, remarks}
POST pdc/instruments/create-range/                {account, start_cheque_number, count, ...}
GET  pdc/instruments/cover-summary/?account=<id>

POST pdc/batches/{id}/add-instruments/            {instrument_ids: []}
POST pdc/batches/{id}/remove-instruments/         {instrument_ids: []}
POST pdc/batches/{id}/deposit/
POST pdc/batches/{id}/close/
GET  pdc/batches/{id}/deposit-slip/               (CSV / Excel / PDF renderer)

POST pdc/presentations/{id}/mark-cleared/         {clearing_date, realised_amount, bank_reference}
POST pdc/presentations/{id}/mark-bounce/          {return_date, return_reason, return_reason_code, ...}
POST pdc/presentations/{id}/record-legal-notice/  {notice_sent_date, document}
```

Bulk variants go through the inherited `PUT pdc/{resource}/bulk_actions/` with `{ids, action, payload}`; bulk-safe actions are declared on each `{Model}Action.get_bulk_allowed_actions()` — notably `verify`, `mark_for_presentation`, `mark_cleared`, `mark_bounce`, `move`, `destroy`.

Serializers follow the mandated split: `{Model}ReadSerializer` (expandable), `{Model}WriteSerializer` (PK fields + validation), `{Model}ListSerializer` (lean), `{Model}MiniSerializer`.

`Account` gains an `expandable_fields` entry `pdc_summary` (`source="*"`, lazy) delegating to `PDCInstrumentService.get_account_cover_summary`, mirroring how `collect` adds `collection_summary`.

---

## 6. Background jobs

`pdc/tasks.py`, all `@robust_task`, all idempotent, all seeded as `PeriodicTask` rows by `pdc/management/commands/seed_pdc_beat_schedule.py` with an explicit `timezone=settings.TIME_ZONE`.

| Task | Cron | Guarantee |
|---|---|---|
| `expire_pdc_instruments_task` | `30 0 * * *` | Filters strictly on non-terminal statuses + `expiry_date < today`; re-running is a no-op. |
| `pdc_expiry_reminder_task` | `0 8 * * *` | `correlation_id = pdc-expiry:{instrument_id}:{date}` dedupes notifications. |
| `build_pdc_presentation_batches_task` | `0 6 * * *` | `get_or_create` on the partial-unique open batch per `(collection_bank, presentation_date)`; adds only newly-eligible instruments. |
| `pdc_low_cover_alert_task` | `15 8 * * *` | `correlation_id = pdc-cover:{account_id}:{date}`. |
| `pdc_legal_notice_sla_task` | `30 8 * * *` | `correlation_id = pdc-legal:{presentation_id}:{date}`. |
| `sync_pdc_presentation_status_task` | phase 3 | Connector-driven; no-op when no `cheque_clearing` connector is configured. |

Run `register_tasks` after adding them.

---

## 7. Permissions, scoping, licensing

**Django model permissions** are auto-created: `add/change/delete/view_pdcinstrument`, `…_pdcbatch`, `…_pdcpresentation`, `…_pdcmovement`, `…_pdcreturnreason`.

**Custom permissions** declared in `Meta.permissions`:

| Codename | Gates |
|---|---|
| `pdc.can_verify_pdc` | `verify` |
| `pdc.can_present_pdc` | `mark_for_presentation`, batch `deposit` |
| `pdc.can_present_security_cheque` | presenting a `security` instrument |
| `pdc.can_mark_clearing` | `mark_cleared`, `mark_bounce` |
| `pdc.can_waive_bounce_charge` | overriding charge posting on a bounce |
| `pdc.can_return_pdc` | `return_to_customer`, `stop_payment`, `mark_lost` |
| `bulk_import_pdcinstrument` / `bulk_export_pdcinstrument` | workbook operations |

Enforced with small `BasePermission` subclasses in `pdc/permissions.py`, following `transfer/permissions.py` exactly (`HasPDCPerm` base with a `perm_code`), applied per-`@action`.

**Data scoping.** `PDCInstrument` scopes on `account__program` with `contact_fields = ["contact"]`, plus a branch-level scope on `branch` for the custody views — so a branch custodian sees their branch's vault and a program-scoped partner sees only their programs' cheques. Registered in the scoping config in `lib/authorization.py` and defaulted in `seed_roles_departments.py`. **A model with no scoping entry is either unfiltered or invisible to scoped roles — this registration is not optional.**

**Licensing.** PDC endpoints are added to the existing `product_lms` entry in `MODULE_ENDPOINT_MAP` (`settings/base.py`), matching the frontend's `Modules.LMS` gate. Promoting PDC to its own license key later is a one-line change in both places.

---

## 8. Notifications & webhooks

Rule-driven through the existing `notifications` app — no hardcoded recipients or channels. New `EventMaster` entries seeded by `seed_notifications`:

`PDC Received`, `PDC Verified`, `PDC Expiring Soon`, `PDC Expired`, `PDC Cover Low`, `PDC Presented`, `PDC Cleared`, `PDC Bounced`, `PDC Legal Notice Due`, `PDC Returned To Customer`.

Fired via `NotificationResolverService.trigger_event_by_name(..., correlation_id=...)`. The same call fans out to tenant webhook endpoints; event names normalise to `{Model} {Action}`.

---

## 9. Phase-3 bank integration

Adds `ConnectorCategory.cheque_clearing` and a provider under `connectors/providers/cheque_clearing/{vendor}/` implementing:

- `generate_deposit_file(batch)` → bank-format flat file / CSV;
- `submit_positive_pay(instruments)` → PPS submission for high-value cheques;
- `fetch_returns(since)` → return-file ingestion mapped onto `mark_bounce` / `mark_cleared`;
- `fetch_status(batch)` → polled by `sync_pdc_presentation_status_task`.

Vendor-specific rows, if a vendor needs them, live in `connectors` — the same split that keeps `transfer.PaymentBatch` vendor-neutral while `connectors.TransBankNachPresentation` holds the vendor detail.

---

## 10. Frontend design (crego-web)

New module at `packages/omni-web/src/modules/pdc/`, following the standard folder contract (`index.tsx` router, `api/`, `queries/`, `types/`, `list/`, `form/`, `config/`, `schema/`, `context/`).

- **Router**: `PDCRouter` mounted at `/pdc/*` in `src/router.tsx` inside `AllowedRoutesGuard`, wrapped `withLicence(withPermission(PDCRouter, Permission.VIEW_PDCINSTRUMENT), Modules.LMS)`.
- **Nav**: new top-level group in `shared/constants/nav/default.ts`, colour `indigo`, icon `file-clock`, five children (Cheques, Presentation Batches, Presentations, Bounces, Custody Register), each gated on its own `Permission.VIEW_*` and `Modules.LMS`.
- **Permissions**: new `Permission.*_PDCINSTRUMENT` / `*_PDCBATCH` / `*_PDCPRESENTATION` / `*_PDCMOVEMENT` keys in `shared/types/permissions.ts`, values matching the Django codenames exactly.
- **Module registry**: entry in `src/config/modules.ts` for redirect/fallback resolution.
- **Data**: TanStack Query + the `baseApi` axios instance; list pages fetch through `DataTable`'s `apiConfig` rather than bespoke queries; mutations in `queries/` invalidate `['pdc-instruments']`, `['pdc-batches']`, `['pdc-presentations']`.
- **Lists**: standard `DataTable` with config-driven `FilterConfig` (status, purpose, account, contact, branch, custodian, bank, cheque-date range, expiry bucket), URL-synced pagination, `bulkOpsConfig` for import/export, `rowSelectionConfig` for bulk verify / batch / clear / bounce.
- **Forms**: `react-hook-form` + `zod` in `form/` with schemas in `schema/`; dialogs via `CommonFormDialog`; destructive actions behind `useConfirm()`.
- **Loan detail**: a PDC tab rendering the `pdc_summary` expand plus the cheque mapped to each EMI.

---

## 11. Registration checklist (crego-omni)

1. `project/apps/pdc/` created with the full app contract (`apps.py` with `ready()` importing `pdc.tasks` and `pdc.workbook_handlers`, `constants.py`, `exceptions.py`, `models.py`, `status_config.py`, `serializers.py`, `filters.py`, `services/`, `views.py`, `permissions.py`, `urls.py`, `tasks.py`, `workbook_handlers/`, `management/commands/`, `migrations/`, `tests/`).
2. `settings/base.py` → add `"pdc"` to `PROJECT_APPS`.
3. `settings/base.py` → add the PDC endpoints to `MODULE_ENDPOINT_MAP["product_lms"]`.
4. `project/urls.py` → import `pdc_urls` and append to `app_urls`.
5. `transfer/constants.py` → add `cheque` to `PaymentMode`.
6. `lib/authorization.py` + `seed_roles_departments.py` → scoping entries and role defaults.
7. `authz/group_permissions.json` → grant the new permissions to the relevant predefined groups.

**Post-deploy, per tenant:**

```
TENANT_ALIAS=<t> pipenv run python manage.py migrate
TENANT_ALIAS=<t> pipenv run python manage.py seed_resource_metadata
TENANT_ALIAS=<t> pipenv run python manage.py register_tasks
TENANT_ALIAS=<t> pipenv run python manage.py seed_predefined_groups
TENANT_ALIAS=<t> pipenv run python manage.py seed_pdc_return_reasons
TENANT_ALIAS=<t> pipenv run python manage.py seed_pdc_beat_schedule
TENANT_ALIAS=<t> pipenv run python manage.py seed_notifications
```

Skipping `seed_resource_metadata` means every PDC endpoint 400s on action validation. Skipping the `MODULE_ENDPOINT_MAP` entry means every PDC request 403s on the license middleware.

---

## 12. Testing

`pdc/tests/` with `test_models.py`, `test_services.py`, `test_serializers.py`, `test_views.py`, `test_tasks.py`, extending `lib.utils.test_utils.BaseTestCase`.

Non-negotiable cases:

- the full happy path — intake → verify → map → batch → deposit → clear → `Payment` created and demand settled;
- every rejected transition in `PDCInstrumentStatusFlow`;
- each of the six eligibility guards in `_assert_presentable`;
- financial bounce posts exactly one charge; technical bounce posts none; a second `mark_bounce` on the same presentation posts none;
- expiry task idempotency (run twice, same result, no duplicate notifications);
- auto-batcher idempotency (run twice, one batch, no duplicate instruments);
- security cheque never auto-batched and blocked without the explicit permission;
- scoping — a branch-scoped user cannot see another branch's inventory.

Financial paths (clearing → payment, bounce → charge) require 100% coverage per the repo standard.

---

## 13. Open technical questions

| # | Question |
|---|---|
| 1 | Bounce charge posting entry point — confirm the `schedule` / `ctm` service to call and how the component is resolved from `pdc.bounce_charge_component_code`. Blocks phase 2. |
| 2 | Should `PaymentMode.cheque` be split into `cheque` and `dd` (demand draft)? Some clients accept DDs on the same rail. |
| 3 | Co-lending: whose `collection_bank` for a shared account? Assumed the originating lender's, following `Payment.parent`. |
| 4 | Does the deposit slip need a client-specific layout, or is a standard PDF/Excel enough for phase 2? |
| 5 | Should a bounce automatically create a `collect.CollectionEnquiry` follow-up so the collections agent picks it up? Cheap to add, high value — recommend yes in phase 2. |
| 6 | Should security-cheque amounts be auto-filled from outstanding at presentation time, or always entered manually? Legal input needed. |
