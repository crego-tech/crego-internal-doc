# Multi-Tenancy Data Isolation Diagram

**Last Updated**: 2026-02-04
**Version**: 1.0
**Status**: Current

---

## Purpose

This diagram demonstrates the comprehensive data isolation architecture of the Crego platform's multi-tenant system. It shows how tenant data is completely segregated at the database, queue, worker, and cache levels, ensuring that no tenant can access another tenant's data. This is critical for security audits, compliance reviews (SOC 2, ISO 27001, GDPR), and enterprise client security assessments.

---

## Target Audience

- **Security Teams**: Understanding data isolation guarantees
- **Compliance Auditors**: SOC 2, ISO 27001, GDPR compliance verification
- **CISOs**: Enterprise security officers evaluating the platform
- **Enterprise Clients**: Security-conscious organizations requiring strict data isolation
- **Legal Teams**: Data residency and privacy regulation compliance

---

## Tenant Resolution & Routing Flow

```
User Request ─▶ Load Balancer ─▶ API (TenantMiddleware) ─▶ Database Router ─▶ Tenant DB

Step-by-step flow:

1. REQUEST ARRIVES
   Browser: GET /api/accounts
   Host: tenant-a.crego.com
   Authorization: Bearer eyJ... (JWT Token)
   
2. TENANT MIDDLEWARE PROCESSING
   ┌────────────────────────────────────────┐
   │  Extract Tenant Context                │
   │                                        │
   │  ┌──────────────────────────────────┐  │
   │  │ If JWT Token Present:            │  │
   │  │  • Validate JWT signature        │  │
   │  │  • Extract claims                │  │
   │  │  • tenant = claims['tenant']     │  │
   │  │  • tenant_alias = "tenant-a"     │  │
   │  └──────────────────────────────────┘  │
   │            OR                          │
   │  ┌──────────────────────────────────┐  │
   │  │ If No JWT (health check):        │  │
   │  │  • Parse Host header             │  │
   │  │  • tenant-a.crego.com            │  │
   │  │  • Lookup in tenant config       │  │
   │  │  • tenant_alias = "tenant-a"     │  │
   │  └──────────────────────────────────┘  │
   │                                        │
   │  Set: request.tenant = "tenant-a"      │
   └────────────────────────────────────────┘
   
3. DATABASE ROUTING
   ┌────────────────────────────────────────┐
   │  TenantDatabaseRouter                  │
   │                                        │
   │  tenant = request.tenant               │
   │  db_alias = f"{tenant}_omni_db"        │
   │  → "tenant_a_omni_db"                  │
   │                                        │
   │  Route all queries to:                 │
   │  tenant_a_omni_db (PostgreSQL)         │
   └────────────────────────────────────────┘
   
4. DATA ACCESS (Isolated)
   ✓ tenant_a_omni_db ────┐
   ✗ tenant_b_omni_db     │ Cannot access
   ✗ tenant_n_omni_db     │ other tenants
   
5. CACHE & QUEUE ACCESS
   Redis: tenant:tenant-a:*     ✓ Accessible
          tenant:tenant-b:*     ✗ Not accessible
          
   RabbitMQ: tenant_a_queue     ✓ Worker bound
             tenant_b_queue     ✗ Not bound
```

---

## Database-Per-Tenant Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                    DATABASE ISOLATION MODEL                          │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  POSTGRESQL MULTI-TENANT (Omni Data)                          │  │
│  │                                                                │  │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐  │  │
│  │  │  Tenant A        │  │  Tenant B        │  │  Tenant N    │  │  │
│  │  │                  │  │                  │  │              │  │  │
│  │  │  DB: tenant_a_   │  │  DB: tenant_b_   │  │  DB: tenant  │  │  │
│  │  │      omni_db     │  │      omni_db     │  │      _n_omni │  │  │
│  │  │                  │  │                  │  │      _db     │  │  │
│  │  │  Credentials:    │  │  Credentials:    │  │  Credentials │  │  │
│  │  │  user_a / pass_a │  │  user_b / pass_b │  │  user_n / ** │  │  │
│  │  │                  │  │                  │  │              │  │  │
│  │  │  Tables:         │  │  Tables:         │  │  Tables:     │  │  │
│  │  │  • users         │  │  • users         │  │  • users     │  │  │
│  │  │  • transactions  │  │  • transactions  │  │  • trans...  │  │  │
│  │  │  • accounts      │  │  • accounts      │  │  • accounts  │  │  │
│  │  │  • documents     │  │  • documents     │  │  • docs...   │  │  │
│  │  │  • audit_logs    │  │  • audit_logs    │  │  • audit_..  │  │  │
│  │  │                  │  │                  │  │              │  │  │
│  │  │  Backups:        │  │  Backups:        │  │  Backups:    │  │  │
│  │  │  Independent     │  │  Independent     │  │  Independent │  │  │
│  │  │  Daily @ 2 AM    │  │  Daily @ 2 AM    │  │  Daily @ 2AM │  │  │
│  │  └──────────────────┘  └──────────────────┘  └──────────────┘  │  │
│  │                                                                │  │
│  │  ┌──────────────────────────────────────────────────────────┐  │  │
│  │  │  Shared DB (System Config Only)                          │  │  │
│  │  │  • Tenant configuration                                  │  │  │
│  │  │  • System settings                                       │  │  │
│  │  │  • Feature flags                                         │  │  │
│  │  └──────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  MONGODB PER-TENANT (Flow Workflows)                          │  │
│  │                                                                │  │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐  │  │
│  │  │  Tenant A        │  │  Tenant B        │  │  Tenant N    │  │  │
│  │  │                  │  │                  │  │              │  │  │
│  │  │  DB: tenant_a_   │  │  DB: tenant_b_   │  │  DB: tenant  │  │  │
│  │  │      flow_db     │  │      flow_db     │  │      _n_flow │  │  │
│  │  │                  │  │                  │  │      _db     │  │  │
│  │  │  Collections:    │  │  Collections:    │  │  Collections │  │  │
│  │  │  • flows         │  │  • flows         │  │  • flows     │  │  │
│  │  │  • designs       │  │  • designs       │  │  • designs   │  │  │
│  │  │  • runners       │  │  • runners       │  │  • runners   │  │  │
│  │  │  • templates     │  │  • templates     │  │  • templates │  │  │
│  │  │  • activity      │  │  • activity      │  │  • activity  │  │  │
│  │  └──────────────────┘  └──────────────────┘  └──────────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘

Isolation Guarantees:
✓ Complete database-level separation
✓ No shared tables or schemas
✓ Separate credentials per tenant
✓ Independent backups
✓ Tenant-specific database tuning
```

---

## Per-Tenant Worker & Queue Isolation

```
┌──────────────────────────────────────────────────────────────────────┐
│              WORKER AND QUEUE ISOLATION                              │
│                                                                      │
│  API Layer (Shared)                                                  │
│  ┌────────────┐  ┌────────────┐                                     │
│  │  Omni API  │  │  Flow API  │                                     │
│  └─────┬──────┘  └─────┬──────┘                                     │
│        │               │                                            │
│        │  Enqueue      │  Enqueue                                   │
│        │  Task         │  Task                                      │
│        ▼               ▼                                            │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  RABBITMQ - Per-Tenant Queue Isolation                        │  │
│  │                                                                │  │
│  │  Queue: tenant_a_queue        Queue: tenant_b_queue           │  │
│  │  DLQ:   tenant_a_queue_dlq    DLQ:   tenant_b_queue_dlq       │  │
│  │                                                                │  │
│  │  Queue: tenant_n_queue                                         │  │
│  │  DLQ:   tenant_n_queue_dlq                                     │  │
│  └────┬───────────────────────┬───────────────────────┬───────────┘  │
│       │                       │                       │              │
│       │ Bound                 │ Bound                 │ Bound        │
│       ▼                       ▼                       ▼              │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  KUBERNETES WORKER DEPLOYMENTS - Per-Tenant                   │  │
│  │                                                                │  │
│  │  ┌──────────────────────────────────────────────────────────┐  │  │
│  │  │  TENANT A WORKERS                                        │  │  │
│  │  │  ┌────────────────────────────────────────────────────┐  │  │  │
│  │  │  │  omni-celery-worker-tenant-a                       │  │  │  │
│  │  │  │  • Replicas: 1-20 (KEDA autoscaling)              │  │  │  │
│  │  │  │  • Env: TENANT_ALIAS=tenant-a                      │  │  │  │
│  │  │  │  • Queue: tenant_a_queue                           │  │  │  │
│  │  │  │  • DB: tenant_a_omni_db                            │  │  │  │
│  │  │  └────────────────────────────────────────────────────┘  │  │  │
│  │  │  ┌────────────────────────────────────────────────────┐  │  │  │
│  │  │  │  omni-celery-beat-tenant-a                         │  │  │  │
│  │  │  │  • Replicas: 1 (Scheduled tasks)                   │  │  │  │
│  │  │  └────────────────────────────────────────────────────┘  │  │  │
│  │  │  ┌────────────────────────────────────────────────────┐  │  │  │
│  │  │  │  flow-celery-worker-tenant-a                       │  │  │  │
│  │  │  │  • Replicas: 1-20 (KEDA autoscaling)              │  │  │  │
│  │  │  │  • Env: TENANT_ALIAS=tenant-a                      │  │  │  │
│  │  │  │  • Queue: tenant_a_queue                           │  │  │  │
│  │  │  │  • MongoDB: tenant_a_flow_db                       │  │  │  │
│  │  │  └────────────────────────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────────────────────────┘  │  │
│  │                                                                │  │
│  │  ┌──────────────────────────────────────────────────────────┐  │  │
│  │  │  TENANT B WORKERS                                        │  │  │
│  │  │  (Same structure as Tenant A)                            │  │  │
│  │  │  • omni-celery-worker-tenant-b                           │  │  │
│  │  │  • omni-celery-beat-tenant-b                             │  │  │
│  │  │  • flow-celery-worker-tenant-b                           │  │  │
│  │  └──────────────────────────────────────────────────────────┘  │  │
│  │                                                                │  │
│  │  ┌──────────────────────────────────────────────────────────┐  │  │
│  │  │  TENANT N WORKERS                                        │  │  │
│  │  │  (... N tenant deployments)                              │  │  │
│  │  └──────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  Isolation Benefits:                                                 │
│  ✓ Resource isolation (CPU/Memory limits per tenant)                │
│  ✓ Fault isolation (worker crash doesn't affect other tenants)      │
│  ✓ Independent scaling (KEDA autoscales per tenant queue length)    │
│  ✓ Monitoring isolation (metrics tagged with tenant)                │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Redis Cache Isolation Strategy

```
┌──────────────────────────────────────────────────────────────────────┐
│           REDIS SHARED CACHE - KEY PREFIXING STRATEGY                │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  Redis Cluster (Shared Instance)                              │  │
│  │  Memorystore (GCP) / ElastiCache (AWS)                        │  │
│  │                                                                │  │
│  │  ┌──────────────────────────────────────────────────────────┐  │  │
│  │  │  TENANT A KEYS (Prefix: tenant:tenant-a:)                │  │  │
│  │  │                                                          │  │  │
│  │  │  • tenant:tenant-a:user:123                              │  │  │
│  │  │  • tenant:tenant-a:session:xyz-abc                       │  │  │
│  │  │  • tenant:tenant-a:ratelimit:api:user:123                │  │  │
│  │  │  • tenant:tenant-a:cache:accounts:list                   │  │  │
│  │  │  • tenant:tenant-a:cache:transactions:page:1             │  │  │
│  │  └──────────────────────────────────────────────────────────┘  │  │
│  │                                                                │  │
│  │  ┌──────────────────────────────────────────────────────────┐  │  │
│  │  │  TENANT B KEYS (Prefix: tenant:tenant-b:)                │  │  │
│  │  │                                                          │  │  │
│  │  │  • tenant:tenant-b:user:789                              │  │  │
│  │  │  • tenant:tenant-b:session:def-ghi                       │  │  │
│  │  │  • tenant:tenant-b:ratelimit:api:user:789                │  │  │
│  │  │  • tenant:tenant-b:cache:accounts:list                   │  │  │
│  │  └──────────────────────────────────────────────────────────┘  │  │
│  │                                                                │  │
│  │  ┌──────────────────────────────────────────────────────────┐  │  │
│  │  │  TENANT N KEYS (Prefix: tenant:tenant-n:)                │  │  │
│  │  │  • tenant:tenant-n:user:555                              │  │  │
│  │  │  • tenant:tenant-n:session:jkl-mno                       │  │  │
│  │  └──────────────────────────────────────────────────────────┘  │  │
│  │                                                                │  │
│  │  ┌──────────────────────────────────────────────────────────┐  │  │
│  │  │  SYSTEM KEYS (No tenant prefix)                          │  │  │
│  │  │  • system:health:last_check                              │  │  │
│  │  │  • system:config:feature_flags                           │  │  │
│  │  └──────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  Cache Operations:                                                   │
│                                                                      │
│  GET tenant:tenant-a:user:123                      ✓ Accessible     │
│  GET tenant:tenant-b:user:789                      ✗ Different key   │
│                                                                      │
│  SCAN tenant:tenant-a:*                            ✓ Bulk ops OK     │
│  DEL tenant:tenant-a:*                             ✓ Tenant delete   │
│                                                                      │
│  Isolation Guarantees:                                               │
│  ✓ Tenant A cannot access tenant:tenant-b:* keys                    │
│  ✓ Key collisions impossible (prefix ensures uniqueness)            │
│  ✓ Bulk operations isolated by prefix pattern                       │
│  ⚠ Application-level enforcement (no Redis-level isolation)         │
│  ⚠ Only non-sensitive data cached (sessions, rate limits, API resp) │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Security Boundaries & Isolation Layers

```
┌──────────────────────────────────────────────────────────────────────┐
│                   7-LAYER SECURITY ISOLATION MODEL                   │
│                                                                      │
│  Layer 1: NETWORK ISOLATION                                          │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  • Kubernetes Network Policies (deny-all default)              │  │
│  │  • Explicit allow: API ─▶ DB, Worker ─▶ DB, Worker ─▶ Queue   │  │
│  │  • Deny cross-namespace traffic                                │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  Layer 2: DATABASE ISOLATION                                         │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  • Database-per-Tenant Model (complete separation)             │  │
│  │  • Separate Credentials per Tenant                             │  │
│  │  • Independent Backups per Tenant                              │  │
│  │  • Encryption at Rest (tenant-specific keys optional)          │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  Layer 3: APPLICATION ISOLATION                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  • TenantMiddleware (JWT validation & tenant extraction)       │  │
│  │  • TenantDatabaseRouter (query routing per tenant)             │  │
│  │  • Permission Check (user-tenant binding verification)         │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  Layer 4: WORKER ISOLATION                                           │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  • Separate K8s Deployments per Tenant                         │  │
│  │  • Dedicated Queues per Tenant                                 │  │
│  │  • Tenant-Specific Environment Variables                       │  │
│  │  • Resource Limits (CPU/Memory) per Tenant                     │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  Layer 5: CACHE ISOLATION                                            │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  • Redis Key Prefixing (tenant:tenant-alias:*)                 │  │
│  │  • TTL-based Eviction (no long-term storage)                   │  │
│  │  • No Sensitive Data in Cache                                  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  Layer 6: MONITORING ISOLATION                                       │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  • Prometheus Metrics (labeled by tenant)                      │  │
│  │  • Application Logs (tenant ID in all logs)                    │  │
│  │  • Alerts per Tenant (threshold violations)                    │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  Layer 7: COMPLIANCE                                                 │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  • Comprehensive Audit Logs (all tenant actions)               │  │
│  │  • Data Residency (tenant-specific regions)                    │  │
│  │  • GDPR Compliance (right to erasure per tenant)               │  │
│  │  • SOC 2 Type II (annual audits)                               │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Key Components

### 1. Tenant Resolution Layer

#### TenantMiddleware (Django/FastAPI)

**Location**:
- Omni: `crego-omni/project/apps/tenancy/middleware.py`
- Flow: `crego-flow/project/auth/middleware.py`

**Responsibilities**:
1. Extract tenant context from JWT token claims (authenticated requests)
2. Parse domain from Host header (unauthenticated requests like health checks)
3. Validate tenant exists and is active
4. Set `request.tenant` attribute for downstream use
5. Pass tenant context to database router and cache operations

**JWT Token Structure**:
```json
{
  "sub": "user-123",
  "email": "user@example.com",
  "tenant": "tenant-a",
  "roles": ["admin", "user"],
  "exp": 1735689600
}
```

**Domain-Based Resolution** (Unauthenticated):
```
Host: tenant-a.crego.com → Tenant Alias: "tenant-a"
Host: demo.crego.com → Tenant Alias: "demo"
```

#### TenantDatabaseRouter (Django ORM)

**Location**: `crego-omni/project/apps/tenancy/router.py`

**Responsibilities**:
1. Route all database queries to tenant-specific database
2. Resolve database alias from tenant context: `tenant-a` → `tenant_a_omni_db`
3. Use `default` database for system-wide configuration tables
4. Prevent cross-tenant queries (raises exception if tenant not set)

**Routing Logic**:
```python
def db_for_read(self, model, **hints):
    tenant = get_current_tenant()
    if tenant:
        return f"{tenant}_omni_db"
    return "default"
```

### 2. Database-Per-Tenant Model

#### PostgreSQL (Omni API)

**Isolation Guarantees**:
- ✅ Complete database-level isolation
- ✅ Separate credentials per tenant (no shared credentials)
- ✅ Independent backups per tenant (point-in-time recovery)
- ✅ Tenant-specific database tuning (indexes, query optimization)
- ✅ Data residency compliance (tenant databases in specific regions)

**Database Naming Convention**:
```
Tenant Alias: tenant-a
Database Name: tenant_a_omni_db
Connection: postgresql://user:pass@host:5432/tenant_a_omni_db
```

**Schema Structure** (Identical across all tenants):
- Users and authentication
- Financial transactions (CTM module)
- Accounts and products
- Schedules and demands
- Documents and contacts
- Audit logs

#### MongoDB (Flow API)

**Isolation Guarantees**:
- ✅ Per-tenant databases on MongoDB Atlas
- ✅ Separate connection strings per tenant
- ✅ Database naming: `tenant_a_flow_db`
- ✅ Independent backups per tenant

**Collections** (Per Tenant):
- flows: Workflow definitions
- designs: Workflow designs
- runners: Workflow execution state
- templates: Document templates
- activity: Activity logs
- approvals: Approval workflows
- checklists: Checklist tasks

### 3. Per-Tenant Worker Deployments

#### Kubernetes Deployment Strategy

**Deployment Naming**:
```
omni-celery-worker-{tenant-alias}
omni-celery-beat-{tenant-alias}
flow-celery-worker-{tenant-alias}
```

**Example for Tenant A**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: omni-celery-worker-tenant-a
  namespace: prod
spec:
  replicas: 1  # Scaled by KEDA 1-20
  template:
    spec:
      containers:
      - name: worker
        env:
        - name: TENANT_ALIAS
          value: "tenant-a"
        - name: CELERY_QUEUE
          value: "tenant_a_queue"
        - name: DATABASE_NAME
          value: "tenant_a_omni_db"
```

**Isolation Benefits**:
- ✅ Resource isolation (CPU, memory limits per tenant)
- ✅ Fault isolation (worker crash doesn't affect other tenants)
- ✅ Independent scaling (KEDA autoscales per tenant based on queue length)
- ✅ Monitoring isolation (metrics tagged with tenant alias)

#### RabbitMQ Queue Isolation

**Queue Naming Convention**:
```
Primary Queue: tenant_{alias}_queue
Dead Letter Queue: tenant_{alias}_queue_dlq
```

**Isolation Guarantees**:
- ✅ Dedicated queues per tenant (no shared queues)
- ✅ Workers bound to tenant-specific queues only
- ✅ Task failures isolated to tenant-specific DLQ
- ✅ Queue metrics tracked per tenant

**Task Routing**:
```python
# API enqueues task with tenant context
celery_app.send_task(
    'process_payment',
    queue=f'tenant_{tenant_alias}_queue',
    headers={'tenant': tenant_alias}
)

# Worker consumes from tenant-specific queue
worker --queues=tenant_a_queue
```

### 4. Redis Cache Isolation

#### Key Prefixing Strategy

**Prefix Pattern**:
```
tenant:{tenant-alias}:{key-type}:{identifier}
```

**Examples**:
- User data: `tenant:tenant-a:user:123`
- Session: `tenant:tenant-a:session:xyz`
- Rate limit: `tenant:tenant-a:ratelimit:api:user:123`
- API cache: `tenant:tenant-a:cache:accounts:list`

**Cache Operations**:
```python
# Set cache
redis.set(
    f'tenant:{tenant_alias}:user:{user_id}',
    user_data,
    ex=3600  # TTL 1 hour
)

# Get cache
redis.get(f'tenant:{tenant_alias}:user:{user_id}')

# Delete all tenant keys
redis.delete(*redis.keys(f'tenant:{tenant_alias}:*'))
```

**Isolation Guarantees**:
- ✅ No cross-tenant key access (enforced at application layer)
- ✅ Bulk operations isolated by prefix pattern
- ✅ Key collisions impossible (prefix ensures uniqueness)
- ⚠️ Shared Redis instance (cost optimization)
- ⚠️ No Redis-level isolation (relies on application enforcement)

**Security Considerations**:
- Only non-sensitive data in cache (sessions, rate limits, API responses)
- No personally identifiable information (PII) cached
- TTL enforced on all keys (max 24 hours)

---

## Isolation Verification

### How We Ensure Isolation

#### 1. Automated Tests

**Unit Tests**:
- TenantMiddleware extracts correct tenant from JWT
- TenantDatabaseRouter routes to correct database
- Redis key prefixing applied correctly

**Integration Tests**:
- Cross-tenant query attempts fail with exception
- Worker consumes only from assigned queue
- Cache operations isolated by tenant

**End-to-End Tests**:
- Multiple concurrent tenant requests don't interfere
- Tenant A cannot retrieve Tenant B's data
- Worker tasks processed in correct tenant context

#### 2. Penetration Testing

**Scenarios Tested**:
- Attempt to access another tenant's database by manipulating JWT
- Attempt to consume from another tenant's queue
- Attempt to access another tenant's cache keys
- SQL injection with cross-tenant queries
- API fuzzing with tenant ID manipulation

#### 3. Security Audits

**Annual SOC 2 Type II Audit**:
- Data isolation controls tested
- Database separation verified
- Queue isolation confirmed
- Cache prefixing validated

**GDPR Compliance Review**:
- Right to erasure per tenant (delete all tenant data)
- Data portability (export all tenant data)
- Data residency (tenant data in specified region)

---

## Tenant Onboarding & Offboarding

### Onboarding a New Tenant

**Steps**:
1. **Create Tenant Configuration**:
   - Add tenant to TENANT_CONFIG (domain, alias, tier)
   - Generate JWT signing keys for tenant

2. **Provision Database**:
   - Create PostgreSQL database: `tenant_{alias}_omni_db`
   - Create MongoDB database: `tenant_{alias}_flow_db`
   - Run migrations to create schema

3. **Create RabbitMQ Queues**:
   - Create queue: `tenant_{alias}_queue`
   - Create DLQ: `tenant_{alias}_queue_dlq`

4. **Deploy Workers**:
   - Apply Kubernetes manifests for worker deployments
   - Configure environment variables with tenant alias

5. **Verify Isolation**:
   - Run isolation tests
   - Verify database routing
   - Verify queue consumption

### Offboarding a Tenant

**Steps**:
1. **Backup Data**:
   - Export PostgreSQL database
   - Export MongoDB database
   - Archive documents from cloud storage

2. **Delete Workers**:
   - Delete Kubernetes deployments
   - Remove worker configurations

3. **Delete Queues**:
   - Delete RabbitMQ queues
   - Purge any remaining messages

4. **Delete Databases**:
   - Drop PostgreSQL database
   - Drop MongoDB database
   - Verify data deletion

5. **Remove Configuration**:
   - Remove tenant from TENANT_CONFIG
   - Revoke JWT keys

**GDPR Right to Erasure**:
- Complete tenant data deletion within 30 days
- Audit logs retained for compliance (90 days)
- Backups deleted after retention period (7 days)

---

## Compliance & Certifications

### SOC 2 Type II

**Controls Implemented**:
- CC6.1 - Logical access controls (database-per-tenant)
- CC6.6 - Data protection (encryption at rest and in transit)
- CC7.2 - Data integrity (audit logs)
- CC7.3 - Change management (GitOps deployment)

**Audit Frequency**: Annual

### ISO 27001

**Information Security Controls**:
- A.9.4 - System and application access control
- A.13.2 - Information transfer (encrypted)
- A.18.1 - Compliance with legal requirements (GDPR)

### GDPR Compliance

**Data Protection Principles**:
- ✅ Data minimization (only necessary data stored)
- ✅ Storage limitation (automatic deletion after retention period)
- ✅ Integrity and confidentiality (encryption, access controls)
- ✅ Right to erasure (tenant-level deletion)
- ✅ Data portability (export all tenant data)

**Data Processing Agreement (DPA)**:
- Tenant is data controller
- Crego is data processor
- Sub-processors disclosed (AWS, GCP, MongoDB Atlas)

---

## Disaster Recovery & Business Continuity

### Backup Strategy

**PostgreSQL Backups**:
- Automated daily backups per tenant database
- Point-in-time recovery (PITR) enabled
- Retention: 7 days
- Geographic replication to secondary region

**MongoDB Backups**:
- MongoDB Atlas continuous backups
- Snapshots every 6 hours
- Retention: 7 days
- Cross-region replication

**Document Storage Backups**:
- Cloud Storage versioning enabled
- Lifecycle policy: Delete after 90 days
- Cross-region replication

### Restore Procedures

**Single Tenant Restore**:
1. Identify tenant database from backup
2. Restore to temporary database
3. Verify data integrity
4. Swap with production database
5. Verify application connectivity

**Multi-Tenant Restore** (Disaster Scenario):
1. Restore all tenant databases from backups
2. Restore MongoDB databases
3. Redeploy Kubernetes applications
4. Recreate RabbitMQ queues
5. Verify isolation between tenants

---

## Performance Considerations

### Database Performance

**Per-Tenant Optimization**:
- ✅ Tenant-specific indexes (optimize for tenant query patterns)
- ✅ Independent database tuning (connection pools, cache sizes)
- ✅ Horizontal scaling (add read replicas per tenant if needed)

**Trade-offs**:
- ⚠️ More databases to manage (automation required)
- ⚠️ Higher connection pool overhead (mitigated by pooling)

### Worker Scaling

**KEDA Autoscaling**:
- Scale based on queue length (50 messages per worker)
- Scale up: 30 seconds
- Scale down: 5 minutes (avoid flapping)
- Scale to zero: Enabled for idle tenants

**Resource Efficiency**:
- ✅ Idle tenants consume no resources (scale to zero)
- ✅ Active tenants scale based on workload
- ✅ Cost optimization (pay only for active usage)

### Cache Performance

**Shared Redis Trade-offs**:
- ✅ Lower cost (single Redis instance)
- ✅ Faster cache access (no tenant-specific connections)
- ⚠️ Potential noisy neighbor (one tenant evicts another's keys)
- ⚠️ No hard isolation (relies on application enforcement)

**Mitigation**:
- TTL on all keys (max 24 hours)
- Eviction policy: LRU (least recently used)
- Monitor cache hit rates per tenant

---

## Notes

- **Complete Isolation**: Database-per-tenant ensures zero risk of cross-tenant data leaks
- **Dedicated Workers**: Per-tenant workers provide resource and fault isolation
- **Redis Prefixing**: Cost-effective cache isolation for non-sensitive data
- **Compliance Ready**: Architecture designed for SOC 2, ISO 27001, GDPR compliance
- **Automated Onboarding**: New tenants provisioned in under 10 minutes
- **Disaster Recovery**: Per-tenant backups enable granular restore operations

---

## Related Diagrams

- [System Architecture](01-system-architecture.md) - Overall component architecture
- [Deployment Topology](02-deployment-topology.md) - Infrastructure deployment
- [Request Flow](04-request-flow.md) - Request processing with tenant context

---

**Maintained By**: Security & Platform Engineering Team
**Review Schedule**: Quarterly & Before Security Audits
**Next Review**: 2026-05-04
