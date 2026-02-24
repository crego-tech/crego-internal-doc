
This is a **single, standardized interview set** to be used for **all candidates**.  
Each question is intentionally detailed so interviewers can probe **depth, ownership, and real production experience**, not just tool knowledge.

---

## 1. Production Incident & Root Cause Analysis (RCA)

**Question**  
Tell me about the **most severe production incident** you have personally handled.

**Cover in your answer:**
- What exactly failed (service, dependency, infra, network, deployment, etc.)
- How the issue was detected (alert, customer complaint, dashboard, log anomaly)
- Blast radius (users affected, revenue/SLA impact)
- Timeline of actions taken
- Root cause (not symptoms)
- Immediate mitigation vs long-term fix
- What was changed to **prevent recurrence**
- What you would do differently today

**What we are evaluating**
- Ownership (did *you* handle it?)
- RCA quality (systems thinking vs blame)
- Calmness under pressure
- Postmortem maturity

---

## 2. Kubernetes Failure Scenario (Debugging Depth)

**Question**  
A service running in **Amazon EKS** is restarting continuously.  
Node CPU and memory look healthy.

**Walk us step by step through how you would debug this.**

**Cover in your answer:**
- Which `kubectl` commands you would run and why
- How you check:
  - Pod events
  - Container logs
  - Liveness/readiness probes
  - Resource limits and requests
  - OOMKills and exit codes
- How ConfigMaps/Secrets might be involved
- How you determine whether this is:
  - App-level
  - Config-level
  - Cluster-level
- When you would escalate vs roll back

**What we are evaluating**
- Kubernetes fundamentals
- Debug methodology (order matters)
- Signal vs noise handling
- Production readiness

---

## 3. Terraform Architecture & Environment Design

**Question**  
Explain how you design **Terraform** for multiple environments such as **dev, staging, and production**.

**Cover in your answer:**
- Repository structure (folders, modules, mono vs multi repo)
- State management:
  - Backend choice (S3, GCS, etc.)
  - State locking
  - Separation per environment
- How you handle:
  - Variables and secrets
  - Environment-specific differences
  - Module versioning
- How you detect and handle drift
- How rollbacks are performed safely

**What we are evaluating**
- Infrastructure design maturity
- Safety and scalability
- Experience beyond `terraform apply`

---

## 4. AWS vs GCP Platform Decision

**Question**  
You are designing a new microservices platform.  
When would you choose **EKS over GKE**, and when would you prefer **GKE over EKS**?

**Cover in your answer:**
- Operational overhead differences
- IAM vs GCP IAM experience
- Networking models
- Cost and scaling behavior
- Day-2 operations (upgrades, node pools)
- Team skill considerations
- Managed vs self-managed trade-offs

**What we are evaluating**
- Cloud platform understanding
- Decision-making, not preference
- Real-world trade-offs

---

## 5. CI/CD Safety & Release Engineering

**Question**  
How do you design a **CI/CD pipeline** so that **bad code never reaches production**?

**Cover in your answer:**
- PR checks and branch protection
- Automated testing strategy
- Security scans (SAST/DAST/image scans)
- Manual vs automated approvals
- Environment promotion strategy
- Canary / blue-green deployments
- Rollback triggers

**What we are evaluating**
- Release safety mindset
- Pipeline robustness
- Balance between speed and safety

---

## 6. Observability & Alerting Design

**Question**  
Design the **observability stack** for a **critical payment service**.

**Cover in your answer:**
- Key SLIs (latency, error rate, availability, throughput)
- Difference between metrics, logs, and traces
- Alerting rules (what should page vs not page)
- How to avoid alert fatigue
- Dashboards you would create
- How this supports incident response

**What we are evaluating**
- SRE thinking
- Signal-driven monitoring
- Practical alert design

---

## 7. Cloud Cost Optimization Scenario

**Question**  
Your AWS bill increased by **40% month-over-month**.

**Walk us through exactly how you would investigate and reduce it.**

**Cover in your answer:**
- Initial data sources (CUR, Cost Explorer, tags)
- Identifying the cost drivers
- Common waste patterns:
  - Idle compute
  - Over-provisioned EKS
  - Storage leaks
  - NAT / data transfer costs
- Short-term fixes vs long-term controls
- Governance and prevention mechanisms

**What we are evaluating**
- FinOps awareness
- Practical cost control
- Business impact thinking

---

## 8. Secrets Management & Security

**Question**  
How do you manage **secrets securely** across:
- CI/CD pipelines
- Kubernetes
- Cloud services

**Cover in your answer:**
- IAM roles vs static credentials
- KMS / Vault / Sealed Secrets
- Secret rotation
- Preventing secrets from leaking into logs or repos
- Developer experience vs security trade-offs

**What we are evaluating**
- Security maturity
- Practical implementation
- Risk awareness

---

## 9. Rollback, Recovery & Data Safety

**Question**  
A production deployment is causing user-facing errors.

**How do you roll back safely without data loss?**

**Cover in your answer:**
- Deployment strategies (blue-green, canary, feature flags)
- Database migration handling
- Backward compatibility
- Traffic shifting
- Communication during rollback
- Post-rollback verification

**What we are evaluating**
- Reliability mindset
- Data safety awareness
- Production discipline

---

## 10. DevOps Judgment & Maturity

**Question**  
Tell us about **one DevOps practice, tool, or process that you removed or simplified**, and why.

**Cover in your answer:**
- What was removed
- Why it was not providing value
- What replaced it (if anything)
- Impact on reliability, speed, or team happiness
**What we are evaluating**
- Engineering judgment
- Ability to reduce complexity
- Seniority signal
---
## Scoring Rubric (Recommended)
Score each question **0–3**:
- **0** – No real experience / theory only  
- **1** – Basic understanding  
- **2** – Solid hands-on experience  
- **3** – Production-grade depth, clear ownership  

**Maximum Score: 30**
- **26–30** → Strong Hire  
- **20–25** → Hire  
- **15–19** → Risky Hire  
- **<15** → Do Not Hire