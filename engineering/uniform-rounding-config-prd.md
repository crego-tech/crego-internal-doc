# PRD — Uniform rounding configuration

> Status: drafted 2026-07-27. Intended as the description body for a Linear issue
> (team Tech, labels `type/feature`, `repo/crego-omni`, `client/shared`).
> Technical plan lives in [uniform-rounding-config-plan.md](uniform-rounding-config-plan.md).

## Problem

Rounding is not one setting in Omni. The same tenant carries the rounding rule in **four separate
places**:

1. **Tenant default** — used by reports and the General Ledger / Trial Balance
2. **Product** configuration
3. **Program** configuration
4. **Account (loan)** configuration — used by accrual, settlement, waiver, repayment and demand math

Each is edited independently, one entity at a time, through the UI. There is no way to say "this
tenant rounds to whole rupees" and have it be true everywhere.

The practical result is drift. A tenant ends up with the report layer on one rule and live loans on
another, so a number shown in a report does not match the number the loan was actually posted with.
Operations teams then raise the mismatch as a data defect when it is really a configuration defect.
Setting it by hand is not a workable answer either — a tenant can have thousands of loan-level
configurations, so uniformity cannot be achieved manually.

## Who this is for

- **Implementation / onboarding** — set a client's rounding rule once at go-live, instead of per entity.
- **Support and operations** — correct a tenant whose configuration has drifted, without a data patch.
- **Finance and reconciliation** — a stated guarantee that reports and loan postings use the same rule.

## Goals

- One action sets the rounding rule across all four places for a tenant.
- Safe to preview: the operator sees exactly what will change before anything is written.
- Safe to repeat: running it twice changes nothing the second time.
- Refuses to write a configuration that would be invalid, rather than writing it and breaking the
  screen that reads it.
- Reports what it did — how many changed, how many were already correct, what it deliberately
  skipped and why.

## Non-goals

- **No recalculation of existing money.** This changes configuration only. Demands, ledger entries
  and schedules already written keep the amounts they were written with. Only future calculation
  uses the new rule. This is a deliberate boundary — restating posted financial records is a
  separate, much larger decision.
- **Not a UI feature.** This is an operator action, not a screen. There is no bulk-edit UI in scope.
- **Does not change what new tenants get by default.** Freshly onboarded tenants continue to receive
  the current shipped default until that is changed separately.

## Requirements

1. The operator specifies a precision and a method, and the tenant to apply it to.
2. All four configuration layers are updated to that value.
3. The operator can restrict the run to a subset of the layers, or to specific products, programs
   or loans.
4. Preview is the default. Writing requires an explicit confirmation flag.
5. Every configuration is validated before it is saved. Anything that would become invalid is
   skipped and named in the output, never silently written.
6. The run produces a summary: changed, already-correct, and skipped-with-reason, per layer.

## Behaviour the operator must be told about

Two things are true today that will surprise someone using this, and the tool must surface them
rather than assume they are known.

**Rounding "up" and "down" always mean whole units.** When the method is up or down, the precision
value is not applied — the result is whole rupees regardless. This is existing intended behaviour.
Choosing precision 0 with up or down is therefore correct and consistent. Choosing a non-zero
precision with up or down looks like a decimal setting but will not behave as one, so the tool must
warn when that combination is requested.

**EMI and BPI are governed by a separate rounding setting.** Instalment amounts read their own
rounding key, independent of the one this change sets. If only the main setting is moved, loan
components can round to whole rupees while the instalment they belong to stays at two decimals —
meaning the instalment no longer equals the sum of its parts. This setting is deliberately **out of
scope for the default run**, but the tool must (a) offer it as an explicit opt-in and (b) report
every configuration where the two settings disagree, so the divergence is visible instead of silent.
Note it does not exist for all product types.

## Acceptance criteria

- A preview run on a tenant lists the intended change for every affected entity and writes nothing.
- A confirmed run leaves all four layers reporting the same rounding rule.
- A second confirmed run reports zero changes.
- Restricting the run to one layer leaves the others untouched.
- An invalid precision or an unrecognised method is rejected before any work starts.
- Requesting a non-zero precision with up or down produces a warning.
- A configuration that cannot legally hold the value is skipped and named, not written.
- After a run, a newly generated accrual and a report on the same loan both reflect the new rule.

## Follow-on work identified during analysis

Making the configuration uniform does not by itself make the output uniform — there are places where
the configured rule is not consulted at runtime. These were found while scoping this and are
**separate tickets**, not part of this one:

- Fee amounts and their tax are recorded exactly as submitted, with no rounding applied. The
  configured rule has no effect on them. This is the same code path as the known group-fee GST
  defect.
- Where an amount is split into two parts (typically base and tax), one part is rounded and the
  other takes the remainder. The total is always preserved, but the second part can carry more
  decimal places than configured — which then appears as an un-rounded figure in reports.
- The Trial Balance calculates two of its totals by different methods, one of which sums
  already-rounded rows. The two can disagree, and the disagreement grows as precision is reduced —
  so it is most visible at exactly the whole-rupee setting this feature is intended to roll out.

A written audit of every place rounding is applied accompanies this work and will be the source for
those tickets.
