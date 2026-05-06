# Approval Module — Handbook

**Version:** P0 (v2.7.0)  
**Updated:** April 2026  
**Audience:** Product, QA, Clients, Implementation Teams

## 1. Overview

The Approval Module gates critical business actions (activating accounts, processing payments, approving invoices) behind configurable, multi-level human approval. The operation is paused, routed through a chain of approvers, and only executed once the required approvals are collected.

## 2. Core Concepts

**Approval Definition.** A reusable template defining: which entity type, when to trigger, who approves, how many approvals are needed, and what happens on approval or rejection.

**Approval Instance.** A live execution of a definition for a specific entity. Captures who initiated it, a snapshot of the entity, tracks the active stage, and collects all decisions.

**Stage, Step, and Approver hierarchy.** A Definition contains one or more Stages, which run **sequentially** (a stage completes before the next starts). Each Stage contains one or more Steps, which run **in parallel** (all steps within a stage are open at once). Each Step has one or more assigned Approvers.

Example structure:

- **Definition**
    - **Stage 1 — Maker Verification** *(runs first)*
        - Step A — Ops Checker *(approvers: Ops Checker role)*
        - Step B — Credit Analyst *(approvers: Credit Analyst role)*
    - **Stage 2 — Checker Approval** *(runs after Stage 1)*
        - Step A — Ops Manager
        - Step B — Finance Manager

**N-of-M Threshold.** A step with 3 approvers but requiring only 2 approvals passes when any 2 approve.

**Entity Snapshot.** The entity's data frozen at the moment the approval was triggered, so approvers always see exactly what they are approving.

## 3. Supported Entities

| Entity | Typical Use |
|---|---|
| Account (Loan Account) | Activation of new loan accounts |
| Payment | Processing outgoing payments |
| Payout | Payouts to borrowers or partners |
| Invoice | Invoice approval before processing |
| Drawdown | Loan disbursement approval |
| Purchase Order | PO approval |

Each entity must be explicitly enabled for approvals in the platform configuration.

## 4. Trigger Types

### 4.1 On Status Change (most common)

Whenever an entity reaches a designated **trigger status**, the approval intercepts. There is no "from status" restriction — the approval fires regardless of which status the entity came from, as long as it arrives at the trigger status.

*Example:* An Account transitions to "Requested". The system finds a definition with `trigger_status = "Requested"`. An approval instance is created, and the Account stays in "Requested" until resolved.

### 4.2 On Create

The approval fires the moment the entity is created.

*Example:* A new Payment is created. An approval instance starts immediately, and the Payment sits in pending status until approved.

### 4.3 Manual

A user explicitly triggers an approval from the UI. The entity's status does not change — the approval runs alongside its current state.

*Example:* A compliance officer manually requests an audit review for an active Account.

### 4.4 On Update *(planned — next phase)*

For configuration and limit changes that need approval before taking effect. Proposed changes will be held in intermediary storage and applied only after approval. This will eventually replace the existing Review module. On Delete will follow the same pattern.

## 5. Approver Types and Role Resolution

### 5.1 User

A specific named individual. Only that person can approve the step.

### 5.2 Role

Any user holding the assigned role can approve. The platform resolves eligible users by matching role assignments against profile types and scoping rules.

The platform has two related classification systems — **profile types** (the user's assignment) and **role codes** (what gets assigned as approvers).

Profile types:

| Profile Type | Description |
|---|---|
| staff | Internal staff users |
| partner | External partner users (anchors, lenders, LSPs, dealers, vendors, etc.) |
| customer | Borrower / end-customer users |
| agent | Field agents, collection agents, sales agents |

Role codes and their mapping:

| Role Code | Maps To |
|---|---|
| staff | Staff profile |
| customer | Customer profile |
| anchor | Partner profile (partner_type: anchor) |
| co_lender | Partner profile (partner_type: co-lender) |
| counterparty | Partner profile |
| lsp | Partner profile (partner_type: LSP) |
| agent | Agent profile |

**How role-based approver resolution works.** When a role is assigned as an approver, the system finds all active users holding that role. For partner-type roles (anchor, lender, co-lender, LSP), the system evaluates eligibility based on the entity's **program partners** — only users who are partners in the entity's program are eligible. For GL-account-related entities, scoping uses the GL account's contact to identify the right approvers.

### 5.3 Approval Group

A custom collection of users created for approval purposes (for example, Risk Committee, Finance Committee, Executive Committee). Managed under the Approvals section of the platform.

## 6. Approval Lifecycle

The lifecycle moves through three phases:

**Phase 1 — Trigger.** An entity action occurs (create, status change, or manual request). The system selects the matching definition using priority and conditions. The entity is set to the trigger status, a snapshot is captured, and an approval instance is created.

**Phase 2 — Stage Processing** *(repeats for each stage)***.** The current stage is activated and all of its steps open for parallel approval. Each approver can Approve (with an optional comment) or Reject (with a mandatory comment). Every decision is recorded with identity, role, and timestamp. After each decision, the system checks the step threshold (is N-of-M met?). If a rejection occurs and veto is configured, the entire approval is rejected. If all steps in the stage are met, the stage is marked Approved and the next stage is activated — or skipped if skip conditions apply.

**Phase 3 — Outcome.** When all stages are done, the system executes the `on_approval_action` (for example, Activate). If a rejection has occurred, it executes the `on_rejection_action` (for example, Reject). The entity reaches its final status and the instance is marked complete.

## 7. Conditional Routing

Multiple definitions can exist for the same entity type. The system picks the right one using **conditions** (rules evaluated against entity data) and **priority** (higher priority is checked first).

| Definition | Priority | Condition | Result |
|---|---|---|---|
| High-Value Payment Approval | 90 | Amount >= 10,00,000 | 3-stage (Maker, Checker, Executive) |
| Standard Payment Approval | 50 | Amount >= 1,00,000 | 2-stage (Maker, Checker) |
| Default Payment Approval | 10 | *(default — no condition)* | 1-stage (Maker only) |

A Rs. 15L payment matches the first definition. A Rs. 5L payment matches the second. A Rs. 50K payment falls to default.

## 8. Rejection Behaviour

Each step is configured with one of three policies:

| Policy | What Happens | Use Case |
|---|---|---|
| **Veto** (rejection kills approval) | One rejection terminates the entire approval instantly. Rejection action is executed. | Compliance checks — a single "No" must stop everything |
| **Advisory** (rejection allowed) | Rejection is recorded but approval continues. Other approvers can still approve. | Peer reviews — dissent doesn't block progress |
| **Approval only** (rejection not allowed) | Step can only be approved. No reject option shown. | Acknowledgement — confirming receipt or awareness |

## 9. Action Callbacks

The approval system does not directly change entity statuses. On completion, it executes a configured action belonging to the entity's own logic:

| Entity | On Approval | Result | On Rejection | Result |
|---|---|---|---|---|
| Account | Activate | Active | Deactivate | Inactive |
| Payment | Process | Processing | Reject | Rejected |
| Payout | Process | Processing | Reject | Rejected |
| Invoice | Approve | Approved | Reject | Rejected |
| Drawdown | Approve | Approved | Reject | Rejected |
| Purchase Order | Approve | Approved | Reject | Rejected |

## 10. UI Guide

### 10.1 Navigation

The Approvals section has four sub-pages: **Instances** (active and completed workflows), **Definitions** (templates), **Groups** (custom approver groups), and **Records** (audit trail).

### 10.2 Pending Approvals (Instances Page)

Three tabs: Pending (default), Approved, Rejected. Each row shows the workflow name, linked entity, status, initiator, and timestamp.

### 10.3 Acting on an Approval

Clicking an instance opens a **side drawer** showing:

- **Header** — Workflow name, status badge, entity type, initiator, timestamp.
- **Entity card** — Key fields from the snapshot, with a link to the full entity.
- **Timeline tab** — Visual flow of all stages and steps with colour-coded status (amber = in progress, green = approved, red = rejected, dashed = skipped), individual approver decisions, and comments.
- **Snapshot tab** — Full entity data at the time the approval was triggered.
- **Action buttons** — Approve (green) and Reject (red), visible only to eligible approvers.

The **approve/reject dialog** shows entity context, a step selector (if multiple steps need the user), expected approvers, and a comment field (optional for approval, mandatory for rejection). Submit via button or Cmd/Ctrl + Enter.

### 10.4 Approval from Entity Detail Pages

The drawer can also open from any entity's detail page, showing all approval instances for that entity with pills to switch between them.

### 10.5 Creating Workflow Definitions

A three-step form:

1. **Basic Info** — Name, description, entity type, trigger type, trigger status (for on_status_change).
2. **Routing** — Priority (0 to 100), default flag, conditions (visual rule builder), on-approval and on-rejection actions.
3. **Workflow Builder** — Add sequential stages, each with parallel steps. Per step: name, required approvals (N), rejection policy, and approver assignments (User, Role, or Group). A live preview shows the workflow structure.

Definitions can be toggled Active or Inactive. Only active definitions trigger approvals.

### 10.6 Approval Groups

Create custom user collections (for example, Risk Committee). Assign a name, description, and member users.

### 10.7 Audit Records

Chronological log of every decision across all workflows: user, decision, step, comment, timestamp.

## 11. Worked Example: Loan Account Activation

**Setup.** Definition "Account Activation Approval" — trigger: `on_status_change`, trigger_status: "Requested", two stages (Maker Verification and Checker Approval). On approval: Activate. On rejection: Deactivate.

| # | Who | Action | System Response |
|---|---|---|---|
| 1 | Relationship Manager | Creates account (Draft), clicks "Submit for Approval" | Account moves to "Requested", approval instance created, Stage 1 activated |
| 2 | Ops Checker | Opens pending approval, reviews snapshot, clicks Approve | Decision recorded. Step A threshold met (1/1). Stage 1 not yet complete — Step B pending |
| 3 | Credit Analyst | Reviews financials, clicks Approve | Step B met. All steps in Stage 1 done, Stage 1 = Approved. Stage 2 activated |
| 4 | Ops Manager | Approves | Step A of Stage 2 met. Step B still pending |
| 5 | Finance Manager | Approves | Stage 2 = Approved. No more stages. System executes Activate. Account = Active |

**If Credit Analyst had rejected at step 3.** Since the step has veto policy, the entire approval is immediately rejected. The system executes Deactivate. The Account becomes Inactive. The rejection comment is preserved in the audit trail.

## 12. Permissions

**Approval Administration** (the "Manage Approval" permission) — Create, edit, and delete definitions, manage groups, view all records. Typically assigned to Admin or Ops Lead roles.

**Approval Execution** — Any user assigned as an approver (by user, role, or group) can see pending approvals, approve or reject assigned steps, and view snapshots. A user cannot approve the same step twice. Superadmins can approve any step regardless of assignment.

## 13. Audit Trail

Every decision records **who** (user, their role, department), **what** (approve or reject, which step), **when** (timestamp), **why** (comment — mandatory for rejections), and **context** (entity snapshot). The audit trail is immutable and accessible from the Records page.

## 14. Version Scope

### 14.1 P0 (v2.3.0) — Current

**Implemented**

- Multi-stage sequential and parallel step approvals
- N-of-M thresholds
- Conditional routing (priority and conditions)
- Approver types: User, Role, Group
- Triggers: On Status Change, On Create, Manual
- Action callbacks (approval and rejection)
- Entity snapshot
- Visual workflow timeline and drawer
- Definition builder UI
- Approval Groups
- Full audit trail

**In development**

- Stage skip conditions

**Under assessment**

- Cancel or recall pending approval
- Re-submission after rejection

### 14.2 Next Phase

- **Approver notifications (email and in-app).** Uses existing notification resolver infrastructure.
- **Escalation and SLA enforcement.** Auto-escalation on approver inaction.
- **On Update trigger.** For config and limit changes. Requires intermediary payload storage. Will deprecate the Review module.
- **On Delete trigger.** Approval before entity deletion.

## 15. Glossary

| Term | Meaning |
|---|---|
| Definition | Reusable approval workflow template |
| Instance | Live execution of a definition for a specific entity |
| Stage | Sequential phase (stages run one after another) |
| Step | Parallel approval point within a stage |
| Threshold (N-of-M) | Required approvals out of total approvers |
| Trigger Status | Intermediate status the entity is held in during approval |
| Action Callback | Business operation executed on approval or rejection |
| Conditional Routing | Selecting different definitions based on entity data and priority |
| Snapshot | Frozen copy of entity data at the moment approval was triggered |
| Veto | Rejection mode where one "No" terminates the entire approval |
| Skip Condition | Rule that causes a stage to be bypassed |
