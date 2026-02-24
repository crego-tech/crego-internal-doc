# System Architecture Diagram

**Last Updated**: 2026-02-04
**Version**: 1.0
**Status**: Current

---

## Purpose

This diagram provides a comprehensive overview of the Crego platform's system architecture, showing all major components, their interactions, data flow, and authentication patterns. It serves as the primary reference for understanding how the platform's frontend, backend, data, and infrastructure layers work together.

---

## Target Audience

- **Technical Teams**: CTOs, Software Architects, Senior Engineers
- **Enterprise Clients**: Technical decision-makers evaluating the platform
- **New Team Members**: Engineers onboarding to the platform
- **Integration Partners**: External systems integrating with Crego APIs

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                      CLIENT LAYER                                           │
│  ┌─────────────────────┐                                    ┌─────────────────────┐        │
│  │   Web Browser       │                                    │   Mobile Client     │        │
│  └──────────┬──────────┘                                    └──────────┬──────────┘        │
└─────────────┼────────────────────────────────────────────────────────────┼──────────────────┘
              │                                                            │
              │                         HTTPS                              │
              └────────────────────────────┬───────────────────────────────┘
                                           │
┌──────────────────────────────────────────┼───────────────────────────────────────────────────┐
│                             LOAD BALANCING LAYER                                            │
│                    ┌─────────────────────────────────────────┐                              │
│                    │      Load Balancer                      │                              │
│                    │  NGINX Ingress (GCP) / ALB (AWS)        │                              │
│                    └─────────────┬───────────────────────────┘                              │
└──────────────────────────────────┼───────────────────────────────────────────────────────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
┌───────▼────────────┐    ┌────────▼────────────┐   ┌────────▼────────────┐
│                    │    │                     │   │                     │
│  FRONTEND LAYER    │    │    API LAYER        │   │   MONITORING        │
│                    │    │                     │   │                     │
│ ┌────────────────┐ │    │ ┌─────────────────┐ │   │ ┌─────────────────┐ │
│ │  Omni Web      │ │    │ │   Omni API      │ │   │ │   Flower        │ │
│ │  React 19.2.3  │◄┼────┼─┤   Django 5.2+   │ │   │ │   Celery UI     │ │
│ │  TypeScript    │ │    │ │   Python 3.13   │ │   │ │   Port :5555    │ │
│ │  Port :3000/   │ │    │ │   Port :8000    │ │   │ └─────────────────┘ │
│ │  Routes: /omni │ │    │ │   /api/*        │ │   │                     │
│ └────────────────┘ │    │ └────────┬────────┘ │   └─────────────────────┘
│                    │    │          │          │
│ ┌────────────────┐ │    │ ┌────────▼────────┐ │
│ │  Flow Web      │ │    │ │   Flow API      │ │
│ │  React 19.2.3  │◄┼────┼─┤   FastAPI       │ │
│ │  TypeScript    │ │    │ │   Python 3.13   │ │
│ │  Port :7777/   │ │    │ │   Port :8000    │ │
│ │  Routes: /flow │ │    │ │   /flow/api/*   │ │
│ └────────────────┘ │    │ └────────┬────────┘ │
│                    │    │          │          │
└────────────────────┘    └──────────┼──────────┘
                                     │
                      ┌──────────────┼──────────────┐
                      │              │              │
┌─────────────────────▼────┐ ┌───────▼──────┐ ┌────▼─────────────────────────┐
│                          │ │              │ │                              │
│  BACKGROUND PROCESSING   │ │  DATA LAYER  │ │  AUTHENTICATION              │
│                          │ │              │ │                              │
│ ┌──────────────────────┐ │ │ ┌──────────┐ │ │ ┌──────────────────────────┐ │
│ │ Omni Celery Worker   │ │ │ │PostgreSQL│ │ │ │    OIDC Provider         │ │
│ │ Per-Tenant Deploy    │─┼─┼─┤Multi-    │ │ │ │    JWT Token Issuer      │ │
│ │ Python 3.13          │ │ │ │Tenant DB │ │ │ │    OpenID Connect        │ │
│ └──────────────────────┘ │ │ │Per-Tenant│ │ │ └────────────┬─────────────┘ │
│                          │ │ │Cloud SQL │ │ │              │               │
│ ┌──────────────────────┐ │ │ └──────────┘ │ │              │ JWT Token     │
│ │ Omni Celery Beat     │ │ │              │ │              │               │
│ │ Scheduled Tasks      │ │ │ ┌──────────┐ │ └──────────────┼───────────────┘
│ │ Per-Tenant           │ │ │ │ MongoDB  │ │                │
│ └──────────────────────┘ │ │ │Per-Tenant│ │                │
│                          │ │ │Workflows │ │                │
│ ┌──────────────────────┐ │ │ │Atlas     │ │                │
│ │ Flow Celery Worker   │─┼─┼─┤          │ │                │
│ │ Per-Tenant Deploy    │ │ │ └──────────┘ │                │
│ │ Python 3.13          │ │ │              │                │
│ └──────────────────────┘ │ │ ┌──────────┐ │                │
│           ▲              │ │ │  Redis   │ │                │
│           │              │ │ │ Shared   │◄┼────────────────┤
│           │              │ │ │ Tenant   │ │                │
│           │              │ │ │ Prefixing│ │                │
│ ┌─────────┴──────────┐   │ │ └──────────┘ │                │
│ │    RabbitMQ        │   │ │              │                │
│ │  Per-Tenant Queues │   │ │ ┌──────────┐ │                │
│ │  Message Broker    │───┼─┼─┤ Cloud    │ │                │
│ └────────────────────┘   │ │ │ Storage  │ │                │
│                          │ │ │ S3/GCS/  │ │                │
└──────────────────────────┘ │ │ Azure    │ │                │
                             │ └──────────┘ │                │
                             └──────────────┘                │
                                                              │
┌─────────────────────────────────────────────────────────────▼──────────────┐
│                    INFRASTRUCTURE & ORCHESTRATION                          │
│                                                                            │
│  ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐      │
│  │   Kubernetes     │   │     ArgoCD       │   │    Terraform     │      │
│  │   GKE / EKS      │◄──┤   GitOps CD      │◄──┤   IaC Multi-Cloud│      │
│  │   Clusters       │   │   App-of-Apps    │   │                  │      │
│  └──────────────────┘   └──────────────────┘   └──────────────────┘      │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────────┐
│                    MONITORING & OBSERVABILITY                              │
│                                                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Prometheus  │  │   Grafana    │  │    Sentry    │  │ OpenTelemetry│  │
│  │   Metrics    │──│  Dashboards  │  │    Error     │  │  Distributed │  │
│  │  Collection  │  │  Visualize   │  │   Tracking   │  │   Tracing    │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Component Interaction Legend

```
Key Symbols:
  │  ─  ┌  ┐  └  ┘  ├  ┤  ┬  ┴  ┼   Box drawing characters (connections)
  ◄──                                 Data flow / API calls
  ▼                                   Flow direction
  [Component Name]                    System component
```

---

## Key Components

### Client Layer

**Web Browser / Mobile Client**
- End-user access points for the platform
- Communicates via HTTPS
- Receives JWT tokens after authentication

### Load Balancing Layer

**Load Balancer**
- **GCP**: NGINX Ingress Controller with Cloud Load Balancing
- **AWS**: Application Load Balancer (ALB) with AWS Load Balancer Controller
- Routes traffic based on URL paths:
  - `/` and `/omni/*` → Omni Web
  - `/flow/*` → Flow Web
  - `/api/*` → Omni API
  - `/flow/api/*` → Flow API
  - `/{omni,flow}/flower/*` → Flower Monitoring

### Frontend Layer

**Omni Web (React SPA)**
- Primary user interface for the Omni application
- Built with React 19.2.3, TypeScript, Vite
- UI Components: Tailwind CSS v4, Radix UI, shadcn/ui
- State Management: TanStack Query (React Query), React Hook Form
- Development: Port 3000
- Production: Port 8000 (containerized)
- Routes: `/` (default) and `/omni/*`

**Flow Web (React SPA)**
- User interface for the Flow workflow engine
- Same tech stack as Omni Web
- Visual workflow builder with @xyflow/react
- Development: Port 7777
- Production: Port 8000 (containerized)
- Routes: `/flow/*`

### API Layer

**Omni API (Django REST Framework)**
- Main business logic API
- Python 3.13, Django 5.2+
- Key Modules:
  - CTM (Core Transaction Module) - Financial transactions
  - Schedule - Payment schedule generation
  - Review - Maker-checker workflows
  - Docs - Document management
  - Contact - Contact management
  - Authz - Authentication and authorization
- Port: 8000
- Routes: `/api/*`
- Authentication: OIDC with JWT tokens

**Flow API (FastAPI)**
- Workflow execution engine
- Python 3.13, FastAPI with Uvicorn
- Async operations with Motor (async MongoDB)
- Graph-based workflow execution
- Template rendering (Jinja2, Mako)
- Port: 8000
- Routes: `/flow/api/*`
- Service-to-service: Calls Omni API via OmniApiClient

### Background Processing Layer

**Omni Celery Worker (Per-Tenant)**
- Processes async tasks from Omni API
- Dedicated deployment per tenant for isolation
- Handles: Payment processing, document generation, notifications
- Message queue: RabbitMQ (per-tenant queues)

**Omni Celery Beat (Per-Tenant)**
- Scheduled task scheduler
- Periodic tasks: Daily reconciliation, scheduled reports
- Dedicated deployment per tenant

**Flow Celery Worker (Per-Tenant)**
- Processes workflow execution tasks
- Long-running workflow operations
- Document generation from templates

**Flower Monitoring**
- Unified Celery monitoring for both Omni and Flow
- Web UI for task monitoring
- Port: 5555
- Routes: `/omni/flower/*`, `/flow/flower/*`

### Data Layer

**PostgreSQL (Multi-Tenant)**
- Database-per-tenant model for complete isolation
- Primary-replica configuration
- Managed services:
  - GCP: Cloud SQL for PostgreSQL
  - AWS: RDS for PostgreSQL
- TenantDatabaseRouter routes queries to tenant-specific database
- Schema: All Omni application data

**MongoDB (Per-Tenant)**
- Document database for workflow engine
- Per-tenant database isolation
- MongoDB Atlas (managed service)
- Schema: Flow workflows, templates, execution state

**Redis (Shared with Tenant Prefixing)**
- Shared cache across all tenants
- Tenant isolation via key prefixing: `tenant:{alias}:*`
- Managed services:
  - GCP: Memorystore for Redis
  - AWS: ElastiCache for Redis
- Use cases: Session storage, API response caching, rate limiting

**RabbitMQ (Per-Tenant Queues)**
- Message broker for Celery tasks
- Dedicated queues per tenant: `tenant_{alias}_queue`
- Ensures task isolation between tenants
- Deployed in Kubernetes (dev) or managed service (prod)

### Infrastructure & Orchestration

**Kubernetes Clusters**
- Container orchestration platform
- GCP: Google Kubernetes Engine (GKE)
- AWS: Elastic Kubernetes Service (EKS)
- Namespaces per environment: dev, prod
- Network policies for security

**ArgoCD (GitOps)**
- Declarative continuous deployment
- App-of-Apps pattern for managing applications
- Automatic sync from Git repository
- Environment-specific configurations via Kustomize overlays

**Terraform (Infrastructure as Code)**
- Multi-cloud infrastructure provisioning
- Manages: Kubernetes clusters, databases, storage, networking
- Separate configurations per cloud provider and environment

### Authentication & Authorization

**OIDC Provider**
- OpenID Connect authentication
- Issues JWT tokens with tenant context
- Token claims include:
  - User ID and email
  - Roles and permissions
  - Tenant alias
  - Token expiry
- APIs validate tokens against JWKS endpoint

### Monitoring & Observability

**Prometheus**
- Metrics collection from all services
- Scrapes metrics from APIs, workers, and infrastructure
- Alert rules for critical conditions

**Grafana**
- Visualization dashboards
- Pre-built dashboards for APIs, workers, databases
- Real-time monitoring

**Sentry**
- Error tracking and performance monitoring
- Captures exceptions from APIs and workers
- Release tracking and source maps

**OpenTelemetry**
- Distributed tracing
- Tracks requests across service boundaries
- Performance profiling

### External Storage

**Cloud Storage**
- Multi-cloud document storage
- AWS S3, GCP Cloud Storage, Azure Blob
- Stores: User uploads, generated documents, backups
- Configured via django-storages (Omni) and boto3 (Flow)

---

## Data Flow Patterns

### 1. Synchronous Request Flow

```
Browser → Load Balancer → Frontend (React) → API (Django/FastAPI) → Database → API → Frontend → Browser
```

- User initiates action in web UI
- Frontend sends authenticated API request (JWT in Authorization header)
- API validates token, resolves tenant, queries database
- Response returned to frontend
- UI updated

### 2. Asynchronous Task Flow

```
API → RabbitMQ (per-tenant queue) → Celery Worker (per-tenant) → Database → Worker → RabbitMQ (result)
```

- API enqueues task to RabbitMQ
- Worker consumes task from queue
- Worker performs long-running operation
- Worker updates database with result
- API can query task status

### 3. Workflow Execution Flow

```
Flow Web → Flow API → MongoDB (workflow definition) → Celery Worker → Execute Nodes → Omni API (optional) → MongoDB (state)
```

- User triggers workflow execution
- Flow API loads workflow graph from MongoDB
- Execution delegated to Celery worker
- Worker executes nodes in graph order
- Node operations may call Omni API
- State saved to MongoDB after each node

### 4. Authentication Flow

```
Browser → OIDC Provider (login) → JWT Token → Browser → API (with JWT header) → OIDC Provider (validate) → API processes request
```

- User authenticates via OIDC provider
- Provider issues JWT token with tenant context
- Frontend includes JWT in all API requests
- API validates token signature and claims
- Tenant context extracted from token

---

## Tenant Context Propagation

Multi-tenancy is a core architectural pattern. Tenant context flows through the system:

1. **Frontend**: User accesses tenant-specific domain (e.g., `tenant1.crego.com`)
2. **Authentication**: OIDC includes tenant alias in JWT token claims
3. **API Middleware**: TenantMiddleware extracts tenant from JWT token
4. **Database Routing**: TenantDatabaseRouter routes queries to tenant-specific database
5. **Background Tasks**: Celery tasks receive tenant context via task headers
6. **Worker Deployment**: Dedicated worker deployment per tenant
7. **Queue Isolation**: Each tenant has dedicated RabbitMQ queues
8. **Cache Isolation**: Redis keys prefixed with tenant alias

---

## Security Boundaries

- **Network Policies**: Kubernetes network policies restrict pod-to-pod communication
- **Database Isolation**: Complete database-per-tenant separation
- **Queue Isolation**: Dedicated message queues per tenant
- **Worker Isolation**: Separate worker deployments per tenant
- **Authentication**: OIDC with JWT tokens for all API requests
- **Authorization**: Role-based access control (RBAC) via Django permissions
- **Encryption**: TLS for all external communication, encryption at rest for databases

---

## Scalability Patterns

### Horizontal Scaling

- **APIs**: Kubernetes Horizontal Pod Autoscaler (HPA) based on CPU/memory
- **Workers**: KEDA (Kubernetes Event-Driven Autoscaling) based on queue length
- **Frontend**: Multiple replicas behind load balancer

### Vertical Scaling

- **Databases**: Managed service auto-scaling (Cloud SQL, RDS, MongoDB Atlas)
- **Cache**: Redis cluster with automatic failover

### Multi-Cloud Redundancy

- **Primary**: GCP for most workloads
- **Secondary**: AWS for disaster recovery and geographic distribution
- **Active-Active**: Production deployments on both clouds

---

## Key Design Decisions

### Why Database-per-Tenant?

- **Complete data isolation**: No risk of cross-tenant data leaks
- **Compliance**: Easier to meet data residency and regulatory requirements
- **Performance**: Tenant-specific database tuning and indexing
- **Backup/Restore**: Tenant-specific backup schedules and recovery

### Why Per-Tenant Workers?

- **Resource isolation**: Prevents one tenant's tasks from affecting others
- **Scalability**: Scale worker resources per tenant based on usage
- **Monitoring**: Per-tenant metrics and alerting
- **Fault isolation**: Worker failures don't affect other tenants

### Why Shared Redis with Prefixing?

- **Cost optimization**: Shared infrastructure for low-risk cached data
- **Performance**: Fast cache access without tenant-specific connections
- **Simplicity**: Single Redis cluster to manage
- **Isolation**: Key prefixing ensures tenant data separation

---

## Integration Points

### External Systems

- **OIDC Provider**: Authentication and user management
- **Cloud Storage**: AWS S3, GCP Cloud Storage, Azure Blob
- **Email Services**: SMTP for notifications
- **SMS Gateways**: Third-party SMS providers
- **Payment Gateways**: Financial transaction processing
- **License Service**: Feature flag and license validation

### Internal Service Communication

- **Flow → Omni**: OmniApiClient for calling Omni API from Flow workflows
- **APIs → Workers**: Task enqueueing via RabbitMQ
- **Workers → APIs**: Callback APIs for task completion notifications

---

## Notes

- All services run on port 8000 (except Flower on port 5555) for consistency
- Environment variables configure cloud-specific resources (database URLs, storage buckets)
- ArgoCD automatically deploys changes pushed to Git repository
- Monitoring dashboards provide real-time visibility into all components
- Multi-cloud deployment provides high availability and disaster recovery

---

## Related Diagrams

- [Deployment Topology](02-deployment-topology.md) - Infrastructure and cloud architecture
- [Multi-Tenancy Isolation](03-multi-tenancy-isolation.md) - Tenant data isolation details
- [Request Flow](04-request-flow.md) - Detailed request tracing

---

**Maintained By**: Platform Engineering Team
**Review Schedule**: Quarterly
**Next Review**: 2026-05-04
