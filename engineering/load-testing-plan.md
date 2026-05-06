# Crego Platform — Load Testing Plan

> **Last updated:** 2026-04-04
> **Status:** Ready for team review
> **Timeline:** 4 weeks (target completion by early May 2026)

## Decisions Log

All open questions have been resolved. Here is the summary of decisions made:

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Peak concurrency target | **50–100 simultaneous users** | Current scale; 1–2 primary production tenants |
| SLA posture | **Informal — no errors + "feels fast" (<2s)** | No contractual SLAs yet; goal is to establish baselines |
| Environment | **Dedicated `loadtest-gcp` environment** | Avoids interference with QA/UAT on preprod; full isolation |
| Primary tool | **Locust (Python)** | Team is Python-fluent, new to load testing; Locust has lowest learning curve |
| Third-party services | **In-cluster mock server** | Deploy a FastAPI mock returning realistic responses with configurable latency |
| Test data | **Full seeding required** (preprod DBs are mostly empty) | Build seeding scripts from scratch for PostgreSQL + MongoDB |
| Team ownership | **Shared** — Backend writes scripts, QA validates scenarios, Infra monitors | Collaborative; plan includes clear per-team deliverables |
| Tenant simulation | **1–2 primary tenants** | Reflects actual production traffic distribution |
| Pass/fail criteria | **Zero 5xx errors + all pages load < 2s** under 100 concurrent users | Formal P95 targets to be established after baseline run |

---

## 1. Platform Architecture Summary

The Crego platform consists of five key components that must be load tested as an integrated system:

| Service | Stack | Database | Port | Key Bottlenecks |
|---------|-------|----------|------|-----------------|
| **crego-omni** (API) | Django 5.2 + Gunicorn (4 workers) | PostgreSQL | 8000 | Double-entry ledger writes, approval workflows, report generation |
| **crego-flow** (API) | FastAPI + Uvicorn + Gunicorn (4 workers) | MongoDB | 8000 | Workflow graph execution, LLM calls (Gemini), bulk uploads |
| **crego-web** (Frontend) | React 19 + Nginx | — | 8000 | Static asset serving, initial bundle load (~600KB+ JS) |
| **Celery Workers** (Omni + Flow) | Celery 2 concurrency per worker | RabbitMQ broker | — | Queue depth, tenant-specific queues, GL posting, notifications |
| **Infrastructure** | GKE + Cloud SQL + Memorystore + RabbitMQ | — | — | HPA max replicas (currently 1 in prod), KEDA scaling lag |

**Request Flow:**
```
Client → GCP Gateway (L7 LB, HTTPS) → Path-based routing:
  /api/*       → omni-api (Django)
  /flow/api/*  → flow-api (FastAPI)
  /flower/*    → flower:5555
  /flow/*      → flow-web (Nginx)
  /            → omni-web (Nginx)
```

**Multi-Tenancy:** Each tenant gets isolated Celery queues (`{service}_tenant_{alias}_default`), database routing via `X-Tenant-Alias` header, and separate Beat schedulers. Load tests will simulate 2 tenants with realistic traffic split.

---

## 2. Load Testing Tool: Locust

**Primary tool: Locust** — the team is Python-fluent and new to structured load testing. Locust provides the lowest friction path to getting real results.

| Aspect | Detail |
|--------|--------|
| **Language** | Python (matches backend team skills) |
| **Why Locust** | Python-native, easy to write stateful user journeys, built-in web UI for real-time monitoring, distributed mode for scaling load generators |
| **Install** | `pip install locust` |
| **Execution** | `locust -f locustfile.py --host=https://loadtest.crego.ai` |
| **Distributed mode** | Master + workers for generating 100+ concurrent users from a single machine |
| **Results** | Built-in web dashboard + CSV export; can integrate with Prometheus via `locust-plugins` |
| **CI/CD** | `locust --headless --csv=results -t 5m` for automated runs |

**Future consideration:** Once the team is comfortable, add k6 for lightweight CI/CD smoke tests (5-min runs on every deployment). For now, Locust covers all needs.

---

## 3. Environment & Infrastructure Setup

### 3.1 Dedicated Load Test Environment (`loadtest-gcp`)

Since running against preprod would interfere with QA/UAT, create a dedicated environment.

**Infra team deliverable — create overlay in `crego-infra`:**

```
overlays/loadtest-gcp/
├── kustomization.yaml
├── gateway.yaml                    # GCP Gateway API config
├── httproute.yaml                  # Path-based routing (same as prod)
├── healthcheck-policies.yaml
├── secret-store.yaml               # GCP Secret Manager backend
├── managed-certificates.yaml       # TLS for loadtest.crego.ai
├── mock-server/
│   ├── deployment.yaml             # FastAPI mock for 3rd-party APIs
│   ├── service.yaml
│   └── configmap.yaml              # Mock response configs
└── patches/
    ├── omni-api-resources.yaml     # 1 CPU / 2Gi RAM (match prod)
    ├── flow-api-resources.yaml     # 1 CPU / 2Gi RAM (match prod)
    ├── celery-workers.yaml         # 500m / 512Mi per worker
    ├── hpa-settings.yaml           # Match prod HPA (maxReplicas=1 initially)
    └── keda-settings.yaml          # Match prod KEDA config
```

**Key requirements:**
- Mirror production resource limits exactly (1 CPU / 2Gi RAM for APIs, 500m / 512Mi for workers)
- Mirror production HPA/KEDA settings (start with maxReplicas=1 to find true baseline)
- Use Cloud SQL (not in-cluster PostgreSQL) and Memorystore Redis to match prod
- In-cluster RabbitMQ (same as prod)
- Separate namespace: `loadtest`
- Domain: `loadtest.crego.ai` (or `loadtest.dev.crego.ai` if using existing DNS zone)
- **2 tenants configured:** `loadtest-primary` (main traffic) and `loadtest-secondary` (concurrent tenant)

**Estimated additional cost:** ~$200-300/month (can be torn down between test cycles)

### 3.2 In-Cluster Mock Server

Deploy a lightweight FastAPI service that replaces all third-party APIs during load tests. This avoids SMS costs, Gemini rate limits, and OIDC dependency.

**Mock server must handle:**

| External Service | Mock Endpoint | Mock Behavior |
|-----------------|---------------|---------------|
| **Kaleyra SMS** | `POST /mock/kaleyra/send` | Return `{"status": "sent", "id": "mock-123"}` after 50ms delay |
| **Email (SMTP)** | `POST /mock/email/send` | Return 200 OK, log to stdout (no actual delivery) |
| **Gemini AI** | `POST /mock/gemini/generate` | Return a realistic extraction JSON after 500ms delay (simulates LLM latency) |
| **OIDC JWKS** | `GET /mock/oidc/.well-known/jwks.json` | Return a static JWKS with test signing keys |
| **S3/GCS** | Use MinIO in-cluster | Lightweight S3-compatible storage for document uploads |

**Configuration in loadtest environment:**
```yaml
# ConfigMap overrides for mock endpoints
KALEYRA_API_URL: "http://mock-server.loadtest.svc.cluster.local:8080/mock/kaleyra"
GEMINI_API_URL: "http://mock-server.loadtest.svc.cluster.local:8080/mock/gemini"
OIDC_JWKS_URI: "http://mock-server.loadtest.svc.cluster.local:8080/mock/oidc/.well-known/jwks.json"
SMTP_HOST: "mock-server.loadtest.svc.cluster.local"
```

**Mock latency configuration (via ConfigMap):**
```json
{
  "kaleyra_delay_ms": 50,
  "gemini_delay_ms": 500,
  "email_delay_ms": 20,
  "oidc_delay_ms": 10
}
```

### 3.3 Data Seeding (Critical — preprod DBs are empty)

**Backend team deliverable — create seeding scripts:**

```
crego-load-tests/seed/
├── seed_postgres.py       # Omni data (Django management command or standalone)
├── seed_mongodb.py        # Flow data (MongoEngine script)
├── seed_config.yaml       # Configurable volumes per tenant
├── sample_data/
│   ├── contacts.json      # Template contact records
│   ├── programs.json      # Product/program configurations
│   ├── flow_designs.json  # Sample workflow graph definitions
│   └── documents/         # Sample PDFs, CSVs for upload tests
└── cleanup.py             # Reset to clean state between runs
```

**Data volumes per tenant:**

| Entity | Volume | Notes |
|--------|--------|-------|
| Users | 100 | Mix of staff, partners, customers, agents |
| Contacts | 10,000 | With addresses, bank details |
| Programs | 5 | Different lending product types |
| Accounts | 5,000 | Distributed across programs |
| Transactions | 50,000 | Historical, various statuses (pending, completed, failed) |
| Components | 150,000 | ~3 components per transaction |
| Ledger entries | 100,000 | Double-entry records |
| GL Accounts | 50 | Chart of accounts hierarchy |
| Flows (crego-flow) | 10 | Active workflow definitions with designs |
| Runners | 500 | Active workflow executions at various stages |
| Documents | 200 | Sample uploaded files in mock S3/MinIO |
| Approval instances | 100 | Multi-level approvals in various states |

**Seeding order (respects foreign key dependencies):**
1. Users and roles → 2. Contacts → 3. Programs → 4. GL Accounts → 5. Accounts → 6. Transactions + Components + Ledgers → 7. Approval instances → 8. Flows + Designs → 9. Runners + Stores → 10. Documents

**Estimated seeding time:** ~10-15 minutes per tenant

### 3.4 Monitoring Stack

**Active during every load test run:**

| Tool | Purpose | Owner | Setup |
|------|---------|-------|-------|
| **Locust Web UI** | Real-time RPS, response times, failure rate | QA | Built into Locust (port 8089) |
| **Grafana** | Infrastructure metrics dashboards | Infra | Enable `ENABLE_MONITORING=true`, `ENABLE_PROMETHEUS=true`, `ENABLE_GRAFANA=true` |
| **Sentry** | Error traces + performance traces | Backend | Set `SENTRY_TRACES_SAMPLE_RATE=1.0` in loadtest env |
| **Flower** | Celery queue depths, task durations, worker status | Infra | Already deployed; URL: `/flower/` |
| **PostgreSQL** | Slow query analysis | Backend | Enable `pg_stat_statements` + `auto_explain` (log queries >500ms) |
| **MongoDB Profiler** | Slow query analysis | Backend | Set profiler level 1, threshold 100ms |
| **kubectl top** | Pod CPU/memory during tests | Infra | Manual spot checks |

**4 Grafana dashboards to create (Infra team deliverable):**
1. **API Performance** — Request rate, P50/P95/P99 latency, error rate per service
2. **Celery Queues** — Queue depth per tenant, task completion rate, worker utilization
3. **Database** — Active connections, query duration, lock waits, connection pool usage
4. **Infrastructure** — Pod CPU/memory, HPA replica count, KEDA scaling events, node utilization

---

## 4. Test Scenarios

### 4.1 API Endpoint Load Tests

Concurrency targets are calibrated for 50–100 simultaneous users across 1–2 tenants.

#### Tier 1 — Critical Path (highest traffic, test first)

| # | Scenario | Service | Method & Endpoint | Target Concurrent Users | Notes |
|---|----------|---------|-------------------|------------------------|-------|
| 1 | **Authentication** | omni-api | `POST /api/auth/login/` | 10 | JWT token generation, OIDC validation (via mock JWKS) |
| 2 | **Token Refresh** | omni-api | `POST /api/auth/token/refresh/` | 20 | Called by every active session periodically |
| 3 | **List Transactions** | omni-api | `GET /api/transactions/?limit=20` | 40 | Most-hit endpoint, pagination + filtering |
| 4 | **Get Transaction Detail** | omni-api | `GET /api/transactions/{id}/` | 30 | Includes nested components, ledger entries |
| 5 | **List Contacts** | omni-api | `GET /api/contacts/?search=...` | 20 | Full-text search, filtering |
| 6 | **List Accounts** | omni-api | `GET /api/products/accounts/` | 20 | Program-scoped queries |
| 7 | **List Runners** | flow-api | `GET /flow/api/runners/?limit=20` | 20 | Recently optimized (2-3x improvement in v2.3.0) |
| 8 | **Get Runner Detail** | flow-api | `GET /flow/api/runners/{id}/` | 15 | Expandable: flow, design, store, activity |
| 9 | **Health Checks** | both | `GET /api/health/`, `GET /flow/api/health/` | 2 | Baseline — must stay <200ms under load |

#### Tier 2 — Write Operations

| # | Scenario | Service | Method & Endpoint | Target Concurrent Users | Notes |
|---|----------|---------|-------------------|------------------------|-------|
| 10 | **Create Transaction** | omni-api | `POST /api/transactions/` | 10 | Double-entry ledger write, GL mapping |
| 11 | **Batch Transactions** | omni-api | `POST /api/transactions/batch/` | 2 | Bulk create with batch processing |
| 12 | **Create Contact** | omni-api | `POST /api/contacts/` | 5 | Validation + deduplication |
| 13 | **Submit Approval** | omni-api | `POST /api/approvals/{id}/approve/` | 5 | Multi-level approval chain |
| 14 | **Execute Runner** | flow-api | `POST /flow/api/runners/{id}/execute/` | 10 | Graph traversal, node execution, store writes |
| 15 | **Create Flow** | flow-api | `POST /flow/api/flows/` | 2 | Design creation + graph validation |
| 16 | **Upload Document** | omni-api | `POST /api/documents/` | 5 | Upload to MinIO (mock S3) |

#### Tier 3 — Heavy Operations (Background Tasks via Celery)

| # | Scenario | Service | Trigger | Concurrency | Notes |
|---|----------|---------|---------|-------------|-------|
| 17 | **Generate Report** | omni-api | `POST /api/reports/generate/` | 3 concurrent | Celery task, 10-minute timeout |
| 18 | **Bulk Upload (Workbook)** | flow-api | `POST /flow/api/workbook/import/` | 2 concurrent | CSV/Excel parse → DB writes, 10-min timeout |
| 19 | **Bulk Export** | flow-api | `POST /flow/api/workbook/export/` | 2 concurrent | DB query → Excel generation → MinIO upload |
| 20 | **AI Document Extract** | flow-api | `POST /flow/api/onyx/parser/extract` | 3 concurrent | Hits mock Gemini (500ms simulated latency) |
| 21 | **Send Notifications** | omni-api | Triggered via transaction events | 10/min | Hits mock Kaleyra/Email (50ms latency) |
| 22 | **GL Posting** | omni-api | Triggered via transaction creation | 10/min | `post_entry_to_gl` Celery task |

### 4.2 User Journey Tests (Locust)

These simulate realistic end-to-end user workflows. Each journey is a Locust `TaskSet`.

**Journey 1: Loan Officer Daily Workflow (heaviest traffic)**
```
1. Login (POST /api/auth/login/)                                    — once per session
2. List assigned accounts (GET /api/products/accounts/?assignee=self) — weight: 3
3. View account detail (GET /api/products/accounts/{id}/)            — weight: 2
4. List transactions for account (GET /api/transactions/?account_id={id}) — weight: 3
5. Create new transaction (POST /api/transactions/)                  — weight: 1
6. Submit for approval (POST /api/approvals/)                        — weight: 1
7. View dashboard metrics (GET /api/reports/dashboard/)              — weight: 1
Think time: 2-5 seconds between actions (realistic user behavior)
```
Target: **40 concurrent users** on primary tenant, 5-minute ramp-up

**Journey 2: Workflow Execution (Flow service focus)**
```
1. Login                                                             — once per session
2. List active flows (GET /flow/api/flows/?status=active)            — weight: 2
3. Create new runner (POST /flow/api/runners/)                       — weight: 1
4. Execute runner step-by-step (POST /flow/api/runners/{id}/execute/) x 5 nodes — weight: 3
5. Upload document to runner (POST /flow/api/documents/)             — weight: 1
6. AI extract document (POST /flow/api/onyx/parser/extract)          — weight: 1
7. Complete workflow                                                  — weight: 1
Think time: 3-8 seconds between actions
```
Target: **15 concurrent users** on primary tenant, 3-minute ramp-up

**Journey 3: Bulk Operations (low concurrency, high resource impact)**
```
1. Login
2. Upload CSV with 500 rows (POST /flow/api/workbook/import/)
3. Poll operation status every 5s (GET /flow/api/workbook_operations/{id}/)
4. Download result file (GET /flow/api/documents/{id}/files/download/)
Think time: 5s polling interval
```
Target: **3 concurrent users**

**Journey 4: Multi-Tenant Concurrent (validates isolation)**
```
Run simultaneously across both configured tenants:
- Tenant loadtest-primary: 40 users running Journey 1 + 10 users running Journey 2
- Tenant loadtest-secondary: 20 users running Journey 1 + 5 users running Journey 2 + 2 users running Journey 3
Total: ~77 concurrent users
```
Target: Verify no cross-tenant performance degradation, queue isolation works

### 4.3 Infrastructure & Scaling Tests

| Test Type | Description | Duration | Pass Criteria |
|-----------|-------------|----------|---------------|
| **Baseline** | 50 concurrent users, steady state | 15 min | Zero 5xx errors, all responses < 2s |
| **Target Load** | 100 concurrent users, steady state | 15 min | Zero 5xx errors, all responses < 2s |
| **Spike Test** | Ramp from 10 → 150 users in 30 seconds | 5 min | Error rate < 1%, recovery within 60s |
| **Soak Test** | 80 users steady for 2 hours | 2 hours | No memory leaks, no connection pool exhaustion, stable response times |
| **Stress Test** | Ramp up 10 users/minute until failure | Until break | Identify breaking point; system returns 503 (not 500) |
| **Failover Test** | Kill 1 API pod during 50-user load | 10 min | LB drains connections, new pod ready <60s, zero dropped requests |
| **Queue Saturation** | Flood Celery with 1,000 tasks while 50 API users active | 15 min | KEDA scales workers, queue drains < 5 min, API unaffected |

---

## 5. Pass / Fail Criteria

Since there are no formal SLAs yet, the goal is "no errors + reasonable speed." These thresholds define what that means concretely:

### Primary Pass Criteria (must pass to consider load test successful)

| Metric | Threshold | Measured How |
|--------|-----------|--------------|
| **5xx error rate** | **0%** under 100 concurrent users | Locust failure count |
| **Page/API response time** | **All responses < 2 seconds** (P100) | Locust response time stats |
| **Pod restarts** | **Zero** during any test | `kubectl get pods` + Grafana |
| **Data integrity** | **Zero** data corruption or lost transactions | Post-test data validation query |

### Secondary Metrics (track but don't fail on — used to establish future SLOs)

| Metric | Track | Purpose |
|--------|-------|---------|
| P50 response time per endpoint | Locust CSV export | Baseline for future P50 target |
| P95 response time per endpoint | Locust CSV export | Baseline for future P95 SLO |
| Celery queue max depth | Flower / Grafana | Determine queue capacity |
| Celery task completion time (P95) | Flower / Grafana | Baseline for async SLO |
| DB active connections (peak) | `pg_stat_activity` | Capacity planning |
| Pod CPU/memory peak utilization | Grafana | Right-sizing resource limits |
| Memory growth trend over soak test | Grafana | Detect memory leaks |
| HPA/KEDA scaling reaction time | Grafana events | Tune scaling parameters |

After the first full run, these secondary metrics become the baseline for defining formal P95 targets in the results report.

---

## 6. Step-by-Step Execution Plan (4 Weeks)

### Week 1: Setup

| Step | Task | Owner | Deliverable |
|------|------|-------|-------------|
| 1.1 | Create `loadtest-gcp` infra overlay | **Infra** | Kustomize overlay deployed via ArgoCD |
| 1.2 | Deploy mock server in-cluster | **Infra** | FastAPI mock for Kaleyra, Gemini, OIDC, Email |
| 1.3 | Deploy MinIO for document storage | **Infra** | S3-compatible storage in loadtest namespace |
| 1.4 | Create Locust project + repo structure | **Backend** | `crego-load-tests/` repo with initial files |
| 1.5 | Write data seeding scripts | **Backend** | `seed_postgres.py` + `seed_mongodb.py` |
| 1.6 | Configure monitoring dashboards (4 dashboards) | **Infra** | Grafana dashboards for API, Celery, DB, Infra |
| 1.7 | Create test user accounts (2 tenants) | **Backend** | 100 users per tenant with appropriate roles |
| 1.8 | Set Sentry trace rate to 100% in loadtest env | **Backend** | ConfigMap update |
| 1.9 | Document current prod baseline from Sentry | **All** | Baseline report (current latencies, error rates) |

### Week 2: Baseline & Individual Endpoint Tests

| Step | Task | Owner | Deliverable |
|------|------|-------|-------------|
| 2.1 | Run seeding scripts, verify data volumes | **Backend** | Confirmation: data counts match targets |
| 2.2 | Smoke test: 1 user per endpoint, verify 200s | **QA** | All endpoints return expected responses |
| 2.3 | Run Tier 1 read tests (each endpoint individually) | **QA** | Per-endpoint P50/P95/P99 at target concurrency |
| 2.4 | Run Tier 2 write tests (each endpoint individually) | **QA** | Write latencies + data integrity check |
| 2.5 | Run Tier 3 background task tests | **Backend** | Task completion times, queue behavior |
| 2.6 | Compile baseline report | **All** | Spreadsheet: endpoint × latency percentile × error rate |

### Week 3: Integration & Journey Tests

| Step | Task | Owner | Deliverable |
|------|------|-------|-------------|
| 3.1 | Run Journey 1 (Loan Officer) at 40 users for 15 min | **QA** | Journey success rate, bottleneck identification |
| 3.2 | Run Journey 2 (Workflow) at 15 users for 15 min | **QA** | Flow service performance under load |
| 3.3 | Run Journey 3 (Bulk Ops) at 3 users for 15 min | **QA** | Celery + MinIO performance |
| 3.4 | Run Journey 4 (Multi-Tenant) — all tenants for 30 min | **QA + Infra** | Cross-tenant isolation validation |
| 3.5 | Run combined load: Tier 1 reads + Tier 3 background tasks | **QA** | API latency under background task pressure |
| 3.6 | Monitor Celery queues, verify KEDA scaling | **Infra** | KEDA scaling logs, queue drain times |
| 3.7 | Collect Grafana snapshots + Sentry traces | **Infra** | Saved dashboards for results report |

### Week 4: Stress, Resilience & Final Report

| Step | Task | Owner | Deliverable |
|------|------|-------|-------------|
| 4.1 | Spike test: 10 → 150 users in 30s | **QA + Infra** | Recovery time, error spike analysis |
| 4.2 | Stress test: ramp until failure | **QA + Infra** | Breaking point identified (N users / N RPS) |
| 4.3 | Soak test: 80 users for 2 hours | **QA + Infra** | Memory trend, connection pool stability |
| 4.4 | Pod failover test | **Infra** | Zero-downtime validation |
| 4.5 | Queue saturation test (1K tasks burst) | **Infra** | KEDA response time, queue drain time |
| 4.6 | Compile final results report | **All** | Document with findings, bottlenecks, recommendations |
| 4.7 | Propose formal SLO targets based on baselines | **All** | P95 targets per endpoint for future enforcement |
| 4.8 | File Linear issues for identified bottlenecks | **Backend** | CRE-xxx issues with `type/improvement` label |

---

## 7. Known Risks & Mitigations

| # | Risk | Impact | Mitigation | Owner |
|---|------|--------|------------|-------|
| 1 | **Prod HPA maxReplicas = 1** | Cannot scale APIs horizontally | Test at maxReplicas=1 first (find single-pod limits), then re-test at 3 to measure scaling benefit | Infra |
| 2 | **Gunicorn timeout = 1000s** (omni) | Long-running request blocks 1 of 4 workers (25% capacity) | Document in findings; recommend reducing to 120s and moving long ops to Celery | Backend |
| 3 | **Celery concurrency = 2** per worker | Low task throughput per pod | Test with concurrency=4 during soak test; monitor memory | Backend |
| 4 | **No rate limiting in omni production** | Unprotected against traffic spikes | Note in findings; recommend enabling `RateLimitMiddleware` | Backend |
| 5 | **Single RabbitMQ replica** | SPOF for all async processing | Include in failover test (kill RabbitMQ pod); document recovery time | Infra |
| 6 | **Mock server latency may not match reality** | Results may understate 3rd-party latency impact | Configure mock delays to match observed production latency; document assumptions | Backend |
| 7 | **Loadtest env cost** | ~$200-300/month ongoing | Tear down between test cycles; only run for scheduled test windows | Infra |
| 8 | **Seeding script maintenance** | Schema changes break seeding | Keep seed scripts in sync with model changes; run as part of CI validation | Backend |

---

## 8. Locust Script Template

```python
# crego-load-tests/locust/locustfile.py
"""
Main Locust file for Crego platform load testing.
Run: locust -f locustfile.py --host=https://loadtest.crego.ai
"""
import json
import random
import time
from locust import HttpUser, task, between, tag, events

# ─── Configuration ────────────────────────────────────────────
TENANT_ALIAS = "loadtest-primary"
TEST_USER_EMAIL = "loadtest-user-{n}@crego.test"
TEST_USER_PASSWORD = "LoadTest2026!"  # Override via env var in CI


class CregoUser(HttpUser):
    """Base user class with authentication and tenant headers."""
    wait_time = between(2, 5)  # Realistic think time between actions
    abstract = True

    def on_start(self):
        """Login and store JWT token."""
        user_num = random.randint(1, 100)
        response = self.client.post(
            "/api/auth/login/",
            json={
                "email": TEST_USER_EMAIL.format(n=user_num),
                "password": TEST_USER_PASSWORD,
            },
            headers={
                "Content-Type": "application/json",
                "X-Tenant-Alias": TENANT_ALIAS,
            },
        )
        if response.status_code == 200:
            data = response.json()
            self.token = data.get("access", "")
            self.refresh_token = data.get("refresh", "")
        else:
            self.token = ""
            self.environment.runner.quit()  # Stop if login fails

    @property
    def auth_headers(self):
        return {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
            "X-Tenant-Alias": TENANT_ALIAS,
            "X-Timezone": "Asia/Kolkata",
        }


# ─── Journey 1: Loan Officer ──────────────────────────────────
class LoanOfficerUser(CregoUser):
    """Simulates a loan officer's daily workflow on crego-omni."""
    weight = 4  # 4x more likely to spawn than other user types

    @task(3)
    @tag("tier1", "read")
    def list_accounts(self):
        self.client.get(
            "/api/products/accounts/?limit=20&offset=0",
            headers=self.auth_headers,
            name="/api/products/accounts/ [LIST]",
        )

    @task(3)
    @tag("tier1", "read")
    def list_transactions(self):
        self.client.get(
            "/api/transactions/?limit=20&offset=0",
            headers=self.auth_headers,
            name="/api/transactions/ [LIST]",
        )

    @task(2)
    @tag("tier1", "read")
    def view_account_detail(self):
        # In real test, pick a random account ID from seeded data
        self.client.get(
            "/api/products/accounts/SEED_ACCOUNT_ID/",
            headers=self.auth_headers,
            name="/api/products/accounts/{id}/ [DETAIL]",
        )

    @task(1)
    @tag("tier2", "write")
    def create_transaction(self):
        self.client.post(
            "/api/transactions/",
            json={
                # Transaction payload matching your schema
                "account_id": "SEED_ACCOUNT_ID",
                "amount": round(random.uniform(1000, 50000), 2),
                "type": "disbursement",
            },
            headers=self.auth_headers,
            name="/api/transactions/ [CREATE]",
        )

    @task(1)
    @tag("tier1", "read")
    def list_contacts(self):
        search_term = random.choice(["sharma", "kumar", "patel", "singh", "verma"])
        self.client.get(
            f"/api/contacts/?search={search_term}&limit=20",
            headers=self.auth_headers,
            name="/api/contacts/ [SEARCH]",
        )


# ─── Journey 2: Workflow User ──────────────────────────────────
class WorkflowUser(CregoUser):
    """Simulates workflow execution on crego-flow."""
    weight = 2

    @task(2)
    @tag("tier1", "read")
    def list_runners(self):
        self.client.get(
            "/flow/api/runners/?limit=20",
            headers=self.auth_headers,
            name="/flow/api/runners/ [LIST]",
        )

    @task(2)
    @tag("tier1", "read")
    def list_flows(self):
        self.client.get(
            "/flow/api/flows/?status=active",
            headers=self.auth_headers,
            name="/flow/api/flows/ [LIST]",
        )

    @task(1)
    @tag("tier2", "write")
    def execute_runner(self):
        # Execute a runner step (pick from seeded runners)
        self.client.post(
            "/flow/api/runners/SEED_RUNNER_ID/execute/",
            json={"node_id": "SEED_NODE_ID"},
            headers=self.auth_headers,
            name="/flow/api/runners/{id}/execute/ [EXECUTE]",
        )

    @task(1)
    @tag("tier1", "read")
    def get_runner_detail(self):
        self.client.get(
            "/flow/api/runners/SEED_RUNNER_ID/",
            headers=self.auth_headers,
            name="/flow/api/runners/{id}/ [DETAIL]",
        )


# ─── Journey 3: Bulk Operations ───────────────────────────────
class BulkOperationsUser(CregoUser):
    """Simulates bulk upload/export on crego-flow."""
    weight = 1
    wait_time = between(5, 10)  # Longer think time for bulk ops

    @task(1)
    @tag("tier3", "write")
    def bulk_upload(self):
        # Upload a small CSV (500 rows)
        with open("data/sample_upload.csv", "rb") as f:
            self.client.post(
                "/flow/api/workbook/import/",
                files={"file": ("upload.csv", f, "text/csv")},
                headers={
                    "Authorization": f"Bearer {self.token}",
                    "X-Tenant-Alias": TENANT_ALIAS,
                },
                name="/flow/api/workbook/import/ [BULK UPLOAD]",
            )


# ─── Health Check (always running) ────────────────────────────
class HealthCheckUser(CregoUser):
    """Continuously monitors health endpoints."""
    weight = 1
    wait_time = between(5, 10)

    @task
    def check_omni_health(self):
        self.client.get("/api/health/", name="/api/health/ [HEALTH]")

    @task
    def check_flow_health(self):
        self.client.get("/flow/api/health/", name="/flow/api/health/ [HEALTH]")
```

**Running the tests:**
```bash
# Local development (web UI at http://localhost:8089)
locust -f locust/locustfile.py --host=https://loadtest.crego.ai

# Headless mode for CI/CD
locust -f locust/locustfile.py --host=https://loadtest.crego.ai \
  --headless -u 100 -r 10 -t 15m --csv=results/baseline

# Distributed mode (for higher load generation)
locust -f locust/locustfile.py --master                    # Terminal 1
locust -f locust/locustfile.py --worker --master-host=IP   # Terminal 2+
```

---

## 9. Repository Structure

```
crego-load-tests/
├── README.md                    # Setup guide, how to run, team responsibilities
├── locust/
│   ├── locustfile.py            # Main file — all user journeys
│   ├── journey_loan_officer.py  # Standalone Journey 1 (for isolated testing)
│   ├── journey_workflow.py      # Standalone Journey 2
│   ├── journey_bulk_ops.py      # Standalone Journey 3
│   ├── journey_multitenant.py   # Journey 4 — multi-tenant concurrent
│   ├── stress_test.py           # Ramp-until-failure test
│   ├── soak_test.py             # Long-duration steady-state test
│   ├── common/
│   │   ├── auth.py              # Login/token helpers
│   │   ├── config.py            # Environment config (URL, tenant, credentials)
│   │   └── data_provider.py     # Provides random seeded IDs for requests
│   └── data/
│       ├── sample_upload.csv    # 500-row CSV for bulk upload tests
│       ├── sample_document.pdf  # PDF for AI extraction tests
│       └── transaction_payloads.json  # Valid transaction request bodies
├── mock-server/
│   ├── Dockerfile
│   ├── app.py                   # FastAPI mock for Kaleyra, Gemini, OIDC, Email
│   ├── config.yaml              # Configurable latency per endpoint
│   └── k8s/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── configmap.yaml
├── seed/
│   ├── seed_postgres.py         # Omni data seeding (Django management command)
│   ├── seed_mongodb.py          # Flow data seeding (MongoEngine script)
│   ├── seed_config.yaml         # Configurable data volumes
│   ├── sample_data/             # Template records
│   └── cleanup.py               # Reset to clean state between runs
├── monitoring/
│   ├── grafana-dashboards/
│   │   ├── api-performance.json
│   │   ├── celery-queues.json
│   │   ├── database.json
│   │   └── infrastructure.json
│   └── alerts.yaml              # Alert rules for test runs
├── results/                     # Test run results (CSV exports, screenshots)
│   └── .gitkeep
├── docs/
│   ├── RUNBOOK.md               # Step-by-step instructions for running each test type
│   └── INTERPRETING_RESULTS.md  # How to read Locust output + Grafana dashboards
├── ci/
│   └── load-test-pipeline.yaml  # GitHub Actions workflow for automated runs
├── requirements.txt             # locust, locust-plugins
└── docker-compose.yaml          # Local: Locust + Prometheus + Grafana
```

---

## 10. CI/CD Integration

**Phase 1 (now):** Manual runs via Locust web UI + headless CLI.

**Phase 2 (after baselines established):** Add automated smoke test to release pipeline:

```yaml
# .github/workflows/load-test-gate.yaml
name: Load Test Gate
on:
  workflow_dispatch:
    inputs:
      users:
        description: 'Number of concurrent users'
        default: '50'
      duration:
        description: 'Test duration'
        default: '5m'

jobs:
  smoke-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Locust
        run: pip install locust

      - name: Run smoke test
        run: |
          locust -f locust/locustfile.py \
            --host=https://loadtest.crego.ai \
            --headless \
            -u ${{ inputs.users }} \
            -r 10 \
            -t ${{ inputs.duration }} \
            --csv=results/smoke \
            --exit-code-on-error 1
        env:
          TENANT_ALIAS: loadtest-primary
          TEST_PASSWORD: ${{ secrets.LOADTEST_PASSWORD }}

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: load-test-results
          path: results/

      - name: Check for failures
        run: |
          FAILURES=$(tail -1 results/smoke_stats.csv | cut -d',' -f4)
          if [ "$FAILURES" != "0" ]; then
            echo "❌ Load test had failures — blocking release"
            exit 1
          fi
```

---

## 11. Checklist Before First Load Test Run

### Infra Team
- [ ] `loadtest-gcp` overlay created and deployed via ArgoCD
- [ ] Cloud SQL instance provisioned for loadtest namespace
- [ ] Memorystore Redis provisioned for loadtest namespace
- [ ] RabbitMQ deployed in loadtest namespace
- [ ] Mock server deployed and accessible at `mock-server.loadtest.svc.cluster.local`
- [ ] MinIO deployed for document storage
- [ ] Grafana dashboards created (4 dashboards: API, Celery, DB, Infra)
- [ ] Prometheus scraping loadtest namespace
- [ ] Flower accessible at `loadtest.crego.ai/flower/`
- [ ] Domain `loadtest.crego.ai` DNS + TLS configured
- [ ] `pg_stat_statements` enabled on Cloud SQL instance
- [ ] Network policies allow traffic from Locust runner to all services

### Backend Team
- [ ] Data seeding scripts written and tested (`seed_postgres.py`, `seed_mongodb.py`)
- [ ] Seeding completed: 2 tenants × target data volumes
- [ ] Test user accounts created (100 users per tenant with appropriate roles)
- [ ] Locust scripts written for all 4 journeys
- [ ] Mock server request/response contracts match actual 3rd-party API formats
- [ ] Sentry trace rate set to 1.0 in loadtest ConfigMap
- [ ] MongoDB profiler enabled (level 1, threshold 100ms)
- [ ] `auto_explain` enabled on PostgreSQL (log queries >500ms)

### QA Team
- [ ] Locust scripts reviewed and smoke-tested at 1 user
- [ ] Test data payloads validated (valid transaction bodies, contact records, etc.)
- [ ] Results export working (CSV + Grafana snapshots)
- [ ] Sample `SEED_ACCOUNT_ID` / `SEED_RUNNER_ID` values populated in scripts
- [ ] Locust web UI accessible for monitoring

### All Teams
- [ ] Load test schedule communicated (avoid concurrent deployments)
- [ ] Results report template prepared (spreadsheet or doc)
- [ ] Linear epic created for load testing initiative
