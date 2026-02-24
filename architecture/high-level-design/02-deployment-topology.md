# Deployment Topology Diagram

**Last Updated**: 2026-02-04
**Version**: 1.0
**Status**: Current

---

## Purpose

This diagram illustrates the Crego platform's multi-cloud, multi-environment deployment architecture. It shows how the platform is deployed across Google Cloud Platform (GCP) and Amazon Web Services (AWS), with detailed views of Kubernetes cluster architecture, shared vs per-tenant components, managed services, and infrastructure automation tools.

---

## Target Audience

- **DevOps Engineers**: Understanding deployment architecture and automation
- **Infrastructure Teams**: Planning capacity, scaling, and disaster recovery
- **Enterprise Clients**: Evaluating cloud redundancy and high availability
- **Security Teams**: Understanding network boundaries and security controls
- **Finance Teams**: Cloud resource allocation and cost optimization

---

## Environment-Cloud Matrix

```
┌────────────────────────────────────────────────────────────────────┐
│          MULTI-CLOUD DEPLOYMENT STRATEGY                           │
│                                                                    │
│   ┌──────────────────┬──────────────────┬──────────────────────┐  │
│   │   Environment    │       GCP        │        AWS           │  │
│   ├──────────────────┼──────────────────┼──────────────────────┤  │
│   │  Development     │  ✓ dev-gcp       │  ✓ dev-aws           │  │
│   │                  │  (Primary Dev)   │  (Testing)           │  │
│   │                  │  Infra Services  │  Infra Services      │  │
│   ├──────────────────┼──────────────────┼──────────────────────┤  │
│   │  Production      │  ✓ prod-gcp      │  ✓ prod-aws          │  │
│   │                  │  (PRIMARY)       │  (SECONDARY)         │  │
│   │                  │  Managed Svcs    │  Managed Svcs        │  │
│   └──────────────────┴──────────────────┴──────────────────────┘  │
│                                                                    │
│   Active-Active Production: 70% GCP / 30% AWS                     │
└────────────────────────────────────────────────────────────────────┘
```

---

## GCP Production Architecture (prod-gcp - PRIMARY)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        GOOGLE CLOUD PLATFORM - PRODUCTION                   │
│                                                                             │
│  Internet Traffic ──▶ Cloud Load Balancer ──▶ NGINX Ingress                │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  GKE CLUSTER (prod-gcp)                        [Google Managed CP]     │ │
│  │                                                                        │ │
│  │  ┌──────────────────────── SHARED COMPONENTS ──────────────────────┐  │ │
│  │  │                                                                  │  │ │
│  │  │  Omni API         Flow API        Omni Web        Flow Web      │  │ │
│  │  │  Django 5.2+      FastAPI         React 19        React 19      │  │ │
│  │  │  2-10 replicas    2-10 replicas   2-5 replicas    2-5 replicas  │  │ │
│  │  │  HPA (CPU/Mem)    HPA (CPU/Mem)   Static          Static        │  │ │
│  │  │                                                                  │  │ │
│  │  │  Flower Monitor                                                  │  │ │
│  │  │  1-2 replicas                                                    │  │ │
│  │  └──────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌──────────────────── PER-TENANT WORKERS ──────────────────────────┐  │ │
│  │  │                                                                    │  │ │
│  │  │  Tenant A:  omni-celery-worker-tenant-a  [KEDA 1-20 replicas]    │  │ │
│  │  │             omni-celery-beat-tenant-a    [1 replica]              │  │ │
│  │  │             flow-celery-worker-tenant-a  [KEDA 1-20 replicas]    │  │ │
│  │  │                                                                    │  │ │
│  │  │  Tenant B:  omni-celery-worker-tenant-b  [KEDA 1-20 replicas]    │  │ │
│  │  │             omni-celery-beat-tenant-b    [1 replica]              │  │ │
│  │  │             flow-celery-worker-tenant-b  [KEDA 1-20 replicas]    │  │ │
│  │  │                                                                    │  │ │
│  │  │  Tenant N:  ... (N tenants)                                       │  │ │
│  │  └────────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌──────────────────── INFRASTRUCTURE ADDONS ───────────────────────┐  │ │
│  │  │                                                                    │  │ │
│  │  │  ArgoCD              External Secrets Operator (ESO)              │  │ │
│  │  │  GitOps CD           GCP Secret Manager Sync                      │  │ │
│  │  │                                                                    │  │ │
│  │  │  cert-manager        External DNS                                 │  │ │
│  │  │  Let's Encrypt TLS   Cloud DNS Automation                         │  │ │
│  │  │                                                                    │  │ │
│  │  │  KEDA                Prometheus          Grafana                  │  │ │
│  │  │  Event Autoscaler    Metrics Collection  Dashboards               │  │ │
│  │  └────────────────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌──────────────────────── MANAGED SERVICES (GCP) ────────────────────────┐ │
│  │                                                                          │ │
│  │  Cloud SQL PostgreSQL        MongoDB Atlas         Memorystore Redis   │ │
│  │  Database-per-Tenant         Per-Tenant DBs        Shared Cache        │ │
│  │  Primary + Replica           Multi-Region          6GB HA              │ │
│  │  Auto Backups                                      Tenant Prefixing    │ │
│  │                                                                          │ │
│  │  Cloud Storage               Secret Manager        Cloud DNS           │ │
│  │  Documents/Backups           App Secrets           DNS Management      │ │
│  │  Multi-Regional              Workload Identity     app.crego.com       │ │
│  └──────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────── GITOPS & INFRASTRUCTURE ─────────────────────────┐ │
│  │                                                                        │ │
│  │  GitHub Repo (crego-infra) ──▶ ArgoCD ──▶ K8s Apply                   │ │
│  │                                                                        │ │
│  │  Terraform (terraform/environments/gcp/prod/) ──▶ GCP Resources       │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  Network: Private GKE Nodes + Cloud NAT (single IP for outbound)           │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## AWS Production Architecture (prod-aws - SECONDARY)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      AMAZON WEB SERVICES - PRODUCTION                       │
│                                                                             │
│  Internet Traffic ──▶ Application Load Balancer (ALB) ──▶ ALB Controller   │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  EKS CLUSTER (prod-aws)                        [AWS Managed CP]        │ │
│  │                                                                        │ │
│  │  ┌──────────────────────── SHARED COMPONENTS ──────────────────────┐  │ │
│  │  │                                                                  │  │ │
│  │  │  Omni API         Flow API        Omni Web        Flow Web      │  │ │
│  │  │  Django 5.2+      FastAPI         React 19        React 19      │  │ │
│  │  │  2-10 replicas    2-10 replicas   2-5 replicas    2-5 replicas  │  │ │
│  │  │  HPA (CPU/Mem)    HPA (CPU/Mem)   Static          Static        │  │ │
│  │  └──────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌──────────────────── PER-TENANT WORKERS ──────────────────────────┐  │ │
│  │  │  (Same structure as GCP - per-tenant deployments)                 │  │ │
│  │  │  Tenant A/B/N workers with KEDA autoscaling                       │  │ │
│  │  └────────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌──────────────────── INFRASTRUCTURE ADDONS ───────────────────────┐  │ │
│  │  │  ArgoCD  │  ESO (AWS Secrets Manager)  │  cert-manager           │  │ │
│  │  │  KEDA    │  External DNS (Route53)     │  Prometheus/Grafana     │  │ │
│  │  └────────────────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌──────────────────────── MANAGED SERVICES (AWS) ────────────────────────┐ │
│  │                                                                          │ │
│  │  RDS PostgreSQL              MongoDB Atlas         ElastiCache Redis   │ │
│  │  Database-per-Tenant         Per-Tenant DBs        Shared Cache        │ │
│  │  Multi-AZ Deployment         AWS Region            6GB Multi-AZ        │ │
│  │  Auto Backups                                      Tenant Prefixing    │ │
│  │                                                                          │ │
│  │  S3 Buckets                  AWS Secrets Manager   Route53             │ │
│  │  Documents/Backups           App Secrets           DNS Management      │ │
│  │  Versioning Enabled          IAM Role Auth         app-aws.crego.com   │ │
│  └──────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────── GITOPS & INFRASTRUCTURE ─────────────────────────┐ │
│  │  GitHub Repo (crego-infra) ──▶ ArgoCD ──▶ K8s Apply                   │ │
│  │  Terraform (terraform/environments/aws/prod/) ──▶ AWS Resources       │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  Network: VPC with Public/Private Subnets + NAT Gateway                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Development Environment (dev-gcp - Simplified)

```
┌──────────────────────────────────────────────────────────────┐
│          DEVELOPMENT ENVIRONMENT - GCP                       │
│                                                              │
│  ┌───────────────── GKE CLUSTER (dev-gcp) ────────────────┐ │
│  │                                                         │ │
│  │  Applications (1 replica each):                        │ │
│  │  • Omni API   • Flow API   • Omni Web   • Flow Web    │ │
│  │                                                         │ │
│  │  Workers (1-5 replicas):                               │ │
│  │  • Test Tenant Workers (omni/flow celery)             │ │
│  │                                                         │ │
│  │  Infrastructure Services (In-Cluster):                 │ │
│  │  ┌─────────────────────────────────────────┐           │ │
│  │  │  PostgreSQL (Single Instance/PV)        │           │ │
│  │  │  Redis (Single Instance)                │           │ │
│  │  │  RabbitMQ (Single Instance)             │           │ │
│  │  └─────────────────────────────────────────┘           │ │
│  │                                                         │ │
│  │  Addons: ArgoCD, ESO, KEDA                             │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  Optional Managed Services:                                  │
│  • MongoDB Atlas (Shared Dev Cluster)                        │
│  • Cloud Storage (Dev Bucket)                                │
└──────────────────────────────────────────────────────────────┘
```

---

## Key Components

### Cloud Providers

#### Google Cloud Platform (Primary)
- **Production**: `prod-gcp` - Primary production environment
- **Development**: `dev-gcp` - Main development environment
- **Regions**: asia-south1 (Mumbai), us-central1 (Iowa)
- **Kubernetes**: GKE (Google Kubernetes Engine) with private nodes
- **Network**: Cloud NAT for outbound, Cloud Load Balancer for inbound
- **Managed Services**: Cloud SQL (PostgreSQL), Memorystore (Redis), Cloud Storage

#### Amazon Web Services (Secondary)
- **Production**: `prod-aws` - Secondary production for redundancy
- **Development**: `dev-aws` - AWS testing environment
- **Regions**: ap-south-1 (Mumbai), us-east-1 (Virginia)
- **Kubernetes**: EKS (Elastic Kubernetes Service)
- **Managed Services**: RDS (PostgreSQL), ElastiCache (Redis), S3

### Kubernetes Architecture

#### Shared Application Components

**APIs (Port 8000)**
- Deployed as Kubernetes Deployments
- Horizontal Pod Autoscaler (HPA) for auto-scaling
  - Min replicas: 2 (prod), 1 (dev)
  - Max replicas: 10 (prod), 3 (dev)
  - Scale on: CPU 70%, Memory 80%
- Service type: ClusterIP
- Exposed via Ingress

**Web Applications (Port 8000)**
- Static React bundles served via NGINX
- Deployments with 2-5 replicas (prod), 1 replica (dev)
- Service type: ClusterIP
- Exposed via Ingress

**Flower Monitoring (Port 5555)**
- Celery task monitoring UI
- 1-2 replicas
- Service type: ClusterIP
- Exposed via Ingress at `/{omni,flow}/flower/*`

#### Per-Tenant Worker Deployments

**Design Pattern**
- Each tenant gets dedicated worker deployments:
  - `omni-celery-worker-{tenant-alias}`
  - `omni-celery-beat-{tenant-alias}`
  - `flow-celery-worker-{tenant-alias}`

**Autoscaling**
- KEDA (Kubernetes Event-Driven Autoscaling)
- Trigger: RabbitMQ queue length
  - Queue: `tenant_{alias}_queue`
  - Threshold: 50+ messages
- Min replicas: 1
- Max replicas: 20
- Scale-to-zero: Enabled for idle tenants

**Resource Allocation**
- CPU: 500m-2000m (request-limit)
- Memory: 512Mi-2Gi (request-limit)
- Dedicated per tenant for isolation

### Managed Services

#### GCP Managed Services

**Cloud SQL (PostgreSQL)**
- Database-per-tenant model
- Configuration:
  - Instance type: db-custom-4-16384 (4 vCPU, 16 GB RAM)
  - Storage: SSD, auto-resize enabled
  - High availability: Primary + replica in different zones
  - Backups: Automated daily backups, 7-day retention
- Connection: Private IP via VPC peering
- SSL/TLS encryption enforced

**Memorystore (Redis)**
- Shared cache with tenant key prefixing
- Configuration:
  - Tier: Standard (HA)
  - Memory: 6 GB
  - Version: Redis 6.x
- Connection: Private IP in VPC
- Use cases: Session storage, API caching, rate limiting

**Cloud Storage**
- Document storage buckets
- Configuration:
  - Storage class: Standard (multi-regional)
  - Versioning: Enabled
  - Lifecycle: Delete versions after 90 days
- Access: Workload Identity with IAM service accounts

#### AWS Managed Services

**RDS (PostgreSQL)**
- Database-per-tenant model
- Configuration:
  - Instance type: db.r6g.xlarge (4 vCPU, 32 GB RAM)
  - Storage: GP3 SSD, auto-scaling enabled
  - Multi-AZ: Enabled for high availability
  - Backups: Automated daily backups, 7-day retention
- Connection: Private subnet, security groups
- Encryption: At-rest and in-transit

**ElastiCache (Redis)**
- Shared cache with tenant key prefixing
- Configuration:
  - Node type: cache.r6g.large
  - Memory: 6 GB
  - Cluster mode: Enabled for HA
- Connection: Private subnet in VPC
- Use cases: Same as Memorystore

**S3 Buckets**
- Document storage
- Configuration:
  - Storage class: S3 Standard
  - Versioning: Enabled
  - Lifecycle: Transition to Glacier after 90 days
- Access: IAM roles for service accounts

#### MongoDB Atlas (Multi-Cloud)

**Configuration**
- Per-tenant databases on shared clusters (dev)
- Dedicated clusters per tenant (prod high-usage tenants)
- Multi-region replication
- Automated backups with point-in-time recovery

**Deployment**
- Primary region: Matches cloud provider (GCP or AWS)
- Replica regions: Cross-cloud for disaster recovery
- Connection: Private link (AWS PrivateLink, GCP Private Service Connect)

### Infrastructure Addons

#### ArgoCD (GitOps)
- **Purpose**: Declarative continuous deployment
- **Pattern**: App-of-Apps for managing all applications
- **Source**: GitHub repository `crego-infra`
- **Sync**: Automatic sync from Git commits
- **Overlays**: Kustomize overlays per environment-cloud

#### External Secrets Operator (ESO)
- **Purpose**: Sync secrets from cloud secret managers to Kubernetes
- **GCP**: Syncs from Secret Manager using Workload Identity
- **AWS**: Syncs from Secrets Manager using IAM roles
- **Target**: Creates Kubernetes Secret `app-env` in namespaces

#### cert-manager
- **Purpose**: Automated TLS certificate management
- **Provider**: Let's Encrypt
- **Issuer**: ClusterIssuer for production certificates
- **Renewal**: Automatic 30 days before expiry

#### External DNS
- **Purpose**: Automated DNS record management
- **GCP**: Updates Cloud DNS
- **AWS**: Updates Route53
- **Sync**: Creates/updates DNS records from Ingress annotations

#### KEDA (Kubernetes Event-Driven Autoscaling)
- **Purpose**: Scale workloads based on event sources
- **Trigger**: RabbitMQ queue length
- **Target**: Celery worker deployments (per-tenant)
- **Behavior**: Scale up when queue > 50 messages, scale to zero when idle

#### Monitoring Stack

**Prometheus**
- Metrics collection from all services
- Scrape interval: 15 seconds
- Retention: 15 days
- Alert rules for critical conditions

**Grafana**
- Visualization dashboards
- Pre-configured dashboards:
  - Kubernetes cluster overview
  - API performance metrics
  - Celery queue monitoring
  - Database connection pools

### Infrastructure Management

#### Terraform
- **Purpose**: Infrastructure as Code
- **Structure**:
  - `terraform/environments/gcp/prod/` - GCP production
  - `terraform/environments/aws/prod/` - AWS production
  - `terraform/environments/gcp/dev/` - GCP development
  - `terraform/environments/aws/dev/` - AWS development
- **Manages**:
  - Kubernetes clusters (GKE, EKS)
  - Managed databases (Cloud SQL, RDS)
  - Storage buckets (Cloud Storage, S3)
  - Networking (VPCs, subnets, NAT gateways)

#### Kustomize
- **Purpose**: Kubernetes configuration management
- **Structure**:
  - `base/` - Common Kubernetes manifests
  - `overlays/dev-gcp/` - Development GCP patches
  - `overlays/dev-aws/` - Development AWS patches
  - `overlays/prod-gcp/` - Production GCP patches
  - `overlays/prod-aws/` - Production AWS patches
- **Patches**: Environment-specific configurations (replicas, resources, secrets)

---

## Network Architecture

### GCP Private Node Architecture

**Private Nodes**
- No external IP addresses assigned to nodes
- Cost savings: ~$1.46/month per node eliminated

**Cloud NAT Gateway**
- Single regional external IP for all outbound traffic
- All pods route outbound traffic through NAT
- Regional IP (not global static IP)

**Load Balancer IPs**
- Dedicated external IPs for NGINX Ingress Controllers
- Separate IPs for different ingress classes (if needed)

**Traffic Flow**
- Inbound: Internet → Cloud Load Balancer → NGINX Ingress → Services → Pods
- Outbound: Pods → Cloud NAT → Regional IP → Internet

**Security Benefits**
- Nodes not directly accessible from internet
- All outbound traffic through controlled NAT gateway
- Reduced attack surface

### AWS Network Architecture

**VPC Configuration**
- Public subnets for ALB
- Private subnets for EKS worker nodes
- NAT Gateway for outbound traffic from private subnets

**Traffic Flow**
- Inbound: Internet → ALB → ALB Controller → Services → Pods
- Outbound: Pods → NAT Gateway → Internet

---

## Deployment Workflow

### GitOps Flow

```
Developer Commits → GitHub → ArgoCD Detects Change → ArgoCD Syncs → Kubernetes Applies Manifests
```

1. **Code Change**: Developer commits to `crego-infra` repository
2. **Git Push**: Changes pushed to GitHub main branch
3. **ArgoCD Polling**: ArgoCD detects new commit (polling interval: 3 minutes)
4. **Sync Decision**: ArgoCD compares Git state with cluster state
5. **Apply Changes**: ArgoCD applies Kubernetes manifests to cluster
6. **Health Check**: ArgoCD monitors application health
7. **Notification**: Sync status reported (Slack, email, etc.)

### Manual Deployment Options

**Deploy Services Script**
```bash
# Deploy to dev-gcp
./scripts/deploy-services.sh -e dev -c gcp

# Deploy to prod-aws
./scripts/deploy-services.sh -e prod -c aws
```

**Bootstrap Cluster**
```bash
# Bootstrap ArgoCD for dev-gcp
./scripts/bootstrap-cluster.sh -e dev -c gcp

# Bootstrap ArgoCD for prod-aws
./scripts/bootstrap-cluster.sh -e prod -c aws
```

**Update Image Tags**
```bash
# Update omni-api image in dev-gcp
./scripts/bump-image.sh omni-api v1.2.3 dev-gcp --commit

# Update flow-api image in prod-gcp and prod-aws
./scripts/bump-image.sh flow-api v2.1.0 prod-gcp --commit
./scripts/bump-image.sh flow-api v2.1.0 prod-aws --commit
```

---

## Autoscaling Strategies

### Horizontal Pod Autoscaler (HPA) - APIs

**Target**: API deployments (omni-api, flow-api)

**Metrics**:
- CPU Utilization: Scale at 70%
- Memory Utilization: Scale at 80%

**Configuration**:
- Min replicas: 2 (prod), 1 (dev)
- Max replicas: 10 (prod), 3 (dev)
- Scale-up: Add pod every 30 seconds
- Scale-down: Remove pod every 5 minutes

**Behavior**:
- Fast scale-up during traffic spikes
- Slow scale-down to avoid flapping

### KEDA (Event-Driven Autoscaling) - Workers

**Target**: Celery worker deployments (per-tenant)

**Trigger**: RabbitMQ queue length
- Queue: `tenant_{alias}_queue`
- Target: 50 messages per worker
- Query: Queue message count from RabbitMQ Management API

**Configuration**:
- Min replicas: 1
- Max replicas: 20
- Polling interval: 30 seconds
- Cooldown period: 300 seconds (5 minutes)

**Scale-to-Zero**:
- Enabled for idle tenants
- Scale to 0 replicas when queue empty for 5 minutes
- Scale up from 0 within 30 seconds of first message

**Resource Efficiency**:
- Idle tenants consume no worker resources
- Active tenants scale based on actual workload
- Cost optimization for multi-tenant deployment

---

## High Availability & Disaster Recovery

### Active-Active Production

**GCP (Primary)**
- Handles 70% of production traffic
- All tenants active
- Real-time replication to AWS

**AWS (Secondary)**
- Handles 30% of production traffic
- All tenants active
- Can handle 100% if GCP fails

### Failover Strategy

**DNS-Based Failover**
- Route53/Cloud DNS health checks
- Automatic failover to healthy region
- TTL: 60 seconds for fast propagation

**Database Replication**
- PostgreSQL: Cross-cloud replication (GCP ↔ AWS)
- MongoDB Atlas: Multi-region cluster
- Redis: Independent per cloud (cache only)

**RTO/RPO Targets**
- Recovery Time Objective (RTO): < 5 minutes
- Recovery Point Objective (RPO): < 1 minute
- Data loss tolerance: Minimal (cache only)

---

## Security

### Network Security

**Kubernetes Network Policies**
- Default deny all traffic
- Explicit allow rules for:
  - API → Database
  - Workers → Database
  - Workers → RabbitMQ
  - Ingress → APIs

**VPC Security**
- GCP: Private GKE cluster with authorized networks
- AWS: EKS in private subnets with security groups

### Access Control

**Workload Identity (GCP)**
- Kubernetes service accounts → GCP service accounts
- No static credentials in pods
- IAM policies for least privilege

**IAM Roles (AWS)**
- Kubernetes service accounts → AWS IAM roles
- OIDC provider for authentication
- IAM policies for least privilege

### Secret Management

**External Secrets Operator**
- Secrets stored in cloud secret managers (never in Git)
- GCP: Secret Manager with Workload Identity
- AWS: Secrets Manager with IAM roles
- Automatic rotation every 90 days

### Encryption

**In-Transit**
- TLS 1.3 for all external communication
- cert-manager with Let's Encrypt
- mTLS for service-to-service (optional)

**At-Rest**
- Database: Encrypted storage volumes
- Cloud Storage: Server-side encryption
- Backups: Encrypted with customer-managed keys

---

## Cost Optimization

### GCP Cost Optimizations

**Private Nodes**
- Save $1.46/month per node on external IPs
- Single NAT IP for all outbound traffic

**Committed Use Discounts**
- 1-year or 3-year commitments for GKE nodes
- Savings: 20-30% on compute costs

**Autoscaling**
- Scale down APIs during low traffic
- Scale workers to zero when idle
- Right-size resources based on actual usage

### AWS Cost Optimizations

**Reserved Instances**
- 1-year or 3-year RIs for EKS nodes
- Savings: 30-50% on EC2 costs

**Spot Instances**
- Use spot instances for non-critical workers
- Savings: 70-90% on compute costs
- Graceful handling of spot terminations

**S3 Lifecycle Policies**
- Transition old objects to Glacier
- Delete old versions after retention period

---

## Monitoring & Observability

### Metrics Collection

**Prometheus Metrics**
- API request rates and latencies
- Worker queue lengths
- Database connection pool utilization
- Resource usage (CPU, memory, disk)

**Custom Metrics**
- Business metrics (transactions, workflows)
- Tenant-specific metrics
- SLA compliance metrics

### Dashboards

**Grafana Dashboards**
- Kubernetes cluster overview
- Application performance (APIs, workers)
- Database performance
- Cost tracking per tenant

### Alerting

**Prometheus Alerts**
- High error rates (> 5%)
- High latency (p95 > 500ms)
- Pod restarts (> 3 in 10 minutes)
- Database connection exhaustion
- Worker queue backlog (> 1000 messages)

**Alert Channels**
- PagerDuty for critical alerts
- Slack for warnings
- Email for informational alerts

---

## Notes

- **Single Repository**: All environment-cloud combinations managed in one Git repository
- **No Branch Sprawl**: Single main branch with Kustomize overlays for configuration
- **Declarative Deployments**: All changes via Git commits, ArgoCD applies automatically
- **Infrastructure as Code**: Terraform manages all cloud resources
- **Multi-Tenant Isolation**: Per-tenant workers and databases ensure complete isolation
- **Cost Efficiency**: KEDA scale-to-zero and right-sized resources optimize costs
- **High Availability**: Active-active production across two cloud providers

---

## Related Diagrams

- [System Architecture](01-system-architecture.md) - Component interactions
- [Multi-Tenancy Isolation](03-multi-tenancy-isolation.md) - Tenant data isolation
- [Request Flow](04-request-flow.md) - End-to-end request tracing

---

**Maintained By**: DevOps & Platform Engineering Team
**Review Schedule**: Quarterly
**Next Review**: 2026-05-04
