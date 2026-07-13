# Collections Module — Phase 2 UX Design Brief (Claude Code kickoff pack)

**How to use:** open a Claude Code session at the workspace root (`crego/`) and paste the Kickoff Prompt below. Iterate screen-by-screen; finalize decisions back into this doc. Once design is frozen, the technical plan is derived from the PRD + this doc.

**Reference:** `crego-internal-docs/engineering/collections-module-prd.md` (Phase 2 scope: case management, bucketing, allocation + supervisor console).

---

## Kickoff Prompt (paste into Claude Code)

> I'm designing the UX for the Collections Module Phase 2 in `crego-web` (supervisor console) with a secondary look at the agent app worklist in `crego-app`. Read `crego-internal-docs/engineering/collections-module-prd.md` and this brief (`crego-internal-docs/engineering/collections-module-ux-design-brief.md`) first.
>
> Before proposing designs, study existing conventions:
> - `packages/omni-web/src/modules/accounts` and `modules/demands` — list/detail page patterns
> - `shared/components/` — `PageLayout`, `StandardPagination`, `JsonLogicBuilder`, `AppSidebar`, and the `ui/` kit (use these, don't invent new primitives)
> - Stack: React 19 + TypeScript, Tailwind v4, react-hook-form + zod
> - Branch `feature/cre-5834-collection-agent-app-screens` in crego-web has collections permission stubs in `shared/types/permissions.ts` and `shared/types/rbac.ts`
> - Agent app screens already built (crego-app branch `feature/cre-5836-...`): enquiry form/list, PTP view, loan collection summary — the web console must feel like the management counterpart of these
>
> Work one screen at a time in the order listed in the brief. For each screen produce a working React prototype (mock data, real shared components) I can run and critique. Capture every decision (layout, columns, filters, actions, empty/error states) in a running `design-decisions.md`. Don't touch backend code.

---

## Context

Omni tracks DPD but has no collections operations. Phase 2 introduces `CollectionCase` (one per delinquent account: bucket, DPD, outstanding, assigned agent, status), rule-driven allocation (bucket × pincode × capacity), and territories. The web console is the biggest net-new surface — a new `packages/omni-web/src/modules/collections` module.

**Personas:** Collection Head / supervisor (primary, web) — allocates and monitors the book. Platform admin (secondary, web) — territories, rules. Collection agent (app) — consumes a case-driven worklist.

## Screens to design (priority order)

1. **Portfolio dashboard** — delinquent book by bucket (counts, outstanding ₹, roll-rates), filters: product/program, region, agent; drill-through to case list. Should answer "where is my risk and is it moving?"
2. **Case list** — dense, filterable table (bucket, DPD, outstanding, agent, status, last activity, PTP flag); saved filters; bulk-select → reassign; row → case detail.
3. **Case detail** — header (account, borrower, bucket, DPD, outstanding, agent) + unified timeline (enquiries, PTPs with lifecycle, payments, bucket transitions, future: comms/notices) + actions (reassign, close/normalize with reason).
4. **Allocation console** — ordered rule list (match: bucket/product/pincode-set/amount band → agent pool + capacity policy); rule editor (consider `JsonLogicBuilder` for conditions); "Run allocation" with dry-run preview (N cases → M agents, unallocated remainder) then commit; run history/audit.
5. **Bulk reassignment** — from case list selection or "agent offboarding" entry point: move all cases of agent A → agent B/pool, with preview.
6. **Territory management** — agent/team ↔ pincode-set mapping; pincode entry UX matters (paste lists, ranges, dedupe/conflict detection when two agents claim a pincode).
7. **(Secondary, crego-app)** Agent worklist — assigned cases sorted by priority (PTP due today > high bucket > geography); reconcile with existing enquiry/PTP screens rather than redesigning them.

## Constraints & conventions

- RBAC: Collection Head sees portfolio/case/allocation; only admin edits territories & rules. Use permission stubs from the cre-5834 branch.
- Multi-tenant theming: no hardcoded colors; follow shared theme (`ThemeColorSelector` conventions).
- Data density over whitespace — users are ops teams living in tables. Every list needs pagination (`StandardPagination`), empty states, and export affordance.
- All destructive/bulk actions need preview + confirm (allocation commit, bulk reassign, case close).
- Compliance surfacing (design for, even if Phase 3 wires it): case detail should reserve space for comms log & agent-disclosure-sent indicator.
- Web console is desktop-first; no mobile requirement.

## Open UX questions (resolve during design)

1. Dashboard: buckets as columns (kanban-ish flow) vs classic summary cards + table? 
2. Allocation rules: JsonLogic power-user editor vs structured form with limited dimensions? (Recommend structured form; JsonLogic escape hatch later.)
3. Case detail timeline: single merged stream vs tabs (activity / PTPs / payments)?
4. Where does collections live in `AppSidebar` IA — top-level module or under an existing section?
5. Pincode sets: free-form tags vs named reusable "territory" objects referenced by rules? (PRD assumes named territories.)

## Definition of done (design phase)

Approved prototypes for screens 1–6, `design-decisions.md` complete (IA, navigation, per-screen layout/columns/actions/states), open questions above resolved. Output feeds the technical plan: API contracts implied by each screen, component inventory, and build sequencing.
