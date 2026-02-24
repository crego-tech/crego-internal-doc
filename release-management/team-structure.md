# Team Structure & Responsibilities

> Last updated: February 2026
> Total headcount: ~12 (Engineering + QA)

---

## Org Chart

```
                           CTO
                            │
            ┌───────────────┼───────────────┐
            │               │               │
      Engg Manager       FE Lead         BE Lead
      (Full-stack)          │               │
                        3 FE Devs       3 BE Devs

                      QA (2 engineers)
                 (report to Engg Manager / CTO)
```

---

## Roles & Responsibilities

### CTO

The CTO owns the engineering org, technical direction, and delivery.

- Owns overall technical architecture and technology decisions
- Sets engineering standards, code quality bar, and security posture
- Approves major infrastructure changes and production deployments
- Manages the Engg Manager, FE Lead, and BE Lead directly
- Escalation point for cross-team technical conflicts
- Owns the release calendar and go/no-go decisions for production

### Engg Manager (Full-Stack)

A senior engineering leader who operates as the technical authority across the full stack. Reports directly to the CTO and drives engineering execution, quality, and technical strategy.

- Reviews the most complex and cross-cutting PRs
- Owns technical design decisions that span frontend and backend
- Acts as the go-to escalation for stuck code reviews (the "2-day stuck" escalation path)
- Drives architectural improvements, tech debt prioritization, and performance work
- Mentors developers and leads across both frontend and backend
- Acts as Release Manager for production deployments
- Partners with the CTO on technical strategy and engineering roadmap
- Owns backlog triage, issue prioritization, and sprint planning (in coordination with FE/BE Leads)
- Coordinates UAT with clients and stakeholders
- Writes or delegates release notes

### Frontend Lead

Manages the frontend team and owns frontend delivery.

- Manages 3 frontend developers
- Owns frontend architecture decisions (component patterns, state management, monorepo structure)
- Reviews frontend PRs and ensures code quality standards
- Assigns frontend issues to developers during sprint planning
- Coordinates with BE Lead on API contracts and integration points
- Responsible for frontend build pipeline and CI/CD health
- Escalation point for frontend-specific technical issues

### Backend Lead

Manages the backend team and owns backend delivery.

- Manages 3 backend developers
- Owns backend architecture decisions (API design, database schema, Celery task patterns)
- Reviews backend PRs and ensures code quality standards
- Assigns backend issues to developers during sprint planning
- Owns database migrations and data integrity
- Responsible for backend CI/CD, test coverage, and API documentation
- Escalation point for backend-specific technical issues

### Frontend Developers (3)

- Build and maintain UI components, pages, and features in the crego-web monorepo
- Write unit and integration tests for frontend code
- Participate in code reviews as both authors and reviewers
- Follow the git branching strategy and PR workflow
- Provide testing notes on issues before PR merge (for QA handoff)

### Backend Developers (3)

- Build and maintain APIs, services, and background tasks across crego-ai, crego-flow, and crego-omni
- Write unit and integration tests for backend code
- Participate in code reviews as both authors and reviewers
- Follow the git branching strategy and PR workflow
- Own database migrations for their features
- Provide testing notes on issues before PR merge (for QA handoff)

### QA Engineers (2)

QA owns quality across the entire release lifecycle.

- Own issues from "QA" through "UAT" in the workflow
- Test features on the internal dev environment against acceptance criteria
- Perform regression and integration testing on pre-prod for releases
- Create and maintain test cases
- File bugs with `type:bug` label and flag `release-blocker` when critical
- Coordinate UAT logistics with Engg Manager and clients
- Sign off on releases before production deployment
- Monitor the "QA" state — pick up testing within 1 business day

---

## RACI Matrix — Release Process

**R** = Responsible (does the work), **A** = Accountable (final decision), **C** = Consulted, **I** = Informed

| Activity | CTO | Engg Manager | FE/BE Lead | Developer | QA |
|---|---|---|---|---|---|
| Create & prioritize issues | I | R/A | C | I | C |
| Sprint planning & assignment | A | R | R | I | C |
| Feature development | I | C | C | R/A | I |
| Code review | I | R | R | R | — |
| PR merge to develop | I | A | R | R | — |
| Testing on dev | I | C | I | C | R/A |
| Cut release branch | A | R | C | I | C |
| Pre-prod testing | I | C | I | C | R/A |
| UAT coordination | I | R | — | C | R |
| UAT sign-off | A | R | — | — | C |
| Production deployment | A | R | I | I | C |
| Production smoke test | I | C | I | I | R/A |
| Release notes | I | R/A | — | C | I |
| Merge master → develop | A | R | I | I | — |
| Hotfix decision | A | R | C | I | C |
| Hotfix implementation | I | R | C | R | C |

---

## Escalation Paths

| Situation | First Escalation | Final Escalation |
|---|---|---|
| PR stuck in review 2+ days | Engg Manager | CTO |
| Issue stuck in QA 2+ days | Engg Manager / QA Lead | CTO |
| Release blocker found in pre-prod | Engg Manager | CTO |
| UAT rejected or scope dispute | Engg Manager | CTO |
| Cross-team technical conflict (FE vs BE) | Engg Manager | CTO |
| Priority disagreement | Engg Manager | CTO |
| Production incident | Engg Manager | CTO |
| Client escalation | Engg Manager | CTO |

---

## Key Pairing Relationships

These roles work closely together and should have regular sync points:

- **CTO + Engg Manager** — Release go/no-go, resource allocation, technical strategy
- **Engg Manager + FE/BE Leads** — Architecture decisions, cross-cutting PRs, tech debt planning
- **Engg Manager + QA** — Stuck issue escalation, testing strategy, release readiness, UAT coordination
- **FE Lead + BE Lead** — API contracts, integration points, cross-repo coordination
