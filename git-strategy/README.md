Author: Abhishek Sharma
Status: Draft
Category: PRD
Last edited time: January 8, 2026 6:23 PM
Summary: The guide outlines a branching and merge strategy for multi-tenant SaaS applications, detailing merge strategies for application and infrastructure repositories. Key strategies include "Squash & Merge" for features, "Merge Commit" for releases, and "Merge Commit" for hotfixes. A visual overview and repository-specific strategies are provided, along with a quick reference table for when to use each strategy, including branch protection settings to ensure code quality and approval processes.

## Multi-tenant SaaS with Mixed Deployment Models

---

## 📊 Visual Overview

```mermaid
graph TB
    subgraph "Repository Strategy"
        A1[Application Repos<br/>crego-omni/flow/web]
        A2[Infra Repo<br/>crego-infra]
    end

    subgraph "Merge Strategies"
        B1[Feature: Squash]
        B2[Release: Merge]
        B3[Hotfix: Merge]
        B4[Infra: Merge]
    end

    subgraph "Deployment Models"
        C1[Shared Company Env<br/>Single deployment]
        C2[Client Cloud<br/>Independent deployments]
    end

    A1 --> B1 & B2 & B3
    A2 --> B4
    B2 --> C1 & C2

```

---

## 🔀 Merge Strategy Matrix

### **Application Repositories** (crego-omni, crego-flow, crego-web)

| Branch Type | Merge Strategy | Why | When |
| --- | --- | --- | --- |
| **Feature** | `Squash & Merge` | Clean history, single commit per feature | Feature → develop |
| **Release** | `Merge Commit` | Preserve release timeline | Release → master/main |
| **Hotfix** | `Merge Commit` | Preserve hotfix context in history | Hotfix → master/main |
| **Develop** | `Merge Commit` | Preserve hotfix context when merging back | Hotfix → develop |

### **Infrastructure Repository** (crego-infra)

| Branch Type | Merge Strategy | Why |
| --- | --- | --- |
| **Environment** | `Merge Commit` | Track config changes clearly |
| **Client Branch** | `Squash & Merge` | Clean client-specific changes |
| **Main → Env** | `Fast-forward` | Propagate base templates |

---

## 🏗️ Repository-Specific Strategy

### **📁 Application Repos** (crego-omni, crego-flow, crego-web)

```mermaid
graph LR
    subgraph "Feature Flow"
        F[Linear Issue<br/>#CRE-123] --> FB[feature/cre-123-desc]
        FB -->|Squash & Merge| D[develop]
    end

    subgraph "Release Flow"
        D --> RB[release/v2.1.0]
        RB -->|Merge Commit| M[master/main]
        M -->|Tag| T[v2.1.0]
    end

    subgraph "Hotfix Flow"
        P[Production Issue] --> HB[hotfix/cre-456-desc]
        HB -->|Merge Commit| M
        HB -->|Merge Commit| D
    end

```

### **📁 Infrastructure Repo** (crego-infra)

```mermaid
graph TB
    subgraph "Folder Structure"
        FS[crego-infra/<br/>├── apps/<br/>├── base/<br/>├── overlays/<br/>├── argocd-apps/<br/>├── components/<br/>├── config/<br/>├── scripts/<br/>└── terraform/]
    end

    subgraph "Branch Strategy"
        M[main] -->|Fast-forward| EB[env/dev]
        M -->|Fast-forward| UB[env/uat]
        M -->|Fast-forward| PB[env/prod]

        M -->|Squash & Merge| CB1[clients/client-a]
        M -->|Squash & Merge| CB2[clients/client-b]

        CB1 --> CA[Client A Cloud]
        CB2 --> CC[Client B Cloud]
    end

```

## 📋 Quick Reference Table

### **When to Use Which Merge Strategy**

| Scenario | Repo Type | Strategy | Command | Result |
| --- | --- | --- | --- | --- |
| Feature complete | App | Squash | GitHub UI | Single commit in develop |
| Release ready | App | Merge | `--no-ff` | Release marker in history |
| Critical fix | App | Merge | `--no-ff` | Hotfix marker in master/main |
| Env update | Infra | Fast-forward | `--ff-only` | Clean propagation |
| Client config | Infra | Squash | `--squash` | Clean client changes |
| Base template | Infra | Merge | Standard | Track template evolution |

### **Branch Protection Settings**

```
Application Repos (master or main depending on repo):
- master/main: Require squash/merge, 2 approvals
- develop:     Allow squash/merge, 2 approvals
- release/*:   Allow merge commits, 2 approvals
- hotfix/*:    Allow merge commit, 2 approvals

Infrastructure Repo:
- main:        Require squash/merge, 2 approvals
- env/prod:    Require fast-forward only, SRE approval
- clients/*:   Allow squash/merge, client+lead approval
```

---

- [Deployment Models](deployment-models.md)
- [Complete Workflow with Merge Strategies](complete-workflow.md)
- [Practical Commands Guide](practical-commands.md)
- [Infrastructure Structure & Workflow](infrastructure-workflow.md)
- [Client Version Management](client-version-management.md)
- [Emergency Procedures](emergency-procedures.md)